#!/bin/bash
# =============================================================
# SSH & SSH-SSL SERVER SETUP SCRIPT
# Configures OpenSSH, Dropbear, Stunnel (SSH-SSL), and
# a Python WebSocket-to-SSH proxy for VPN tunnelling.
#
# Ports configured:
#   22   — OpenSSH (standard)
#   109  — Dropbear (primary alternate)
#   143  — Dropbear (secondary alternate)
#   447  — SSH over SSL  (Stunnel → port 22)
#   777  — Dropbear over SSL (Stunnel → port 109)
#   8880 — SSH over WebSocket (ws-proxy → Dropbear:109)
#
# Requirements:
#   - Debian/Ubuntu server with root access
#   - A domain name pointed at this server (for Let's Encrypt)
#     OR leave DOMAIN blank to use a self-signed certificate
#
# Usage:
#   chmod +x ssh-ssl-setup.sh
#   sudo ./ssh-ssl-setup.sh
# =============================================================

set -e

# ─── Colour helpers ──────────────────────────────────────────
BGreen='\033[1;32m'
BYellow='\033[1;33m'
BCyan='\033[1;36m'
BRed='\033[1;31m'
NC='\033[0m'

info()    { echo -e "${BCyan}[*] $*${NC}"; }
success() { echo -e "${BGreen}[✓] $*${NC}"; }
warn()    { echo -e "${BYellow}[!] $*${NC}"; }
error()   { echo -e "${BRed}[✗] $*${NC}"; exit 1; }

# ─── Root check ──────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "This script must be run as root."

# ─── Configuration ───────────────────────────────────────────
# Set your domain if you want a Let's Encrypt certificate.
# Leave blank ("") to fall back to a self-signed certificate.
DOMAIN="${1:-}"          # pass domain as first argument, or set here
STUNNEL_CERT=/etc/stunnel/stunnel.pem

# ─── Package manager setup ───────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
# Suppress interactive restart prompts on Debian/Ubuntu
if [ -f /etc/needrestart/needrestart.conf ]; then
    sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/g" \
        /etc/needrestart/needrestart.conf 2>/dev/null || true
fi
dpkg --configure -a --force-confdef --force-confold >/dev/null 2>&1 || true
apt-get install -f -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" </dev/null >/dev/null 2>&1 || true

APT="apt-get install -y \
    -o Dpkg::Options::='--force-confdef' \
    -o Dpkg::Options::='--force-confold'"

info "Updating package list..."
apt-get update -y </dev/null >/dev/null 2>&1

echo ""
echo -e "${BGreen}============================================${NC}"
echo -e "${BCyan}   SSH & SSH-SSL SETUP — FirewallFalcon     ${NC}"
echo -e "${BGreen}============================================${NC}"
echo ""

# ═══════════════════════════════════════════
# SECTION 1 — OPENSSH HARDENING
# ═══════════════════════════════════════════
info "Installing & hardening OpenSSH..."
eval "$APT openssh-server" </dev/null >/dev/null 2>&1

SSHD_CONF=/etc/ssh/sshd_config

# Back up the original config once
[ ! -f "${SSHD_CONF}.orig" ] && cp "$SSHD_CONF" "${SSHD_CONF}.orig"

# Apply recommended hardening settings
apply_sshd_setting() {
    local key="$1" val="$2"
    if grep -qE "^#?${key}" "$SSHD_CONF"; then
        sed -i "s|^#\?${key}.*|${key} ${val}|g" "$SSHD_CONF"
    else
        echo "${key} ${val}" >> "$SSHD_CONF"
    fi
}

apply_sshd_setting "Port"                    "22"
apply_sshd_setting "PermitRootLogin"         "yes"          # change to 'no' for production
apply_sshd_setting "PasswordAuthentication"  "yes"
apply_sshd_setting "X11Forwarding"           "no"
apply_sshd_setting "MaxAuthTries"            "3"
apply_sshd_setting "ClientAliveInterval"     "60"
apply_sshd_setting "ClientAliveCountMax"     "3"
apply_sshd_setting "AllowTcpForwarding"      "yes"          # needed for VPN tunnelling
apply_sshd_setting "GatewayPorts"            "no"
apply_sshd_setting "UseDNS"                  "no"           # speeds up login

systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1 || true
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
success "OpenSSH configured on port 22"

# ═══════════════════════════════════════════
# SECTION 2 — DROPBEAR (ALTERNATE SSH)
# ═══════════════════════════════════════════
info "Installing Dropbear (ports 109 & 143)..."
eval "$APT dropbear" </dev/null >/dev/null 2>&1

# Generate host keys if missing
mkdir -p /etc/dropbear
for TYPE in dss rsa ecdsa ed25519; do
    KEYFILE="/etc/dropbear/dropbear_${TYPE}_host_key"
    [ -f "$KEYFILE" ] || dropbearkey -t "$TYPE" -f "$KEYFILE" >/dev/null 2>&1 || true
done

# Add /bin/false as a valid shell (so VPN-only accounts cannot open a real shell)
grep -qxF '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells

# Write Dropbear configuration
cat > /etc/default/dropbear <<'EOF'
NO_START=0
DROPBEAR_PORT=109
# Also listen on port 143; -I = idle timeout (s); -K = keepalive interval (s)
DROPBEAR_EXTRA_ARGS="-p 143 -I 60 -K 30"
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
EOF

systemctl enable dropbear >/dev/null 2>&1 || true
systemctl restart dropbear
success "Dropbear running on ports 109 and 143"

# ═══════════════════════════════════════════
# SECTION 3 — WEBSOCKET → SSH PROXY
# Bridges WebSocket connections to Dropbear
# so SSH clients can connect via WS on port 8880
# ═══════════════════════════════════════════
info "Installing Python WebSocket-to-SSH proxy (port 8880)..."

cat > /usr/local/bin/ws-proxy.py <<'PYEOF'
#!/usr/bin/env python3
"""
ws-proxy.py — Minimal WebSocket-to-SSH bridge.
Listens on 127.0.0.1:8880, performs the WebSocket handshake,
then pipes traffic to/from Dropbear on 127.0.0.1:109.
"""
import socket
import threading

TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
LISTEN_HOST = '127.0.0.1'
LISTEN_PORT = 8880
HANDSHAKE_TIMEOUT = 15   # seconds to wait for the HTTP upgrade header


def forward(src: socket.socket, dst: socket.socket) -> None:
    """Pipe data between two sockets until one closes."""
    try:
        while True:
            data = src.recv(8192)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try:
            src.close()
        except Exception:
            pass
        try:
            dst.close()
        except Exception:
            pass


def handle_client(client: socket.socket) -> None:
    client.settimeout(HANDSHAKE_TIMEOUT)
    ssh = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ssh.settimeout(HANDSHAKE_TIMEOUT)
    try:
        ssh.connect((TARGET_HOST, TARGET_PORT))

        # Read the HTTP upgrade request
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = client.recv(1)
            if not chunk:
                return
            buf += chunk

        # Reply with WebSocket 101
        client.sendall(
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n\r\n"
        )

        # Go into full-duplex pipe mode
        client.settimeout(None)
        ssh.settimeout(None)
        t1 = threading.Thread(target=forward, args=(client, ssh), daemon=True)
        t2 = threading.Thread(target=forward, args=(ssh, client), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
    except Exception:
        pass
    finally:
        try:
            client.close()
        except Exception:
            pass
        try:
            ssh.close()
        except Exception:
            pass


def main() -> None:
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((LISTEN_HOST, LISTEN_PORT))
    srv.listen(5000)
    print(f"ws-proxy listening on {LISTEN_HOST}:{LISTEN_PORT} → SSH {TARGET_HOST}:{TARGET_PORT}")
    while True:
        try:
            client, _ = srv.accept()
            threading.Thread(target=handle_client, args=(client,), daemon=True).start()
        except Exception:
            pass


if __name__ == "__main__":
    main()
PYEOF

chmod +x /usr/local/bin/ws-proxy.py

# Systemd unit
cat > /etc/systemd/system/ws-proxy.service <<'EOF'
[Unit]
Description=WebSocket-to-SSH proxy (port 8880 → Dropbear 109)
After=network.target dropbear.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ws-proxy >/dev/null 2>&1
success "WebSocket-SSH proxy running on 127.0.0.1:8880"

# ═══════════════════════════════════════════
# SECTION 4 — SSL CERTIFICATE
# Tries Let's Encrypt first; falls back to
# a self-signed certificate automatically.
# ═══════════════════════════════════════════
info "Setting up SSL certificate..."
eval "$APT stunnel4 openssl" </dev/null >/dev/null 2>&1

mkdir -p /etc/stunnel

if [ -n "$DOMAIN" ]; then
    info "Requesting Let's Encrypt certificate for $DOMAIN ..."
    eval "$APT certbot" </dev/null >/dev/null 2>&1 || true

    # Stop anything on port 80 temporarily
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true

    certbot certonly \
        --standalone \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        >/dev/null 2>&1 && LE_OK=1 || LE_OK=0

    if [ "$LE_OK" -eq 1 ] && \
       [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        chmod -R 755 /etc/letsencrypt/archive
        chmod -R 755 /etc/letsencrypt/live
        cat "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" \
            "/etc/letsencrypt/live/$DOMAIN/privkey.pem" \
            > "$STUNNEL_CERT"
        success "Let's Encrypt certificate obtained for $DOMAIN"
    else
        warn "Let's Encrypt failed — falling back to self-signed certificate"
        DOMAIN=""   # trigger self-signed path below
    fi
fi

if [ -z "$DOMAIN" ] || [ ! -f "$STUNNEL_CERT" ]; then
    warn "Generating self-signed certificate (valid 365 days)..."
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=US/ST=NA/L=NA/O=SSHServer/CN=ssh-server" \
        -out "$STUNNEL_CERT" \
        -keyout /etc/stunnel/stunnel.key \
        >/dev/null 2>&1
    # Combine into one PEM file that Stunnel expects
    cat /etc/stunnel/stunnel.key >> "$STUNNEL_CERT"
    rm -f /etc/stunnel/stunnel.key
    success "Self-signed certificate created at $STUNNEL_CERT"
fi

chmod 600 "$STUNNEL_CERT"

# ═══════════════════════════════════════════
# SECTION 5 — STUNNEL (SSH-SSL WRAPPER)
#
#   [ssh-ssl]       port 447  → OpenSSH :22
#   [dropbear-ssl]  port 777  → Dropbear :109
#   [wss-bypass]    port 444  → WS-proxy :8880
# ═══════════════════════════════════════════
info "Configuring Stunnel SSL tunnels..."

# Enable the Stunnel daemon
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4 2>/dev/null || true

cat > /etc/stunnel/stunnel.conf <<EOF
; Stunnel global settings
pid     = /var/run/stunnel.pid
cert    = ${STUNNEL_CERT}
client  = no
; Socket options for performance
socket  = a:SO_REUSEADDR=1
socket  = l:TCP_NODELAY=1
socket  = r:TCP_NODELAY=1

; ─── SSH over SSL ─────────────────────────────
; Connect an SSL-capable client to port 447
; and it tunnels to OpenSSH on port 22.
[ssh-ssl]
accept  = 447
connect = 127.0.0.1:22

; ─── Dropbear over SSL ────────────────────────
; Connect an SSL-capable client to port 777
; and it tunnels to Dropbear on port 109.
[dropbear-ssl]
accept  = 777
connect = 127.0.0.1:109

; ─── WebSocket over SSL ───────────────────────
; Port 444 wraps the WebSocket proxy in SSL,
; so SSH clients that need WSS can use this.
[wss-bypass]
accept  = 444
connect = 127.0.0.1:8880
EOF

systemctl enable stunnel4 >/dev/null 2>&1 || true
systemctl restart stunnel4 >/dev/null 2>&1
success "Stunnel running — ssh-ssl:447 | dropbear-ssl:777 | wss-ssl:444"

# ═══════════════════════════════════════════
# SECTION 6 — FIREWALL (UFW)
# ═══════════════════════════════════════════
info "Opening firewall ports..."

if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp   >/dev/null 2>&1   # OpenSSH
    ufw allow 109/tcp  >/dev/null 2>&1   # Dropbear
    ufw allow 143/tcp  >/dev/null 2>&1   # Dropbear alt
    ufw allow 444/tcp  >/dev/null 2>&1   # WSS bypass (SSL)
    ufw allow 447/tcp  >/dev/null 2>&1   # SSH over SSL
    ufw allow 777/tcp  >/dev/null 2>&1   # Dropbear over SSL
    success "UFW rules applied"
else
    warn "ufw not found — skipping firewall configuration"
    warn "Manually open TCP ports: 22, 109, 143, 444, 447, 777"
fi

# ═══════════════════════════════════════════
# SECTION 7 — STATUS SUMMARY
# ═══════════════════════════════════════════
echo ""
echo -e "${BGreen}============================================================${NC}"
echo -e "${BCyan}              SETUP COMPLETE — SERVICE SUMMARY              ${NC}"
echo -e "${BGreen}============================================================${NC}"

print_status() {
    local name="$1" unit="$2"
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        echo -e "  ${BGreen}● RUNNING${NC}  $name"
    else
        echo -e "  ${BRed}○ STOPPED${NC}  $name (check: systemctl status $unit)"
    fi
}

echo ""
echo -e "${BYellow}  SERVICE                        PORT(S)${NC}"
echo    "  ──────────────────────────────  ──────────────────"
print_status "OpenSSH                        " "ssh"
echo    "                                  TCP 22"
print_status "Dropbear                       " "dropbear"
echo    "                                  TCP 109, 143"
print_status "WS-to-SSH Proxy                " "ws-proxy"
echo    "                                  TCP 8880 (local)"
print_status "Stunnel (SSH-SSL)              " "stunnel4"
echo    "                                  TCP 447 → :22  (ssh-ssl)"
echo    "                                  TCP 777 → :109 (dropbear-ssl)"
echo    "                                  TCP 444 → :8880 (wss-ssl)"
echo ""
echo -e "${BYellow}  CONNECTION GUIDE${NC}"
echo    "  ─────────────────────────────────────────────────────────────"
echo    "  Standard SSH        : ssh user@<server-ip> -p 22"
echo    "  Dropbear SSH        : ssh user@<server-ip> -p 109  (or 143)"
echo    "  SSH over SSL        : stunnel client or HTTP Injector → port 447"
echo    "  Dropbear over SSL   : stunnel client or HTTP Injector → port 777"
echo    "  SSH over WebSocket  : WS proxy URL  ws://<server-ip>:8880"
echo    "  SSH over WSS (TLS)  : WSS proxy URL wss://<server-ip>:444"
echo    "  ─────────────────────────────────────────────────────────────"
echo ""
echo -e "${BGreen}============================================================${NC}"
echo ""
