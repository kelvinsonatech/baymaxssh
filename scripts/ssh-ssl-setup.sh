#!/bin/bash
# =============================================================
# SSH + WEBSOCKET + SSL VPN SERVER SETUP + MANAGEMENT PANEL
#
# Working payload/SSL layout (HTTP Injector / HTTP Custom style):
#
#   80   — WebSocket / SSH proxy  (payload -> 101 -> SSH)
#   443  — SSL/TLS  (stunnel) -> WebSocket proxy -> SSH   (SSL payload)
#   447  — SSL/TLS  (stunnel) -> OpenSSH direct
#   22   — OpenSSH  (management / direct)
#   109  — Dropbear (direct)
#   143  — Dropbear (direct alt)
#
# The port-80 proxy is DUAL MODE:
#   * If the client sends an HTTP/WebSocket payload, it replies
#     "HTTP/1.1 101 Switching Protocols" then tunnels to SSH.
#   * If the client speaks raw SSH (no payload), it tunnels directly.
#   This makes it work with WebSocket payloads AND plain SSH.
#
# Usage:
#   chmod +x ssh-ssl-setup.sh
#   sudo ./ssh-ssl-setup.sh
# =============================================================

set -e

BGreen='\033[1;32m'; BYellow='\033[1;33m'; BCyan='\033[1;36m'
BRed='\033[1;31m'; BPurple='\033[1;35m'; NC='\033[0m'

info()    { echo -e "${BCyan}[*] $*${NC}"; }
success() { echo -e "${BGreen}[✓] $*${NC}"; }
warn()    { echo -e "${BYellow}[!] $*${NC}"; }
error()   { echo -e "${BRed}[✗] $*${NC}"; exit 1; }

[[ $EUID -ne 0 ]] && error "This script must be run as root."

CONF_DIR=/etc/ssh-panel
mkdir -p "$CONF_DIR"
STUNNEL_CERT=/etc/stunnel/stunnel.pem

# ═══════════════════════════════════════════
# ASK FOR DOMAIN
# ═══════════════════════════════════════════
clear
echo -e "${BGreen}============================================${NC}"
echo -e "${BCyan}    SSH + WEBSOCKET + SSL VPN INSTALLER      ${NC}"
echo -e "${BGreen}============================================${NC}"
echo ""
echo -e "${BYellow}Enter your domain name (pointed at this server's IP).${NC}"
echo -e "${BYellow}Leave blank to use a self-signed certificate.${NC}"
echo ""
read -rp "  Domain: " DOMAIN
DOMAIN="$(echo "$DOMAIN" | tr -d '[:space:]')"

apt-get install -y curl >/dev/null 2>&1 || true
SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
echo "$DOMAIN"    > "$CONF_DIR/domain.conf"
echo "$SERVER_IP" > "$CONF_DIR/ip.conf"

if [ -n "$DOMAIN" ]; then
    echo -e "\n${BGreen}Using domain:${NC} $DOMAIN"
else
    echo -e "\n${BYellow}No domain — a self-signed certificate will be used.${NC}"
fi
sleep 1

# ─── Package manager setup ───────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
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
echo -e "${BCyan}     INSTALLING VPN PROTOCOLS                ${NC}"
echo -e "${BGreen}============================================${NC}"
echo ""

# ═══════════════════════════════════════════
# SECTION 1 — OPENSSH
# ═══════════════════════════════════════════
info "Installing & configuring OpenSSH..."
eval "$APT openssh-server curl" </dev/null >/dev/null 2>&1

SSHD_CONF=/etc/ssh/sshd_config
[ ! -f "${SSHD_CONF}.orig" ] && cp "$SSHD_CONF" "${SSHD_CONF}.orig"

apply_sshd_setting() {
    local key="$1" val="$2"
    if grep -qE "^#?${key}" "$SSHD_CONF"; then
        sed -i "s|^#\?${key}.*|${key} ${val}|g" "$SSHD_CONF"
    else
        echo "${key} ${val}" >> "$SSHD_CONF"
    fi
}

apply_sshd_setting "Port"                    "22"
apply_sshd_setting "PermitRootLogin"         "yes"
apply_sshd_setting "PasswordAuthentication"  "yes"
apply_sshd_setting "AllowTcpForwarding"      "yes"
apply_sshd_setting "GatewayPorts"            "yes"
apply_sshd_setting "PermitTunnel"            "yes"
apply_sshd_setting "ClientAliveInterval"     "30"
apply_sshd_setting "ClientAliveCountMax"     "6"
apply_sshd_setting "UseDNS"                  "no"

systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1 || true
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
success "OpenSSH configured on port 22"

# ═══════════════════════════════════════════
# SECTION 2 — DROPBEAR (direct SSH targets)
# ═══════════════════════════════════════════
info "Installing Dropbear (ports 109 & 143)..."
eval "$APT dropbear" </dev/null >/dev/null 2>&1

mkdir -p /etc/dropbear
for TYPE in dss rsa ecdsa ed25519; do
    KEYFILE="/etc/dropbear/dropbear_${TYPE}_host_key"
    [ -f "$KEYFILE" ] || dropbearkey -t "$TYPE" -f "$KEYFILE" >/dev/null 2>&1 || true
done

# Dropbear (and OpenSSH) accept tunnel-only accounts whose shell is /bin/false.
grep -qxF '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells
grep -qxF '/usr/sbin/nologin' /etc/shells || echo '/usr/sbin/nologin' >> /etc/shells

cat > /etc/default/dropbear <<'EOF'
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 143 -I 300 -K 30"
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
EOF

systemctl enable dropbear >/dev/null 2>&1 || true
systemctl restart dropbear
success "Dropbear running on ports 109 and 143"

# ═══════════════════════════════════════════
# SECTION 3 — DUAL-MODE WEBSOCKET/SSH PROXY (port 80)
# ═══════════════════════════════════════════
info "Installing dual-mode WebSocket/SSH proxy (port 80)..."

cat > /usr/local/bin/ws-proxy.py <<'PYEOF'
#!/usr/bin/env python3
"""
Dual-mode WebSocket/SSH proxy.

Listens on 0.0.0.0:80. For each connection it peeks at the first bytes:

  * If the client speaks SSH directly (data begins with "SSH-"), the
    connection is tunnelled straight to the backend SSH server.
  * Otherwise the data is treated as an HTTP/WebSocket payload: the
    proxy replies "HTTP/1.1 101 Switching Protocols" and then tunnels
    to SSH. This is what VPN apps (HTTP Injector, HTTP Custom, etc.)
    expect for a WebSocket payload.
  * If nothing arrives quickly, it assumes a direct SSH client that is
    waiting for the server banner and tunnels straight through.

Backend SSH = Dropbear on 127.0.0.1:109.
"""
import socket
import threading

BACKEND_HOST = '127.0.0.1'
BACKEND_PORT = 109
LISTEN_HOST  = '0.0.0.0'
LISTEN_PORT  = 80
PEEK_TIMEOUT = 3          # seconds to wait for an initial payload
RESPONSE = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Upgrade: websocket\r\n"
    b"Connection: Upgrade\r\n\r\n"
)


def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            try:
                s.close()
            except Exception:
                pass


def bridge(client, backend, prefix=b""):
    if prefix:
        try:
            backend.sendall(prefix)
        except Exception:
            pass
    t1 = threading.Thread(target=pipe, args=(client, backend), daemon=True)
    t2 = threading.Thread(target=pipe, args=(backend, client), daemon=True)
    t1.start(); t2.start(); t1.join(); t2.join()


def handle(client):
    backend = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        backend.connect((BACKEND_HOST, BACKEND_PORT))
    except Exception:
        client.close()
        return

    first = b""
    try:
        client.settimeout(PEEK_TIMEOUT)
        first = client.recv(4096)
    except socket.timeout:
        first = b""
    except Exception:
        client.close(); backend.close(); return
    finally:
        try:
            client.settimeout(None)
        except Exception:
            pass

    # Direct SSH client: forward the bytes we already read.
    if first.startswith(b"SSH-") or first == b"":
        try:
            bridge(client, backend, prefix=first)
        finally:
            client.close(); backend.close()
        return

    # HTTP / WebSocket payload: read the rest of the request headers,
    # then answer with a 101 upgrade and tunnel to SSH.
    buf = first
    try:
        client.settimeout(PEEK_TIMEOUT)
        while b"\r\n\r\n" not in buf and len(buf) < 8192:
            more = client.recv(4096)
            if not more:
                break
            buf += more
    except Exception:
        pass
    finally:
        try:
            client.settimeout(None)
        except Exception:
            pass

    try:
        client.sendall(RESPONSE)
    except Exception:
        client.close(); backend.close(); return

    try:
        bridge(client, backend)
    finally:
        client.close(); backend.close()


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((LISTEN_HOST, LISTEN_PORT))
    srv.listen(1024)
    print("dual-mode proxy on %s:%d -> SSH %s:%d" %
          (LISTEN_HOST, LISTEN_PORT, BACKEND_HOST, BACKEND_PORT))
    while True:
        try:
            client, _ = srv.accept()
            threading.Thread(target=handle, args=(client,), daemon=True).start()
        except Exception:
            pass


if __name__ == "__main__":
    main()
PYEOF

chmod +x /usr/local/bin/ws-proxy.py

cat > /etc/systemd/system/ws-proxy.service <<'EOF'
[Unit]
Description=Dual-mode WebSocket/SSH proxy (port 80 -> Dropbear 109)
After=network.target dropbear.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ws-proxy >/dev/null 2>&1
# (started after the certificate step, which needs port 80 for certbot)
success "WebSocket/SSH proxy installed (port 80)"

# ═══════════════════════════════════════════
# SECTION 4 — SSL CERTIFICATE
# ═══════════════════════════════════════════
info "Setting up SSL certificate..."
eval "$APT stunnel4 openssl" </dev/null >/dev/null 2>&1
mkdir -p /etc/stunnel

# Make sure nothing is holding port 80 while certbot validates.
systemctl stop ws-proxy 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

if [ -n "$DOMAIN" ]; then
    info "Requesting Let's Encrypt certificate for $DOMAIN ..."
    eval "$APT certbot" </dev/null >/dev/null 2>&1 || true
    certbot certonly --standalone -d "$DOMAIN" \
        --non-interactive --agree-tos \
        --register-unsafely-without-email >/dev/null 2>&1 && LE_OK=1 || LE_OK=0

    if [ "${LE_OK:-0}" -eq 1 ] && [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        chmod -R 755 /etc/letsencrypt/archive /etc/letsencrypt/live
        cat "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" \
            "/etc/letsencrypt/live/$DOMAIN/privkey.pem" > "$STUNNEL_CERT"
        success "Let's Encrypt certificate obtained for $DOMAIN"
    else
        warn "Let's Encrypt failed — using self-signed certificate"
        DOMAIN=""
    fi
fi

if [ -z "$DOMAIN" ] || [ ! -f "$STUNNEL_CERT" ]; then
    warn "Generating self-signed certificate..."
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/C=US/ST=NA/L=NA/O=VPN/CN=vpn-server" \
        -out "$STUNNEL_CERT" -keyout /etc/stunnel/stunnel.key >/dev/null 2>&1
    cat /etc/stunnel/stunnel.key >> "$STUNNEL_CERT"
    rm -f /etc/stunnel/stunnel.key
    success "Self-signed certificate created"
fi
chmod 600 "$STUNNEL_CERT"

# Port 80 is free again — start the proxy.
systemctl start ws-proxy >/dev/null 2>&1 || true

# ═══════════════════════════════════════════
# SECTION 5 — STUNNEL (SSL / TLS)
#   443 -> WebSocket proxy (SSL + payload)
#   447 -> OpenSSH direct  (plain SSL)
# ═══════════════════════════════════════════
info "Configuring Stunnel (SSL on 443 & 447)..."
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4 2>/dev/null || true

cat > /etc/stunnel/stunnel.conf <<EOF
pid     = /var/run/stunnel4.pid
cert    = ${STUNNEL_CERT}
client  = no
socket  = a:SO_REUSEADDR=1
socket  = l:TCP_NODELAY=1
socket  = r:TCP_NODELAY=1
TIMEOUTclose = 0

; SSL + WebSocket payload: TLS on 443 -> dual-mode proxy on 80 -> SSH
[ssl-ws]
accept  = 443
connect = 127.0.0.1:80

; Plain SSL to OpenSSH: TLS on 447 -> OpenSSH 22
[ssl-ssh]
accept  = 447
connect = 127.0.0.1:22
EOF

systemctl enable stunnel4 >/dev/null 2>&1 || true
systemctl restart stunnel4 >/dev/null 2>&1
success "Stunnel running — SSL 443 (payload) & 447 (direct SSH)"

# ═══════════════════════════════════════════
# SECTION 6 — FIREWALL
# ═══════════════════════════════════════════
info "Opening firewall ports..."
if command -v ufw >/dev/null 2>&1; then
    for P in 22 80 109 143 443 447; do
        ufw allow ${P}/tcp >/dev/null 2>&1
    done
    success "UFW rules applied"
else
    warn "ufw not found — open TCP ports manually: 22 80 109 143 443 447"
fi

# ═══════════════════════════════════════════
# SECTION 7 — INSTALL THE 'menu' COMMAND
# ═══════════════════════════════════════════
info "Installing management panel (menu command)..."

cat > /usr/local/bin/menu <<'MENUEOF'
#!/bin/bash
# SSH VPN MANAGEMENT PANEL — type "menu" to open.

BGreen='\033[1;32m'; BYellow='\033[1;33m'; BCyan='\033[1;36m'
BRed='\033[1;31m'; BPurple='\033[1;35m'; NC='\033[0m'

CONF_DIR=/etc/ssh-panel
DOMAIN=$(cat "$CONF_DIR/domain.conf" 2>/dev/null)
SERVER_IP=$(cat "$CONF_DIR/ip.conf" 2>/dev/null)
HOST_DISPLAY="${DOMAIN:-$SERVER_IP}"

[[ $EUID -ne 0 ]] && { echo -e "${BRed}Run as root: sudo menu${NC}"; exit 1; }

pause() { echo ""; read -rp "Press ENTER to return to the menu..." _; }

show_ports() {
    echo -e "  ${BPurple}CONNECTION PORTS${NC}"
    echo -e "  WebSocket (payload) : ${HOST_DISPLAY}:80"
    echo -e "  SSL + payload (TLS) : ${HOST_DISPLAY}:443"
    echo -e "  SSL direct SSH      : ${HOST_DISPLAY}:447"
    echo -e "  OpenSSH             : ${HOST_DISPLAY}:22"
    echo -e "  Dropbear            : ${HOST_DISPLAY}:109 / 143"
}

create_user() {
    clear
    echo -e "${BGreen}=========== CREATE SSH USER ===========${NC}"
    read -rp "  Username        : " USERNAME
    [ -z "$USERNAME" ] && { echo -e "${BRed}Username cannot be empty.${NC}"; pause; return; }
    if id "$USERNAME" >/dev/null 2>&1; then
        echo -e "${BRed}User '$USERNAME' already exists.${NC}"; pause; return
    fi
    read -rp "  Password        : " PASSWORD
    [ -z "$PASSWORD" ] && { echo -e "${BRed}Password cannot be empty.${NC}"; pause; return; }
    read -rp "  Days valid      : " DAYS
    [[ ! "$DAYS" =~ ^[0-9]+$ ]] && DAYS=30
    EXP_DATE=$(date -d "+$DAYS days" +"%Y-%m-%d")

    useradd -e "$EXP_DATE" -M -s /bin/false "$USERNAME"
    echo -e "${PASSWORD}\n${PASSWORD}" | passwd "$USERNAME" >/dev/null 2>&1

    clear
    echo -e "${BGreen}=========================================${NC}"
    echo -e "${BCyan}        SSH ACCOUNT CREATED               ${NC}"
    echo -e "${BGreen}=========================================${NC}"
    echo -e "  Host / Domain : ${BYellow}${HOST_DISPLAY}${NC}"
    echo -e "  Username      : ${BYellow}${USERNAME}${NC}"
    echo -e "  Password      : ${BYellow}${PASSWORD}${NC}"
    echo -e "  Expires on    : ${BYellow}${EXP_DATE}${NC}  (${DAYS} days)"
    echo -e "${BGreen}-----------------------------------------${NC}"
    show_ports
    echo -e "${BGreen}-----------------------------------------${NC}"
    echo -e "  ${BPurple}SAMPLE WEBSOCKET PAYLOAD${NC}"
    echo -e "  GET / HTTP/1.1[crlf]Host: ${HOST_DISPLAY}[crlf]"
    echo -e "  Upgrade: websocket[crlf][crlf]"
    echo -e "  ${BPurple}SSL/SNI host${NC} : ${HOST_DISPLAY}"
    echo -e "${BGreen}=========================================${NC}"
    pause
}

delete_user() {
    clear
    echo -e "${BGreen}=========== DELETE SSH USER ===========${NC}"
    read -rp "  Username to delete : " USERNAME
    if ! id "$USERNAME" >/dev/null 2>&1; then
        echo -e "${BRed}User '$USERNAME' does not exist.${NC}"; pause; return
    fi
    pkill -u "$USERNAME" 2>/dev/null
    userdel -f "$USERNAME" >/dev/null 2>&1
    echo -e "${BGreen}User '$USERNAME' deleted.${NC}"
    pause
}

list_users() {
    clear
    echo -e "${BGreen}=========== SSH USER LIST ===========${NC}"
    printf "  %-20s %-12s %-8s\n" "USERNAME" "EXPIRES" "STATUS"
    echo   "  -------------------------------------------"
    while IFS=: read -r user _ uid _ _ _ shell; do
        if [ "$uid" -ge 1000 ] && { [ "$shell" = "/bin/false" ] || [ "$shell" = "/usr/sbin/nologin" ]; }; then
            EXP=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
            EXP_SHORT=$(date -d "$EXP" +"%Y-%m-%d" 2>/dev/null || echo "$EXP")
            if pgrep -u "$user" >/dev/null 2>&1; then STATUS="online"; else STATUS="offline"; fi
            printf "  %-20s %-12s %-8s\n" "$user" "$EXP_SHORT" "$STATUS"
        fi
    done < /etc/passwd
    pause
}

online_users() {
    clear
    echo -e "${BGreen}=========== ONLINE USERS ===========${NC}"
    printf "  %-20s %-10s\n" "USERNAME" "SESSIONS"
    echo   "  --------------------------------"
    while IFS=: read -r user _ uid _ _ _ shell; do
        if [ "$uid" -ge 1000 ] && { [ "$shell" = "/bin/false" ] || [ "$shell" = "/usr/sbin/nologin" ]; }; then
            COUNT=$(pgrep -u "$user" 2>/dev/null | wc -l)
            [ "$COUNT" -gt 0 ] && printf "  %-20s %-10s\n" "$user" "$COUNT"
        fi
    done < /etc/passwd
    pause
}

change_password() {
    clear
    echo -e "${BGreen}======== CHANGE PASSWORD ========${NC}"
    read -rp "  Username     : " USERNAME
    if ! id "$USERNAME" >/dev/null 2>&1; then
        echo -e "${BRed}User does not exist.${NC}"; pause; return
    fi
    read -rp "  New password : " PASSWORD
    [ -z "$PASSWORD" ] && { echo -e "${BRed}Password cannot be empty.${NC}"; pause; return; }
    echo -e "${PASSWORD}\n${PASSWORD}" | passwd "$USERNAME" >/dev/null 2>&1
    echo -e "${BGreen}Password updated for '$USERNAME'.${NC}"
    pause
}

renew_user() {
    clear
    echo -e "${BGreen}======== RENEW ACCOUNT ========${NC}"
    read -rp "  Username     : " USERNAME
    if ! id "$USERNAME" >/dev/null 2>&1; then
        echo -e "${BRed}User does not exist.${NC}"; pause; return
    fi
    read -rp "  Add days     : " DAYS
    [[ ! "$DAYS" =~ ^[0-9]+$ ]] && DAYS=30
    NEW_EXP=$(date -d "+$DAYS days" +"%Y-%m-%d")
    chage -E "$NEW_EXP" "$USERNAME"
    echo -e "${BGreen}'$USERNAME' now expires on $NEW_EXP.${NC}"
    pause
}

service_status() {
    clear
    echo -e "${BGreen}======== SERVICE STATUS ========${NC}"
    for svc in ssh dropbear ws-proxy stunnel4; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${BGreen}● RUNNING${NC}  $svc"
        else
            echo -e "  ${BRed}○ STOPPED${NC}  $svc"
        fi
    done
    echo ""
    show_ports
    pause
}

restart_services() {
    clear
    echo -e "${BYellow}Restarting all services...${NC}"
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    systemctl restart dropbear 2>/dev/null
    systemctl restart ws-proxy 2>/dev/null
    systemctl restart stunnel4 2>/dev/null
    echo -e "${BGreen}All services restarted.${NC}"
    pause
}

while true; do
    clear
    echo -e "${BGreen}==================================================${NC}"
    echo -e "${BCyan}            SSH VPN MANAGEMENT PANEL              ${NC}"
    echo -e "${BGreen}==================================================${NC}"
    echo -e "   Host   : ${BYellow}${HOST_DISPLAY}${NC}"
    echo -e "${BGreen}--------------------------------------------------${NC}"
    echo -e "   ${BYellow}1)${NC} Create SSH user"
    echo -e "   ${BYellow}2)${NC} Delete SSH user"
    echo -e "   ${BYellow}3)${NC} List all users"
    echo -e "   ${BYellow}4)${NC} Show online users"
    echo -e "   ${BYellow}5)${NC} Change user password"
    echo -e "   ${BYellow}6)${NC} Renew / extend account"
    echo -e "   ${BYellow}7)${NC} Service status"
    echo -e "   ${BYellow}8)${NC} Restart all services"
    echo -e "   ${BYellow}0)${NC} Exit"
    echo -e "${BGreen}==================================================${NC}"
    read -rp "   Select an option: " OPT
    case "$OPT" in
        1) create_user ;;
        2) delete_user ;;
        3) list_users ;;
        4) online_users ;;
        5) change_password ;;
        6) renew_user ;;
        7) service_status ;;
        8) restart_services ;;
        0) clear; exit 0 ;;
        *) echo -e "${BRed}Invalid option.${NC}"; sleep 1 ;;
    esac
done
MENUEOF

chmod +x /usr/local/bin/menu
success "Management panel installed — type 'menu' to open it"

# ═══════════════════════════════════════════
# FINAL MESSAGE
# ═══════════════════════════════════════════
clear
echo -e "${BGreen}============================================================${NC}"
echo -e "${BPurple}      INSTALLATION COMPLETE — ALL PROTOCOLS INSTALLED       ${NC}"
echo -e "${BGreen}============================================================${NC}"
echo ""
echo -e "  Host / Domain : ${BYellow}${DOMAIN:-$SERVER_IP}${NC}"
echo ""
echo -e "  ${BCyan}Installed services & ports:${NC}"
echo -e "    WebSocket (payload)  → 80"
echo -e "    SSL + payload (TLS)  → 443"
echo -e "    SSL direct SSH (TLS) → 447"
echo -e "    OpenSSH              → 22"
echo -e "    Dropbear             → 109, 143"
echo ""
echo -e "  ${BCyan}Client tips:${NC}"
echo -e "    WebSocket payload : GET / HTTP/1.1[crlf]Host: ${DOMAIN:-$SERVER_IP}[crlf]Upgrade: websocket[crlf][crlf]"
echo -e "    SSL/SNI host      : ${DOMAIN:-$SERVER_IP}"
echo ""
echo -e "${BGreen}============================================================${NC}"
echo -e "${BYellow}   Type ${BGreen}menu${BYellow} to open the panel and create users.${NC}"
echo -e "${BGreen}============================================================${NC}"
echo ""
