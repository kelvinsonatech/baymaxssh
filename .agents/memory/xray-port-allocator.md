---
name: xray port allocator & 443 handover
description: How the shared vmess/vless/trojan port scheme and the port-443 handover must behave in ssh-ssl-setup.sh
---

# Xray shared port allocation (ssh-ssl-setup.sh / xray-gen)

All three protocols (vmess/vless/trojan) share ONE canonical Cloudflare-friendly
port scheme (TLS 2083/2087/2096, HTTP 8080/2082/2095; 443 reserved for the SSL
payload/handover). Canonical ports are handed to protocols that are ACTIVE, in
priority order vmess>vless>trojan; later ones roll up to the next free port.

**A protocol is ACTIVE if it has accounts OR it was handed port 443.**
**Why:** if the 443-handover protocol has no accounts, it must still emit an
inbound (empty client list) or nothing binds 443 and the handover check fails +
rolls back. It must also get its own non-colliding ports, so it participates in
allocation, not just emission.

**Allocator must NOT use command substitution.** `_alloc` sets a named variable
(`eval "$2=$p"`); it must never be called as `x=$(_alloc ...)`.
**Why:** `$(...)` runs in a subshell, so the running `_used` reservation list is
discarded between calls and cross-protocol fallback silently produces duplicate
ports → xray fails to start with two inbounds on one port.

**How to apply:** when editing port logic, verify no duplicate ports across all
ACTIVE protocols for these cases: single-protocol, 443-to-protocol-with-account,
443-to-protocol-without-account (but another protocol active), all-three-active.
