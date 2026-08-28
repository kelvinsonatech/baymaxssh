# SSH Command Center

An OpenSSH-only VPS installer and account manager. It intentionally contains no
V2Ray, Xray, VMess, VLESS, Trojan, Hysteria, SlowDNS, WireGuard, OpenVPN,
WebSocket proxy, TLS tunnel, or Dropbear services.

This is a new installer. It does not replace or modify the older
`ssh-ssl-setup.sh` script.

## Install

Test on a fresh Debian 11/12 or Ubuntu 20.04/22.04/24.04 VPS with an active
root shell. Keep your current SSH session open until you confirm a second login
works.

### Direct install from GitHub

The hosted copy is available at:

`https://raw.githubusercontent.com/kelvinsonatech/myssh/replit-agent/ssh-command-center.sh`

Download it before running so the installer can install its `sshcc` command:

```bash
curl -fsSL https://raw.githubusercontent.com/kelvinsonatech/myssh/replit-agent/ssh-command-center.sh \
  -o /tmp/ssh-command-center.sh
chmod +x /tmp/ssh-command-center.sh
sudo /tmp/ssh-command-center.sh install
```

### Local install

```bash
chmod +x ssh-command-center.sh
sudo ./ssh-command-center.sh install
```

After installation, open the management console:

```bash
sudo sshcc
```

The console manages SSH accounts, expiry dates, passwords, active sessions,
disconnects, service status, bandwidth counters, and OpenSSH restarts.

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