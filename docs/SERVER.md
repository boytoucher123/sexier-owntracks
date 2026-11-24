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
| Username | `class_of_2024` (pre-filled, shared by everyone) |
| Password | ask the server owner |
| Recorder URL | leave empty for now: the Recorder only listens on the server itself |

Each person's name becomes the device in `owntracks/class_of_2024/<Name>`.

## Broker

- Listeners: `1883` plain (LAN only), `8883` TLS (the router forwards it from the
  internet), `8884` TLS (spare, not forwarded).
- `allow_anonymous false` with a password file. There is **no ACL file**, so any
  logged-in user can read and write every topic. That is fine for one shared login.
- The public IP is dynamic. DuckDNS keeps the hostname pointed at it.

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
FLOCK_REAL_PASSWORD='…' flutter test test/mqtt_integration_test.dart
```
