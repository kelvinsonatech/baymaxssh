---
name: SlowDNS (dnstt) UDP 53 binding
description: Why SlowDNS silently fails to start and how the installer fixes it
---

# SlowDNS (dnstt-server) needs UDP 53 free, or it silently dies

`dnstt-server -udp :53 ...` binds 0.0.0.0:53. On most Ubuntu/Debian VPS,
`systemd-resolved` (or dnsmasq) already occupies port 53, so the systemd unit
starts, fails to bind, and keeps restarting with no obvious error to the user.

**Why:** two SlowDNS install attempts "looked correct" (matched a working
reference installer) but the tunnel never came up — the missing step was freeing
port 53, which neither the reference nor the first attempt did.

**How to apply:** disable only systemd-resolved's stub listener; never use a
broad `fuser -k 53/udp`, because that can kill the intentional dnsmasq content
filter. If dnsmasq is active, bind dnstt to the server's locally assigned public
IP on UDP 53 so dnsmasq can retain loopback:53; otherwise dnstt may bind `:53`.
After restart, verify `systemctl is-active`, open only UDP 53 in ufw, and restore
the previous unit transactionally if repair fails. Client needs the NS domain,
server.pub key, a public DNS resolver, and a normal SSH account.

**Do not let SlowDNS abort the installer.** The main script runs `set -e`. The
SlowDNS phase has unguarded fail-prone commands (apt, `git clone` bamsoftware,
`go build`); a non-zero exit there killed the whole install (left the box with
no `menu`). Wrap the entire phase in `set +e` … `set -e`. Toolchain: try apt
`golang-go` first, fall back to the official go.dev tarball (arch-aware) — apt's
Go can be too old to build current dnstt. Backend is `127.0.0.1:22` (OpenSSH),
matching the SSL-payload backend. Working impl landed after the errexit guard.
