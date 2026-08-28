# SSH Command Center

An OpenSSH-only VPS installer and account manager. It intentionally contains no
V2Ray, Xray, VMess, VLESS, Trojan, Hysteria, SlowDNS, WireGuard, OpenVPN,
WebSocket proxy, TLS tunnel, or Dropbear services.

## Install

Test on a fresh Debian 11/12 or Ubuntu 20.04/22.04/24.04 VPS with an active
root shell. Keep your current SSH session open until you confirm a second login
works.

```bash
chmod +x ssh-command-center.sh
sudo ./ssh-command-center.sh install
```

For unattended installation on a custom port:

```bash
sudo SSHCC_PORT=2222 ./ssh-command-center.sh install
```

After installation, open the management console:

```bash
sudo sshcc
```

The console manages SSH accounts, expiry dates, passwords, active sessions,
disconnects, service status, and OpenSSH restarts.

## Security defaults

- Root SSH login is disabled.
- Password and public-key authentication are enabled.
- Fail2ban blocks repeated failed login attempts.
- X11 forwarding and gateway ports are disabled.
- OpenSSH configuration is validated before every restart.
- No default user accounts or hard-coded passwords are created.

## Important

Changing SSH configuration can lock you out of a remote server. Take a VPS
snapshot first and keep one existing root session open while testing a new
account in a separate terminal.