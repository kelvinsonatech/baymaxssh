---
name: myssh setup script conventions
description: Durable rules for editing/pushing the standalone SSH/VPN setup script (repo kelvinsonatech/myssh)
---
- Standalone publish target is `github.com/kelvinsonatech/baymaxssh` on `main`. Edit `scripts/ssh-ssl-setup.sh`, copy to repo-root `ssh-ssl-setup.sh` before every local commit, and keep both copies identical.
- Install URL: raw.githubusercontent.com/kelvinsonatech/baymaxssh/main/ssh-ssl-setup.sh (append `?v=$(date +%s)` to bust cache).
- Validation per change: `bash -n` on main script + extract each embedded heredoc (esp. `/usr/local/bin/menu`) and `bash -n` it. No runtime here; real testing on user's server.
- **Why heredoc helpers bite:** the menu heredoc is a separate script — helpers like `warn` defined in the installer don't exist inside it; define helpers in both scopes.
- **Port 443 handover lesson:** Xray runs as non-root; binding 443 needs `AmbientCapabilities=CAP_NET_BIND_SERVICE` drop-in. Always release-then-bind order between stunnel/xray, wait for the port to free, and roll back on failure so users keep 443 SSH.
- The api-server/mockup-sandbox workflows in this workspace are unrelated to this script — ignore their logs.
- **`set -e` gotcha:** the installer runs under `set -e`, so a bare `[ cond ] && cmd` as a statement's last line aborts the whole script when the test is false (returns 1). Use `if [ cond ]; then cmd; fi` instead. Bit us in the phase() progress function.
- User wants minimal, tight-scoped changes; open question: suspend (keep UUID) vs delete over-limit Xray accounts.
