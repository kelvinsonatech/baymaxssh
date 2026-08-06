---
name: Browser DoH bypass of the DNS content filter
description: Why/how the abuse-guard filter neutralizes browser encrypted DNS without touching port 443
---

# Browser DoH bypass

**Symptom:** users dodge the dnsmasq content filter by searching a blocked site on Google and clicking the result — it opens.

**Cause:** Chrome/Firefox/Brave/Edge use their own DoH resolver over port 443, so they never query the server's port-53 filter. Port 443 cannot be blocked — it carries the VPN's own proxy/bug-host path.

**Fix (light, no new services):** poison DoH at the DNS layer so browsers fall back to classic DNS (which is filtered):
- `DOH_BOOTSTRAP` static list (~45 provider bootstrap *hostnames*) is force-added to `$BLOCK_HOSTS` as `0.0.0.0` via `_ensure_doh_block`, called in BOTH the reuse fast-path and the full build path of `fetch_blocklist`, AFTER the whitelist strip so it can't be removed.
- Firefox canary: `server=/use-application-dns.net/` in the dnsmasq conf returns NXDOMAIN (Mozilla's documented admin opt-out). NOTE: 0.0.0.0 does NOT disable Firefox DoH — the canary needs NXDOMAIN/NODATA, hence `server=/.../` not an addn-hosts entry.

**Why safe for the tunnel:** only DoH *hostnames* are poisoned. HTTP Custom bug hosts use raw IPs (1.1.1.1) or CDN SNIs, and dnsmasq upstreams are set by IP — so port 443 is never touched.

**Residual limit:** a user who manually hard-codes a custom DoH server in-app is outside DNS visibility; only automatic browser DoH is closed.
