---
name: Hysteria UDP tunnel (menu option 13)
description: How the high-speed UDP (Hysteria 1) tunnel is wired into ssh-ssl-setup.sh and why it can't break the other protocols
---

# UDP (Hysteria) tunnel — ssh-ssl-setup.sh menu 13

Added Aug 2026 from the user's AGN-UDP paste. AGN-UDP is a **Hysteria 1** fork
(the paste's "badvpn-udpgw" description is wrong). Implemented with upstream
Hysteria 1 (`apernet/hysteria` release tag `v1.3.5`, asset
`hysteria-linux-<arch>`). Gotchas: v1 release tags are plain `vX.Y.Z` — the
`app/vX.Y.Z` prefix belongs to Hysteria 2 and 404s, and a 404 page saved as the
binary causes "Exec format error"; always `curl -fL`, run `--version` (v1 has
no `version` subcommand) to validate, and never trust a mere `[ -x ]` check —
delete corrupt leftovers or the installer skips re-download forever.

**Auth format (critical):** AGN-style UDP client apps authenticate with the
**password ONLY**, not `username:password`. Users are stored as `username:password`
lines in `/etc/hysteria/users` for our own bookkeeping, but `hy_write_config`
must emit ONLY the password part (`${line#*:}`) into Hysteria's
`auth.mode=passwords` list. Emitting the full `user:pass` string was the bug
that made the app silently fail to connect (login never matched). Shared `obfs`
stored in `/etc/hysteria/obfs`, defaulted to the first username (matches AGN
"Li-Quest" panels where OBFS(U)==first user). Self-signed cert → clients must
enable "allow insecure".

**Port hopping:** Hysteria listens on ONE base UDP port (36712); iptables
REDIRECTs the whole UDP range 20000-50000 to it. Range + base are hardcoded in
the `/usr/local/bin/hysteria-porthop up|down` helper AND in the installer vars
`HY_PORT/HY_HOP_LO/HY_HOP_HI` — **keep them in sync** (helper is a quoted
heredoc so it can't read the vars). The helper must `export PATH` with sbin
dirs first — systemd's minimal PATH misses /usr/sbin on some distros and
iptables becomes "command not found" (same lesson as abuse-guard); installer
also apt-installs iptables if absent.

**Why it can't break other protocols:** all rules are UDP-only. Every other
protocol (SSH/SSL/WS/V2Ray) is TCP. The
REDIRECT lives in nat/PREROUTING (ingress), separate from abuse-guard's egress
OUTPUT chain. Rules apply/cleanup via the unit's ExecStartPre/ExecStopPost so
they persist across reboot and vanish on deactivate.

**Not a payload/bug-host replacement:** Hysteria is UDP/QUIC — it does NOT use
payloads or bug hosts, so it will NOT work on zero-data/free-bundle tricks. It's
for paid data (fast, gaming/streaming). Told the user this explicitly.

## ZIVPN attempt — reverted, do not retry without a real device
ZIVPN (Android app) menu option was added then FULLY reverted per user request. Config was made byte-identical to upstream `zahidbd2/udp-zivpn` (`:5667`, fixed `obfs:"zivpn"` — app has NO obfs field, `auth mode passwords`, password-only, hop 6000-19999→5667) and stock Hysteria 1.3.5 accepted a matching Hysteria client in local tests — but it still would NOT connect from the user's real ZIVPN app.
**Why:** official ZIVPN uses its OWN forked binary (`udp-zivpn-linux-amd64`, ~hysteria 1.4.9), not stock hysteria; a local hysteria-vs-hysteria test cannot catch the real protocol/handshake difference. Do not claim ZIVPN == stock Hysteria + obfs=zivpn.
**How to apply:** if ZIVPN is requested again, do NOT reuse the stock hysteria binary assuming compat. Use the upstream zivpn binary (security review first) or get the user to test on a real device early, and STOP after 1-2 failed real-device attempts instead of iterating blind.
