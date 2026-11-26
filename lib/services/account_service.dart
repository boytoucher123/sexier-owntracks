import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../util/format.dart';

import 'package:latlong2/latlong.dart';
import 'package:http/io_client.dart';

import '../config/server_config.dart';
import '../models/settings.dart';
import '../strings.dart';

class AccountException implements Exception {
  AccountException(this.message, {this.status});
  final String message;
  final int? status;
  bool get unauthorized => status == 401;
  @override
  String toString() => message;
}

/// A login the server made for you at sign-up.
class NewAccount {
  const NewAccount({
    required this.username,
    required this.password,
    required this.name,
  });
  final String username;
  final String password;
  final String name;
}

class GroupMember {
  const GroupMember({
    required this.username,
    required this.name,
    required this.leader,
  });
  final String username;
  final String name;
  final bool leader;
}

/// Someone asking to join a group you lead.
class JoinRequest {
  const JoinRequest({
    required this.username,
    required this.name,
    required this.accountCreated,
    required this.requested,
  });
  final String username;
  final String name;
  final DateTime accountCreated;
  final DateTime requested;
}

/// Where a group's locations go and how often its members report. Set by
/// the group's leader; members get it automatically.
class GroupConfig {
  const GroupConfig({
    required this.standard,
    this.host = '',
    this.port = 8883,
    this.tls = true,
    this.ca = '',
    this.recorderUrl = '',
    this.topicPrefix = 'owntracks',
    this.trackingMode = TrackingMode.balanced,
  });

  /// Runs on the server your account is on (its details are filled in by
  /// that server). Otherwise the leader's own server. Either way everyone
  /// signs in with their own account.
  final bool standard;
  final String host;
  final int port;
  final bool tls;

  /// PEM of the CA that signed the group server's certificate ('' = a
  /// normal public certificate).
  final String ca;
  final String recorderUrl;

  final String topicPrefix;
  final TrackingMode trackingMode;

  factory GroupConfig.fromJson(Map<String, dynamic> j) => GroupConfig(
    standard: j['standard'] == true,
    host: j['host'] as String? ?? '',
    port: (j['port'] as num?)?.toInt() ?? 8883,
    tls: j['tls'] as bool? ?? true,
    ca: j['ca'] as String? ?? '',
    recorderUrl: j['recorder_url'] as String? ?? '',
    topicPrefix: j['topic_prefix'] as String? ?? 'owntracks',
    trackingMode: TrackingMode.values.firstWhere(
      (m) => m.name == j['tracking_mode'],
      orElse: () => TrackingMode.balanced,
    ),
  );

  /// The body for setting your own server (leaders only).
  Map<String, Object?> toServerJson() => {
    'host': host,
    'port': port,
    'tls': tls,
    'ca': ca,
    'recorder_url': recorderUrl,
    'topic_prefix': topicPrefix,
    'tracking_mode': trackingMode.name,
  };
}

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.leader,
    required this.isLeader,
    required this.members,
    this.code,
    this.requests = const [],
    this.config,
    this.invite,
    this.places = const [],
  });
  final int id;
  final String name;
  final String leader;
  final bool isLeader;
  final List<GroupMember> members;

  /// The invite code, like `K7Q-2MX`. Only the leader gets it.
  final String? code;
  final List<JoinRequest> requests;

  /// Null until the leader sets the group up (a server to use).
  final GroupConfig? config;

  /// What the leader shares: `flock://host:port/join/CODE?ca=…`.
  final String? invite;

  /// Shared places (Home, School...) anyone in the group can add.
  final List<Place> places;

  bool hasMember(String username) => members.any((m) => m.username == username);

  String? memberName(String username) => members
      .where((m) => m.username == username)
      .map((m) => m.name)
      .firstOrNull;

  String get leaderName =>
      members.where((m) => m.leader).map((m) => m.name).firstOrNull ?? leader;
}

/// A named spot the group shares: "At School since 3 pm".
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.radius = 100,
    this.createdBy = '',
  });
  final int id;
  final String name;
  final double lat;
  final double lon;

  /// Metres.
  final double radius;
  final String createdBy;

  LatLng get center => LatLng(lat, lon);

  bool contains(LatLng p) => metersBetween(center, p) <= radius;

  factory Place.fromJson(Map<String, dynamic> j) => Place(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String? ?? '',
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    radius: (j['radius'] as num? ?? 100).toDouble(),
    createdBy: j['created_by'] as String? ?? '',
  );
}

/// The place [p] is in, nearest centre first, or null.
Place? placeAt(Iterable<Place> places, LatLng p) {
  Place? best;
  var bestD = double.infinity;
  for (final pl in places) {
    final d = metersBetween(pl.center, p);
    if (d <= pl.radius && d < bestD) {
      best = pl;
      bestD = d;
    }
  }
  return best;
}

/// A group you asked to join that hasn't let you in yet.
class PendingJoin {
  const PendingJoin({
    required this.id,
    required this.name,
    required this.leaderName,
  });
  final int id;
  final String name;
  final String leaderName;
}

/// Everything the server knows about you: your groups and who you can see.
class Account {
  const Account({
    required this.username,
    required this.name,
    this.groups = const [],
    this.pending = const [],
    this.visible = const {},
    this.json = const {},
  });

  /// The server's answer as it came, kept so the app can start offline.
  final Map<String, dynamic> json;
  final String username;
  final String name;
  final List<Group> groups;
  final List<PendingJoin> pending;

  /// People you share a group with: username -> name.
  final Map<String, String> visible;

  /// Join requests waiting for you, across the groups you lead.
  int get waitingRequests =>
      groups.fold(0, (n, g) => n + (g.isLeader ? g.requests.length : 0));

  /// Usernames of people asking to join your groups (you can see their card).
  Set<String> get requesters => {
    for (final g in groups)
      for (final r in g.requests) r.username,
  };

  factory Account.fromJson(Map<String, dynamic> j) {
    DateTime t(Object? s) =>
        DateTime.fromMillisecondsSinceEpoch(((s as num?) ?? 0).toInt() * 1000);
    List<Map<String, dynamic>> list(Object? v) => [
      for (final e in (v as List? ?? const []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    return Account(
      json: j,
      username: j['username'] as String? ?? '',
      name: j['name'] as String? ?? '',
      groups: [
        for (final g in list(j['groups']))
          Group(
            id: (g['id'] as num).toInt(),
            name: g['name'] as String? ?? '',
            leader: g['leader'] as String? ?? '',
            isLeader: g['role'] == 'leader',
            code: g['code'] as String?,
            invite: g['invite'] as String?,
            config: g['config'] is Map
                ? GroupConfig.fromJson(Map<String, dynamic>.from(g['config']))
                : null,
            places: [for (final p in list(g['places'])) Place.fromJson(p)],
            members: [
              for (final m in list(g['members']))
                GroupMember(
                  username: m['username'] as String,
                  name: m['name'] as String? ?? m['username'] as String,
                  leader: m['leader'] == true,
                ),
            ],
            requests: [
              for (final r in list(g['requests']))
                JoinRequest(
                  username: r['username'] as String,
                  name: r['name'] as String? ?? r['username'] as String,
                  accountCreated: t(r['created']),
                  requested: t(r['requested']),
                ),
            ],
          ),
      ],
      pending: [
        for (final p in list(j['pending']))
          PendingJoin(
            id: (p['id'] as num).toInt(),
            name: p['name'] as String? ?? '',
            leaderName: p['leader_name'] as String? ?? '',
          ),
      ],
      visible: {
        for (final v in list(j['visible']))
          v['username'] as String:
              v['name'] as String? ?? v['username'] as String,
      },
    );
  }
}

/// What an invite says: where the group's Flock server is, the group code,
/// and the fingerprint of the server's certificate authority (when it uses
/// its own). Shared as `https://host:port/flock/join/CODE?ca=FINGERPRINT`
/// (tappable in chats; its page opens Flock with `flock://host:port/join/…`).
/// [parse] finds either anywhere in pasted text.
class Invite {
  const Invite({required this.server, required this.code, this.caFingerprint});
  final String server;
  final String code;
  final String? caFingerprint;

  static final _re = RegExp(
    r'(?:flock://|https://)([A-Za-z0-9.\-]+(?::\d{1,5})?)/(?:flock/)?join/'
    r'([A-Za-z0-9\-]{4,12})(?:\?ca=([A-Za-z0-9_\-]{43}))?',
  );

  /// Accepts the shared https link, the flock:// link it opens, or a message
  /// containing either.
  static Invite? parse(String text) {
    final m = _re.firstMatch(text);
    if (m == null) return null;
    return Invite(
      server: m.group(1)!.toLowerCase(),
      code: m.group(2)!,
      caFingerprint: m.group(3),
    );
  }
}

/// SHA-256 of a PEM certificate's DER bytes, base64url without padding
/// (the same as the server's `ca_fingerprint`).
String caFingerprint(String pem) {
  final body = pem
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join();
  final digest = sha256.convert(base64Decode(body));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}

/// Talks to a server's account service (sign-up, groups, approvals) over
/// HTTPS. The server comes from your invite; there is none built in.
class AccountService {
  AccountService({http.Client? client}) : _injected = client;

  final http.Client? _injected;
  final Map<String, http.Client> _clients = {};

  http.Client _clientFor(AppSettings s) =>
      _injected ??
      _clients.putIfAbsent(
        s.accountCa,
        () => IOClient(HttpClient(context: serverSecurityContext(s.accountCa))),
      );

  /// Gets the server's certificate authority for an invite and checks it
  /// against the invite's fingerprint, so a stranger can't stand in for the
  /// server. Returns '' for a server with a normal public certificate.
  Future<String> trustFor(Invite invite) async {
    final fp = invite.caFingerprint;
    if (fp == null) return '';
    String pem;
    try {
      final http.Response res;
      if (_injected != null) {
        res = await _injected.get(
          Uri.parse('https://${invite.server}/flock/api/ca'),
        );
      } else {
        // Can't check the certificate yet: we're fetching what to check it
        // against. The fingerprint check below is what makes this safe.
        final hc = HttpClient()..badCertificateCallback = (_, _, _) => true;
        res = await IOClient(hc)
            .get(Uri.parse('https://${invite.server}/flock/api/ca'));
        hc.close();
      }
      pem = (jsonDecode(res.body) as Map)['pem'] as String;
    } on Object {
      throw AccountException(Txt.couldnTReachTheServer);
    }
    if (caFingerprint(pem) != fp) {
      throw AccountException(Txt.thisInviteDoesnTMatch);
    }
    return pem;
  }

  /// Makes your account on the server in [at] (its accountServer/accountCa).
  Future<NewAccount> signUp(AppSettings at, String name) async {
    final j = await _call('POST', '/signup', at: at, body: {'name': name});
    return NewAccount(
      username: j['username'] as String,
      password: j['password'] as String,
      name: j['name'] as String? ?? name,
    );
  }

  Future<Account> me(AppSettings s) async =>
      Account.fromJson(await _call('GET', '/me', login: s));

  Future<Account> rename(AppSettings s, String name) async => Account.fromJson(
    await _call('PATCH', '/me', login: s, body: {'name': name}),
  );

  Future<void> deleteAccount(AppSettings s) => _call('DELETE', '/me', login: s);

  Future<Account> createGroup(AppSettings s, String name) async =>
      Account.fromJson(
        await _call('POST', '/groups', login: s, body: {'name': name}),
      );

  Future<Account> join(AppSettings s, String code) async => Account.fromJson(
    await _call('POST', '/join', login: s, body: {'code': code}),
  );

  Future<Account> approve(AppSettings s, int group, String user) async =>
      Account.fromJson(
        await _call(
          'POST',
          '/groups/$group/requests/${Uri.encodeComponent(user)}/approve',
          login: s,
        ),
      );

  Future<Account> deny(AppSettings s, int group, String user) async =>
      Account.fromJson(
        await _call(
          'POST',
          '/groups/$group/requests/${Uri.encodeComponent(user)}/deny',
          login: s,
        ),
      );

  /// Removes [user] from the group: the leader removing someone, or you
  /// leaving (pass your own username).
  Future<Account> remove(AppSettings s, int group, String user) async =>
      Account.fromJson(
        await _call(
          'DELETE',
          '/groups/$group/members/${Uri.encodeComponent(user)}',
          login: s,
        ),
      );

  Future<Account> newCode(AppSettings s, int group) async =>
      Account.fromJson(await _call('POST', '/groups/$group/code', login: s));

  Future<Account> renameGroup(AppSettings s, int group, String name) async =>
      Account.fromJson(
        await _call('PATCH', '/groups/$group', login: s, body: {'name': name}),
      );

  /// Leader only. `{'tracking_mode': ...}` alone keeps the server; a full
  /// [GroupConfig.toServerJson] puts the group on the leader's own server.
  Future<Account> setConfig(
    AppSettings s,
    int group,
    Map<String, Object?> body,
  ) async => Account.fromJson(
    await _call('PUT', '/groups/$group/config', login: s, body: body),
  );

  /// Anyone in the group: share a place with everyone in it.
  Future<Account> addPlace(
    AppSettings s,
    int group, {
    required String name,
    required LatLng at,
    required double radius,
  }) async => Account.fromJson(
    await _call(
      'POST',
      '/groups/$group/places',
      login: s,
      body: {
        'name': name,
        'lat': at.latitude,
        'lon': at.longitude,
        'radius': radius.round(),
      },
    ),
  );

  /// Whoever added it, or the leader.
  Future<Account> removePlace(AppSettings s, int group, int place) async =>
      Account.fromJson(
        await _call('DELETE', '/groups/$group/places/$place', login: s),
      );

  Future<Account> makeLeader(AppSettings s, int group, String user) async =>
      Account.fromJson(
        await _call(
          'POST',
          '/groups/$group/leader',
          login: s,
          body: {'username': user},
        ),
      );

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    AppSettings? login,
    AppSettings? at,
    Map<String, Object?>? body,
  }) async {
    final server = (login ?? at)!;
    final req = http.Request(
      method,
      Uri.parse('https://${server.accountServer}/flock/api$path'),
    );
    req.headers['Accept'] = 'application/json';
    if (login != null) {
      req.headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('${login.username}:${login.password}'))}';
    }
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _clientFor(server).send(req).timeout(const Duration(seconds: 20)),
      );
    } on Object {
      throw AccountException(Txt.couldnTReachTheServer2);
    }
    Map<String, dynamic> j = const {};
    if (res.body.isNotEmpty) {
      try {
        final d = jsonDecode(res.body);
        if (d is Map) j = Map<String, dynamic>.from(d);
      } on FormatException {
        // fall through to the status-based message
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return j;
    final msg = j['error'] is String
        ? j['error'] as String
        : Txt.theServerHadAProblem(res.statusCode);
    throw AccountException(msg, status: res.statusCode);
  }
}
