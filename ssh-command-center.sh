#!/usr/bin/env bash
# SSH Command Center — OpenSSH-only VPS installer and account manager.
# Supported: Debian 11/12 and Ubuntu 20.04/22.04/24.04.

set -Eeuo pipefail

readonly APP_NAME="SSH Command Center"
readonly APP_DIR="/etc/ssh-command-center"
readonly SSHD_DROPIN="/etc/ssh/sshd_config.d/90-ssh-command-center.conf"
readonly MENU_BIN="/usr/local/bin/sshcc"

RED='\033[38;5;203m'
GREEN='\033[38;5;84m'
CYAN='\033[38;5;45m'
BLUE='\033[38;5;75m'
YELLOW='\033[38;5;221m'
WHITE='\033[97m'
GRAY='\033[38;5;244m'
BOLD='\033[1m'
RESET='\033[0m'

die() { printf "\n%bError:%b %s\n" "$RED" "$RESET" "$*" >&2; exit 1; }
ok() { printf "  %b✓%b %s\n" "$GREEN" "$RESET" "$*"; }
note() { printf "  %b•%b %s\n" "$CYAN" "$RESET" "$*"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this command as root."; }

banner() {
  clear
  printf "%b" "$CYAN"
  cat <<'EOF'
   ╭──────────────────────────────────────────────╮
   │          SSH COMMAND CENTER                  │
   │        Secure access. One protocol.          │
   ╰──────────────────────────────────────────────╯
EOF
  printf "%b\n" "$RESET"
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

detect_service() {
  if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
    printf "ssh"
  else
    printf "sshd"
  fi
}

restart_ssh() {
  local service
  service="$(detect_service)"
  sshd -t || die "OpenSSH configuration check failed. Existing service was not restarted."
  systemctl enable "$service" >/dev/null 2>&1 || true
  systemctl restart "$service"
}

configure_firewall() {
  local port="$1"
  command_exists ufw || return 0
  ufw allow "${port}/tcp" comment "$APP_NAME" >/dev/null 2>&1 || true
}

install_fail2ban() {
  cat > /etc/fail2ban/jail.d/ssh-command-center.conf <<'EOF'
[sshd]
enabled = true
port = ssh
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
  systemctl enable --now fail2ban >/dev/null 2>&1
}

write_menu() {
  install -m 0755 "$0" "$MENU_BIN"
}

install_server() {
  require_root
  banner

  [[ -r /etc/os-release ]] || die "This installer requires Debian or Ubuntu."
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) die "Unsupported operating system: ${PRETTY_NAME:-unknown}" ;;
  esac

  # Keep the same default SSH endpoint as the original installer.
  local port="22"

  note "Updating package indexes"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq

  note "Installing OpenSSH and protection tools"
  apt-get install -y -qq openssh-server fail2ban ufw curl ca-certificates

  install -d -m 0755 "$APP_DIR" /etc/ssh/sshd_config.d
  [[ -f /etc/ssh/sshd_config ]] || die "OpenSSH server configuration was not found."

  cat > "$SSHD_DROPIN" <<EOF
# Managed by $APP_NAME
Port $port
Protocol 2
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
UsePAM yes
AllowTcpForwarding yes
GatewayPorts no
X11Forwarding no
PermitTunnel yes
ClientAliveInterval 60
ClientAliveCountMax 3
MaxAuthTries 4
LoginGraceTime 30
UseDNS no
EOF

  printf "%s\n" "$port" > "$APP_DIR/port"
  chmod 0600 "$APP_DIR/port"

  note "Checking OpenSSH configuration"
  configure_firewall "$port"
  install_fail2ban
  write_menu
  restart_ssh

  banner
  ok "OpenSSH is installed and running"
  ok "Fail2ban is protecting SSH logins"
  ok "Management command installed: sshcc"
  printf "\n  %bPort%b       %s\n" "$GRAY" "$RESET" "$port"
  printf "  %bRoot login%b disabled\n" "$GRAY" "$RESET"
  printf "  %bProtocols%b  OpenSSH only\n\n" "$GRAY" "$RESET"
  printf "  Run %bsshcc%b to create users and manage the server.\n\n" "$GREEN$BOLD" "$RESET"
}

ssh_port() {
  if [[ -s "$APP_DIR/port" ]]; then
    cat "$APP_DIR/port"
  else
    sshd -T 2>/dev/null | awk '/^port / {print $2; exit}'
  fi
}

valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]
}

create_user() {
  local username password days expiry
  banner
  printf "  %bCREATE SSH ACCOUNT%b\n\n" "$WHITE$BOLD" "$RESET"
  read -r -p "  Username: " username
  valid_username "$username" || die "Use lowercase letters, numbers, underscores, or hyphens."
  id "$username" >/dev/null 2>&1 && die "User '$username' already exists."
  read -r -s -p "  Password: " password; printf "\n"
  [[ ${#password} -ge 8 ]] || die "Password must contain at least 8 characters."
  read -r -p "  Validity in days [30]: " days
  days="${days:-30}"
  [[ "$days" =~ ^[0-9]+$ ]] && (( days >= 1 && days <= 3650 )) || die "Days must be between 1 and 3650."
  expiry="$(date -d "+${days} days" +%F)"
  useradd -m -s /bin/bash -e "$expiry" "$username"
  printf "%s:%s\n" "$username" "$password" | chpasswd
  passwd -u "$username" >/dev/null 2>&1 || true
  ok "Account '$username' created; expires $expiry."
}

delete_user() {
  local username answer
  banner
  read -r -p "  Username to delete: " username
  id "$username" >/dev/null 2>&1 || die "User '$username' does not exist."
  [[ "$username" != "root" ]] || die "Root cannot be deleted."
  read -r -p "  Delete '$username' and its home directory? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] || return 0
  pkill -KILL -u "$username" >/dev/null 2>&1 || true
  userdel -r "$username"
  ok "Account '$username' deleted."
}

renew_user() {
  local username days expiry
  banner
  read -r -p "  Username to renew: " username
  id "$username" >/dev/null 2>&1 || die "User '$username' does not exist."
  read -r -p "  Extend from today by days [30]: " days
  days="${days:-30}"
  [[ "$days" =~ ^[0-9]+$ ]] && (( days >= 1 && days <= 3650 )) || die "Invalid number of days."
  expiry="$(date -d "+${days} days" +%F)"
  chage -E "$expiry" "$username"
  ok "Account '$username' now expires $expiry."
}

change_password() {
  local username
  banner
  read -r -p "  Username: " username
  id "$username" >/dev/null 2>&1 || die "User '$username' does not exist."
  passwd "$username"
}

list_users() {
  banner
  printf "  %b%-20s %-13s %-12s%b\n" "$WHITE$BOLD" "USERNAME" "EXPIRES" "STATUS" "$RESET"
  printf "  %b────────────────────────────────────────────────%b\n" "$GRAY" "$RESET"
  while IFS=: read -r user _ uid _ _ _ shell; do
    (( uid >= 1000 )) || continue
    [[ "$shell" != */nologin && "$shell" != */false ]] || continue
    local expiry status
    expiry="$(chage -l "$user" | awk -F': ' '/Account expires/ {print $2}')"
    passwd -S "$user" 2>/dev/null | grep -q ' L ' && status="locked" || status="active"
    printf "  %-20s %-13s %-12s\n" "$user" "${expiry:0:13}" "$status"
  done < /etc/passwd
}

online_users() {
  banner
  printf "  %bACTIVE SSH SESSIONS%b\n\n" "$WHITE$BOLD" "$RESET"
  if ! who | grep -q .; then
    printf "  No interactive sessions are active.\n"
    return
  fi
  who
  printf "\n"
  ss -tnp 2>/dev/null | awk -v p=":$(ssh_port)" '$1 == "ESTAB" && $4 ~ p {print "  " $4 "  ←  " $5}'
}

disconnect_user() {
  local username
  banner
  read -r -p "  Username to disconnect: " username
  id "$username" >/dev/null 2>&1 || die "User '$username' does not exist."
  [[ "$username" != "root" ]] || die "Root sessions are not managed here."
  pkill -KILL -u "$username" >/dev/null 2>&1 || true
  ok "All sessions for '$username' disconnected."
}

service_status() {
  local service state port ip
  banner
  service="$(detect_service)"
  state="$(systemctl is-active "$service" 2>/dev/null || true)"
  port="$(ssh_port)"
  ip="$(curl -4fsS --max-time 3 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
  printf "  %bSERVER STATUS%b\n\n" "$WHITE$BOLD" "$RESET"
  printf "  %-18s %s\n" "OpenSSH" "$state"
  printf "  %-18s %s\n" "Public address" "${ip:-unavailable}"
  printf "  %-18s %s/tcp\n" "SSH port" "$port"
  printf "  %-18s %s\n" "Fail2ban" "$(systemctl is-active fail2ban 2>/dev/null || true)"
  printf "  %-18s %s\n" "Uptime" "$(uptime -p)"
  printf "  %-18s %s\n" "Load" "$(cut -d' ' -f1-3 /proc/loadavg)"
}

bandwidth_status() {
  banner
  printf "  %bBANDWIDTH%b\n\n" "$WHITE$BOLD" "$RESET"
  if command_exists vnstat; then
    vnstat --oneline 2>/dev/null || vnstat 2>/dev/null || true
  else
    printf "  vnstat is not installed; showing interface counters instead.\n\n"
    ip -s link 2>/dev/null | sed -n '1,80p' || true
  fi
}

pause() {
  printf "\n"
  read -r -p "  Press Enter to continue..." _
}

menu() {
  require_root
  while true; do
    banner
    printf "  %bOpenSSH%b  %s  %b│%b  %bPort%b  %s\n\n" \
      "$GRAY" "$RESET" "$(systemctl is-active "$(detect_service)" 2>/dev/null || true)" \
      "$GRAY" "$RESET" "$GRAY" "$RESET" "$(ssh_port)"
    printf "  %b1%b  Create SSH account\n" "$GREEN" "$RESET"
    printf "  %b2%b  Delete SSH account\n" "$RED" "$RESET"
    printf "  %b3%b  List SSH accounts\n" "$BLUE" "$RESET"
    printf "  %b4%b  Show active sessions\n" "$CYAN" "$RESET"
    printf "  %b5%b  Disconnect a user\n" "$YELLOW" "$RESET"
    printf "  %b6%b  Change password\n" "$BLUE" "$RESET"
    printf "  %b7%b  Renew account\n" "$GREEN" "$RESET"
    printf "  %b8%b  Server status\n" "$CYAN" "$RESET"
    printf "  %b9%b  Bandwidth usage\n" "$BLUE" "$RESET"
    printf "  %b10%b Restart OpenSSH\n" "$YELLOW" "$RESET"
    printf "  %b0%b  Exit\n\n" "$GRAY" "$RESET"
    read -r -p "  Select an option: " option
    case "$option" in
      1) create_user; pause ;;
      2) delete_user; pause ;;
      3) list_users; pause ;;
      4) online_users; pause ;;
      5) disconnect_user; pause ;;
      6) change_password; pause ;;
      7) renew_user; pause ;;
      8) service_status; pause ;;
      9) bandwidth_status; pause ;;
      10) restart_ssh; ok "OpenSSH restarted."; pause ;;
      0) clear; exit 0 ;;
      *) sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  install) install_server ;;
  menu) menu ;;
  "") install_server ;;
  --help|-h)
    cat <<EOF
$APP_NAME

Usage:
  sudo bash $0           Install and secure an OpenSSH-only server
  sudo bash $0 install   Install and secure an OpenSSH-only server
  sudo sshcc             Open the account management console

The SSH service remains on TCP port 22, matching the original installer.
EOF
    ;;
  *) die "Unknown command '$1'. Use --help." ;;
esac