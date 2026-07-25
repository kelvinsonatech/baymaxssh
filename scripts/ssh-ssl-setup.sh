#!/bin/bash
# =============================================================
# SSH & SSH-SSL SERVER SETUP + MANAGEMENT PANEL
#
# Installs: OpenSSH, Dropbear, Stunnel (SSH-SSL), and a
# WebSocket-to-SSH proxy. Then installs a "menu" command that
# opens a management panel to create/delete SSH users.
#
# Ports:
#   80   — Dropbear (main SSH)
#   109  — Dropbear (alt)
#   143  — Dropbear (alt)
#   443  — Dropbear over SSL (Stunnel → :80)
#   22   — OpenSSH
#   447  — OpenSSH over SSL  (Stunnel → :22)
#   444  — WebSocket over SSL (Stunnel → :8880)
#   8880 — SSH over WebSocket (ws-proxy → Dropbear:109)
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
BPurple='\033[1;35m'
NC='\033[0m'

info()    { echo -e "${BCyan}[*] $*${NC}"; }
success() { echo -e "${BGreen}[✓] $*${NC}"; }
warn()    { echo -e "${BYellow}[!] $*${NC}"; }
error()   { echo -e "${BRed}[✗] $*${NC}"; exit 1; }

# ─── Root check ──────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "This script must be run as root."

# ─── Config directory ────────────────────────────────────────
CONF_DIR=/etc/ssh-panel
mkdir -p "$CONF_DIR"
STUNNEL_CERT=/etc/stunnel/stunnel.pem

# ═══════════════════════════════════════════
# ASK FOR DOMAIN
# ═══════════════════════════════════════════
clear
echo -e "${BGreen}============================================${NC}"
echo -e "${BCyan}      SSH & SSH-SSL SERVER INSTALLER         ${NC}"
echo -e "${BGreen}============================================${NC}"
echo ""
echo -e "${BYellow}Enter your domain name (pointed at this server's IP).${NC}"
echo -e "${BYellow}Leave blank to use a self-signed certificate.${NC}"
echo ""
read -rp "  Domain: " DOMAIN
DOMAIN="$(echo "$DOMAIN" | tr -d '[:space:]')"

# Detect the server's public IP for display later
SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
echo "$DOMAIN"    > "$CONF_DIR/domain.conf"
echo "$SERVER_IP" > "$CONF_DIR/ip.conf"

if [ -n "$DOMAIN" ]; then
    echo -e "\n${BGreen}Using domain:${NC} $DOMAIN"
else
    echo -e "\n${BYellow}No domain entered — a self-signed certificate will be used.${NC}"
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
echo -e "${BCyan}      INSTALLING SSH & SSL PROTOCOLS         ${NC}"
echo -e "${BGreen}============================================${NC}"
echo ""

# ═══════════════════════════════════════════
# SECTION 1 — OPENSSH HARDENING
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
apply_sshd_setting "X11Forwarding"           "no"
apply_sshd_setting "MaxAuthTries"            "6"
apply_sshd_setting "ClientAliveInterval"     "60"
apply_sshd_setting "ClientAliveCountMax"     "3"
apply_sshd_setting "AllowTcpForwarding"      "yes"
apply_sshd_setting "UseDNS"                  "no"

systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1 || true
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
success "OpenSSH configured on port 22"

# ═══════════════════════════════════════════
# SECTION 2 — DROPBEAR
# ═══════════════════════════════════════════
info "Installing Dropbear (main port 80, extras 109 & 143)..."
eval "$APT dropbear" </dev/null >/dev/null 2>&1

mkdir -p /etc/dropbear
for TYPE in dss rsa ecdsa ed25519; do
    KEYFILE="/etc/dropbear/dropbear_${TYPE}_host_key"
    [ -f "$KEYFILE" ] || dropbearkey -t "$TYPE" -f "$KEYFILE" >/dev/null 2>&1 || true
done

grep -qxF '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells
grep -qxF '/usr/sbin/nologin' /etc/shells || echo '/usr/sbin/nologin' >> /etc/shells

cat > /etc/default/dropbear <<'EOF'
NO_START=0
DROPBEAR_PORT=80
DROPBEAR_EXTRA_ARGS="-p 109 -p 143 -I 60 -K 30"
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
EOF

systemctl enable dropbear >/dev/null 2>&1 || true
systemctl restart dropbear
success "Dropbear running on ports 80, 109 and 143"

# ═══════════════════════════════════════════
# SECTION 3 — WEBSOCKET → SSH PROXY
# ═══════════════════════════════════════════
info "Installing Python WebSocket-to-SSH proxy (port 8880)..."

cat > /usr/local/bin/ws-proxy.py <<'PYEOF'
#!/usr/bin/env python3
"""WebSocket-to-SSH bridge: 0.0.0.0:8880 -> Dropbear 127.0.0.1:109."""
import socket
import threading

TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
LISTEN_HOST = '0.0.0.0'
LISTEN_PORT = 8880
HANDSHAKE_TIMEOUT = 15


def forward(src, dst):
    try:
        while True:
            data = src.recv(8192)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        for s in (src, dst):
            try:
                s.close()
            except Exception:
                pass


def handle_client(client):
    client.settimeout(HANDSHAKE_TIMEOUT)
    ssh = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ssh.settimeout(HANDSHAKE_TIMEOUT)
    try:
        ssh.connect((TARGET_HOST, TARGET_PORT))
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = client.recv(1)
            if not chunk:
                return
            buf += chunk
        client.sendall(
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n\r\n"
        )
        client.settimeout(None)
        ssh.settimeout(None)
        t1 = threading.Thread(target=forward, args=(client, ssh), daemon=True)
        t2 = threading.Thread(target=forward, args=(ssh, client), daemon=True)
        t1.start(); t2.start(); t1.join(); t2.join()
    except Exception:
        pass
    finally:
        for s in (client, ssh):
            try:
                s.close()
            except Exception:
                pass


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((LISTEN_HOST, LISTEN_PORT))
    srv.listen(5000)
    print("ws-proxy on %s:%d -> %s:%d" % (LISTEN_HOST, LISTEN_PORT, TARGET_HOST, TARGET_PORT))
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

cat > /etc/systemd/system/ws-proxy.service <<'EOF'
[Unit]
Description=WebSocket-to-SSH proxy (port 8880 -> Dropbear 109)
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
success "WebSocket-SSH proxy running on port 8880"

# ═══════════════════════════════════════════
# SECTION 4 — SSL CERTIFICATE
# ═══════════════════════════════════════════
info "Setting up SSL certificate..."
eval "$APT stunnel4 openssl" </dev/null >/dev/null 2>&1
mkdir -p /etc/stunnel

if [ -n "$DOMAIN" ]; then
    info "Requesting Let's Encrypt certificate for $DOMAIN ..."
    eval "$APT certbot" </dev/null >/dev/null 2>&1 || true
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    # Dropbear holds port 80; free it so certbot can validate the domain
    systemctl stop dropbear 2>/dev/null || true
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
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=US/ST=NA/L=NA/O=SSHServer/CN=ssh-server" \
        -out "$STUNNEL_CERT" -keyout /etc/stunnel/stunnel.key >/dev/null 2>&1
    cat /etc/stunnel/stunnel.key >> "$STUNNEL_CERT"
    rm -f /etc/stunnel/stunnel.key
    success "Self-signed certificate created"
fi
chmod 600 "$STUNNEL_CERT"

# ═══════════════════════════════════════════
# SECTION 5 — STUNNEL (SSH-SSL)
# ═══════════════════════════════════════════
info "Configuring Stunnel SSL tunnels..."
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4 2>/dev/null || true

cat > /etc/stunnel/stunnel.conf <<EOF
pid     = /var/run/stunnel.pid
cert    = ${STUNNEL_CERT}
client  = no
socket  = a:SO_REUSEADDR=1
socket  = l:TCP_NODELAY=1
socket  = r:TCP_NODELAY=1

[dropbear-ssl]
accept  = 443
connect = 127.0.0.1:80

[ssh-ssl]
accept  = 447
connect = 127.0.0.1:22

[wss-bypass]
accept  = 444
connect = 127.0.0.1:8880
EOF

systemctl enable stunnel4 >/dev/null 2>&1 || true
systemctl restart stunnel4 >/dev/null 2>&1
success "Stunnel running — dropbear-ssl:443 | ssh-ssl:447 | wss-ssl:444"

# Ensure Dropbear is back up (it was stopped for cert issuance)
systemctl restart dropbear >/dev/null 2>&1 || true

# ═══════════════════════════════════════════
# SECTION 6 — FIREWALL
# ═══════════════════════════════════════════
info "Opening firewall ports..."
if command -v ufw >/dev/null 2>&1; then
    for P in 22 80 109 143 443 444 447 8880; do
        ufw allow ${P}/tcp >/dev/null 2>&1
    done
    success "UFW rules applied"
else
    warn "ufw not found — open TCP ports manually: 22 80 109 143 443 444 447 8880"
fi

# ═══════════════════════════════════════════
# SECTION 7 — INSTALL THE 'menu' COMMAND
# ═══════════════════════════════════════════
info "Installing management panel (menu command)..."

cat > /usr/local/bin/menu <<'MENUEOF'
#!/bin/bash
# =============================================================
# SSH SERVER MANAGEMENT PANEL
# Type "menu" any time to open this panel.
# =============================================================

BGreen='\033[1;32m'; BYellow='\033[1;33m'; BCyan='\033[1;36m'
BRed='\033[1;31m'; BPurple='\033[1;35m'; NC='\033[0m'

CONF_DIR=/etc/ssh-panel
DOMAIN=$(cat "$CONF_DIR/domain.conf" 2>/dev/null)
SERVER_IP=$(cat "$CONF_DIR/ip.conf" 2>/dev/null)
HOST_DISPLAY="${DOMAIN:-$SERVER_IP}"

[[ $EUID -ne 0 ]] && { echo -e "${BRed}Run as root: sudo menu${NC}"; exit 1; }

pause() { echo ""; read -rp "Press ENTER to return to the menu..." _; }

# ─── Create an SSH user ──────────────────────────────────────
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

    # Create a shell-less user (VPN/tunnel only, cannot open a real shell)
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
    echo -e "  ${BPurple}CONNECTION PORTS${NC}"
    echo -e "  Dropbear            : ${HOST_DISPLAY}:80 / 109 / 143"
    echo -e "  Dropbear over SSL   : ${HOST_DISPLAY}:443"
    echo -e "  OpenSSH             : ${HOST_DISPLAY}:22"
    echo -e "  OpenSSH over SSL    : ${HOST_DISPLAY}:447"
    echo -e "  SSH over WebSocket  : ws://${HOST_DISPLAY}:8880"
    echo -e "  SSH over WSS (TLS)  : wss://${HOST_DISPLAY}:444"
    echo -e "${BGreen}=========================================${NC}"
    pause
}

# ─── Delete an SSH user ──────────────────────────────────────
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

# ─── List SSH users ──────────────────────────────────────────
list_users() {
    clear
    echo -e "${BGreen}=========== SSH USER LIST ===========${NC}"
    printf "  %-20s %-12s %-8s\n" "USERNAME" "EXPIRES" "STATUS"
    echo   "  -------------------------------------------"
    # Managed users are shell-less (/bin/false or /usr/sbin/nologin)
    while IFS=: read -r user _ uid _ _ _ shell; do
        if [ "$uid" -ge 1000 ] && { [ "$shell" = "/bin/false" ] || [ "$shell" = "/usr/sbin/nologin" ]; }; then
            EXP=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
            [ "$EXP" = "never" ] && EXP="never"
            # Convert to short date if possible
            EXP_SHORT=$(date -d "$EXP" +"%Y-%m-%d" 2>/dev/null || echo "$EXP")
            if pgrep -u "$user" >/dev/null 2>&1; then STATUS="online"; else STATUS="offline"; fi
            printf "  %-20s %-12s %-8s\n" "$user" "$EXP_SHORT" "$STATUS"
        fi
    done < /etc/passwd
    pause
}

# ─── Show online users ───────────────────────────────────────
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

# ─── Change a user's password ────────────────────────────────
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

# ─── Renew (extend) an account ───────────────────────────────
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

# ─── Service status ──────────────────────────────────────────
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
    echo -e "  ${BCyan}Ports:${NC} 80/109/143 (dropbear) 443 (dropbear-ssl)"
    echo -e "         22 (ssh) 447 (ssh-ssl) 444 (wss) 8880 (ws)"
    pause
}

# ─── Restart all services ────────────────────────────────────
restart_services() {
    clear
    echo -e "${BYellow}Restarting all SSH/SSL services...${NC}"
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    systemctl restart dropbear 2>/dev/null
    systemctl restart ws-proxy 2>/dev/null
    systemctl restart stunnel4 2>/dev/null
    echo -e "${BGreen}All services restarted.${NC}"
    pause
}

# ─── Main menu loop ──────────────────────────────────────────
while true; do
    clear
    echo -e "${BGreen}==================================================${NC}"
    echo -e "${BCyan}            SSH SERVER MANAGEMENT PANEL           ${NC}"
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
echo -e "    Dropbear           → 80, 109, 143"
echo -e "    Dropbear over SSL  → 443"
echo -e "    OpenSSH            → 22"
echo -e "    OpenSSH over SSL   → 447"
echo -e "    SSH over WebSocket → 8880"
echo -e "    SSH over WSS (TLS) → 444"
echo ""
echo -e "${BGreen}============================================================${NC}"
echo -e "${BYellow}   Type ${BGreen}menu${BYellow} to open the management panel and create users.${NC}"
echo -e "${BGreen}============================================================${NC}"
echo ""
