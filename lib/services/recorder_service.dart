import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/server_config.dart';
import '../models/person.dart';
import '../models/settings.dart';
import 'owntracks_protocol.dart';
import '../strings.dart';

class RecorderException implements Exception {
  RecorderException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Fetches location history from the OwnTracks Recorder HTTP API.
/// https://github.com/owntracks/recorder#http-api
class RecorderService {
  RecorderService({http.Client? client}) : _injected = client;

  final http.Client? _injected;
  final Map<String, http.Client> _clients = {};

  /// Trusts the server's CA (same as MQTT), with full checks on.
  http.Client _clientFor(AppSettings s) =>
      _injected ??
      _clients.putIfAbsent(
        s.caPem,
        () => IOClient(HttpClient(context: serverSecurityContext(s.caPem))),
      );

  Future<List<LocationFix>> history(
    AppSettings s, {
    required String user,
    required String device,
    required DateTime from,
    DateTime? to,
  }) async {
    if (!s.hasRecorder) {
      throw RecorderException(Txt.locationHistoryIsnTSet);
    }
    final uri = buildLocationsUri(
      s.recorderUrl,
      user: user,
      device: device,
      from: from,
      to: to ?? DateTime.now(),
    );

    // If the Recorder has no login of its own, fall back to the shared login,
    // which is how most reverse-proxy setups are configured.
    final u = s.recorderUsername.isNotEmpty ? s.recorderUsername : s.username;
    final p = s.recorderUsername.isNotEmpty ? s.recorderPassword : s.password;
    final headers = <String, String>{'Accept': 'application/json'};
    if (u.isNotEmpty) {
      headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('$u:$p'))}';
    }

    final http.Response res;
    try {
      res = await _clientFor(s)
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
    } on Object {
      throw RecorderException(Txt.couldnTReachTheHistory);
    }
    if (res.statusCode == 401) {
      throw RecorderException(Txt.theHistoryServerRejectedThe);
    }
    if (res.statusCode == 403) {
      throw RecorderException(Txt.youCanOnlySeeHistory);
    }
    if (res.statusCode == 404) {
      throw RecorderException(Txt.theHistoryServerAddressLooks);
    }
    if (res.statusCode != 200) {
      throw RecorderException(Txt.theHistoryServerHadA(res.statusCode));
    }
    return parseLocationsResponse(res.body);
  }

  /// Recorder expects UTC timestamps like `2026-01-31T13:45:00`.
  static Uri buildLocationsUri(
    String base, {
    required String user,
    required String device,
    required DateTime from,
    required DateTime to,
  }) {
    var b = base.trim();
    if (!b.contains('://')) b = 'https://$b';
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    String fmt(DateTime d) =>
        d.toUtc().toIso8601String().split('.').first.replaceAll('Z', '');
    final root = Uri.parse('$b/api/0/locations');
    return root.replace(
      queryParameters: {
        'user': user,
        'device': device,
        'from': fmt(from),
        'to': fmt(to),
        'format': 'json',
      },
    );
  }

  /// Accepts `{"data": [...]}` or a bare list. Returns fixes oldest-first.
  static List<LocationFix> parseLocationsResponse(String body) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw RecorderException(Txt.theHistoryServerSentSomething);
    }
    final List<dynamic> items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map && decoded['data'] is List) {
      items = decoded['data'] as List;
    } else {
      items = const [];
    }
    final fixes = <LocationFix>[];
    for (final item in items) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      m['_type'] ??= 'location';
      final fix = OwnTracksProtocol.parseLocation(m);
      if (fix != null) fixes.add(fix);
    }
    fixes.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return fixes;
  }
}
