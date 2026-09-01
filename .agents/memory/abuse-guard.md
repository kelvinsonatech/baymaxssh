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
`-m addrtype --dst-type LOCAL` FIRST so traffic for the server itself is untouched.
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

**Never-break-protocols invariant (Aug 6, 2026):** port-53 enforcement makes
dnsmasq a single point of failure — if it OOMs under a huge blocklist, ALL
protocols lose DNS and look broken. Guards now in place: (1) RAM-aware cap on
blocklist size (dedupe in feed-priority order so the cap trims the bulk
malicious feed, never the torrent/carding core); (2) enable/refresh fail-open
— canary or dnsmasq failure tears the filter down instead of enforcing a dead
resolver; (3) cron watchdog every minute lifts enforcement if dnsmasq stops
answering. Any future filter change must preserve fail-open.

**SCRIPT STATE (Aug 6 2026, end of day): user hard-reverted to the post-watermark commit.** Everything after it is GONE from the script: tracker/DHT hardening, DHT IP drops, INFRA_ALLOW, xray_install self-heal, torrent-only feed trim, web panel. Feeds again include fraud/scam/phishing/TIF, and the GitHub-in-feed Xray-install failure can recur. The curated-list `#`-comment bug never existed at this state (comments came later) — but if trackers are ever re-added to CBEOF, NO comment lines (see below). User reverts aggressively; keep changes small and expect rollbacks.

**Torrent enforcement = peer-discovery denial, never DPI (design; currently reverted out).** Block
public trackers + DHT bootstrap HOSTNAMES via the DNS filter (curated list +
wildcards) AND drop NEW packets to hard-coded DHT router IPs
(router.bittorrent.com/utorrent/transmissionbt) in the egress chain AFTER the
ESTABLISHED,RELATED RETURN (so only the first UDP/TCP packet is checked → zero
throughput cost). **Why:** a download TOOL (IDM, wget, browser, torrent client)
cannot be selectively blocked — they all use normal HTTP(S)/UDP, and telling a
"pirated movie" download from a legit one needs DPI, which the user has
permanently ruled out (don't-slow-server invariant). Kill the SOURCE
(trackers/DHT/piracy domains) and torrenting fails regardless of app. Never add
a BitTorrent-handshake string match on the data path.

**Feed scope preference: torrent/piracy ONLY (user rule — currently NOT in script due to revert).** After the hard revert restored fraud/scam/phishing/TIF feeds, YouTube/TikTok complaints followed; feeds are back to blocklistproject torrent + hagezi anti-piracy only. Popular platforms (google/youtube/tiktok/socials/netflix) sit in INFRA_ALLOW so no feed can ever block them.

**Infra allowlist (design; currently reverted out).** Aggregated feeds once swept in github.com —
dnsmasq answered 0.0.0.0, curl looped back to the server's own :443 and failed
with a cert-name mismatch, breaking Xray install. `INFRA_ALLOW` (GitHub hosts,
debian/ubuntu mirrors, letsencrypt, cloudflare) is stripped from BLOCK_HOSTS by
`_strip_infra` on EVERY enable/refresh — both the fresh-download and the
"reuse today's list" fast path. Suffix match covers subdomains but not
lookalikes (evil-github.com stays blockable). Any new download source the
script depends on must be added to INFRA_ALLOW.

**NEVER put comment lines in curated.list (Aug 6, 2026 outage).** The wildcard
generator turned every line into `address=/$1/0.0.0.0`; a `#` comment line
became `address=/#/0.0.0.0`, and dnsmasq treats `#` as MATCH-ALL — every domain
on the server resolved to 0.0.0.0 (google.com dead for all users). Generators
now regex-validate each line as a real domain before emitting, but keep
CBEOF comment-free anyway, and after any curated-list change verify
`/etc/dnsmasq.d/abuse-guard-wild.conf` contains no `address=/#/` entry.

**VPN-infra immunity:** never block tcp/443 to well-known resolver IPs —
HTTP Custom / injector configs use 1.1.1.1 / 8.8.8.8 etc. as bug-host/proxy
SNI on 443, so those DoH blocks clip the user's own tunnel. Keep DoT(853) blocks ONLY — no 443 blocking in any form (tcp or udp/QUIC); port-53 redirect stays the primary
enforcement. Blocklist build strips the server's own domain and admin allowlist
so feeds can never blackhole the tunnel's own hosts.
