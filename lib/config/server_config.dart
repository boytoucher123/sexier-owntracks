/// This build of Flock is made for one server. These are its details.
///
/// The broker's certificate is issued by a private CA ("OwnTracks MQTT CA").
/// Bundling that CA's certificate (public, not the key) lets the app verify
/// the server properly, with no "allow self-signed" switch needed. Server
/// certificates can be reissued freely as long as this CA signs them.
library;

import 'dart:convert';
import 'dart:io';

const String kDefaultHost = 'owntracks-class-of-2024.duckdns.org';
const int kDefaultPort = 8883;

/// The old shared login. Phones still using it are asked to make their own
/// account; the server no longer accepts it.
const String kLegacyUsername = 'class_of_2024';

/// Everyone has one device, always called this: `owntracks/<username>/phone`.
const String kDeviceName = 'phone';

/// Location history (OwnTracks Recorder) behind an HTTPS proxy on the same
/// server. It accepts the same username and password as MQTT, so nobody has
/// to enter anything extra. Not secret: it is useless without the login.
const String kDefaultRecorderUrl =
    'https://owntracks-class-of-2024.duckdns.org:8443';

/// Accounts and groups: sign-up, invite codes, approvals.
const String kAccountApiUrl = '$kDefaultRecorderUrl/flock/api';

/// The server keeps about this many days of history; the app offers this many.
const int kHistoryDays = 3;

/// CN=OwnTracks MQTT CA, valid until 2036.
const String kServerCaPem = '''
-----BEGIN CERTIFICATE-----
MIIFGTCCAwGgAwIBAgIUR4wqpmcruE1pcSmCqQUfxDAt0tswDQYJKoZIhvcNAQEL
BQAwHDEaMBgGA1UEAwwRT3duVHJhY2tzIE1RVFQgQ0EwHhcNMjYwOTA4MDk0MzMy
WhcNMzYwOTA1MDk0MzMyWjAcMRowGAYDVQQDDBFPd25UcmFja3MgTVFUVCBDQTCC
AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALmFR6QWwLDfTlB2aiQpeYnP
04euUXFgqvnb5nw7U+eGL49ywTl7TasFWqORschxxORCUk0t4uuH+8ySJrF5I2Rt
dxQtM1dniBA07WfI5phBlkT74eLaaIN/crGApxU0pcjAI8MSpzCA1aseJhj/tlug
24CJfIXE/sLaaYOUcDH20+6OBLZT9sQOx1R6WsFtm/8Bx0RvrTIjDkDd+a9N9NTM
uLI7yr3/THvY59lqULwo7RCtfcrUve+Vzr6FJQqn62JUllmXKYEY3itkOlLgp9AZ
BEUTMjuEsiazJbH6aZceBs6l8/CTxZEVJ6y1tv8ZxqrkHWEehKFX9rBInhGLNExl
eBSpiIAv2v40c3OXs3/ZqxQPnPFTOYuni6R5qw8MMCA9tOMWv/Cr7SZEnL5fHvQP
FmPGmfM7ZrweOW3s95b19xTdohJC5E+tad1yLhIS12gN47hHadyE/e+6T0NWnsrd
UPGrTmzcpxnCeT8f1tPnLrrpDdKVPaNWTvdkTIyTa8AhLZcZoQbAO7jQ4JyjTJby
3y2anMULLT8VVKKDTpHfQtr8no0gfJXYo537N7uUQ60u93+K1i/aR6VY/bxS7e4b
2D5P53bt4hrC1+768VDjLKi7Rv8MrDfTrW9OeKRmHwozMCTysk6YBtDZ/acyOHJv
bPtZS/8UachoeCANh6DzAgMBAAGjUzBRMB0GA1UdDgQWBBReRDB7jR/x7Khwz0Ky
F/iQNRzm9jAfBgNVHSMEGDAWgBReRDB7jR/x7Khwz0KyF/iQNRzm9jAPBgNVHRMB
Af8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4ICAQC0zt0DpUc0ChM4tgpdCMfGxZ4K
ukUPLjXxyyZM47NxrhijztVVoOvfPNicR5MSdhzW1m6GnDPMntyiLxNNdUerbz+u
T0xqCDk/C0N4TB6UFqqBPGWEIg92jPj8Qnktlxbtz+YIHuo/7kC5k1xZjhSnSyk7
9MPQ6A0hFlP8AYzayQeCRyxtJ/Z9QH5+Fd+M4mayO0hj3xlm+8V1lPQ86favaUAQ
4eOGlGW1pqnvAbZtNHs5znO0RtbWHCVEwn4rH6/tp0bdVodcERT2o9wBvvyQIAZn
/okby/pZ/1h/pNhcwKcdr5+qRNzMhc8S7NIY/ctILYjX/k4s+CzU/ZAms13BOw04
XaQ7BFLVs3PKddvX1Q8GFLIpnMs7WtgUXKfq5AP25SZw87wGLdmf64H9S5Q/DNLY
mpKdAsc6sSYSu/5Qv+ea8LzTpXCgqThX6edABCZYAJojhBmh1JvStoBfvOsh45wE
H6YdCabAfHvn4YmFeHCW3/jcbjUmq88hdxtjsGJ2v3Vy3qU6fbVOcoUFSi/uOsjw
UL/RlNkQ8tbTYobrXAJ9j4sJXc2WJZXLPpgglHP6L4KO4Y/IkG6cI4Eod8O+Kf6C
+c0Hr9a290e3MgQyZF0a7XjD8QdLB4WH+GYi1nqja/C+OdF0/FwpAmCkXGqMXWJY
SUnRavmpkiCWDcGuzQ==
-----END CERTIFICATE-----
''';

/// The phone's normal trusted roots plus our server's private CA, so the
/// server's certificate verifies without disabling any checks. Used for both
/// MQTT and the history server.
SecurityContext serverSecurityContext() =>
    SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(utf8.encode(kServerCaPem));
