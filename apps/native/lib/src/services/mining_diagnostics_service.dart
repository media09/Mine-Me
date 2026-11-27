import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Best-effort, privacy-safe lifecycle diagnostics for a single device session.
class MiningDiagnostics {
  MiningDiagnostics(this._client);

  final SupabaseClient _client;

  static String newTraceId() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> record({
    required String deviceId,
    required String eventType,
    required String traceId,
    Map<String, Object?> details = const {},
  }) async {
    try {
      await _client.from('device_events').insert({
        'device_id': deviceId,
        'event_type': eventType,
        'details': {
          'trace_id': traceId,
          'source': 'native_app',
          ...details,
        },
      });
    } catch (_) {
      // Diagnostics must never prevent a safe stop or change mining behaviour.
    }
  }
}
