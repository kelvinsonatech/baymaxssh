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

**How to apply:** before starting slowdns, disable resolved's stub listener
(`/etc/systemd/resolved.conf.d/*.conf` -> `[Resolve]\nDNSStubListener=no`),
rewrite `/etc/resolv.conf` to a real resolver (1.1.1.1/8.8.8.8) so name
resolution still works, `fuser -k 53/udp`, then restart resolved. After
`systemctl restart slowdns`, verify with `systemctl is-active` and surface a
warning pointing at `journalctl -u slowdns` if it's not active. Also open
UDP 53 in ufw. Client needs: NS domain, server.pub key, a public DNS resolver,
and a normal SSH account (SlowDNS just tunnels to 127.0.0.1:22).
