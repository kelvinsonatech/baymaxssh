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

# ── palette ─────────────────────────────────────────────
NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'
B='\033[1;34m'; P='\033[1;35m'; C='\033[1;36m'; W='\033[1;37m'
GR='\033[0;90m'
# 256-colour accents
TEAL='\033[38;5;44m'; ORANGE='\033[38;5;208m'; PINK='\033[38;5;213m'
LIME='\033[38;5;118m'; SKY='\033[38;5;39m'; VIOLET='\033[38;5;99m'

# Keep legacy names working
BGreen="$G"; BYellow="$Y"; BCyan="$C"; BRed="$R"; BPurple="$P"

CONF_DIR=/etc/ssh-panel
DOMAIN=$(cat "$CONF_DIR/domain.conf" 2>/dev/null)
SERVER_IP=$(cat "$CONF_DIR/ip.conf" 2>/dev/null)
HOST_DISPLAY="${DOMAIN:-$SERVER_IP}"

[[ $EUID -ne 0 ]] && { echo -e "${R}Run as root: sudo menu${NC}"; exit 1; }

WIDTH=60   # inner width of the frames

# ── frame drawing helpers ───────────────────────────────
# strip ANSI codes to measure real text length
_vislen() { local s; s=$(echo -ne "$1" | sed 's/\x1b\[[0-9;]*m//g'); echo -n "${#s}"; }

line_top()  { echo -e "${1}╭$(printf '─%.0s' $(seq 1 $WIDTH))╮${NC}"; }
line_mid()  { echo -e "${1}├$(printf '─%.0s' $(seq 1 $WIDTH))┤${NC}"; }
line_bot()  { echo -e "${1}╰$(printf '─%.0s' $(seq 1 $WIDTH))╯${NC}"; }
line_fill() { echo -e "${1}│$(printf ' %.0s' $(seq 1 $WIDTH))│${NC}"; }

# row "border-color" "text-with-ansi"
row() {
    local col="$1" text="$2" len pad
    len=$(_vislen "$text")
    pad=$(( WIDTH - 2 - len ))
    (( pad < 0 )) && pad=0
    echo -e "${col}│${NC} ${text}$(printf ' %.0s' $(seq 1 $pad)) ${col}│${NC}"
}
# centered row
crow() {
    local col="$1" text="$2" len left right
    len=$(_vislen "$text")
    left=$(( (WIDTH - len) / 2 )); right=$(( WIDTH - len - left ))
    (( left < 0 )) && left=0; (( right < 0 )) && right=0
    echo -e "${col}│${NC}$(printf ' %.0s' $(seq 1 $left))${text}$(printf ' %.0s' $(seq 1 $right))${col}│${NC}"
}

pause() { echo ""; read -rp "$(echo -e "  ${GR}↵  press ENTER to go back${NC} ")" _; }

# count tunnel users / online
count_users()  { awk -F: '$3>=1000 && ($7=="/bin/false"||$7=="/usr/sbin/nologin"){c++} END{print c+0}' /etc/passwd; }
count_online() {
    local n=0 u uid sh
    while IFS=: read -r u _ uid _ _ _ sh; do
        if [ "$uid" -ge 1000 ] 2>/dev/null && { [ "$sh" = "/bin/false" ] || [ "$sh" = "/usr/sbin/nologin" ]; }; then
            pgrep -u "$u" >/dev/null 2>&1 && n=$((n+1))
        fi
    done < /etc/passwd
    echo "$n"
}

banner() {
    clear
    echo ""
    echo -e "   ${TEAL} ██████╗ ██████╗ ${SKY}██╗   ██╗${PINK}██████╗ ███╗   ██╗${NC}"
    echo -e "   ${TEAL}██╔════╝██╔════╝ ${SKY}██║   ██║${PINK}██╔══██╗████╗  ██║${NC}"
    echo -e "   ${TEAL}╚█████╗ ╚█████╗  ${SKY}███████║${PINK}██████╔╝██╔██╗ ██║${NC}"
    echo -e "   ${TEAL} ╚═══██╗ ╚═══██╗ ${SKY}██╔══██║${PINK}██╔═══╝ ██║╚██╗██║${NC}"
    echo -e "   ${TEAL}██████╔╝██████╔╝ ${SKY}██║  ██║${PINK}██║     ██║ ╚████║${NC}"
    echo -e "   ${TEAL}╚═════╝ ╚═════╝  ${SKY}╚═╝  ╚═╝${PINK}╚═╝     ╚═╝  ╚═══╝${NC}"
    echo -e "        ${GR}ws · ssl · dropbear · openssh manager${NC}"
    echo ""
}

status_bar() {
    local col="$P" s dot
    line_top "$col"
    crow "$col" "${W}${BOLD}SSH VPN CONTROL PANEL${NC}"
    line_mid "$col"
    row "$col" "${GR}HOST${NC}    ${Y}${HOST_DISPLAY}${NC}"
    row "$col" "${GR}USERS${NC}   ${C}$(count_users)${NC} total   ${LIME}$(count_online)${NC} online"
    local svcline="${GR}SVC${NC}    "
    for s in ssh dropbear ws-proxy stunnel4; do
        if systemctl is-active --quiet "$s" 2>/dev/null; then dot="${G}●${NC}"; else dot="${R}○${NC}"; fi
        svcline+="${dot} ${s}   "
    done
    row "$col" "$svcline"
    line_bot "$col"
}

show_ports() {
    local col="$SKY"
    line_top "$col"
    crow "$col" "${W}${BOLD}CONNECTION PORTS${NC}"
    line_mid "$col"
    row "$col" "${LIME}▸${NC} WebSocket (payload)  ${GR}→${NC} ${W}${HOST_DISPLAY}:80${NC}"
    row "$col" "${LIME}▸${NC} SSL + payload (TLS)  ${GR}→${NC} ${W}${HOST_DISPLAY}:443${NC}"
    row "$col" "${LIME}▸${NC} SSL direct SSH       ${GR}→${NC} ${W}${HOST_DISPLAY}:447${NC}"
    row "$col" "${LIME}▸${NC} OpenSSH              ${GR}→${NC} ${W}${HOST_DISPLAY}:22${NC}"
    row "$col" "${LIME}▸${NC} Dropbear             ${GR}→${NC} ${W}${HOST_DISPLAY}:109 / 143${NC}"
    line_bot "$col"
}

section() {  # section "TITLE" color
    local col="${2:-$TEAL}"
    banner
    line_top "$col"; crow "$col" "${W}${BOLD}$1${NC}"; line_bot "$col"
    echo ""
}

ok()   { echo -e "  ${G}✔${NC} $*"; }
err()  { echo -e "  ${R}✘${NC} $*"; }
note() { echo -e "  ${Y}➜${NC} $*"; }

create_user() {
    section "CREATE SSH USER" "$LIME"
    read -rp "$(echo -e "  ${C}Username${NC}   : ")" USERNAME
    [ -z "$USERNAME" ] && { err "Username cannot be empty."; pause; return; }
    if id "$USERNAME" >/dev/null 2>&1; then
        err "User '${W}$USERNAME${NC}' already exists."; pause; return
    fi
    read -rp "$(echo -e "  ${C}Password${NC}   : ")" PASSWORD
    [ -z "$PASSWORD" ] && { err "Password cannot be empty."; pause; return; }
    read -rp "$(echo -e "  ${C}Days valid${NC} : ")" DAYS
    [[ ! "$DAYS" =~ ^[0-9]+$ ]] && DAYS=30
    EXP_DATE=$(date -d "+$DAYS days" +"%Y-%m-%d")

    useradd -e "$EXP_DATE" -M -s /bin/false "$USERNAME"
    echo -e "${PASSWORD}\n${PASSWORD}" | passwd "$USERNAME" >/dev/null 2>&1

    banner
    local col="$G"
    line_top "$col"; crow "$col" "${W}${BOLD}✔ ACCOUNT CREATED${NC}"; line_mid "$col"
    row "$col" "${GR}Host${NC}      ${Y}${HOST_DISPLAY}${NC}"
    row "$col" "${GR}Username${NC}  ${W}${USERNAME}${NC}"
    row "$col" "${GR}Password${NC}  ${W}${PASSWORD}${NC}"
    row "$col" "${GR}Expires${NC}   ${W}${EXP_DATE}${NC}  ${GR}(${DAYS} days)${NC}"
    line_bot "$col"
    show_ports
    local col2="$VIOLET"
    line_top "$col2"; crow "$col2" "${W}${BOLD}CLIENT PAYLOAD / SNI${NC}"; line_mid "$col2"
    row "$col2" "${GR}WS payload${NC}"
    row "$col2" "${DIM}GET / HTTP/1.1[crlf]Host: ${HOST_DISPLAY}[crlf]${NC}"
    row "$col2" "${DIM}Upgrade: websocket[crlf][crlf]${NC}"
    row "$col2" "${GR}SSL / SNI host${NC}  ${W}${HOST_DISPLAY}${NC}"
    line_bot "$col2"
    pause
}

delete_user() {
    section "DELETE SSH USER" "$R"
    read -rp "$(echo -e "  ${C}Username to delete${NC} : ")" USERNAME
    if ! id "$USERNAME" >/dev/null 2>&1; then
        err "User '${W}$USERNAME${NC}' does not exist."; pause; return
    fi
    pkill -u "$USERNAME" 2>/dev/null
    userdel -f "$USERNAME" >/dev/null 2>&1
    ok "User '${W}$USERNAME${NC}' deleted."
    pause
}

list_users() {
    section "SSH USER LIST" "$SKY"
    local col="$SKY"
    line_top "$col"
    row "$col" "$(printf '%-18s %-12s %-8s' 'USERNAME' 'EXPIRES' 'STATUS')"
    line_mid "$col"
    local any=0
    while IFS=: read -r user _ uid _ _ _ shell; do
        if [ "$uid" -ge 1000 ] && { [ "$shell" = "/bin/false" ] || [ "$shell" = "/usr/sbin/nologin" ]; }; then
            any=1
            EXP=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
            EXP_SHORT=$(date -d "$EXP" +"%Y-%m-%d" 2>/dev/null || echo "$EXP")
            if pgrep -u "$user" >/dev/null 2>&1; then
                STAT="${G}● online${NC}"
            else
                STAT="${GR}○ offline${NC}"
            fi
            row "$col" "$(printf '%-18s %-12s' "$user" "$EXP_SHORT")${STAT}"
        fi
    done < /etc/passwd
    [ "$any" -eq 0 ] && row "$col" "${GR}(no users yet — create one from the menu)${NC}"
    line_bot "$col"
    pause
}

online_users() {
    section "ONLINE USERS" "$LIME"
    local col="$LIME"
    line_top "$col"
    row "$col" "$(printf '%-22s %-10s' 'USERNAME' 'SESSIONS')"
    line_mid "$col"
    local any=0
    while IFS=: read -r user _ uid _ _ _ shell; do
        if [ "$uid" -ge 1000 ] && { [ "$shell" = "/bin/false" ] || [ "$shell" = "/usr/sbin/nologin" ]; }; then
            COUNT=$(pgrep -u "$user" 2>/dev/null | wc -l)
            if [ "$COUNT" -gt 0 ]; then
                any=1
                row "$col" "$(printf '%-22s ' "$user")${C}${COUNT}${NC}"
            fi
        fi
    done < /etc/passwd
    [ "$any" -eq 0 ] && row "$col" "${GR}(nobody connected right now)${NC}"
    line_bot "$col"
    pause
}

change_password() {
    section "CHANGE PASSWORD" "$ORANGE"
    read -rp "$(echo -e "  ${C}Username${NC}     : ")" USERNAME
    if ! id "$USERNAME" >/dev/null 2>&1; then
        err "User does not exist."; pause; return
    fi
    read -rp "$(echo -e "  ${C}New password${NC} : ")" PASSWORD
    [ -z "$PASSWORD" ] && { err "Password cannot be empty."; pause; return; }
    echo -e "${PASSWORD}\n${PASSWORD}" | passwd "$USERNAME" >/dev/null 2>&1
    ok "Password updated for '${W}$USERNAME${NC}'."
    pause
}

renew_user() {
    section "RENEW / EXTEND ACCOUNT" "$VIOLET"
    read -rp "$(echo -e "  ${C}Username${NC} : ")" USERNAME
    if ! id "$USERNAME" >/dev/null 2>&1; then
        err "User does not exist."; pause; return
    fi
    read -rp "$(echo -e "  ${C}Add days${NC} : ")" DAYS
    [[ ! "$DAYS" =~ ^[0-9]+$ ]] && DAYS=30
    NEW_EXP=$(date -d "+$DAYS days" +"%Y-%m-%d")
    chage -E "$NEW_EXP" "$USERNAME"
    ok "'${W}$USERNAME${NC}' now expires on ${W}$NEW_EXP${NC}."
    pause
}

service_status() {
    section "SERVICE STATUS" "$P"
    local col="$P"
    line_top "$col"
    for svc in ssh dropbear ws-proxy stunnel4; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            row "$col" "${G}● RUNNING${NC}   ${W}$svc${NC}"
        else
            row "$col" "${R}○ STOPPED${NC}   ${W}$svc${NC}"
        fi
    done
    line_bot "$col"
    show_ports
    pause
}

restart_services() {
    section "RESTART ALL SERVICES" "$ORANGE"
    note "Restarting services, please wait..."
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    systemctl restart dropbear 2>/dev/null
    systemctl restart ws-proxy 2>/dev/null
    systemctl restart stunnel4 2>/dev/null
    ok "All services restarted."
    pause
}

menu_item() {  # menu_item NUM ICON "Label" color
    echo -e "  ${4}${BOLD}$1${NC} ${GR}│${NC} ${4}$2${NC}  ${W}$3${NC}"
}

while true; do
    banner
    status_bar
    echo ""
    menu_item "1" "➕" "Create SSH user"          "$LIME"
    menu_item "2" "🗑 " "Delete SSH user"          "$R"
    menu_item "3" "📋" "List all users"           "$SKY"
    menu_item "4" "🟢" "Show online users"        "$G"
    menu_item "5" "🔑" "Change user password"     "$ORANGE"
    menu_item "6" "♻️ " "Renew / extend account"   "$VIOLET"
    menu_item "7" "📊" "Service status"           "$C"
    menu_item "8" "🔄" "Restart all services"     "$Y"
    menu_item "0" "🚪" "Exit"                     "$GR"
    echo ""
    read -rp "$(echo -e "  ${P}❯${NC} select an option : ")" OPT
    case "$OPT" in
        1) create_user ;;
        2) delete_user ;;
        3) list_users ;;
        4) online_users ;;
        5) change_password ;;
        6) renew_user ;;
        7) service_status ;;
        8) restart_services ;;
        0) clear; echo -e "  ${G}Goodbye 👋${NC}\n"; exit 0 ;;
        *) echo -e "  ${R}Invalid option.${NC}"; sleep 1 ;;
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
