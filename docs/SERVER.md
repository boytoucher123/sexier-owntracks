# Running a Flock server

The app has **no server built in**. Everything comes from the invite a group
leader shares: the server address, the certificate to trust and the group code.
Without an invite the app can't connect anywhere.

A Flock server is an OwnTracks setup (**mosquitto** and **ot-recorder**) plus
`server/flock-server` for accounts and groups, behind **Caddy**. The reference
deployment is a Debian phone (proot-distro in Termux). No passwords or hostnames
are kept in this repo.

## Server details: `/etc/flock/server.json`

```json
{
  "public_host": "your.host.example",
  "api_port": 8443,
  "mqtt_port": 8883,
  "ca_file": "/etc/mosquitto/certs/ca.crt"
}
```

With a public certificate (the reference server uses Let's Encrypt through
DuckDNS, renewed by acme.sh from `server/owntracks-start`, which then runs
`server/owntracks-cert-reload`), leave `ca_file` out.
`ca_file` is only needed with a private CA. Its SHA-256 goes into every invite
(`?ca=…`), and the app checks the downloaded CA against that fingerprint before
trusting it. Leave it out with a public certificate.

## Invites

`flock-admin invite GROUP_ID` prints the invite:

- `https://HOST:PORT/flock/join/CODE?ca=FP`: a page with an **Open in Flock**
  button. This is the form to share in chats.
- `flock://HOST:PORT/join/CODE?ca=FP`: opens Flock directly with the invite
  filled in. Pasting either form into the app also works.

Joining signs you up on that server (or reuses your login there) and asks the
leader to approve.

Each person is `owntracks/<username>/phone`. The username is made from their
name: `Fred Durk` becomes `fred-durk`.

## Accounts and groups (flock-server)

`server/flock-server` runs on `127.0.0.1:8091`. Caddy publishes it at
`https://…:8443/flock/`. It uses only the Python standard library and keeps its
data in `/var/lib/flock/flock.db` (sqlite).

- **Sign-up:** `POST /flock/api/signup {"name"}` makes the username and a random
  password, adds them to `/etc/mosquitto/passwd` (mosquitto's own `$7$`
  format), and returns them once. Limits: 3 per IP per hour, 30 a day.
- **Groups:**
  - Anyone can start a group and becomes its leader.
  - Joining is by invite, and the leader approves each request.
  - A leader can make a new code, rename the group, remove people or hand over
    leadership.
  - When the leader leaves, the longest-standing member takes over. When the
    last member leaves, the group is deleted.
- **Privacy is enforced by mosquitto:**
  - After every change, flock-server rewrites `/etc/mosquitto/acl` and sends
    mosquitto SIGHUP, which reloads it without disconnecting anyone.
  - Each user can read and write their own topics, read the people they share a
    group with, and send them a refresh command.
  - Groups on the same server can't see each other. You only see people you
    share a group with.
  - A leader can also read the card (name and photo) of someone asking to join.
- **Group settings:**
  - Each group has a `config`. It is either `{"standard": true}` (runs on this
    server) or the leader's own server (host, port, TLS, optional CA, history
    address and topic prefix). There is no shared group login: everyone signs
    in with their own account either way.
  - Both kinds carry `tracking_mode`, which is the group's default. Each person
    can pick their own tracking level in the app.
  - Only approved members receive the config.
  - **New groups start with no config and must bring their own server.** Only
    the server's owner can put a group on this server:
    `flock-admin set-standard GROUP_ID`.
- **Places:** anyone in a group can add a shared place (`POST
  /flock/api/groups/ID/places {name, lat, lon, radius}`, radius 25 m to 2 km,
  50 per group). Whoever added a place, or the leader, can remove it
  (`DELETE …/places/PID`). Members get them in `/me`. The app uses them for
  "At School since 3 pm", place names in history, and arrival messages.
- **Only standard groups use this server.** The ACL gives broker rights only
  to members of a standard group, or people asking to join one. The history
  check works the same way.
- **History:** Caddy asks flock-server before each Recorder request. Only
  `/api/0/locations` for yourself or someone in your groups is allowed.
- **Owner commands:** `flock-admin users | groups | add-user NAME |
  delete-user USER | set-standard GROUP_ID | invite GROUP_ID | rewrite-acl`.
- **Tests:** `python3 server/test_flock_server.py`.

## Broker

- Listeners: `1883` plain (LAN only), `8883` TLS (forwarded from the internet).
- `allow_anonymous false`, with the password file and the ACL file
  (`acl_file /etc/mosquitto/acl`) both written by flock-server.

## History (Recorder)

- ot-recorder stores every location it sees on MQTT and serves an HTTP API on
  `127.0.0.1:8083` only.
- **Caddy** publishes it on `8443` over HTTPS, with the same certificate as MQTT.
- **Login is the account's MQTT login**, checked by flock-server. Ten wrong
  passwords from one IP block it for 15 minutes.
- **Read-only, own groups only:** only `GET /api/0/locations` (for you or
  someone in your groups) and `/version` get through. Everything else returns
  403 or 404.
- **Retention:** `owntracks-prune` runs hourly and deletes points older than
  4 days. The app offers today and the two days before.

## Testing against a real broker

On the server, where `localhost` is in the certificate:

```bash
flock-admin add-user "Flock Test"        # prints a throwaway login
FLOCK_REAL_USER=flock-test FLOCK_REAL_PASSWORD='…' \
  flutter test test/mqtt_integration_test.dart
flock-admin delete-user flock-test
```
