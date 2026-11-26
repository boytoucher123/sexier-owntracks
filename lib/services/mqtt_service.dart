import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../config/server_config.dart';
import '../models/settings.dart';
import 'owntracks_protocol.dart';
import '../strings.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class IncomingMessage {
  const IncomingMessage(this.topic, this.payload);
  final String topic;
  final String payload;
}

/// Outcome of "Test connection" in plain English.
class ConnectionTestResult {
  const ConnectionTestResult.ok()
    : success = true,
      message = Txt.connectedEverythingLooksGood,
      suggestion = null,
      suggestionLabel = null;
  const ConnectionTestResult.fail(this.message)
    : success = false,
      suggestion = null,
      suggestionLabel = null;
  const ConnectionTestResult.suggest(
    this.message, {
    required AppSettings this.suggestion,
    required String this.suggestionLabel,
  }) : success = false;

  final bool success;
  final String message;

  /// Settings that did work, found by trying common alternatives.
  final AppSettings? suggestion;

  /// Plain description of what's different, e.g. "port 1883, not secure".
  final String? suggestionLabel;
}

/// Thin wrapper around mqtt_client that speaks OwnTracks conventions and
/// turns low-level failures into messages a normal person can act on.
class MqttService {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  // Retry state for when the first connection fails (e.g. no signal).
  AppSettings? _wanted;
  String? _wantedClientId;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  final _messages = StreamController<IncomingMessage>.broadcast();

  final ValueNotifier<ConnectionStatus> status = ValueNotifier(
    ConnectionStatus.disconnected,
  );
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// Called each time a connection (re)establishes, after subscribing.
  VoidCallback? onConnected;

  Stream<IncomingMessage> get messages => _messages.stream;

  bool get isConnected => status.value == ConnectionStatus.connected;

  /// Tests [s]; if it fails for a reason other than the login, quietly tries
  /// the usual alternatives (self-signed certificate, plain 1883, WebSockets)
  /// and offers the first one that works.
  static Future<ConnectionTestResult> testAndDiagnose(
    AppSettings s, {
    required String clientId,
  }) async {
    final first = await test(s, clientId: clientId);
    if (first.success || first.message.contains('username or password')) {
      return first;
    }
    for (final (alt, label) in alternativesFor(s)) {
      final r = await test(alt, clientId: clientId, timeoutMs: 6000);
      if (r.success) {
        return ConnectionTestResult.suggest(
          Txt.butItDoesWorkWith(first.message, label),
          suggestion: alt,
          suggestionLabel: label,
        );
      }
      if (r.message.contains('username or password')) {
        // Reached the server this way; the login is what's wrong.
        return ConnectionTestResult.fail(Txt.foundYourServerButIt(label));
      }
    }
    return first;
  }

  /// Common setups to try when the given one fails.
  @visibleForTesting
  static List<(AppSettings, String)> alternativesFor(AppSettings s) {
    final out = <(AppSettings, String)>[];
    void add(AppSettings a, String label) {
      final same =
          a.port == s.port &&
          a.useTls == s.useTls &&
          a.useWebSocket == s.useWebSocket &&
          a.allowUntrustedCertificates == s.allowUntrustedCertificates;
      final dup = out.any(
        (o) =>
            o.$1.port == a.port &&
            o.$1.useTls == a.useTls &&
            o.$1.useWebSocket == a.useWebSocket &&
            o.$1.allowUntrustedCertificates == a.allowUntrustedCertificates,
      );
      if (!same && !dup) out.add((a, label));
    }

    final host = s.host.contains('://')
        ? Uri.tryParse(s.host)?.host ?? s.host
        : s.host;
    final base = s.copyWith(host: host);
    if (s.useTls && !s.allowUntrustedCertificates) {
      add(
        s.copyWith(allowUntrustedCertificates: true),
        Txt.aSelfSignedCertificateAllowed,
      );
    }
    add(
      base.copyWith(port: 8883, useTls: true, useWebSocket: false),
      Txt.secureConnectionOnPort8883,
    );
    add(
      base.copyWith(
        port: 8883,
        useTls: true,
        useWebSocket: false,
        allowUntrustedCertificates: true,
      ),
      Txt.secureConnectionOnPort88832,
    );
    add(
      base.copyWith(
        port: 1883,
        useTls: false,
        useWebSocket: false,
        allowUntrustedCertificates: false,
      ),
      Txt.port1883WithoutASecure,
    );
    add(
      base.copyWith(
        host: 'wss://$host/mqtt',
        port: 443,
        useTls: true,
        useWebSocket: true,
        allowUntrustedCertificates: false,
      ),
      Txt.websocketsOnPort443,
    );
    return out;
  }

  /// Connects with a throwaway client to check the details work.
  static Future<ConnectionTestResult> test(
    AppSettings s, {
    required String clientId,
    int timeoutMs = 10000,
  }) async {
    final client = _buildClient(s, '$clientId-test');
    client.connectTimeoutPeriod = timeoutMs;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('$clientId-test')
        .startClean();
    try {
      final result = await client.connect(s.username, s.password);
      if (result?.state == MqttConnectionState.connected) {
        return const ConnectionTestResult.ok();
      }
      return ConnectionTestResult.fail(
        describeReturnCode(result?.returnCode, s),
      );
    } on Object catch (e) {
      return ConnectionTestResult.fail(_explain(client, e, s));
    } finally {
      try {
        client.disconnect();
      } on Object {
        // already gone
      }
    }
  }

  Future<void> connect(AppSettings s, {required String clientId}) async {
    await disconnect();
    if (!s.hasConnectionDetails) return;
    _wanted = s;
    _wantedClientId = clientId;
    _retryAttempt = 0;
    await _attempt();
  }

  /// Try again right away if we're not connected (e.g. app came back to the
  /// foreground). No-op when connected or when nothing is configured.
  Future<void> retryNow() async {
    if (_wanted == null) return;
    if (status.value == ConnectionStatus.connected ||
        status.value == ConnectionStatus.connecting) {
      return;
    }
    _retryTimer?.cancel();
    await _attempt();
  }

  Future<void> _attempt() async {
    final s = _wanted;
    final clientId = _wantedClientId;
    if (s == null || clientId == null) return;
    await _teardownClient();

    status.value = ConnectionStatus.connecting;
    lastError.value = null;

    final client = _buildClient(s, clientId);
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillTopic(s.ownTopic)
        .withWillMessage(OwnTracksProtocol.encodeLwt(DateTime.now()))
        .withWillQos(MqttQos.atLeastOnce)
        .startClean();

    client.onConnected = () => status.value = ConnectionStatus.connected;
    client.onAutoReconnect = () => status.value = ConnectionStatus.connecting;
    client.onAutoReconnected = () {
      status.value = ConnectionStatus.connected;
      onConnected?.call();
    };
    client.onDisconnected = () {
      if (status.value != ConnectionStatus.error) {
        status.value = ConnectionStatus.disconnected;
      }
    };
    _client = client;

    try {
      final result = await client.connect(s.username, s.password);
      if (!identical(_client, client)) return; // superseded meanwhile
      if (result?.state != MqttConnectionState.connected) {
        _fail(
          describeReturnCode(result?.returnCode, s),
          retry: _isTransient(result?.returnCode),
        );
        return;
      }
    } on Object catch (e) {
      if (!identical(_client, client)) return;
      _fail(
        _explain(client, e, s),
        retry: _isTransient(client.connectionStatus?.returnCode),
      );
      return;
    }
    _retryAttempt = 0;

    _updatesSub = client.updates?.listen((events) {
      for (final ev in events) {
        final msg = ev.payload;
        if (msg is! MqttPublishMessage) continue;
        final text = MqttPublishPayload.bytesToStringAsString(
          msg.payload.message,
        );
        _messages.add(IncomingMessage(ev.topic, text));
      }
    });

    // The broker only delivers what this login may see (you and the people
    // in your groups), so listen broadly and let it filter.
    for (final t in peopleTopics(s)) {
      client.subscribe(t, MqttQos.atLeastOnce);
    }
    client.subscribe('${s.ownTopic}/cmd', MqttQos.atLeastOnce);

    status.value = ConnectionStatus.connected;
    onConnected?.call();
  }

  /// Everyone's location and card topics (`owntracks/<user>/<device>`).
  static List<String> peopleTopics(AppSettings s) => [
    '${s.baseTopic}/+/+',
    '${s.baseTopic}/+/+/info',
  ];

  /// Subscribe again so the broker re-sends everyone's last location, e.g.
  /// after someone new was let into one of your groups.
  void refreshPeople() {
    final c = _client;
    final s = _wanted;
    if (c == null ||
        s == null ||
        c.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    for (final t in peopleTopics(s)) {
      c.unsubscribe(t);
      c.subscribe(t, MqttQos.atLeastOnce);
    }
  }

  void _fail(String message, {required bool retry}) {
    lastError.value = message;
    status.value = ConnectionStatus.error;
    try {
      _client?.disconnect();
    } on Object {
      // ignore
    }
    _client = null;
    if (retry && _wanted != null) {
      const steps = [5, 10, 30, 60];
      final secs = steps[_retryAttempt.clamp(0, steps.length - 1)];
      _retryAttempt++;
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(seconds: secs), _attempt);
    }
  }

  /// Wrong password or rejected ID won't fix itself; everything else might.
  static bool _isTransient(MqttConnectReturnCode? code) =>
      code != MqttConnectReturnCode.badUsernameOrPassword &&
      code != MqttConnectReturnCode.notAuthorized &&
      code != MqttConnectReturnCode.identifierRejected &&
      code != MqttConnectReturnCode.unacceptedProtocolVersion;

  /// Publishes [payload]. Returns false if we're offline.
  bool publish(String topic, String payload, {bool retain = true}) {
    final c = _client;
    if (c == null ||
        c.connectionStatus?.state != MqttConnectionState.connected) {
      return false;
    }
    final b = MqttClientPayloadBuilder()..addUTF8String(payload);
    c.publishMessage(topic, MqttQos.atLeastOnce, b.payload!, retain: retain);
    return true;
  }

  Future<void> disconnect() async {
    _wanted = null;
    _wantedClientId = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _teardownClient();
    status.value = ConnectionStatus.disconnected;
  }

  Future<void> _teardownClient() async {
    await _updatesSub?.cancel();
    _updatesSub = null;
    final c = _client;
    _client = null;
    if (c != null) {
      c.autoReconnect = false;
      c.onDisconnected = null;
      try {
        c.disconnect();
      } on Object {
        // ignore
      }
    }
  }

  void dispose() {
    disconnect();
    _messages.close();
  }

  static MqttServerClient _buildClient(AppSettings s, String clientId) {
    var host = s.host.trim();
    if (s.useWebSocket && !host.contains('://')) {
      host = '${s.useTls ? 'wss' : 'ws'}://$host';
    }
    // One attempt, so a wrong password fails fast instead of retrying.
    final client = MqttServerClient.withPort(
      host,
      clientId,
      s.port,
      maxConnectionAttempts: 1,
    );
    client.logging(on: false);
    client.keepAlivePeriod = s.keepAliveSeconds;
    client.connectTimeoutPeriod = 10000;
    client.setProtocolV311();
    if (s.useWebSocket) {
      client.useWebSocket = true;
    } else if (s.useTls) {
      client.secure = true;
      client.securityContext = serverSecurityContext(s.caPem);
      if (s.allowUntrustedCertificates) {
        // mqtt_client casts this to `bool Function(Object)`, so the parameter
        // must be typed Object or the cast throws a TypeError.
        client.onBadCertificate = (Object _) => true;
      }
    }
    return client;
  }

  /// Prefer the broker's own refusal reason (e.g. bad password) over the
  /// generic exception mqtt_client throws when a handshake is refused.
  static String _explain(MqttServerClient client, Object e, AppSettings s) {
    final code = client.connectionStatus?.returnCode;
    if (code != null &&
        code != MqttConnectReturnCode.noneSpecified &&
        code != MqttConnectReturnCode.connectionAccepted) {
      return describeReturnCode(code, s);
    }
    return describeError(e, s);
  }

  static String describeReturnCode(MqttConnectReturnCode? code, AppSettings s) {
    switch (code) {
      case MqttConnectReturnCode.badUsernameOrPassword:
      case MqttConnectReturnCode.notAuthorized:
        return Txt.theServerRejectedTheUsername;
      case MqttConnectReturnCode.identifierRejected:
        return Txt.theServerRejectedThisPhone;
      case MqttConnectReturnCode.brokerUnavailable:
        return Txt.theServerIsUpBut;
      case MqttConnectReturnCode.unacceptedProtocolVersion:
        return Txt.theServerDoesnTSpeak;
      default:
        return Txt.couldnTConnectTo(s.host, s.port);
    }
  }

  static String describeError(Object e, AppSettings s) {
    if (e is NoConnectionException) {
      final m = e.toString().toLowerCase();
      if (m.contains('username') ||
          m.contains('password') ||
          m.contains('not authorized') ||
          m.contains('badusername')) {
        return Txt.theServerRejectedTheUsername;
      }
      return Txt.theServerAtDidnT(s.host, s.port);
    }
    if (e is HandshakeException || e is TlsException) {
      final m = e.toString().toUpperCase();
      if (m.contains('CERTIFICATE_VERIFY_FAILED') ||
          m.contains('SELF_SIGNED') ||
          m.contains('UNABLE_TO_GET_ISSUER') ||
          m.contains('CERTIFICATE')) {
        if (m.contains('HOSTNAME MISMATCH') ||
            m.contains('IP ADDRESS MISMATCH')) {
          return Txt.theServerSSecurityCertificate;
        }
        return Txt.theServerSSecurityCertificate2;
      }
      return Txt.aSecureConnectionCouldnT(s.port);
    }
    if (e is SocketException) {
      final m = e.message.toLowerCase();
      final os = e.osError?.message.toLowerCase() ?? '';
      if (m.contains('lookup') ||
          os.contains('no address') ||
          os.contains('nodename') ||
          os.contains('name or service')) {
        return Txt.couldnTFindAServer(s.host);
      }
      if (os.contains('refused')) {
        return Txt.foundTheServerButNothing(s.port);
      }
      if (os.contains('network is unreachable')) {
        return Txt.thisPhoneLooksOfflineCheck;
      }
      if (m.contains('timed out') || os.contains('timed out')) {
        return Txt.theServerTookTooLong;
      }
      return Txt.couldnTReach(s.host, s.port);
    }
    if (e is TimeoutException) {
      return Txt.theServerTookTooLong;
    }
    return Txt.somethingWentWrongConnecting(e);
  }
}
