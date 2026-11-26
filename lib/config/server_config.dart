/// Fixed app-wide values. There is no built-in server: everything about a
/// server (address, certificate, logins) arrives in an invite and from the
/// group's settings once you're let in.
library;

import 'dart:convert';
import 'dart:io';

/// Everyone has one device, always called this: `owntracks/<username>/phone`.
const String kDeviceName = 'phone';

/// How many days of history the app offers.
const int kHistoryDays = 3;

/// The phone's normal trusted roots, plus a server's own CA when it uses one
/// ([pem], from the invite or the group's settings). Full checks stay on.
SecurityContext serverSecurityContext(String pem) {
  final c = SecurityContext(withTrustedRoots: true);
  if (pem.trim().isNotEmpty) c.setTrustedCertificatesBytes(utf8.encode(pem));
  return c;
}
