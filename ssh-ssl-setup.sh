#!/bin/bash
# BaymaxSSH — OpenSSH-only server installer and account manager.
# Installs OpenSSH on port 22 and removes protocol services created by older
# BaymaxSSH releases (Dropbear, WebSocket, Stunnel, Xray, SlowDNS, Hysteria).

set -e

BGreen='\033[1;32m'; BYellow='\033[1;33m'; BCyan='\033[1;36m'
BRed='\033[1;31m'; NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
TEAL='\033[38;5;44m'; SKY='\033[38;5;39m'; LIME='\033[38;5;155m'
CORAL='\033[38;5;209m'; GRY='\033[38;5;240m'; BWHITE='\033[97m'
PINK='\033[38;5;213m'
export LANG=C.UTF-8 LC_ALL=C.UTF-8 2>/dev/null || true

UI_SILENT=0
info()    { [ "$UI_SILENT" = "1" ] && return 0; echo -e "${BCyan}[*] $*${NC}"; }
success() { [ "$UI_SILENT" = "1" ] && return 0; echo -e "${BGreen}[✓] $*${NC}"; }
warn()    { echo -e "${BYellow}[!] $*${NC}"; }
error()   { echo -e "${BRed}[✗] $*${NC}"; exit 1; }

INSTALL_TOTAL=7; INSTALL_STEP=0; INSTALL_T0=$SECONDS
_PH_T0=$SECONDS; _PH_NAME=""
_MG=('\033[38;5;45m' '\033[38;5;44m' '\033[38;5;44m' '\033[38;5;48m' '\033[38;5;83m' '\033[38;5;155m')
_PULSE=('.' 'o' 'O' 'o')

_meter() {
    local pct="$1" bw=22 fl em i seg out=""
    fl=$(( bw * pct / 100 )); em=$(( bw - fl ))
    i=0
    while [ "$i" -lt "$fl" ]; do
        seg=$(( i * 6 / bw )); [ "$seg" -gt 5 ] && seg=5
        out="${out}${_MG[$seg]}━"; i=$(( i + 1 ))
    done
    out="${out}${GRY}"
    i=0; while [ "$i" -lt "$em" ]; do out="${out}╌"; i=$(( i + 1 )); done
    printf '%b' "$out${NC}"
}

_seal() {
    [ -z "$_PH_NAME" ] && return 0
    local d=$(( SECONDS - _PH_T0 ))
    printf "\r\033[K ${GRY}[${DIM}%02d${GRY}/%02d]${NC} ${LIME}✔${NC} ${DIM}%-18.18s${NC} ${GRY}%02ds${NC}\n" \
        "$INSTALL_STEP" "$INSTALL_TOTAL" "$_PH_NAME" "$d"
}

_phase_line() {
    local marker="$1" pct="$2"
    printf "\r\033[K ${GRY}[${BWHITE}%02d${GRY}/%02d]${NC} ${SKY}%s${NC} ${BWHITE}${BOLD}%-18.18s${NC} %b ${TEAL}${BOLD}%3d%%${NC}" \
        "$INSTALL_STEP" "$INSTALL_TOTAL" "$marker" "$_PH_NAME" "$(_meter "$pct")" "$pct"
}

phase() {
    _seal
    INSTALL_STEP=$(( INSTALL_STEP + 1)); _PH_NAME="$1"; _PH_T0=$SECONDS
    local pct=$(( INSTALL_STEP * 100 / INSTALL_TOTAL )) i
    for i in 0 1 2 3; do
        _phase_line "${_PULSE[$i]}" "$pct"
        [ -t 1 ] && sleep 0.06
    done
    if [ "$INSTALL_STEP" -ge "$INSTALL_TOTAL" ]; then
        _seal; _PH_NAME=""
        printf "\n ${LIME}${BOLD}✔ all %d phases complete${NC} ${GRY}in %02ds${NC}\n" \
            "$INSTALL_TOTAL" "$(( SECONDS - INSTALL_T0 ))"
    fi
}

[[ $EUID -ne 0 ]] && error "This script must be run as root."

CONF_DIR=/etc/ssh-panel
mkdir -p "$CONF_DIR"

clear 2>/dev/null || true
echo ""
echo -e "  ${CORAL}╭──────╮${NC}   ${BWHITE}${BOLD}baymax${CORAL}ssh${NC}"
echo -e "  ${CORAL}│${BWHITE}  •  • ${CORAL}│${NC}   ${GRY}friendly SSH setup${NC}"
echo -e "  ${CORAL}╰─┬──┬─╯${NC}   ${GRY}one protocol · clear controls${NC}"
echo -e "  ${CORAL}  ╰──╯${NC}     ${BWHITE}${BOLD}OpenSSH installer${NC}"
echo ""

apt-get install -y curl >/dev/null 2>&1 || true
SERVER_IP=$(curl -fsS --connect-timeout 8 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$SERVER_IP" ] && SERVER_IP="server-ip"
echo "$SERVER_IP" > "$CONF_DIR/ip.conf"
rm -f "$CONF_DIR/domain.conf" "$CONF_DIR/nsdomain.conf"

_OS=$( (. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME") || echo "Linux" )
echo -e "  ${GRY}┌─ ${BWHITE}${BOLD}SSH-ONLY SETUP${NC} ${GRY}────────────────────────────────────┐${NC}"
printf  "  ${GRY}│${NC}  ${SKY}◆${NC} %-11s ${BWHITE}%-33.33s${NC}${GRY}│${NC}\n" "Server IP" "$SERVER_IP"
printf  "  ${GRY}│${NC}  ${SKY}◆${NC} %-11s ${BWHITE}%-33.33s${NC}${GRY}│${NC}\n" "OS" "$_OS"
printf  "  ${GRY}│${NC}  ${SKY}◆${NC} %-11s ${LIME}%-33.33s${NC}${GRY}│${NC}\n" "Protocol" "OpenSSH only · TCP 22"
printf  "  ${GRY}│${NC}  ${SKY}◆${NC} %-11s ${BWHITE}%-33.33s${NC}${GRY}│${NC}\n" "Steps" "$INSTALL_TOTAL install phases"
echo -e "  ${GRY}└──────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  ${CORAL}${BOLD}▸${NC} ${BWHITE}${BOLD}baymaxssh${NC} ${GRY}is preparing a clean SSH-only server.${NC}"
echo ""
UI_SILENT=1

export DEBIAN_FRONTEND=noninteractive
APT="apt-get install -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"

phase "System packages"
dpkg --configure -a --force-confdef --force-confold >/dev/null 2>&1 || true
apt-get install -f -y </dev/null >/dev/null 2>&1 || true
apt-get update -y </dev/null >/dev/null 2>&1
eval "$APT openssh-server curl vnstat iproute2" </dev/null >/dev/null 2>&1

phase "OpenSSH server"
SSHD_CONF=/etc/ssh/sshd_config
[ ! -f "${SSHD_CONF}.orig" ] && cp "$SSHD_CONF" "${SSHD_CONF}.orig"

apply_sshd_setting() {
    local key="$1" val="$2"
    if grep -qE "^#?${key}[[:space:]]" "$SSHD_CONF"; then
        sed -i "s|^#\?${key}[[:space:]].*|${key} ${val}|g" "$SSHD_CONF"
    else
        echo "${key} ${val}" >> "$SSHD_CONF"
    fi
}

apply_sshd_setting "Port"                   "22"
apply_sshd_setting "PermitRootLogin"        "yes"
apply_sshd_setting "PasswordAuthentication" "yes"
apply_sshd_setting "AllowTcpForwarding"     "yes"
apply_sshd_setting "GatewayPorts"           "yes"
apply_sshd_setting "PermitTunnel"           "yes"
apply_sshd_setting "ClientAliveInterval"    "30"
apply_sshd_setting "ClientAliveCountMax"    "6"
apply_sshd_setting "UseDNS"                 "no"
grep -qxF '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells
sshd -t
systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1 || true
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
SSHD_EFFECTIVE=$(sshd -T 2>/dev/null)
grep -qx 'port 22' <<<"$SSHD_EFFECTIVE" || error "OpenSSH effective configuration is not using TCP 22; legacy services were left untouched."
grep -qx 'passwordauthentication yes' <<<"$SSHD_EFFECTIVE" || error "OpenSSH password login is not active; legacy services were left untouched."
SSH_BANNER=$(timeout 4 bash -c 'exec 3<>/dev/tcp/127.0.0.1/22; IFS= read -r line <&3; printf "%s" "$line"' 2>/dev/null || true)
[[ "$SSH_BANNER" == SSH-* ]] || error "No OpenSSH handshake was received on TCP 22; legacy services were left untouched."

phase "SSH firewall"
if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp >/dev/null 2>&1 || error "Could not open TCP 22 in UFW; legacy services were left untouched."
    if ufw status 2>/dev/null | grep -qi '^Status: active'; then
        ufw status 2>/dev/null | grep -qE '^22/tcp[[:space:]]+ALLOW' || error "UFW did not confirm TCP 22; legacy services were left untouched."
    fi
fi

phase "Legacy cleanup"

# Remove rules first while the old helper scripts still exist.
[ -x /usr/local/bin/hysteria-porthop ] && /usr/local/bin/hysteria-porthop down >/dev/null 2>&1 || true
[ -x /usr/local/bin/abuse-guard ] && /usr/local/bin/abuse-guard disable >/dev/null 2>&1 || true
LEGACY_XRAY_PORTS=$(
    grep -Eo '=[0-9]{1,5}' /etc/xray/ports.conf 2>/dev/null |
        tr -d '=' | awk '$1 >= 1 && $1 <= 65535 && $1 != 22' | sort -un | tr '\n' ' '
)

for svc in dropbear dropbear.socket ws-proxy stunnel4 stunnel xray slowdns hysteria-udp abuse-guard; do
    systemctl stop "$svc" >/dev/null 2>&1 || true
    systemctl disable "$svc" >/dev/null 2>&1 || true
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl kill --kill-who=all --signal=SIGKILL "$svc" >/dev/null 2>&1 || true
        sleep 0.2
    fi
    systemctl is-active --quiet "$svc" 2>/dev/null &&
        error "Legacy service '$svc' is still active; its files were left in place for safe recovery."
done

# Remove only services, binaries and configuration owned by older BaymaxSSH.
rm -f /etc/systemd/system/ws-proxy.service \
      /etc/systemd/system/slowdns.service \
      /etc/systemd/system/hysteria-udp.service \
      /etc/systemd/system/abuse-guard.service \
      /etc/systemd/system/xray.service.d/priv-port.conf \
      /etc/cron.d/xray-check /etc/cron.d/abuse-guard-watchdog \
      /etc/dnsmasq.d/abuse-guard.conf /etc/dnsmasq.d/abuse-guard-wild.conf \
      /etc/fail2ban/jail.d/abuse-guard.local \
      /usr/local/bin/ws-proxy /usr/local/bin/ws-proxy.py \
      /usr/local/bin/.ws-proxy.src.md5 \
      /usr/local/bin/xray /usr/local/bin/xray-gen /usr/local/bin/xray-check \
      /usr/local/bin/dnstt-server \
      /usr/local/bin/hysteria /usr/local/bin/hysteria-porthop \
      /usr/local/bin/abuse-guard 2>/dev/null || true
rm -rf /etc/dropbear /etc/stunnel /etc/xray /usr/local/etc/xray \
       /etc/slowdns /etc/hysteria /etc/abuse-guard \
       /tmp/ws-proxy-build /root/dnstt 2>/dev/null || true

# Restore normal system DNS if an older SlowDNS install disabled the stub.
if [ -f /etc/systemd/resolved.conf.d/slowdns.conf ]; then
    rm -f /etc/systemd/resolved.conf.d/slowdns.conf
    if [ -e /run/systemd/resolve/stub-resolv.conf ]; then
        rm -f /etc/resolv.conf
        ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    fi
    systemctl restart systemd-resolved >/dev/null 2>&1 || true
fi

# Remove firewall openings previously created for non-SSH protocols.
if command -v ufw >/dev/null 2>&1; then
    for rule in 80/tcp 109/tcp 143/tcp 443/tcp 447/tcp 53/udp \
                2082/tcp 2083/tcp 2087/tcp 2095/tcp 2096/tcp 8080/tcp \
                36712/udp 20000:50000/udp; do
        ufw --force delete allow "$rule" >/dev/null 2>&1 || true
    done
    for port in $LEGACY_XRAY_PORTS; do
        ufw --force delete allow "${port}/tcp" >/dev/null 2>&1 || true
    done
fi

if command -v iptables >/dev/null 2>&1; then
    IFACE=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}'); [ -z "$IFACE" ] && IFACE=eth0
    while iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 20000:50000 -j REDIRECT --to-ports 36712 2>/dev/null; do :; done
    iptables -D INPUT -p udp --dport 36712 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p udp --dport 20000:50000 -j ACCEPT 2>/dev/null || true
    for chain in ABUSE_OUT ABUSE_GUARD ABUSE_DOH; do
        while iptables -D OUTPUT -j "$chain" 2>/dev/null; do :; done
        while iptables -D FORWARD -j "$chain" 2>/dev/null; do :; done
        iptables -F "$chain" 2>/dev/null || true
        iptables -X "$chain" 2>/dev/null || true
    done
    for chain in ABUSE_DNS ABUSE_DNSP; do
        while iptables -t nat -D OUTPUT -j "$chain" 2>/dev/null; do :; done
        while iptables -t nat -D PREROUTING -j "$chain" 2>/dev/null; do :; done
        iptables -t nat -F "$chain" 2>/dev/null || true
        iptables -t nat -X "$chain" 2>/dev/null || true
    done
fi

if command -v ip6tables >/dev/null 2>&1; then
    for chain in ABUSE_OUT ABUSE_GUARD ABUSE_DOH; do
        while ip6tables -D OUTPUT -j "$chain" 2>/dev/null; do :; done
        while ip6tables -D FORWARD -j "$chain" 2>/dev/null; do :; done
        ip6tables -F "$chain" 2>/dev/null || true
        ip6tables -X "$chain" 2>/dev/null || true
    done
fi

apt-get purge -y dropbear stunnel4 >/dev/null 2>&1 || true
systemctl daemon-reload >/dev/null 2>&1 || true

phase "Bandwidth monitor"
PRIMARY_IFACE=$(ip route 2>/dev/null | awk '/default/{print $5; exit}')
[ -z "$PRIMARY_IFACE" ] && PRIMARY_IFACE=$(ls /sys/class/net 2>/dev/null | grep -v lo | head -n1)
if [ -n "$PRIMARY_IFACE" ]; then
    echo "$PRIMARY_IFACE" > "$CONF_DIR/iface.conf"
    vnstat --add -i "$PRIMARY_IFACE" >/dev/null 2>&1 || true
fi
systemctl enable vnstat >/dev/null 2>&1 || true
systemctl restart vnstat >/dev/null 2>&1 || true

phase "Management panel"
cat > /usr/local/bin/menu <<'MENUEOF'
#!/bin/bash
# BaymaxSSH OpenSSH-only management panel.

NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'
C='\033[1;36m'; W='\033[1;37m'; GR='\033[0;90m'
TEAL='\033[38;5;44m'; ORANGE='\033[38;5;208m'
LIME='\033[38;5;118m'; SKY='\033[38;5;39m'
VIOLET='\033[38;5;99m'; CORAL='\033[38;5;209m'

CONF_DIR=/etc/ssh-panel
SERVER_IP=$(cat "$CONF_DIR/ip.conf" 2>/dev/null)
[ -z "$SERVER_IP" ] && SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[[ $EUID -ne 0 ]] && { echo -e "${R}Run as root: sudo menu${NC}"; exit 1; }
if locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then export LC_ALL=C.UTF-8; fi

COLS=$(tput cols 2>/dev/null || stty size 2>/dev/null | awk '{print $2}')
[ -z "$COLS" ] && COLS=64
WIDTH=$(( COLS - 4 )); (( WIDTH > 60 )) && WIDTH=60; (( WIDTH < 34 )) && WIDTH=34

_vislen() { local s; s=$(echo -ne "$1" | sed 's/\x1b\[[0-9;]*m//g'); echo -n "${#s}"; }
line_top() { echo -e "${1}╭$(printf '─%.0s' $(seq 1 $WIDTH))╮${NC}"; }
line_mid() { echo -e "${1}├$(printf '─%.0s' $(seq 1 $WIDTH))┤${NC}"; }
line_bot() { echo -e "${1}╰$(printf '─%.0s' $(seq 1 $WIDTH))╯${NC}"; }
row() {
    local col="$1" text="$2" len pad
    len=$(_vislen "$text"); pad=$(( WIDTH - 2 - len )); (( pad < 0 )) && pad=0
    echo -e "${col}│${NC} ${text}$(printf ' %.0s' $(seq 1 $pad)) ${col}│${NC}"
}
crow() {
    local col="$1" text="$2" len left right
    len=$(_vislen "$text"); left=$(( (WIDTH - len) / 2 )); right=$(( WIDTH - len - left ))
    echo -e "${col}│${NC}$(printf ' %.0s' $(seq 1 $left))${text}$(printf ' %.0s' $(seq 1 $right))${col}│${NC}"
}
pause() { echo ""; read -rp "$(echo -e "  ${GR}Press Enter to continue...${NC}")"; }

count_users() {
    awk -F: '$3>=1000 && $7=="/bin/false"{n++} END{print n+0}' /etc/passwd
}
count_online() {
    local n=0 u
    while IFS=: read -r u _ uid _ _ _ shell; do
        [ "$uid" -ge 1000 ] 2>/dev/null && [ "$shell" = "/bin/false" ] && pgrep -u "$u" >/dev/null 2>&1 && n=$((n + 1))
    done < /etc/passwd
    echo "$n"
}

IFACE=$(cat "$CONF_DIR/iface.conf" 2>/dev/null)
[ -z "$IFACE" ] && IFACE=$(ip route 2>/dev/null | awk '/default/{print $5; exit}')
hb() { numfmt --to=iec --suffix=B --format="%.2f" "${1:-0}" 2>/dev/null || echo "${1:-0} B"; }
bw_total() {
    local rx tx
    rx=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
    tx=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)
    echo $((rx + tx))
}

banner() {
    clear; echo ""
    echo -e "  ${CORAL}╭──────╮${NC}   ${W}${BOLD}baymax${CORAL}ssh${NC}"
    echo -e "  ${CORAL}│${W}  •  • ${CORAL}│${NC}   ${GR}friendly SSH setup${NC}"
    echo -e "  ${CORAL}╰─┬──┬─╯${NC}   ${GR}one protocol · clear controls${NC}"
    echo -e "  ${CORAL}  ╰──╯${NC}     ${W}${BOLD}SSH control console${NC}"
    echo ""
}

status_bar() {
    local state dot
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        state="${G}active${NC}"; dot="${G}●${NC}"
    else
        state="${R}offline${NC}"; dot="${R}○${NC}"
    fi
    line_top "$CORAL"; crow "$CORAL" "${W}${BOLD}BAYMAXSSH · OPENSSH ONLY${NC}"; line_mid "$CORAL"
    row "$CORAL" "${GR}HOST${NC}    ${Y}${SERVER_IP}${NC}"
    row "$CORAL" "${GR}USERS${NC}   ${C}$(count_users)${NC} total   ${LIME}$(count_online)${NC} online"
    row "$CORAL" "${GR}DATA${NC}    ${W}${BOLD}$(hb "$(bw_total)")${NC} ${GR}since boot${NC}"
    row "$CORAL" "${GR}SVC${NC}     ${dot} ${W}OpenSSH${NC} ${GR}· TCP 22 ·${NC} ${state}"
    line_bot "$CORAL"
}

section() { banner; line_top "${2:-$TEAL}"; crow "${2:-$TEAL}" "${W}${BOLD}$1${NC}"; line_bot "${2:-$TEAL}"; echo ""; }
ok() { echo -e "  ${G}✔${NC} $*"; }
err() { echo -e "  ${R}✘${NC} $*"; }

show_ssh() {
    line_top "$SKY"; crow "$SKY" "${W}${BOLD}SSH CONNECTION${NC}"; line_mid "$SKY"
    row "$SKY" "${GR}Host${NC}      ${W}${SERVER_IP}${NC}"
    row "$SKY" "${GR}Port${NC}      ${W}22${NC}"
    row "$SKY" "${GR}Protocol${NC}  ${LIME}OpenSSH${NC}"
    line_bot "$SKY"
}

create_user() {
    section "CREATE SSH USER" "$LIME"
    read -rp "$(echo -e "  ${C}Username${NC}   : ")" USERNAME
    [ -z "$USERNAME" ] && { err "Username cannot be empty."; pause; return; }
    [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || { err "Use lowercase letters, numbers, _ or -."; pause; return; }
    id "$USERNAME" >/dev/null 2>&1 && { err "User already exists."; pause; return; }
    read -rp "$(echo -e "  ${C}Password${NC}   : ")" PASSWORD
    [ -z "$PASSWORD" ] && { err "Password cannot be empty."; pause; return; }
    read -rp "$(echo -e "  ${C}Days valid${NC} : ")" DAYS
    [[ "$DAYS" =~ ^[0-9]+$ ]] || DAYS=30
    EXP_DATE=$(date -d "+$DAYS days" +"%Y-%m-%d")
    useradd -e "$EXP_DATE" -M -s /bin/false "$USERNAME"
    printf '%s:%s\n' "$USERNAME" "$PASSWORD" | chpasswd
    banner; ok "Account created."; echo ""; show_ssh
    echo -e "  ${GR}Username${NC}: ${W}${USERNAME}${NC}   ${GR}Password${NC}: ${W}${PASSWORD}${NC}"
    echo -e "  ${GR}Expires${NC}:  ${W}${EXP_DATE}${NC}"
    pause
}

delete_user() {
    section "DELETE SSH USER" "$R"
    read -rp "$(echo -e "  ${C}Username${NC} : ")" USERNAME
    id "$USERNAME" >/dev/null 2>&1 || { err "User does not exist."; pause; return; }
    pkill -u "$USERNAME" 2>/dev/null || true
    userdel -f "$USERNAME" >/dev/null 2>&1
    ok "User '$USERNAME' deleted."; pause
}

list_users() {
    section "SSH USER LIST" "$SKY"
    line_top "$SKY"; row "$SKY" "$(printf '%-16s %-12s %s' USERNAME EXPIRES STATUS)"; line_mid "$SKY"
    local any=0 user uid shell exp stat
    while IFS=: read -r user _ uid _ _ _ shell; do
        if [ "$uid" -ge 1000 ] && [ "$shell" = "/bin/false" ]; then
            any=1; exp=$(chage -l "$user" 2>/dev/null | awk -F: '/Account expires/{gsub(/^ +/,"",$2); print $2}')
            pgrep -u "$user" >/dev/null 2>&1 && stat="${G}online${NC}" || stat="${GR}offline${NC}"
            row "$SKY" "$(printf '%-16s %-12s ' "$user" "$exp")${stat}"
        fi
    done < /etc/passwd
    [ "$any" -eq 0 ] && row "$SKY" "${GR}(no SSH users yet)${NC}"
    line_bot "$SKY"; pause
}

online_users() {
    section "ONLINE SSH USERS" "$LIME"
    local any=0 user uid shell count
    line_top "$LIME"
    while IFS=: read -r user _ uid _ _ _ shell; do
        if [ "$uid" -ge 1000 ] && [ "$shell" = "/bin/false" ]; then
            count=$(pgrep -u "$user" 2>/dev/null | wc -l)
            if [ "$count" -gt 0 ]; then any=1; row "$LIME" "${W}${user}${NC}  ${GR}sessions:${NC} ${C}${count}${NC}"; fi
        fi
    done < /etc/passwd
    [ "$any" -eq 0 ] && row "$LIME" "${GR}(nobody connected right now)${NC}"
    line_bot "$LIME"; pause
}

change_password() {
    section "CHANGE SSH PASSWORD" "$ORANGE"
    read -rp "$(echo -e "  ${C}Username${NC}     : ")" USERNAME
    id "$USERNAME" >/dev/null 2>&1 || { err "User does not exist."; pause; return; }
    read -rp "$(echo -e "  ${C}New password${NC} : ")" PASSWORD
    [ -z "$PASSWORD" ] && { err "Password cannot be empty."; pause; return; }
    printf '%s:%s\n' "$USERNAME" "$PASSWORD" | chpasswd
    ok "Password changed for '$USERNAME'."; pause
}

renew_user() {
    section "RENEW SSH USER" "$VIOLET"
    read -rp "$(echo -e "  ${C}Username${NC}   : ")" USERNAME
    id "$USERNAME" >/dev/null 2>&1 || { err "User does not exist."; pause; return; }
    read -rp "$(echo -e "  ${C}Days valid${NC} : ")" DAYS
    [[ "$DAYS" =~ ^[0-9]+$ ]] || { err "Enter a valid number."; pause; return; }
    EXP_DATE=$(date -d "+$DAYS days" +"%Y-%m-%d")
    chage -E "$EXP_DATE" "$USERNAME"
    ok "User renewed until $EXP_DATE."; pause
}

service_status() {
    section "OPENSSH STATUS" "$C"
    show_ssh; echo ""
    systemctl --no-pager --full status ssh 2>/dev/null | sed -n '1,8p' || \
        systemctl --no-pager --full status sshd 2>/dev/null | sed -n '1,8p'
    pause
}

bandwidth() {
    section "BANDWIDTH USAGE" "$SKY"
    line_top "$SKY"
    row "$SKY" "${GR}Interface${NC}  ${W}${IFACE:-unknown}${NC}"
    row "$SKY" "${GR}Since boot${NC} ${W}${BOLD}$(hb "$(bw_total)")${NC}"
    line_bot "$SKY"
    command -v vnstat >/dev/null 2>&1 && { echo ""; vnstat -i "$IFACE" 2>/dev/null || true; }
    pause
}

restart_ssh() {
    section "RESTART OPENSSH" "$Y"
    if sshd -t && { systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; }; then
        ok "OpenSSH restarted successfully."
    else
        err "OpenSSH restart failed. Configuration was not applied."
    fi
    pause
}

menu_item() { printf "  %b%2s%b ${GR}│${NC} %b%-3s%b %b%s%b\n" "$4" "$1" "$NC" "$4" "$2" "$NC" "$W" "$3" "$NC"; }
menu_group() { echo -e "  ${GR}── ${DIM}$1${NC}"; }

while true; do
    banner; status_bar; echo ""
    menu_group "SSH ACCOUNTS"
    menu_item "1" "+" "Create SSH user"        "$LIME"
    menu_item "2" "x" "Delete SSH user"        "$R"
    menu_item "3" "#" "List all users"         "$SKY"
    menu_item "4" "o" "Show online users"      "$G"
    menu_item "5" "*" "Change user password"   "$ORANGE"
    menu_item "6" "+" "Renew / extend account" "$VIOLET"
    echo ""; menu_group "OPENSSH SERVER"
    menu_item "7" "@" "OpenSSH status"         "$C"
    menu_item "8" "~" "Bandwidth usage"        "$SKY"
    menu_item "9" ">" "Restart OpenSSH"        "$Y"
    echo ""; menu_group "SESSION"
    menu_item "0" "<" "Exit"                   "$GR"
    echo ""; echo -e "  ${GR}baymaxssh · OpenSSH only · Ctrl+C to quit${NC}"
    read -rp "$(echo -e "  ${CORAL}❯${NC} select an option : ")" OPT
    case "$OPT" in
        1) create_user;; 2) delete_user;; 3) list_users;; 4) online_users;;
        5) change_password;; 6) renew_user;; 7) service_status;;
        8) bandwidth;; 9) restart_ssh;;
        0) clear; echo -e "  ${CORAL}Goodbye from baymaxssh.${NC}\n"; exit 0;;
        *) echo -e "  ${R}Invalid option.${NC}"; sleep 1;;
    esac
done
MENUEOF
chmod +x /usr/local/bin/menu

cat > /etc/update-motd.d/00-litronx <<'MOTDEOF'
#!/bin/bash
NC='\033[0m'; BOLD='\033[1m'; GRY='\033[38;5;240m'; W='\033[97m'
CORAL='\033[38;5;209m'; TEAL='\033[38;5;44m'; LIME='\033[38;5;155m'
IP=$(cat /etc/ssh-panel/ip.conf 2>/dev/null)
UP=$(uptime -p 2>/dev/null | sed 's/^up //')
systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null
[ $? -eq 0 ] && STATE="${LIME}● active${NC}" || STATE="\033[1;31m○ offline${NC}"
echo ""
echo -e "  ${CORAL}╭──────╮${NC}   ${W}${BOLD}baymax${CORAL}ssh${NC}"
echo -e "  ${CORAL}│${W}  •  • ${CORAL}│${NC}   ${GRY}OpenSSH-only server${NC}"
echo -e "  ${CORAL}╰─┬──┬─╯${NC}   ${GRY}${IP:-server-ip}:22${NC}"
echo -e "  ${CORAL}  ╰──╯${NC}     ${STATE} ${GRY}· up ${UP:-just now}${NC}"
echo -e "        ${GRY}type ${W}${BOLD}menu${NC}${GRY} to manage SSH users${NC}"
echo ""
MOTDEOF
chmod +x /etc/update-motd.d/00-litronx
: > /etc/motd 2>/dev/null || true
/etc/update-motd.d/00-litronx > /run/motd.dynamic 2>/dev/null || true

phase "Default users"
DEFAULT_USER_PASS="0000"; DEFAULT_USER_DAYS=30
DEFAULT_USER_EXP=$(date -d "+${DEFAULT_USER_DAYS} days" +"%Y-%m-%d")
for U in deon febo geto weon ceon; do
    if ! id "$U" >/dev/null 2>&1; then
        useradd -e "$DEFAULT_USER_EXP" -M -s /bin/false "$U"
        printf '%s:%s\n' "$U" "$DEFAULT_USER_PASS" | chpasswd
    fi
done

UI_SILENT=0
_ELAPSED=$(( SECONDS - INSTALL_T0 ))
clear 2>/dev/null || true
echo ""
echo -e "  ${CORAL}${BOLD}  ✔  BAYMAXSSH SSH-ONLY SETUP COMPLETE${NC}"
echo -e "     ${GRY}Legacy tunnel protocols removed in ${BWHITE}${_ELAPSED}s${GRY}.${NC}"
echo ""
echo -e "  ${TEAL}╭──────────────────────────────────────────────────────╮${NC}"
printf  "  ${TEAL}│${NC}  ${SKY}◆${NC} %-13s ${BWHITE}${BOLD}%-33.33s${NC}${TEAL}│${NC}\n" "Server IP" "$SERVER_IP"
echo -e "  ${TEAL}├─ ${BWHITE}${BOLD}ACTIVE PROTOCOL${NC} ${TEAL}────────────────────────────────────┤${NC}"
printf  "  ${TEAL}│${NC}   ${LIME}▸${NC} %-22s ${BWHITE}%-24s${NC}${TEAL}│${NC}\n" "OpenSSH" "TCP 22"
echo -e "  ${TEAL}├─ ${BWHITE}${BOLD}DEFAULT USERS${NC} ${GRY}(pass: 0000, ${DEFAULT_USER_DAYS}d)${NC} ${TEAL}────────────────────┤${NC}"
printf  "  ${TEAL}│${NC}   ${PINK}●${NC} %-50s${TEAL}│${NC}\n" "deon · febo · geto · weon · ceon"
echo -e "  ${TEAL}╰──────────────────────────────────────────────────────╯${NC}"
echo ""
echo -e "  ${TEAL}${BOLD}▸${NC} Connect with: ${BWHITE}ssh username@${SERVER_IP} -p 22${NC}"
echo -e "  ${TEAL}${BOLD}▸${NC} Type ${LIME}${BOLD}menu${NC} to manage SSH accounts."
echo ""

info "Cleaning install traces from server history..."
[ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ] && rm -f "${BASH_SOURCE[0]}" 2>/dev/null
for f in ssh-ssl-setup.sh /root/ssh-ssl-setup.sh /tmp/ssh-ssl-setup.sh; do
    [ -f "$f" ] && rm -f "$f" 2>/dev/null
done
for H in /root/.bash_history "$HOME/.bash_history" /root/.zsh_history "$HOME/.zsh_history"; do
    [ -f "$H" ] || continue
    sed -i -E '/(ssh-ssl-setup\.sh|raw\.githubusercontent\.com\/kelvinsonatech\/baymaxssh)/d' "$H" 2>/dev/null
done
history -c 2>/dev/null || true
: > "${HISTFILE:-/root/.bash_history}" 2>/dev/null || true
success "SSH-only installation complete"