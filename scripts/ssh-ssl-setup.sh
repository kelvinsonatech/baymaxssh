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
# extended palette for the advanced installer UI
BOLD='\033[1m'; DIM='\033[2m'
TEAL='\033[38;5;44m'; SKY='\033[38;5;39m'; LIME='\033[38;5;155m'
GRY='\033[38;5;240m'; BWHITE='\033[97m'; PINK='\033[38;5;213m'; ORANGE='\033[38;5;208m'
export LANG=C.UTF-8 LC_ALL=C.UTF-8 2>/dev/null || true

# During the phased install, info/success are silenced so the single animated
# progress bar stays on one clean line; warn/error still print (problems only).
UI_SILENT=0
info()    { [ "$UI_SILENT" = "1" ] && return 0; echo -e "${BCyan}[*] $*${NC}"; }
success() { [ "$UI_SILENT" = "1" ] && return 0; echo -e "${BGreen}[✓] $*${NC}"; }
warn()    { echo -e "${BYellow}[!] $*${NC}"; }
error()   { echo -e "${BRed}[✗] $*${NC}"; exit 1; }

# ── advanced installer progress HUD (single animated gradient bar) ──
INSTALL_TOTAL=12; INSTALL_STEP=0; PROG_PCT=0; INSTALL_T0=$SECONDS
# simple, fast progress bar — drawn once per phase, zero added delay
_TW=$(tput cols 2>/dev/null || echo 64); [ "$_TW" -gt 76 ] && _TW=76; [ "$_TW" -lt 44 ] && _TW=44
phase() {  # phase "Title" — one instant redraw of the single progress line
    INSTALL_STEP=$(( INSTALL_STEP + 1 ))
    local t="$1" pct bw fl em el i fill="" track=""
    pct=$(( INSTALL_STEP * 100 / INSTALL_TOTAL ))
    bw=$(( _TW - 40 )); [ "$bw" -lt 12 ] && bw=12
    fl=$(( bw * pct / 100 )); em=$(( bw - fl )); el=$(( SECONDS - INSTALL_T0 ))
    i=0; while [ "$i" -lt "$fl" ]; do fill="${fill}█"; i=$(( i + 1 )); done
    i=0; while [ "$i" -lt "$em" ]; do track="${track}░"; i=$(( i + 1 )); done
    printf "\r\033[K ${GRY}[${BWHITE}%2d${GRY}/%d]${NC} ${SKY}◆${NC} ${BWHITE}%-16.16s${NC} ${TEAL}%s${GRY}%s${NC} ${TEAL}${BOLD}%3d%%${NC} ${GRY}%02ds${NC}" \
        "$INSTALL_STEP" "$INSTALL_TOTAL" "$t" "$fill" "$track" "$pct" "$el"
    if [ "$INSTALL_STEP" -ge "$INSTALL_TOTAL" ]; then printf "\n"; fi
}

[[ $EUID -ne 0 ]] && error "This script must be run as root."

CONF_DIR=/etc/ssh-panel
mkdir -p "$CONF_DIR"
STUNNEL_CERT=/etc/stunnel/stunnel.pem

# ═══════════════════════════════════════════
# ASK FOR DOMAIN
# ═══════════════════════════════════════════
clear
printf '\033[?25l'   # hide cursor for the intro animation
# gradient ASCII banner, revealed line-by-line
_banner=(
"    ███████╗███████╗██╗  ██╗    ██╗   ██╗██████╗ ███╗   ██╗"
"    ██╔════╝██╔════╝██║  ██║    ██║   ██║██╔══██╗████╗  ██║"
"    ███████╗███████╗███████║    ██║   ██║██████╔╝██╔██╗ ██║"
"    ╚════██║╚════██║██╔══██║    ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║"
"    ███████║███████║██║  ██║     ╚████╔╝ ██║     ██║ ╚████║"
"    ╚══════╝╚══════╝╚═╝  ╚═╝      ╚═══╝  ╚═╝     ╚═╝  ╚═══╝"
)
_grad=('\033[38;5;201m' '\033[38;5;165m' '\033[38;5;39m' '\033[38;5;51m' '\033[38;5;46m' '\033[38;5;226m')
echo ""
for i in "${!_banner[@]}"; do
    echo -e "  ${_grad[$i]}${BOLD}${_banner[$i]}${NC}"
    sleep 0.05
done
echo -e "         ${GRY}ws${NC} ${DIM}·${NC} ${GRY}ssl${NC} ${DIM}·${NC} ${GRY}openssh${NC} ${DIM}·${NC} ${GRY}dropbear${NC} ${DIM}·${NC} ${GRY}v2ray${NC}   ${BWHITE}${BOLD}server installer${NC}"
echo ""
printf '\033[?25h'   # restore cursor for the prompt

# ── styled domain prompt ──
echo -e "  ${TEAL}╭──────────────────────────────────────────────────────╮${NC}"
echo -e "  ${TEAL}│${NC}  ${BWHITE}${BOLD}DOMAIN SETUP${NC}                                        ${TEAL}│${NC}"
echo -e "  ${TEAL}├──────────────────────────────────────────────────────┤${NC}"
echo -e "  ${TEAL}│${NC}  ${GRY}Enter a domain pointed at this server, or leave${NC}     ${TEAL}│${NC}"
echo -e "  ${TEAL}│${NC}  ${GRY}blank to use a self-signed certificate (connect${NC}     ${TEAL}│${NC}"
echo -e "  ${TEAL}│${NC}  ${GRY}by IP).${NC}                                              ${TEAL}│${NC}"
echo -e "  ${TEAL}╰──────────────────────────────────────────────────────╯${NC}"
echo ""
read -rp "$(echo -e "   ${SKY}❯${NC} ${BWHITE}Domain${NC} ${GRY}(blank = self-signed)${NC} : ")" DOMAIN
DOMAIN="$(echo "$DOMAIN" | tr -d '[:space:]')"

# ── SlowDNS (DNSTT) nameserver prompt ──
echo ""
echo -e "  ${TEAL}╭──────────────────────────────────────────────────────╮${NC}"
echo -e "  ${TEAL}│${NC}  ${BWHITE}${BOLD}SLOWDNS SETUP${NC} ${GRY}(optional)${NC}                             ${TEAL}│${NC}"
echo -e "  ${TEAL}├──────────────────────────────────────────────────────┤${NC}"
echo -e "  ${TEAL}│${NC}  ${GRY}Enter the NS host delegated to this server's IP${NC}     ${TEAL}│${NC}"
echo -e "  ${TEAL}│${NC}  ${GRY}(e.g. dns.example.com). Requires an NS + A record${NC}   ${TEAL}│${NC}"
echo -e "  ${TEAL}│${NC}  ${GRY}at your DNS host. Leave blank to skip SlowDNS.${NC}      ${TEAL}│${NC}"
echo -e "  ${TEAL}╰──────────────────────────────────────────────────────╯${NC}"
echo ""
read -rp "$(echo -e "   ${SKY}❯${NC} ${BWHITE}NS domain${NC} ${GRY}(blank = skip)${NC} : ")" NS_DOMAIN
NS_DOMAIN="$(echo "$NS_DOMAIN" | tr -d '[:space:]')"

apt-get install -y curl >/dev/null 2>&1 || true
SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
echo "$DOMAIN"    > "$CONF_DIR/domain.conf"
echo "$SERVER_IP" > "$CONF_DIR/ip.conf"
echo "$NS_DOMAIN" > "$CONF_DIR/nsdomain.conf"

# ── system info panel ──
_OS=$( (. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME") || echo "Linux" )
echo ""
echo -e "  ${GRY}┌─ ${BWHITE}${BOLD}SYSTEM${NC} ${GRY}────────────────────────────────────────────┐${NC}"
printf  "  ${GRY}│${NC}  ${SKY}◆${NC} %-11s ${BWHITE}%-33.33s${NC}${GRY}│${NC}\n" "Server IP" "$SERVER_IP"
printf  "  ${GRY}│${NC}  ${SKY}◆${NC} %-11s ${BWHITE}%-33.33s${NC}${GRY}│${NC}\n" "OS" "$_OS"
if [ -n "$DOMAIN" ]; then
    printf "  ${GRY}│${NC}  ${SKY}◆${NC} %-11s ${LIME}%-33.33s${NC}${GRY}│${NC}\n" "TLS mode" "domain: $DOMAIN"
else
    printf "  ${GRY}│${NC}  ${SKY}◆${NC} %-11s ${BWHITE}%-33.33s${NC}${GRY}│${NC}\n" "TLS mode" "self-signed (connect by IP)"
fi
printf  "  ${GRY}│${NC}  ${SKY}◆${NC} %-11s ${BWHITE}%-33.33s${NC}${GRY}│${NC}\n" "Steps" "$INSTALL_TOTAL install phases"
echo -e "  ${GRY}└──────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  ${TEAL}${BOLD}▸ Installing — sit tight${NC}${GRY}, this runs itself.${NC}"
echo ""
sleep 0.4
UI_SILENT=1   # from here on, the single progress bar is the only output

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

phase "System packages"
apt-get update -y </dev/null >/dev/null 2>&1

# ═══════════════════════════════════════════
# SECTION 1 — OPENSSH
# ═══════════════════════════════════════════
phase "OpenSSH server"
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
phase "Dropbear SSH"
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
# SECTION 2b — SLOWDNS (DNSTT) over UDP 53
# ═══════════════════════════════════════════
phase "SlowDNS (DNSTT)"
NS_DOMAIN=$(cat "$CONF_DIR/nsdomain.conf" 2>/dev/null)
if [ -n "$NS_DOMAIN" ]; then
    systemctl stop slowdns >/dev/null 2>&1 || true
    killall dnstt-server >/dev/null 2>&1 || true

    # Toolchain: prefer distro golang; fall back to snap.
    eval "$APT git golang-go" </dev/null >/dev/null 2>&1
    GO_BIN="$(command -v go || echo /usr/local/go/bin/go)"
    if [ ! -x "$GO_BIN" ] && ! command -v go >/dev/null 2>&1; then
        eval "$APT snapd" </dev/null >/dev/null 2>&1
        systemctl enable --now snapd.socket >/dev/null 2>&1 || true
        [ -L /snap ] || ln -s /var/lib/snapd/snap /snap >/dev/null 2>&1 || true
        snap install go --classic >/dev/null 2>&1 || true
        GO_BIN=/snap/bin/go
    fi

    # Build dnstt-server if we don't already have the binary.
    if [ ! -x /usr/local/bin/dnstt-server ] && [ -x "$GO_BIN" ]; then
        cd /root; rm -rf dnstt
        git clone https://www.bamsoftware.com/git/dnstt.git >/dev/null 2>&1
        if [ -d dnstt/dnstt-server ]; then
            ( cd dnstt/dnstt-server && "$GO_BIN" build >/dev/null 2>&1 \
              && mv dnstt-server /usr/local/bin/dnstt-server \
              && chmod +x /usr/local/bin/dnstt-server )
        fi
    fi

    if [ -x /usr/local/bin/dnstt-server ]; then
        mkdir -p /etc/slowdns
        if [ ! -f /etc/slowdns/server.key ]; then
            /usr/local/bin/dnstt-server -gen-key \
                -privkey-file /etc/slowdns/server.key \
                -pubkey-file /etc/slowdns/server.pub >/dev/null 2>&1
        fi
        cp -f /etc/slowdns/server.pub "$CONF_DIR/slowdns_pub.txt" 2>/dev/null || true

        cat > /etc/systemd/system/slowdns.service <<EOF
[Unit]
Description=SlowDNS Tunnel Server
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/slowdns
ExecStart=/usr/local/bin/dnstt-server -udp :53 -privkey-file /etc/slowdns/server.key ${NS_DOMAIN} 127.0.0.1:22
Restart=always
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable slowdns >/dev/null 2>&1 || true
        systemctl restart slowdns >/dev/null 2>&1 || true
        success "SlowDNS running on UDP 53 (NS: $NS_DOMAIN)"
    else
        warn "SlowDNS skipped — Go toolchain unavailable, could not build dnstt-server"
    fi
else
    info "SlowDNS skipped — no NS domain provided"
fi

# ═══════════════════════════════════════════
# SECTION 3 — DUAL-MODE WEBSOCKET/SSH PROXY (port 80)
# ═══════════════════════════════════════════
phase "WebSocket proxy"

# Remove any leftover Python proxy from a previous install.
rm -f /usr/local/bin/ws-proxy.py 2>/dev/null || true

# --- Ensure a Go compiler is available -----------------------------------
if ! command -v go >/dev/null 2>&1; then
    info "Installing Go toolchain..."
    eval "$APT golang-go" </dev/null >/dev/null 2>&1 || true
fi
GO_BIN="$(command -v go || true)"

BUILD_DIR=/tmp/ws-proxy-build
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

cat > "$BUILD_DIR/main.go" <<'GOEOF'
// Dual-mode WebSocket/SSH proxy (compiled).
//
// Listens on 0.0.0.0:80. For each connection it peeks at the first bytes:
//   * If the client speaks SSH directly (data begins with "SSH-"), the
//     connection is tunnelled straight to the backend SSH server.
//   * Otherwise the bytes are treated as an HTTP/WebSocket payload: the
//     proxy replies "HTTP/1.1 101 Switching Protocols" and tunnels to SSH.
//   * If nothing arrives quickly, it assumes a direct SSH client waiting
//     for the banner and tunnels straight through.
//
// Backend SSH = Dropbear on 127.0.0.1:109.
package main

import (
	"bytes"
	"io"
	"log"
	"net"
	"time"
)

const (
	listenAddr  = "0.0.0.0:80"
	backendAddr = "127.0.0.1:109"
	peekTimeout = 3 * time.Second
)

var response = []byte("HTTP/1.1 101 Switching Protocols\r\n" +
	"Upgrade: websocket\r\n" +
	"Connection: Upgrade\r\n\r\n")

func pipe(dst, src net.Conn, done chan struct{}) {
	buf := make([]byte, 65536)
	io.CopyBuffer(dst, src, buf)
	if c, ok := dst.(*net.TCPConn); ok {
		c.CloseWrite()
	}
	done <- struct{}{}
}

func bridge(client, backend net.Conn, prefix []byte) {
	if len(prefix) > 0 {
		backend.Write(prefix)
	}
	done := make(chan struct{}, 2)
	go pipe(backend, client, done)
	go pipe(client, backend, done)
	<-done
	<-done
	client.Close()
	backend.Close()
}

func handle(client net.Conn) {
	backend, err := net.Dial("tcp", backendAddr)
	if err != nil {
		client.Close()
		return
	}

	first := make([]byte, 4096)
	client.SetReadDeadline(time.Now().Add(peekTimeout))
	n, _ := client.Read(first)
	client.SetReadDeadline(time.Time{})
	head := first[:n]

	// Direct SSH client (or nothing yet): forward straight through.
	if n == 0 || bytes.HasPrefix(head, []byte("SSH-")) {
		bridge(client, backend, head)
		return
	}

	// HTTP / WebSocket payload: read the rest of the request headers.
	buf := append([]byte{}, head...)
	for !bytes.Contains(buf, []byte("\r\n\r\n")) && len(buf) < 8192 {
		client.SetReadDeadline(time.Now().Add(peekTimeout))
		m, e := client.Read(first)
		client.SetReadDeadline(time.Time{})
		if m > 0 {
			buf = append(buf, first[:m]...)
		}
		if e != nil {
			break
		}
	}

	if _, err := client.Write(response); err != nil {
		client.Close()
		backend.Close()
		return
	}
	bridge(client, backend, nil)
}

func main() {
	ln, err := net.Listen("tcp", listenAddr)
	if err != nil {
		log.Fatalf("listen %s: %v", listenAddr, err)
	}
	log.Printf("dual-mode proxy on %s -> SSH %s", listenAddr, backendAddr)
	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		if tc, ok := conn.(*net.TCPConn); ok {
			tc.SetNoDelay(true)
		}
		go handle(conn)
	}
}
GOEOF

BUILT=0
if [ -n "$GO_BIN" ]; then
    ( cd "$BUILD_DIR" && \
      GOFLAGS=-mod=mod GO111MODULE=off GOCACHE=/tmp/go-cache \
      "$GO_BIN" build -ldflags "-s -w" -o /usr/local/bin/ws-proxy main.go ) \
      >/dev/null 2>&1 && [ -x /usr/local/bin/ws-proxy ] && BUILT=1
fi

if [ "$BUILT" -eq 1 ]; then
    PROXY_EXEC=/usr/local/bin/ws-proxy
    success "Compiled Go proxy installed (port 80)"
else
    # ---- Fallback: Python proxy (if Go could not be installed/built) ----
    warn "Go build unavailable — falling back to Python proxy"
    eval "$APT python3" </dev/null >/dev/null 2>&1 || true
    cat > /usr/local/bin/ws-proxy.py <<'PYEOF'
#!/usr/bin/env python3
import socket, threading
BACKEND=('127.0.0.1',109); LISTEN=('0.0.0.0',80); T=3
RESP=b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
def pipe(s,d):
    try:
        while True:
            b=s.recv(65536)
            if not b: break
            d.sendall(b)
    except Exception: pass
    finally:
        for x in (s,d):
            try: x.shutdown(socket.SHUT_RDWR)
            except Exception: pass
            try: x.close()
            except Exception: pass
def bridge(c,b,pre=b""):
    if pre:
        try: b.sendall(pre)
        except Exception: pass
    t1=threading.Thread(target=pipe,args=(c,b),daemon=True)
    t2=threading.Thread(target=pipe,args=(b,c),daemon=True)
    t1.start();t2.start();t1.join();t2.join()
def handle(c):
    b=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    try: b.connect(BACKEND)
    except Exception: c.close(); return
    f=b""
    try:
        c.settimeout(T); f=c.recv(4096)
    except socket.timeout: f=b""
    except Exception: c.close(); b.close(); return
    finally:
        try: c.settimeout(None)
        except Exception: pass
    if f.startswith(b"SSH-") or f==b"":
        try: bridge(c,b,f)
        finally: c.close(); b.close()
        return
    buf=f
    try:
        c.settimeout(T)
        while b"\r\n\r\n" not in buf and len(buf)<8192:
            m=c.recv(4096)
            if not m: break
            buf+=m
    except Exception: pass
    finally:
        try: c.settimeout(None)
        except Exception: pass
    try: c.sendall(RESP)
    except Exception: c.close(); b.close(); return
    try: bridge(c,b)
    finally: c.close(); b.close()
def main():
    s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    s.bind(LISTEN); s.listen(1024)
    while True:
        try:
            c,_=s.accept()
            threading.Thread(target=handle,args=(c,),daemon=True).start()
        except Exception: pass
main()
PYEOF
    chmod +x /usr/local/bin/ws-proxy.py
    PROXY_EXEC="/usr/bin/python3 /usr/local/bin/ws-proxy.py"
fi

cat > /etc/systemd/system/ws-proxy.service <<EOF
[Unit]
Description=Dual-mode WebSocket/SSH proxy (port 80 -> Dropbear 109)
After=network.target dropbear.service

[Service]
Type=simple
User=root
ExecStart=${PROXY_EXEC}
LimitNOFILE=1048576
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
phase "SSL certificate"
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
phase "Stunnel TLS"
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
phase "Firewall rules"
if command -v ufw >/dev/null 2>&1; then
    for P in 22 80 109 143 443 447; do
        ufw allow ${P}/tcp >/dev/null 2>&1
    done
    ufw allow 53/udp >/dev/null 2>&1
    success "UFW rules applied"
else
    warn "ufw not found — open ports manually: TCP 22 80 109 143 443 447, UDP 53"
fi

# ═══════════════════════════════════════════
# SECTION 6b — BANDWIDTH MONITOR (vnstat)
# ═══════════════════════════════════════════
phase "Bandwidth monitor"
eval "$APT vnstat" </dev/null >/dev/null 2>&1 || true
# Detect the primary network interface and register it with vnstat.
PRIMARY_IFACE=$(ip route 2>/dev/null | awk '/default/{print $5; exit}')
[ -z "$PRIMARY_IFACE" ] && PRIMARY_IFACE=$(ls /sys/class/net 2>/dev/null | grep -v lo | head -n1)
if [ -n "$PRIMARY_IFACE" ]; then
    echo "$PRIMARY_IFACE" > "$CONF_DIR/iface.conf"
    vnstat --add -i "$PRIMARY_IFACE" >/dev/null 2>&1 || true
fi
systemctl enable vnstat >/dev/null 2>&1 || true
systemctl restart vnstat >/dev/null 2>&1 || true
success "Bandwidth monitor active on ${PRIMARY_IFACE:-auto}"

# ═══════════════════════════════════════════
# SECTION 6c — XRAY HELPER SCRIPTS (config generator + quota/expiry checker)
#   These are installed but Xray itself stays OFF until activated in the menu.
# ═══════════════════════════════════════════
phase "Xray / V2Ray"

# --- config generator: rebuilds Xray config from the accounts file --------
cat > /usr/local/bin/xray-gen <<'XGEOF'
#!/bin/bash
CONF_DIR=/etc/ssh-panel
XACC=/etc/xray/accounts.txt
XCONF=/usr/local/etc/xray/config.json
XAPI=10085
# VMess ports
VM_WS_TLS=8443; VM_WS_NONE=8080; VM_HTTP_NONE=8081; VM_HTTP_TLS=8444; VM_SPLIT_TLS=8445; VM_SPLIT_NONE=8082
# VLESS ports
VL_WS_TLS=8446; VL_WS_NONE=8083; VL_HTTP_NONE=8084; VL_HTTP_TLS=8447; VL_SPLIT_TLS=8448; VL_SPLIT_NONE=8085
# Trojan ports (TLS only)
TR_TCP_TLS=8449; TR_WS_TLS=8450; TR_SPLIT_TLS=8451
# If the operator handed port 443 to V2Ray (SSL payload disabled), move that
# protocol's WS-TLS listener onto 443.
P443=$(cat /etc/xray/port443 2>/dev/null)
case "$P443" in
    vmess)  VM_WS_TLS=443;;
    vless)  VL_WS_TLS=443;;
    trojan) TR_WS_TLS=443;;
esac
mkdir -p /etc/xray /usr/local/etc/xray; touch "$XACC"
DOMAIN=$(cat "$CONF_DIR/domain.conf" 2>/dev/null)
HOST="${DOMAIN:-$(cat "$CONF_DIR/ip.conf" 2>/dev/null)}"
if [ -n "$DOMAIN" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"; KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
else
    [ -f /etc/xray/xray.crt ] || openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/CN=${HOST:-xray}" -out /etc/xray/xray.crt -keyout /etc/xray/xray.key >/dev/null 2>&1
    CERT=/etc/xray/xray.crt; KEY=/etc/xray/xray.key
fi

# Build per-protocol client lists from the accounts file.
# Record format: proto|remark|secret|expiry|quota   (legacy 4-field = vmess)
VMESS=""; VLESS=""; TROJAN=""
_add() { case "$1" in
    vmess)  VMESS="$VMESS${VMESS:+,}$2";;
    vless)  VLESS="$VLESS${VLESS:+,}$2";;
    trojan) TROJAN="$TROJAN${TROJAN:+,}$2";; esac; }
while IFS='|' read -r f1 f2 f3 f4 f5; do
    [ -z "$f1" ] && continue
    case "$f1" in
        vmess|vless|trojan) proto=$f1; rk=$f2; sec=$f3;;
        *) proto=vmess; rk=$f1; sec=$f2;;
    esac
    [ -z "$sec" ] && continue
    case "$proto" in
        vmess)  _add vmess  "{\"id\":\"$sec\",\"alterId\":0,\"email\":\"$rk\"}";;
        vless)  _add vless  "{\"id\":\"$sec\",\"email\":\"$rk\"}";;
        trojan) _add trojan "{\"password\":\"$sec\",\"email\":\"$rk\"}";;
    esac
done < "$XACC"

# Emit one inbound. args: port proto clients net security path
ib() {
    local port="$1" proto="$2" cl="$3" net="$4" sec="$5" path="$6"
    local settings tlsblk="" netjson streamextra=""
    case "$proto" in
        vmess)  settings="{\"clients\":[${cl}]}";;
        vless)  settings="{\"clients\":[${cl}],\"decryption\":\"none\"}";;
        trojan) settings="{\"clients\":[${cl}]}";;
    esac
    [ "$sec" = "tls" ] && tlsblk="\"tlsSettings\":{\"certificates\":[{\"certificateFile\":\"$CERT\",\"keyFile\":\"$KEY\"}]}"
    case "$net" in
        ws)        netjson=ws;        streamextra="\"wsSettings\":{\"path\":\"$path\",\"headers\":{\"Host\":\"$HOST\"}}";;
        tcp)       netjson=tcp;;
        tcphttp)   netjson=tcp;       streamextra="\"tcpSettings\":{\"header\":{\"type\":\"http\",\"request\":{\"path\":[\"$path\"],\"headers\":{\"Host\":[\"$HOST\"]}}}}";;
        splithttp) netjson=splithttp; streamextra="\"splithttpSettings\":{\"path\":\"$path\",\"host\":\"$HOST\"}";;
    esac
    local parts="\"network\":\"$netjson\",\"security\":\"$sec\""
    [ -n "$tlsblk" ] && parts="$parts,$tlsblk"
    [ -n "$streamextra" ] && parts="$parts,$streamextra"
    echo "{\"port\":$port,\"protocol\":\"$proto\",\"settings\":$settings,\"streamSettings\":{$parts}}"
}

INB="{\"listen\":\"127.0.0.1\",\"port\":$XAPI,\"protocol\":\"dokodemo-door\",\"settings\":{\"address\":\"127.0.0.1\"},\"tag\":\"api\"}"
_ib() { INB="$INB,$(ib "$@")"; }
# VMess (6 variants)
_ib $VM_WS_TLS    vmess "$VMESS" ws        tls  /vmess
_ib $VM_WS_NONE   vmess "$VMESS" ws        none /vmess
_ib $VM_HTTP_NONE vmess "$VMESS" tcphttp   none /
_ib $VM_HTTP_TLS  vmess "$VMESS" tcphttp   tls  /
_ib $VM_SPLIT_TLS vmess "$VMESS" splithttp tls  /split
_ib $VM_SPLIT_NONE vmess "$VMESS" splithttp none /split
# VLESS (6 variants)
_ib $VL_WS_TLS    vless "$VLESS" ws        tls  /vless
_ib $VL_WS_NONE   vless "$VLESS" ws        none /vless
_ib $VL_HTTP_NONE vless "$VLESS" tcphttp   none /
_ib $VL_HTTP_TLS  vless "$VLESS" tcphttp   tls  /
_ib $VL_SPLIT_TLS vless "$VLESS" splithttp tls  /split
_ib $VL_SPLIT_NONE vless "$VLESS" splithttp none /split
# Trojan (TLS-only: 3 variants)
_ib $TR_TCP_TLS   trojan "$TROJAN" tcp       tls /
_ib $TR_WS_TLS    trojan "$TROJAN" ws        tls /trojan
_ib $TR_SPLIT_TLS trojan "$TROJAN" splithttp tls /split

cat > "$XCONF" <<JSON
{
  "log": {"loglevel": "warning"},
  "stats": {},
  "api": {"tag": "api", "services": ["HandlerService", "StatsService"]},
  "policy": {"levels": {"0": {"statsUserUplink": true, "statsUserDownlink": true}}, "system": {"statsInboundUplink": true, "statsInboundDownlink": true}},
  "inbounds": [${INB}],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}],
  "routing": {"rules": [{"type": "field", "inboundTag": ["api"], "outboundTag": "api"}]}
}
JSON
if systemctl is-enabled xray >/dev/null 2>&1; then systemctl restart xray >/dev/null 2>&1; fi
XGEOF
chmod +x /usr/local/bin/xray-gen

# --- limit checker: drops expired / over-quota accounts, then regenerates --
cat > /usr/local/bin/xray-check <<'XCEOF'
#!/bin/bash
XACC=/etc/xray/accounts.txt
XAPI=127.0.0.1:10085
[ -f "$XACC" ] || exit 0
now=$(date +%s)
tmp=$(mktemp); changed=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    IFS='|' read -r f1 f2 f3 f4 f5 <<< "$line"
    case "$f1" in
        vmess|vless|trojan) rk=$f2; exp=$f4; quota=$f5;;
        *) rk=$f1; exp=$f3; quota=$f4;;
    esac
    [ -z "$rk" ] && continue
    drop=0
    # expiry check
    if [ -n "$exp" ] && [ "$exp" != "never" ]; then
        e=$(date -d "$exp" +%s 2>/dev/null || echo 0)
        [ "$e" -gt 0 ] && [ "$now" -ge "$e" ] && drop=1
    fi
    # quota check
    if [ "$drop" -eq 0 ] && [ -n "$quota" ] && [ "$quota" -gt 0 ] 2>/dev/null; then
        up=$(xray api stats --server=$XAPI -name "user>>>${rk}>>>traffic>>>uplink" 2>/dev/null | grep -o '[0-9]\+' | tail -1); up=${up:-0}
        dn=$(xray api stats --server=$XAPI -name "user>>>${rk}>>>traffic>>>downlink" 2>/dev/null | grep -o '[0-9]\+' | tail -1); dn=${dn:-0}
        [ $((up + dn)) -ge "$quota" ] && drop=1
    fi
    if [ "$drop" -eq 1 ]; then changed=1; else echo "$line" >> "$tmp"; fi
done < "$XACC"
if [ "$changed" -eq 1 ]; then mv "$tmp" "$XACC"; /usr/local/bin/xray-gen; else rm -f "$tmp"; fi
XCEOF
chmod +x /usr/local/bin/xray-check

# --- cron: run the checker every 10 minutes ------------------------------
cat > /etc/cron.d/xray-check <<'EOF'
*/10 * * * * root /usr/local/bin/xray-check >/dev/null 2>&1
EOF
chmod 644 /etc/cron.d/xray-check
command -v cron >/dev/null 2>&1 || eval "$APT cron" </dev/null >/dev/null 2>&1 || true
systemctl enable cron >/dev/null 2>&1 || true
systemctl restart cron >/dev/null 2>&1 || true
success "Xray helper scripts installed (quota + expiry enforcement ready)"

# ═══════════════════════════════════════════
# SECTION 7 — INSTALL THE 'menu' COMMAND
# ═══════════════════════════════════════════
phase "Management panel"

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

# Use a UTF-8 locale so box/symbol characters are measured correctly.
if locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then export LC_ALL=C.UTF-8; fi

# Frame width adapts to the terminal so boxes never wrap on phones.
COLS=$(tput cols 2>/dev/null || stty size 2>/dev/null | awk '{print $2}')
[ -z "$COLS" ] && COLS=64
WIDTH=$(( COLS - 4 ))          # inner width of the frames
(( WIDTH > 60 )) && WIDTH=60
(( WIDTH < 34 )) && WIDTH=34

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

# ── bandwidth helpers ───────────────────────────────────
IFACE=$(cat "$CONF_DIR/iface.conf" 2>/dev/null)
[ -z "$IFACE" ] && IFACE=$(ip route 2>/dev/null | awk '/default/{print $5; exit}')
[ -z "$IFACE" ] && IFACE=$(ls /sys/class/net 2>/dev/null | grep -v lo | head -n1)

hb() { numfmt --to=iec --suffix=B --format="%.2f" "${1:-0}" 2>/dev/null || echo "${1:-0} B"; }

# Prints "rx tx total" in bytes for all-time usage.
# Uses vnstat (persists across reboots); falls back to /sys counters (since boot).
bw_alltime() {
    local rx tx line
    if command -v vnstat >/dev/null 2>&1; then
        line=$(vnstat -i "$IFACE" --oneline b 2>/dev/null)
        rx=$(echo "$line" | cut -d';' -f13)
        tx=$(echo "$line" | cut -d';' -f14)
    fi
    if ! [[ "$rx" =~ ^[0-9]+$ ]] || ! [[ "$tx" =~ ^[0-9]+$ ]]; then
        rx=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
        tx=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)
    fi
    echo "$rx $tx $((rx + tx))"
}

# Prints "rx tx total" in bytes for a vnstat period label: d (today) or m (month).
bw_period() {
    local p="$1" line rx tx f
    command -v vnstat >/dev/null 2>&1 || { echo "0 0 0"; return; }
    line=$(vnstat -i "$IFACE" --oneline b 2>/dev/null)
    if [ "$p" = "d" ]; then rx=$(echo "$line" | cut -d';' -f4);  tx=$(echo "$line" | cut -d';' -f5)
    else                    rx=$(echo "$line" | cut -d';' -f9);  tx=$(echo "$line" | cut -d';' -f10); fi
    [[ "$rx" =~ ^[0-9]+$ ]] || rx=0; [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
    echo "$rx $tx $((rx + tx))"
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
    read -r _rx _tx _tot <<<"$(bw_alltime)"
    row "$col" "${GR}DATA${NC}    ${W}${BOLD}$(hb "$_tot")${NC} ${GR}used${NC}"
    local svcline="${GR}SVC${NC}    "
    for s in ssh dropbear ws-proxy stunnel4 slowdns; do
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
    local _ns; _ns=$(cat "$CONF_DIR/nsdomain.conf" 2>/dev/null)
    if [ -n "$_ns" ]; then
        row "$col" "${LIME}▸${NC} SlowDNS (UDP 53)     ${GR}→${NC} ${W}${_ns}${NC}"
    fi
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
warn() { echo -e "  ${Y}⚠${NC} $*"; }

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

bandwidth() {
    local col="$SKY"
    # Live view: refresh every 2s until the user presses a key.
    while true; do
        section "BANDWIDTH MONITOR" "$SKY"
        read -r arx atx atot <<<"$(bw_alltime)"
        line_top "$col"
        crow "$col" "${GR}TOTAL BANDWIDTH USED${NC}"
        crow "$col" "${W}${BOLD}$(hb "$atot")${NC}"
        line_mid "$col"
        row "$col" "${SKY}↓ Download${NC}   ${W}$(hb "$arx")${NC}"
        row "$col" "${ORANGE}↑ Upload${NC}     ${W}$(hb "$atx")${NC}"
        line_bot "$col"
        echo ""
        echo -e "  ${G}● live${NC} ${GR}— updates every 2s · press ENTER to go back${NC}"
        # wait up to 2s for ENTER; if pressed, exit the loop
        if read -t 2 -r _; then break; fi
    done
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
    local col="$P" svcs="ssh dropbear ws-proxy stunnel4 slowdns"
    [ -f /usr/local/bin/xray ] && svcs="$svcs xray"
    line_top "$col"
    for svc in $svcs; do
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
    systemctl restart slowdns 2>/dev/null
    ok "All services restarted."
    pause
}

slowdns_info() {
    section "SLOWDNS INFO" "$TEAL"
    local ns pub
    ns=$(cat "$CONF_DIR/nsdomain.conf" 2>/dev/null)
    pub=$(cat "$CONF_DIR/slowdns_pub.txt" 2>/dev/null)
    if [ -z "$ns" ] || [ -z "$pub" ]; then
        err "SlowDNS is not configured on this server."
        note "Re-run the installer and enter an NS domain to enable it."
        pause; return
    fi
    if systemctl is-active --quiet slowdns 2>/dev/null; then
        ok "Service: ${G}running${NC} (UDP 53)"
    else
        err "Service: ${R}stopped${NC}  — use option 10 to restart"
    fi
    echo ""
    echo -e "  ${GR}NS domain${NC}"
    echo -e "    ${W}${BOLD}${ns}${NC}"
    echo ""
    echo -e "  ${GR}Public key${NC}"
    echo -e "    ${LIME}${pub}${NC}"
    echo ""
    echo -e "  ${GR}DNS resolver${NC}  ${W}1.1.1.1${NC}  ${GR}(or 8.8.8.8)${NC}"
    echo ""
    echo -e "  ${GR}Termux / client command${NC}"
    echo -e "    ${DIM}curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns \\
      && chmod +x slowdns && ./slowdns ${ns} ${pub}${NC}"
    echo ""
    echo -e "  ${GR}Login${NC}  use any SSH user (e.g. from option 1) — SlowDNS tunnels to SSH."
    pause
}

# ═══════════════════════════════════════════
# XRAY / V2RAY (VMESS) — menu-activated, not auto-started
# ═══════════════════════════════════════════
XBIN=/usr/local/bin/xray
XCONF=/usr/local/etc/xray/config.json
XACC=/etc/xray/accounts.txt
# Dedicated ports (no clash with 22/80/109/143/443/447)
# VMess
VM_WS_TLS=8443; VM_WS_NONE=8080; VM_HTTP_NONE=8081; VM_HTTP_TLS=8444; VM_SPLIT_TLS=8445; VM_SPLIT_NONE=8082
# VLESS
VL_WS_TLS=8446; VL_WS_NONE=8083; VL_HTTP_NONE=8084; VL_HTTP_TLS=8447; VL_SPLIT_TLS=8448; VL_SPLIT_NONE=8085
# Trojan (TLS only)
TR_TCP_TLS=8449; TR_WS_TLS=8450; TR_SPLIT_TLS=8451
# Port-443 handover flag (when set, V2Ray owns 443 and SSL payload is off)
XP443F=/etc/xray/port443
STCONF=/etc/stunnel/stunnel.conf
STCERT=/etc/stunnel/stunnel.pem

xray_paths() {
    mkdir -p /etc/xray /usr/local/etc/xray
    touch "$XACC"
    XDOMAIN=$(cat "$CONF_DIR/domain.conf" 2>/dev/null)
    XIP=$(cat "$CONF_DIR/ip.conf" 2>/dev/null)
    XHOST="${XDOMAIN:-$XIP}"
    XADDR="$XHOST"
    if [ -n "$XDOMAIN" ] && [ -f "/etc/letsencrypt/live/$XDOMAIN/fullchain.pem" ]; then
        XR_CERT="/etc/letsencrypt/live/$XDOMAIN/fullchain.pem"
        XR_KEY="/etc/letsencrypt/live/$XDOMAIN/privkey.pem"
    else
        [ -f /etc/xray/xray.crt ] || openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
            -subj "/CN=${XHOST:-xray}" -out /etc/xray/xray.crt -keyout /etc/xray/xray.key >/dev/null 2>&1
        XR_CERT=/etc/xray/xray.crt; XR_KEY=/etc/xray/xray.key
    fi
    # Mirror the 443 handover so displayed links use the right port.
    P443=$(cat "$XP443F" 2>/dev/null)
    case "$P443" in
        vmess)  VM_WS_TLS=443;;
        vless)  VL_WS_TLS=443;;
        trojan) TR_WS_TLS=443;;
    esac
}

# Rewrite stunnel.conf. $1=yes keeps the SSL-payload listener on 443; no drops it.
write_stunnel_conf() {
    {
        echo "pid     = /var/run/stunnel4.pid"
        echo "cert    = ${STCERT}"
        echo "client  = no"
        echo "socket  = a:SO_REUSEADDR=1"
        echo "socket  = l:TCP_NODELAY=1"
        echo "socket  = r:TCP_NODELAY=1"
        echo "TIMEOUTclose = 0"
        echo ""
        if [ "$1" = "yes" ]; then
            echo "[ssl-ws]"
            echo "accept  = 443"
            echo "connect = 127.0.0.1:80"
            echo ""
        fi
        echo "[ssl-ssh]"
        echo "accept  = 447"
        echo "connect = 127.0.0.1:22"
    } > "$STCONF"
}

# Toggle port 443 between SSL-payload SSH and V2Ray.
xray_443() {
    xray_paths
    section "PORT 443 — SSL PAYLOAD ↔ V2RAY" "$PINK"
    local cur; cur=$(cat "$XP443F" 2>/dev/null)
    local col="$PINK"; line_top "$col"
    if [ -n "$cur" ]; then
        row "$col" "${GR}443 NOW${NC}  ${P}V2Ray — ${cur} (WS-TLS)${NC}"
        row "$col" "${GR}SSL PAYLOAD${NC} ${R}disabled${NC}"
    else
        row "$col" "${GR}443 NOW${NC}  ${G}SSL payload SSH${NC}"
    fi
    line_bot "$col"; echo ""
    if [ -n "$cur" ]; then
        read -rp "$(echo -e "  ${C}Restore SSL-payload SSH on 443?${NC} ${GR}(y/N)${NC} : ")" a
        if [[ "$a" =~ ^[Yy] ]]; then
            rm -f "$XP443F"
            # Order matters: Xray must RELEASE 443 before stunnel can bind it.
            rebuild_config; systemctl restart xray >/dev/null 2>&1
            sleep 1
            write_stunnel_conf yes
            systemctl restart stunnel4 >/dev/null 2>&1
            sleep 1
            if ss -ltn 2>/dev/null | grep -q ':443 '; then
                ok "Port 443 restored to ${G}SSL-payload SSH${NC}."
            else
                err "stunnel didn't bind 443 — retrying..."; systemctl restart stunnel4 >/dev/null 2>&1
                sleep 1
                systemctl is-active --quiet stunnel4 && ok "Port 443 restored to ${G}SSL-payload SSH${NC}." || err "stunnel4 failed — check: journalctl -u stunnel4"
            fi
        else
            note "No change."
        fi
    else
        local wcol="$ORANGE"
        line_top "$wcol"
        crow "$wcol" "${Y}${BOLD}⚠  WARNING${NC}"
        line_mid "$wcol"
        row "$wcol" "${W}This disables SSL-payload SSH on port 443.${NC}"
        row "$wcol" "${GR}443 SSH users stop working · 80/109/143/447 stay up${NC}"
        line_bot "$wcol"
        echo ""
        echo -e "  ${C}${BOLD}Give 443 to which V2Ray protocol?${NC}"
        echo ""
        menu_item "1" "⚡" "VMess  (WS-TLS)"  "$LIME"
        menu_item "2" "⚡" "VLESS  (WS-TLS)"  "$SKY"
        menu_item "3" "⚡" "Trojan (WS-TLS)"  "$PINK"
        menu_item "0" "↩ " "Cancel"           "$GR"
        echo ""
        read -rp "$(echo -e "  ${P}❯${NC} choose : ")" pc
        local proto=""
        case "$pc" in 1) proto=vmess;; 2) proto=vless;; 3) proto=trojan;; *) note "Cancelled."; pause; return;; esac
        if ! xray_install; then err "Xray must be installed first — create an account."; pause; return; fi
        echo "$proto" > "$XP443F"
        # Xray usually runs as a non-root user; 443 is a privileged port.
        # Grant CAP_NET_BIND_SERVICE via a systemd drop-in (idempotent).
        mkdir -p /etc/systemd/system/xray.service.d
        cat > /etc/systemd/system/xray.service.d/priv-port.conf <<'DROPEOF'
[Service]
AmbientCapabilities=CAP_NET_BIND_SERVICE
DROPEOF
        systemctl daemon-reload >/dev/null 2>&1
        # Order matters: stunnel must RELEASE 443 before Xray can bind it.
        write_stunnel_conf no
        systemctl restart stunnel4 >/dev/null 2>&1
        local w=0
        while ss -ltn 2>/dev/null | grep -q ':443 ' && [ $w -lt 5 ]; do sleep 1; w=$((w+1)); done
        rebuild_config
        systemctl enable xray >/dev/null 2>&1; systemctl restart xray >/dev/null 2>&1
        sleep 2
        if systemctl is-active --quiet xray && ss -ltn 2>/dev/null | grep -q ':443 '; then
            ok "Port 443 now serves ${P}${proto}${NC} (WS-TLS). Re-open any account to get its 443 link."
        else
            err "Xray could not take over 443. Last errors:"
            journalctl -u xray -n 8 --no-pager 2>/dev/null | sed 's/^/    /'
            note "Rolling back — 443 returns to SSL-payload SSH."
            rm -f "$XP443F"; rebuild_config
            systemctl restart xray >/dev/null 2>&1
            write_stunnel_conf yes; systemctl restart stunnel4 >/dev/null 2>&1
        fi
    fi
    pause
}

# Rebuild the Xray config from the accounts file (shared generator).
rebuild_config() { /usr/local/bin/xray-gen >/dev/null 2>&1; }

# Total traffic used by a remark (uplink+downlink), in bytes.
xray_used() {
    local up dn
    up=$(xray api stats --server=127.0.0.1:10085 -name "user>>>$1>>>traffic>>>uplink" 2>/dev/null | grep -o '[0-9]\+' | tail -1)
    dn=$(xray api stats --server=127.0.0.1:10085 -name "user>>>$1>>>traffic>>>downlink" 2>/dev/null | grep -o '[0-9]\+' | tail -1)
    echo $(( ${up:-0} + ${dn:-0} ))
}

# Parse one account line into P_PROTO/P_RK/P_SEC/P_EXP/P_QUOTA (legacy 4-field = vmess).
parse_acct() {
    local f1 f2 f3 f4 f5; IFS='|' read -r f1 f2 f3 f4 f5 <<< "$1"
    case "$f1" in
        vmess|vless|trojan) P_PROTO=$f1; P_RK=$f2; P_SEC=$f3; P_EXP=$f4; P_QUOTA=$f5;;
        *) P_PROTO=vmess; P_RK=$f1; P_SEC=$f2; P_EXP=$f3; P_QUOTA=$f4;;
    esac
}

mkvmess() {  # ps port net type tls path id
    local j="{\"v\":\"2\",\"ps\":\"$1\",\"add\":\"${XADDR}\",\"port\":\"$2\",\"id\":\"$7\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"$3\",\"type\":\"$4\",\"host\":\"${XHOST}\",\"path\":\"$6\",\"tls\":\"$5\",\"sni\":\"${XHOST}\"}"
    echo "vmess://$(printf '%s' "$j" | base64 -w0)"
}

# mkuri proto secret port net security path remark
#   net=ws|tcp|tcphttp|splithttp   security=tls|none
mkuri() {
    local proto="$1" sec="$2" port="$3" net="$4" security="$5" path="$6" rk="$7"
    local q net_t="$net"
    case "$net" in tcphttp) net_t="tcp"; q="headerType=http&host=${XHOST}&path=${path}";;
        tcp) q="";; ws) q="host=${XHOST}&path=${path}";; splithttp) q="host=${XHOST}&path=${path}";; esac
    local base="type=${net_t}&security=${security}"
    [ "$security" = "tls" ] && base="${base}&sni=${XHOST}"
    [ -n "$q" ] && base="${base}&${q}"
    if [ "$proto" = "vless" ]; then
        echo "vless://${sec}@${XADDR}:${port}?encryption=none&${base}#${rk}"
    else
        echo "trojan://${sec}@${XADDR}:${port}?${base}#${rk}"
    fi
}

show_links() {  # remark
    local rk="$1"
    parse_acct "$(grep -m1 "|${rk}|" "$XACC" 2>/dev/null || grep -m1 "^${rk}|" "$XACC" 2>/dev/null)"
    banner
    echo -e "  ${GR}Remark${NC}  ${W}${P_RK}${NC}    ${GR}Type${NC} ${P}${BOLD}$(echo "$P_PROTO" | tr a-z A-Z)${NC}"
    echo -e "  ${GR}Secret${NC}  ${W}${P_SEC}${NC}"
    echo -e "  ${GR}Host${NC}    ${Y}${XHOST}${NC}"
    echo -e "  ${GR}Expires${NC} ${W}${P_EXP:-never}${NC}"
    if [ -n "$P_QUOTA" ] && [ "$P_QUOTA" -gt 0 ] 2>/dev/null; then
        echo -e "  ${GR}Quota${NC}   ${W}$(hb "$P_QUOTA")${NC}   ${GR}Used${NC} ${W}$(hb "$(xray_used "$P_RK")")${NC}"
    else
        echo -e "  ${GR}Quota${NC}   ${W}Unlimited${NC}   ${GR}Used${NC} ${W}$(hb "$(xray_used "$P_RK")")${NC}"
    fi
    local sep="  ${GR}──────────────────────────────────────────────────${NC}"
    echo -e "$sep"
    case "$P_PROTO" in
      vmess)
        echo -e "  ${G}${BOLD}TLS${NC}        ${DIM}(ws · $VM_WS_TLS)${NC}\n  $(mkvmess "${rk}-TLS" $VM_WS_TLS ws none tls /vmess $P_SEC)"; echo -e "$sep"
        echo -e "  ${G}${BOLD}NoneTLS${NC}    ${DIM}(ws · $VM_WS_NONE)${NC}\n  $(mkvmess "${rk}-NoneTLS" $VM_WS_NONE ws none "" /vmess $P_SEC)"; echo -e "$sep"
        echo -e "  ${G}${BOLD}HTTP None${NC}  ${DIM}(tcp · $VM_HTTP_NONE)${NC}\n  $(mkvmess "${rk}-HTTP-None" $VM_HTTP_NONE tcp http "" / $P_SEC)"; echo -e "$sep"
        echo -e "  ${G}${BOLD}HTTP TLS${NC}   ${DIM}(tcp · $VM_HTTP_TLS)${NC}\n  $(mkvmess "${rk}-HTTP-TLS" $VM_HTTP_TLS tcp http tls / $P_SEC)"; echo -e "$sep"
        echo -e "  ${G}${BOLD}SPLIT TLS${NC}  ${DIM}(split · $VM_SPLIT_TLS)${NC}\n  $(mkvmess "${rk}-SPLIT-TLS" $VM_SPLIT_TLS splithttp none tls /split $P_SEC)"; echo -e "$sep"
        echo -e "  ${G}${BOLD}SPLIT HTTP${NC} ${DIM}(split · $VM_SPLIT_NONE)${NC}\n  $(mkvmess "${rk}-SPLIT-HTTP" $VM_SPLIT_NONE splithttp none "" /split $P_SEC)"; echo -e "$sep";;
      vless)
        echo -e "  ${G}${BOLD}TLS${NC}        ${DIM}(ws · $VL_WS_TLS)${NC}\n  $(mkuri vless $P_SEC $VL_WS_TLS ws tls /vless "${rk}-TLS")"; echo -e "$sep"
        echo -e "  ${G}${BOLD}NoneTLS${NC}    ${DIM}(ws · $VL_WS_NONE)${NC}\n  $(mkuri vless $P_SEC $VL_WS_NONE ws none /vless "${rk}-NoneTLS")"; echo -e "$sep"
        echo -e "  ${G}${BOLD}HTTP None${NC}  ${DIM}(tcp · $VL_HTTP_NONE)${NC}\n  $(mkuri vless $P_SEC $VL_HTTP_NONE tcphttp none / "${rk}-HTTP-None")"; echo -e "$sep"
        echo -e "  ${G}${BOLD}HTTP TLS${NC}   ${DIM}(tcp · $VL_HTTP_TLS)${NC}\n  $(mkuri vless $P_SEC $VL_HTTP_TLS tcphttp tls / "${rk}-HTTP-TLS")"; echo -e "$sep"
        echo -e "  ${G}${BOLD}SPLIT TLS${NC}  ${DIM}(split · $VL_SPLIT_TLS)${NC}\n  $(mkuri vless $P_SEC $VL_SPLIT_TLS splithttp tls /split "${rk}-SPLIT-TLS")"; echo -e "$sep"
        echo -e "  ${G}${BOLD}SPLIT HTTP${NC} ${DIM}(split · $VL_SPLIT_NONE)${NC}\n  $(mkuri vless $P_SEC $VL_SPLIT_NONE splithttp none /split "${rk}-SPLIT-HTTP")"; echo -e "$sep";;
      trojan)
        echo -e "  ${G}${BOLD}TCP TLS${NC}    ${DIM}(tcp · $TR_TCP_TLS)${NC}\n  $(mkuri trojan $P_SEC $TR_TCP_TLS tcp tls / "${rk}-TCP-TLS")"; echo -e "$sep"
        echo -e "  ${G}${BOLD}WS TLS${NC}     ${DIM}(ws · $TR_WS_TLS)${NC}\n  $(mkuri trojan $P_SEC $TR_WS_TLS ws tls /trojan "${rk}-WS-TLS")"; echo -e "$sep"
        echo -e "  ${G}${BOLD}SPLIT TLS${NC}  ${DIM}(split · $TR_SPLIT_TLS)${NC}\n  $(mkuri trojan $P_SEC $TR_SPLIT_TLS splithttp tls /split "${rk}-SPLIT-TLS")"; echo -e "$sep";;
    esac
}

xray_open_ports() {
    command -v ufw >/dev/null 2>&1 || return
    for P in $VM_WS_TLS $VM_WS_NONE $VM_HTTP_NONE $VM_HTTP_TLS $VM_SPLIT_TLS $VM_SPLIT_NONE \
             $VL_WS_TLS $VL_WS_NONE $VL_HTTP_NONE $VL_HTTP_TLS $VL_SPLIT_TLS $VL_SPLIT_NONE \
             $TR_TCP_TLS $TR_WS_TLS $TR_SPLIT_TLS; do
        ufw allow ${P}/tcp >/dev/null 2>&1
    done
}

xray_install() {
    [ -f "$XBIN" ] && return 0
    note "Installing Xray-core (needs internet)..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
    [ -f "$XBIN" ]
}

xray_activate() {
    xray_paths
    section "CREATE XRAY / V2RAY ACCOUNT" "$PINK"
    if ! xray_install; then err "Xray install failed — check the server's internet."; pause; return; fi
    PROTO=""
    # if accounts already exist, offer to add a client under one of them (same protocol & ports)
    if [ -s "$XACC" ]; then
        local rks=() prs=() line i=1 pick p443
        p443=$(cat "$XP443F" 2>/dev/null)
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            parse_acct "$line"; [ -z "$P_RK" ] && continue
            rks+=("$P_RK"); prs+=("$P_PROTO")
        done < "$XACC"
        if [ ${#rks[@]} -gt 0 ]; then
            echo -e "  ${C}What do you want to create?${NC}"
            echo -e "    ${LIME}1${NC}) New account (pick protocol)"
            echo -e "    ${LIME}2${NC}) Add client under an existing account ${GR}(same protocol & ports)${NC}"
            read -rp "$(echo -e "  ${P}❯${NC} choose ${GR}(1-2)${NC} : ")" MODE
            if [ "$MODE" = "2" ]; then
                echo ""
                echo -e "  ${C}Existing accounts:${NC}"
                for i in "${!rks[@]}"; do
                    local tag=""
                    [ -n "$p443" ] && [ "${prs[$i]}" = "$p443" ] && tag=" ${P}(on port 443)${NC}"
                    echo -e "    ${LIME}$((i+1))${NC}) ${W}${rks[$i]}${NC} ${GR}[${prs[$i]}]${NC}${tag}"
                done
                read -rp "$(echo -e "  ${P}❯${NC} choose ${GR}(1-${#rks[@]})${NC} : ")" pick
                if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#rks[@]} ]; then
                    PROTO="${prs[$((pick-1))]}"
                    ok "New client will use ${P}${PROTO}${NC} — same ports as '${W}${rks[$((pick-1))]}${NC}'."
                else
                    err "Invalid choice."; pause; return
                fi
            fi
        fi
    fi
    if [ -z "$PROTO" ]; then
        echo -e "  ${C}Protocol${NC}"
        echo -e "    ${LIME}1${NC}) VMess   ${LIME}2${NC}) VLESS   ${LIME}3${NC}) Trojan"
        read -rp "$(echo -e "  ${P}❯${NC} choose ${GR}(1-3)${NC} : ")" PC
        case "$PC" in 2) PROTO=vless;; 3) PROTO=trojan;; *) PROTO=vmess;; esac
    fi
    read -rp "$(echo -e "  ${C}Remark (name)${NC}         : ")" REMARK
    [ -z "$REMARK" ] && REMARK="${PROTO}-$(date +%s)"
    REMARK=$(echo "$REMARK" | tr ' |' '--')
    if grep -q "|${REMARK}|" "$XACC" 2>/dev/null || grep -q "^${REMARK}|" "$XACC" 2>/dev/null; then
        err "Remark '${REMARK}' already exists — pick another."; pause; return
    fi
    read -rp "$(echo -e "  ${C}Days valid (0=never)${NC}  : ")" XDAYS
    if [[ "$XDAYS" =~ ^[0-9]+$ ]] && [ "$XDAYS" -gt 0 ]; then XEXP=$(date -d "+$XDAYS days" +%Y-%m-%d); else XEXP="never"; fi
    read -rp "$(echo -e "  ${C}Quota GB (0=unlimited)${NC}: ")" XGB
    [[ "$XGB" =~ ^[0-9]+$ ]] || XGB=0
    XQUOTA=$(( XGB * 1024 * 1024 * 1024 ))
    SECRET=$(cat /proc/sys/kernel/random/uuid)   # uuid for vmess/vless, password for trojan
    echo "${PROTO}|${REMARK}|${SECRET}|${XEXP}|${XQUOTA}" >> "$XACC"
    rebuild_config
    xray_open_ports
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray >/dev/null 2>&1
    sleep 1
    if systemctl is-active --quiet xray; then
        ok "Xray is now ${G}ACTIVE${NC} — account '${W}${REMARK}${NC}' (${P}${PROTO}${NC}) created."
    else
        err "Xray failed to start — check: journalctl -u xray"
    fi
    echo ""
    show_links "$REMARK"
    pause
}

xray_list() {
    xray_paths
    section "XRAY ACCOUNTS" "$PINK"
    local col="$PINK"; line_top "$col"
    row "$col" "$(printf '%-8s %-14s %-11s %-8s %s' 'TYPE' 'REMARK' 'EXPIRES' 'QUOTA' 'USED')"
    line_mid "$col"
    local any=0 line q u
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        parse_acct "$line"; [ -z "$P_RK" ] && continue; any=1
        if [ -n "$P_QUOTA" ] && [ "$P_QUOTA" -gt 0 ] 2>/dev/null; then q=$(hb "$P_QUOTA"); else q="∞"; fi
        u=$(hb "$(xray_used "$P_RK")")
        row "$col" "$(printf '%-8s %-14s %-11s %-8s %s' "$P_PROTO" "$P_RK" "${P_EXP:-never}" "$q" "$u")"
    done < "$XACC"
    [ $any -eq 0 ] && row "$col" "${GR}(no accounts yet — create one first)${NC}"
    line_bot "$col"
    echo ""
    read -rp "$(echo -e "  ${C}Type a remark to show its links${NC} ${GR}(ENTER to skip)${NC} : ")" q
    if [ -n "$q" ]; then
        if grep -q "|${q}|" "$XACC" 2>/dev/null || grep -q "^${q}|" "$XACC" 2>/dev/null; then show_links "$q"; else err "Remark not found."; fi
    fi
    pause
}

xray_delete() {
    xray_paths
    section "DELETE XRAY ACCOUNT" "$R"
    read -rp "$(echo -e "  ${C}Remark to delete${NC} : ")" q
    if ! grep -q "|${q}|" "$XACC" 2>/dev/null && ! grep -q "^${q}|" "$XACC" 2>/dev/null; then err "Remark not found."; pause; return; fi
    # remark is field 2 (new proto|remark|...) or field 1 (legacy remark|...)
    awk -F'|' -v r="$q" '{ if ($1=="vmess"||$1=="vless"||$1=="trojan") nm=$2; else nm=$1; if (nm!=r) print }' "$XACC" > "$XACC.tmp" && mv "$XACC.tmp" "$XACC"
    rebuild_config
    systemctl restart xray >/dev/null 2>&1
    ok "Account '${W}$q${NC}' deleted."
    pause
}

xray_menu() {
    xray_paths
    while true; do
        section "XRAY / V2RAY (VMESS · VLESS · TROJAN)" "$PINK"
        local st col="$PINK"
        if [ ! -f "$XBIN" ]; then st="${R}✗ not installed${NC}"
        elif systemctl is-active --quiet xray 2>/dev/null; then st="${G}● active${NC}"
        else st="${Y}○ installed (stopped)${NC}"; fi
        local p443; p443=$(cat "$XP443F" 2>/dev/null)
        line_top "$col"
        row "$col" "${GR}STATUS${NC}  ${st}"
        row "$col" "${GR}HOST${NC}    ${Y}${XHOST}${NC}"
        row "$col" "${GR}ACCTS${NC}   ${C}$(grep -c '|' "$XACC" 2>/dev/null | grep . || echo 0)${NC}"
        if [ -n "$p443" ]; then row "$col" "${GR}PORT443${NC} ${P}V2Ray (${p443})${NC}"; else row "$col" "${GR}PORT443${NC} ${G}SSL payload SSH${NC}"; fi
        line_bot "$col"
        echo ""
        menu_item "1" "⚡" "Create account (VMess/VLESS/Trojan)" "$LIME"
        menu_item "2" "📋" "Show accounts / links"          "$SKY"
        menu_item "3" "🗑 " "Delete account"                 "$R"
        menu_item "4" "▶ " "Start Xray"                      "$G"
        menu_item "5" "⏹ " "Stop Xray"                       "$Y"
        menu_item "6" "🔀" "Port 443: SSL payload ↔ V2Ray"   "$ORANGE"
        menu_item "0" "↩ " "Back to main menu"              "$GR"
        echo ""
        read -rp "$(echo -e "  ${P}❯${NC} select : ")" o
        case "$o" in
            1) xray_activate ;;
            2) xray_list ;;
            3) xray_delete ;;
            4) systemctl enable xray >/dev/null 2>&1; systemctl start xray >/dev/null 2>&1; ok "Xray started."; sleep 1 ;;
            5) systemctl stop xray >/dev/null 2>&1; ok "Xray stopped."; sleep 1 ;;
            6) xray_443 ;;
            0) break ;;
            *) err "Invalid option."; sleep 1 ;;
        esac
    done
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
    menu_item "8" "📶" "Bandwidth usage"          "$SKY"
    menu_item "9" "🌐" "Xray / V2Ray (VMess)"     "$PINK"
    menu_item "10" "🔄" "Restart all services"    "$Y"
    menu_item "11" "🐌" "SlowDNS info / config"   "$TEAL"
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
        8) bandwidth ;;
        9) xray_menu ;;
        10) restart_services ;;
        11) slowdns_info ;;
        0) clear; echo -e "  ${G}Goodbye 👋${NC}\n"; exit 0 ;;
        *) echo -e "  ${R}Invalid option.${NC}"; sleep 1 ;;
    esac
done
MENUEOF

chmod +x /usr/local/bin/menu
success "Management panel installed — type 'menu' to open it"

# ═══════════════════════════════════════════
# DEFAULT SSH USERS (auto-created)
# ═══════════════════════════════════════════
phase "Default users"
DEFAULT_USER_PASS="0000"
DEFAULT_USER_DAYS=30
DEFAULT_USER_EXP=$(date -d "+${DEFAULT_USER_DAYS} days" +"%Y-%m-%d")
for U in deon febo geto weon ceon; do
    if id "$U" >/dev/null 2>&1; then
        info "User '$U' already exists — skipped"
    else
        useradd -e "$DEFAULT_USER_EXP" -M -s /bin/false "$U"
        echo -e "${DEFAULT_USER_PASS}\n${DEFAULT_USER_PASS}" | passwd "$U" >/dev/null 2>&1
        success "User '$U' created (pass: ${DEFAULT_USER_PASS}, expires: ${DEFAULT_USER_EXP})"
    fi
done

# ═══════════════════════════════════════════
# FINAL MESSAGE
# ═══════════════════════════════════════════
UI_SILENT=0
_ELAPSED=$(( SECONDS - INSTALL_T0 ))
clear
echo ""
echo -e "  ${LIME}${BOLD}  ✔  INSTALLATION COMPLETE${NC}   ${GRY}all protocols installed in ${BWHITE}${_ELAPSED}s${GRY}.${NC}"
echo ""
echo -e "  ${TEAL}╭──────────────────────────────────────────────────────╮${NC}"
printf  "  ${TEAL}│${NC}  ${SKY}◆${NC} %-13s ${BWHITE}${BOLD}%-33.33s${NC}${TEAL}│${NC}\n" "Host / Domain" "${DOMAIN:-$SERVER_IP}"
echo -e "  ${TEAL}├─ ${BWHITE}${BOLD}SERVICES & PORTS${NC} ${TEAL}──────────────────────────────────┤${NC}"
printf  "  ${TEAL}│${NC}   ${LIME}▸${NC} %-22s ${BWHITE}%-24s${NC}${TEAL}│${NC}\n" "WebSocket (payload)" "80"
printf  "  ${TEAL}│${NC}   ${LIME}▸${NC} %-22s ${BWHITE}%-24s${NC}${TEAL}│${NC}\n" "SSL + payload (TLS)" "443"
printf  "  ${TEAL}│${NC}   ${LIME}▸${NC} %-22s ${BWHITE}%-24s${NC}${TEAL}│${NC}\n" "SSL direct SSH (TLS)" "447"
printf  "  ${TEAL}│${NC}   ${LIME}▸${NC} %-22s ${BWHITE}%-24s${NC}${TEAL}│${NC}\n" "OpenSSH" "22"
printf  "  ${TEAL}│${NC}   ${LIME}▸${NC} %-22s ${BWHITE}%-24s${NC}${TEAL}│${NC}\n" "Dropbear" "109, 143"
if [ -n "$NS_DOMAIN" ] && [ -x /usr/local/bin/dnstt-server ]; then
    printf "  ${TEAL}│${NC}   ${LIME}▸${NC} %-22s ${BWHITE}%-24s${NC}${TEAL}│${NC}\n" "SlowDNS (UDP 53)" "$NS_DOMAIN"
fi
echo -e "  ${TEAL}├─ ${BWHITE}${BOLD}DEFAULT USERS${NC} ${GRY}(pass: 0000, ${DEFAULT_USER_DAYS}d)${NC} ${TEAL}────────────────────┤${NC}"
printf  "  ${TEAL}│${NC}   ${PINK}●${NC} %-50s${TEAL}│${NC}\n" "deon · febo · geto · weon · ceon"
echo -e "  ${TEAL}╰──────────────────────────────────────────────────────╯${NC}"
echo ""
echo -e "  ${GRY}Client tips${NC}"
echo -e "    ${DIM}WS payload${NC}  GET / HTTP/1.1[crlf]Host: ${BWHITE}${DOMAIN:-$SERVER_IP}${NC}[crlf]Upgrade: websocket[crlf][crlf]"
echo -e "    ${DIM}SSL/SNI${NC}     ${BWHITE}${DOMAIN:-$SERVER_IP}${NC}"
if [ -n "$NS_DOMAIN" ] && [ -f "$CONF_DIR/slowdns_pub.txt" ]; then
    echo -e "    ${DIM}SlowDNS${NC}     NS ${BWHITE}${NS_DOMAIN}${NC}  ${GRY}pubkey:${NC}"
    echo -e "                ${LIME}$(cat "$CONF_DIR/slowdns_pub.txt")${NC}"
fi
echo ""
echo -e "  ${TEAL}${BOLD}▸${NC} Type ${LIME}${BOLD}menu${NC} to open the control panel and create users."
echo ""

# ═══════════════════════════════════════════
# SELF-CLEANUP — remove traces from shell history & disk
# ═══════════════════════════════════════════
info "Cleaning install traces from server history..."
# 1) Delete any downloaded copy of this installer.
[ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ] && rm -f "${BASH_SOURCE[0]}" 2>/dev/null
for f in ssh-ssl-setup.sh /root/ssh-ssl-setup.sh /tmp/ssh-ssl-setup.sh; do
    [ -f "$f" ] && rm -f "$f" 2>/dev/null
done
# 2) Scrub install command lines from every shell history file we can find.
for H in /root/.bash_history "$HOME/.bash_history" /root/.zsh_history "$HOME/.zsh_history" \
         /root/.ash_history "$HOME/.ash_history" /root/.local/share/fish/fish_history; do
    [ -f "$H" ] || continue
    sed -i -E '/(ssh-ssl-setup\.sh|raw\.githubusercontent\.com\/kelvinsonatech\/myssh)/d' "$H" 2>/dev/null
done
# 3) Drop the current session's in-memory history so it can't be flushed back.
history -c 2>/dev/null || true
: > "${HISTFILE:-/root/.bash_history}" 2>/dev/null || true
success "Install traces removed from history"
echo ""
