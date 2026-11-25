import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/server_config.dart';
import '../models/settings.dart';

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

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.leader,
    required this.isLeader,
    required this.members,
    this.code,
    this.requests = const [],
  });
  final int id;
  final String name;
  final String leader;
  final bool isLeader;
  final List<GroupMember> members;

  /// The invite code, like `K7Q-2MX`. Only the leader gets it.
  final String? code;
  final List<JoinRequest> requests;

  String get leaderName =>
      members.where((m) => m.leader).map((m) => m.name).firstOrNull ?? leader;
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
  });

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

/// Talks to the server's account service (sign-up, groups, approvals) over
/// HTTPS, trusting the server's private CA like MQTT does.
class AccountService {
  AccountService({http.Client? client, String baseUrl = kAccountApiUrl})
    : _http = client ?? IOClient(HttpClient(context: serverSecurityContext())),
      _base = baseUrl;

  final http.Client _http;
  final String _base;

  Future<NewAccount> signUp(String name) async {
    final j = await _call('POST', '/signup', body: {'name': name});
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
    Map<String, Object?>? body,
  }) async {
    final req = http.Request(method, Uri.parse('$_base$path'));
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
        await _http.send(req).timeout(const Duration(seconds: 20)),
      );
    } on Object {
      throw AccountException(
        'Couldn\'t reach the server. Check your connection and try again.',
      );
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
        : 'The server had a problem (error ${res.statusCode}).';
    throw AccountException(msg, status: res.statusCode);
  }
}
