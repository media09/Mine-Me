import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

class MiningGatewayException implements Exception {
  const MiningGatewayException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MiningGatewayConnection {
  MiningGatewayConnection._(this._channel) {
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_closed) {
        _channel.sink.add(jsonEncode({'type': 'heartbeat'}));
      }
    });
  }

  final WebSocketChannel _channel;
  late final Timer _heartbeat;
  bool _closed = false;

  Stream<Map<String, dynamic>> get messages => _channel.stream
      .map((event) => jsonDecode(event as String))
      .where((event) => event is Map<String, dynamic>)
      .cast<Map<String, dynamic>>();

  void submitShare({
    required String jobId,
    required String nonce,
    required String result,
  }) {
    if (_closed) throw const MiningGatewayException('La session de calcul est fermée.');
    _channel.sink.add(jsonEncode({
      'type': 'submit',
      'jobId': jobId,
      'nonce': nonce,
      'result': result,
    }));
  }

  void reportTelemetry({required double hashesPerSecond, required int hashesComputed, required double sampleSeconds}) {
    if (_closed) return;
    _channel.sink.add(jsonEncode({
      'type': 'telemetry',
      'hashesPerSecond': hashesPerSecond,
      'hashesComputed': hashesComputed,
      'sampleSeconds': sampleSeconds,
    }));
  }

  void pause() {
    if (!_closed) _channel.sink.add(jsonEncode({'type': 'pause'}));
  }

  void stop() {
    if (!_closed) _channel.sink.add(jsonEncode({'type': 'stop'}));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat.cancel();
    await _channel.sink.close();
  }
}

/// Obtains a short-lived, server-signed MINE-ME token and opens the
/// authenticated gateway. The app never receives the HashVault wallet secret
/// or the gateway signing secret.
class MiningGatewayService {
  MiningGatewayService(this._client);
  final SupabaseClient _client;

  Future<MiningGatewayConnection> connect({required String deviceId}) async {
    final accessToken = _client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const MiningGatewayException('Votre session membre a expiré. Reconnectez-vous.');
    }

    final endpoint = Uri.parse(
      '${MineMeConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/api/mining/session',
    );
    final response = await http.post(
      endpoint,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'deviceId': deviceId}),
    );

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const MiningGatewayException('Le service MINE-ME a retourné une réponse invalide.');
    }

    if (response.statusCode != 200) {
      throw MiningGatewayException(
        (body['error'] as String?) ?? 'Impossible d’autoriser cet appareil.',
      );
    }

    final token = body['token'];
    final gatewayUrl = body['gatewayUrl'];
    if (token is! String || gatewayUrl is! String ||
        !gatewayUrl.startsWith('wss://')) {
      throw const MiningGatewayException('La configuration sécurisée du gateway est invalide.');
    }

    final channel = WebSocketChannel.connect(Uri.parse(gatewayUrl));
    try {
      await channel.ready.timeout(const Duration(seconds: 12));
      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      return MiningGatewayConnection._(channel);
    } catch (_) {
      await channel.sink.close();
      throw const MiningGatewayException('Connexion sécurisée au service de calcul impossible.');
    }
  }
}
