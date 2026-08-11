---
name: Hysteria UDP tunnel (menu option 13)
description: How the high-speed UDP (Hysteria 1) tunnel is wired into ssh-ssl-setup.sh and why it can't break the other protocols
---

# UDP (Hysteria) tunnel — ssh-ssl-setup.sh menu 13

Added Aug 2026 from the user's AGN-UDP paste. AGN-UDP is a **Hysteria 1** fork
(the paste's "badvpn-udpgw" description is wrong). Implemented with upstream
Hysteria 1 (`apernet/hysteria` release tag `app/v1.3.5`, asset
`hysteria-linux-<arch>`).

**Auth format:** users are `username:password` lines in `/etc/hysteria/users`,
emitted into Hysteria's `auth.mode=passwords` list. That combined `user:pass`
string is exactly what UDP client apps (UDP Custom / HTTP Injector UDP /
NapsternetV) send. Shared `obfs` password stored in `/etc/hysteria/obfs`.
Self-signed cert → clients must enable "allow insecure".

**Port hopping:** Hysteria listens on ONE base UDP port (36712); iptables
REDIRECTs the whole UDP range 20000-50000 to it. Range + base are hardcoded in
the `/usr/local/bin/hysteria-porthop up|down` helper AND in the installer vars
`HY_PORT/HY_HOP_LO/HY_HOP_HI` — **keep them in sync** (helper is a quoted
heredoc so it can't read the vars). The helper must `export PATH` with sbin
dirs first — systemd's minimal PATH misses /usr/sbin on some distros and
iptables becomes "command not found" (same lesson as abuse-guard); installer
also apt-installs iptables if absent.

**Why it can't break other protocols:** all rules are UDP-only. Every other
protocol (SSH/SSL/WS/V2Ray) is TCP; SlowDNS is UDP 53, outside 20000-50000. The
REDIRECT lives in nat/PREROUTING (ingress), separate from abuse-guard's egress
OUTPUT chain. Rules apply/cleanup via the unit's ExecStartPre/ExecStopPost so
they persist across reboot and vanish on deactivate.

**Not a payload/bug-host replacement:** Hysteria is UDP/QUIC — it does NOT use
payloads or bug hosts, so it will NOT work on zero-data/free-bundle tricks. It's
for paid data (fast, gaming/streaming). Told the user this explicitly.
