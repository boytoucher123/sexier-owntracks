# Server pieces

These run on the OwnTracks server phone (Debian in proot-distro, Termux).
[docs/SERVER.md](../docs/SERVER.md) describes the whole setup.

| File | Installed as | What |
|---|---|---|
| `flock-server` | `/usr/local/bin/flock-server` | Accounts, groups, invite codes, ACL file, history check (127.0.0.1:8091) |
| `flock-admin` | `/usr/local/bin/flock-admin` | Owner commands (wrapper around flock-server) |
| `Caddyfile` | `/etc/caddy/Caddyfile` | HTTPS on 8443 for the API and Recorder history |
| `owntracks-start` | `/usr/local/bin/owntracks-start` | Supervisor started at boot: keeps every service running |

Mosquitto needs `acl_file /etc/mosquitto/acl` in `/etc/mosquitto/mosquitto.conf`
(restart mosquitto once after adding it). flock-server writes that file and
`/etc/mosquitto/passwd`, and makes mosquitto reload with SIGHUP.

Tests: `python3 server/test_flock_server.py` (uses temporary files only).
