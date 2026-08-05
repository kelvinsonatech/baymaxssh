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
server-side-only choice after bypass tests): nat OUTPUT redirects all port-53
lookups into dnsmasq (owner-exempt the dnsmasq uid or lookups loop), and known
DoT/DoH resolver endpoints are rejected (ESTABLISHED-return first for zero
cost). v6 DNS is rejected so clients fall back to v4. Boot unit must order
After=dnsmasq.service or enforcement is silently skipped on reboot. Fallback `nameserver 1.1.1.1` so DNS
survives if dnsmasq dies; blocked domains answer 0.0.0.0 instantly so no
fallthrough. Restore resolv.conf FIRST in teardown.

**SlowDNS coexistence on :53 must be transaction-safe.** dnstt binds 0.0.0.0:53;
to free loopback:53 for dnsmasq, rebind dnstt to `${PUBIP}:53` — but only after
verifying PUBIP is actually a local address (`ip -o addr | grep -w`), else skip
the filter. Always restore the original unit and verify slowdns is-active on any
failure; warn loudly if it doesn't come back. See slowdns-udp53.md for the base
:53 constraint.
