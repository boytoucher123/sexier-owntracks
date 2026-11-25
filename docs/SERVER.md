# The server this app talks to

Flock is built for one OwnTracks server: an Android phone at home running
Debian (proot-distro in Termux) with **mosquitto** and **ot-recorder**.
No passwords are kept in this repo.

## App settings

| Setting | Value |
|---|---|
| Server address | `owntracks-class-of-2024.duckdns.org` (pre-filled) |
| Port | `8883` (pre-filled) |
| Secure connection | **On** |
| Allow self-signed certificate | **Off** (not needed; see below) |
| WebSockets | Off (the broker has no WebSocket listener) |
| Username / password | made by the server at sign-up, never typed |
| Recorder URL | `https://owntracks-class-of-2024.duckdns.org:8443` (pre-filled; uses the account's login) |

Each person is `owntracks/<username>/phone`, with the username made from their
name (`Fred Durk` becomes `fred-durk`).

## Accounts and groups (flock-server)

`server/flock-server` runs on `127.0.0.1:8091`. Caddy publishes it at
`https://…:8443/flock/api/`. It is Python standard library only and keeps its
data in `/var/lib/flock/flock.db` (sqlite).

- **Sign-up:** `POST /flock/api/signup {"name"}` makes the username and a random
  password, adds them to `/etc/mosquitto/passwd` (mosquitto's own `$7$`
  format), and returns them once. Limits: 3 per IP per hour, 30 a day.
- **Groups:** anyone can start one and becomes its leader. Joining is by invite
  code, and the leader approves each request. A leader can make a new code,
  rename the group, remove people or hand over leadership. When the leader
  leaves, the longest-standing member takes over; when the last member leaves,
  the group is deleted.
- **Privacy is enforced by mosquitto.** After every change flock-server
  rewrites `/etc/mosquitto/acl` and sends mosquitto SIGHUP, which reloads it
  without disconnecting anyone. Each user can read and write their own topics,
  read the people they share a group with, and send them a refresh command.
  A leader can also read the card (name and photo) of someone asking to join.
- **History:** Caddy asks flock-server before each Recorder request. Only
  `/api/0/locations` for yourself or someone in your groups is allowed.
- **Owner commands:** `flock-admin users | groups | add-user NAME |
  delete-user USER | rewrite-acl`.
- **Tests:** `python3 server/test_flock_server.py`.

## Broker

- Listeners: `1883` plain (LAN only), `8883` TLS (the router forwards it from the
  internet), `8884` TLS (spare, not forwarded).
- `allow_anonymous false`, with the password file and the ACL file
  (`acl_file /etc/mosquitto/acl`) both written by flock-server.
- The public IP is dynamic. DuckDNS keeps the hostname pointed at it.

## History (Recorder)

- ot-recorder stores every location it sees on MQTT and serves an HTTP API on
  `127.0.0.1:8083` only.
- **Caddy** publishes it on **`8443`** (HTTPS, same certificate as MQTT). The
  router forwards TCP 8443 to the server.
- **Login is the account's MQTT login**, checked by flock-server against
  mosquitto's password file. Ten wrong passwords from one IP block it for 15 minutes.
- **Read-only, own groups only:** only `GET /api/0/locations` (for you or
  someone in your groups) and `/version` get through. Everything else returns
  403 or 404.
- **Retention:** `owntracks-prune` runs hourly and deletes points older than
  4 days. The app offers today and the two days before.

## Certificates

The server certificate is signed by a private CA, **"OwnTracks MQTT CA"**
(valid until 2036, SHA-256 fingerprint
`F7:3B:F6:B2:2E:CC:49:FB:E9:3A:7A:93:30:1E:90:02:DA:E2:9B:0A:E8:0E:36:A7:BF:94:F8:B0:11:9C:03:61`).
The CA's certificate is bundled in `lib/config/server_config.dart` and added to
the phone's trusted roots for the MQTT connection. Certificate checks stay fully
on, and no one has to install anything.

- The server certificate covers `owntracks-class-of-2024.duckdns.org`, `localhost`,
  `127.0.0.1` and `192.168.0.216`. Connecting by the public IP fails with a
  hostname mismatch, so use the DuckDNS name.
- Server certificates can be reissued without an app update as long as the
  same CA signs them. A new CA would need a new app build.

## Testing against the real broker

On the server, where `localhost` is in the certificate:

```bash
flock-admin add-user "Flock Test"        # prints a throwaway login
FLOCK_REAL_USER=flock-test FLOCK_REAL_PASSWORD='…' \
  flutter test test/mqtt_integration_test.dart
flock-admin delete-user flock-test
```
