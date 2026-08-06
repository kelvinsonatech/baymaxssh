---
name: abuse-guard anti-abuse module
description: Design constraints for the menu-toggled abuse protection (egress firewall, fail2ban, torrent block, DNS filter) in ssh-ssl-setup.sh
---

# abuse-guard (ssh-ssl-setup.sh -> /usr/local/bin/abuse-guard)

Menu-toggled (option 12); nothing enforced until enabled, fully reversible.

**Egress firewall must RETURN on ESTABLISHED/RELATED before any rate/port rule.**
**Why:** that keeps bulk data off the inspection path, so throughput cost is
zero — the stated non-negotiable ("don't slow the server"). Only NEW connections
hit the cheap SMTP-block / torrent-port / per-dstip flood-cap rules.
**How to apply:** never add a DPI/string match or a bandwidth-rate limit on the
data path; flood caps are per-dstip NEW-connection limits (500/s burst 1000) so
many users sharing one CDN IP are never clipped.

**Any service the guard touches needs an ownership ledger.** Record whether
dnsmasq/fail2ban pre-existed (`owns_*` flags + prev enabled-state files under
/etc/abuse) at enable; on disable, only stop/disable what the guard installed,
otherwise just reload without the guard's config and restore prior state.
**Why:** blindly stopping/disabling dnsmasq or fail2ban on disable clobbers a
setup the operator already relied on.

**DNS filter now ENFORCES client DNS too** (user reversed the earlier
server-side-only choice after bypass tests): redirect all port-53 lookups into
dnsmasq via BOTH nat OUTPUT (server-side proxies: sshd/xray/ws-proxy) AND nat
PREROUTING (forwarded/TUN clients). PREROUTING must RETURN on
`-m addrtype --dst-type LOCAL` FIRST or it hijacks SlowDNS inbound on PUBIP:53.
PREROUTING→loopback REDIRECT needs `sysctl net.ipv4.conf.all.route_localnet=1`.
OUTPUT must owner-exempt the dnsmasq uid (`id -u dnsmasq`) or upstream queries
loop. Block DoT(853), DoH(443+QUIC to known resolver IPs) on OUTPUT+FORWARD;
reject v6 DNS so clients fall back to v4. Boot unit orders After=dnsmasq.service.
**Large blocklists (1.6M) can silently fail to load / OOM** → dnsmasq is up but
answers real IPs = no filtering. Always verify with a canary dig (@127.0.0.1
must return 0.0.0.0) after start; `abuse-guard test` exposes the whole path.
**Client encrypted DNS the tunnel can't see is the irreducible limit** — if a
site still opens after `test` PASSes, the client isn't routing DNS/web through
the server. Fallback `nameserver 1.1.1.1` so DNS
survives if dnsmasq dies; blocked domains answer 0.0.0.0 instantly so no
fallthrough. Restore resolv.conf FIRST in teardown.

**SlowDNS coexistence on :53 must be transaction-safe.** dnstt binds 0.0.0.0:53;
to free loopback:53 for dnsmasq, rebind dnstt to `${PUBIP}:53` — but only after
verifying PUBIP is actually a local address (`ip -o addr | grep -w`), else skip
the filter. Always restore the original unit and verify slowdns is-active on any
failure; warn loudly if it doesn't come back. See slowdns-udp53.md for the base
:53 constraint.

**Self-test enforcement lesson:** the self-test can show dnsmasq working while
the iptables enforcement rules (OUTPUT port-53 redirect, DoH/DoT blocks) are
missing — this happens when the user updates the script but doesn't re-run the
enable toggle, or when iptables isn't in PATH on the target VPS. Fix pattern:
enable must export sbin PATH / auto-install iptables, and after any installer
update the user should toggle the module off/on to reapply rules. Verified
passing end-to-end on the user's VPS (1.6M-domain blocklist, redirect + DoH
blocks all [ok]).

**Blocklist scope (Aug 6, 2026, user decision):** torrent/piracy ONLY — porn,
betting, fraud/scam feeds removed at user request (only torrenting affects the
server). Feeds: blocklistproject torrent.txt + hagezi anti-piracy
(`wildcard/anti.piracy-onlydomains.txt` — the repo has NO `hosts/` dir; use
wildcard onlydomains or dnsmasq formats). ~41k domains merged. Self-test canary
is thepiratebay.org.
