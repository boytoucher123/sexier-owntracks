import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings.dart';

/// Persists settings. Passwords go to the platform keychain/keystore;
/// everything else to shared preferences.
class SettingsStore {
  SettingsStore({FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  static const _kSettings = 'settings.v1';
  static const _kFace = 'face.v1';
  static const _kClientSuffix = 'clientSuffix.v1';
  static const _kPassword = 'password';
  static const _kRecorderPassword = 'recorderPassword';
  static const _kAccount = 'account.v1';
  static const _kOutbox = 'outbox.v1';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSettings);
    final password = await _readSecure(_kPassword);
    final recorderPassword = await _readSecure(_kRecorderPassword);
    if (raw == null) return const AppSettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return AppSettings.fromJson(
        j,
        password: password,
        recorderPassword: recorderPassword,
      );
    } on Object {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSettings, s.encode());
    await _secure.write(key: _kPassword, value: s.password);
    await _secure.write(key: _kRecorderPassword, value: s.recorderPassword);
  }

  Future<Uint8List?> loadFace() async {
    final prefs = await SharedPreferences.getInstance();
    final b64 = prefs.getString(_kFace);
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } on FormatException {
      return null;
    }
  }

  Future<void> saveFace(Uint8List? bytes) async {
    final prefs = await SharedPreferences.getInstance();
    if (bytes == null) {
      await prefs.remove(_kFace);
    } else {
      await prefs.setString(_kFace, base64Encode(bytes));
    }
  }

  /// Location reports made while offline, waiting to be sent: (topic, json).
  Future<List<(String, String)>> loadOutbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kOutbox);
      if (raw == null) return [];
      return [
        for (final e in jsonDecode(raw) as List)
          if (e is List && e.length == 2) (e[0] as String, e[1] as String),
      ];
    } on Object {
      return [];
    }
  }

  Future<void> saveOutbox(List<(String, String)> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (items.isEmpty) {
        await prefs.remove(_kOutbox);
      } else {
        await prefs.setString(
          _kOutbox,
          jsonEncode([
            for (final (t, p) in items) [t, p],
          ]),
        );
      }
    } on Object {
      // Not fatal: those reports just won't be resent.
    }
  }

  /// The server's last answer about your groups. Kept in secure storage:
  /// a group on its own server includes that server's login.
  Future<Map<String, dynamic>?> loadAccount() async {
    final raw = await _readSecure(_kAccount);
    if (raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> saveAccount(Map<String, dynamic> json) async {
    try {
      await _secure.write(key: _kAccount, value: jsonEncode(json));
    } on Object {
      // Not fatal: the app just fetches it again next time.
    }
  }

  /// A random suffix generated once per install, so two phones that both
  /// call themselves "Fred" never kick each other off the broker.
  Future<String> clientIdSuffix() async {
    final prefs = await SharedPreferences.getInstance();
    var s = prefs.getString(_kClientSuffix);
    if (s == null) {
      final r = Random.secure();
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      s = List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
      await prefs.setString(_kClientSuffix, s);
    }
    return s;
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSettings);
    await prefs.remove(_kFace);
    await _secure.delete(key: _kPassword);
    await _secure.delete(key: _kRecorderPassword);
    await _secure.delete(key: _kAccount);
  }

  Future<String> _readSecure(String key) async {
    try {
      return await _secure.read(key: key) ?? '';
    } on Object {
      return '';
    }
  }
}
