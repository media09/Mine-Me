import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'android_mining_service.dart';
import 'mining_diagnostics_service.dart';
import 'mining_gateway_service.dart';
import 'native_randomx_worker.dart';

enum NativeMiningState {
  idle,
  authorising,
  connecting,
  initialising,
  running,
  paused,
  stopping,
  error,
}

class NativeMiningController extends ChangeNotifier {
  NativeMiningController(this._client)
      : _diagnostics = MiningDiagnostics(_client);

  final SupabaseClient _client;
  final MiningDiagnostics _diagnostics;

  NativeMiningState state = NativeMiningState.idle;
  String? errorMessage;
  String? activeDeviceId;
  String? workerCode;
  String? randomXMode;
  double hashesPerSecond = 0;
  int acceptedShares = 0;
  int rejectedShares = 0;

  int _requestedIntensity = 20;
  String? _traceId;
  String _stage = 'idle';
  MiningGatewayConnection? _gateway;
  NativeRandomXWorker? _worker;
  StreamSubscription<Map<String, dynamic>>? _gatewaySubscription;
  StreamSubscription<Map<String, dynamic>>? _workerSubscription;
  bool _disposed = false;

  void _record(String event, [Map<String, Object?> details = const {}]) {
    final deviceId = activeDeviceId;
    final traceId = _traceId;
    if (deviceId == null || traceId == null) return;
    unawaited(_diagnostics.record(
      deviceId: deviceId,
      eventType: event,
      traceId: traceId,
      details: {'stage': _stage, ...details},
    ));
  }

  Future<void> start(String deviceId, {int intensityPercent = 20}) async {
    if (state != NativeMiningState.idle &&
        state != NativeMiningState.paused &&
        state != NativeMiningState.error) return;

    if (state == NativeMiningState.paused || state == NativeMiningState.error) {
      await disposeSession();
    }
    activeDeviceId = deviceId;
    _traceId = MiningDiagnostics.newTraceId();
    _stage = 'authorising';
    _requestedIntensity = intensityPercent.clamp(1, 80);
    _setState(NativeMiningState.authorising);
    errorMessage = null;
    acceptedShares = 0;
    rejectedShares = 0;
    hashesPerSecond = 0;
    _record('started', {'intensity_percent': _requestedIntensity});

    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        throw const MiningGatewayException(
          'Connectez-vous avant de démarrer.',
          code: 'member_session_missing',
        );
      }

      _stage = 'device_prepare';
      await _client.from('devices')
          .update({'status': 'enrolled'})
          .eq('id', deviceId)
          .eq('user_id', user.id)
          .inFilter('status', ['paused', 'stopped', 'offline']);

      _stage = 'session_request';
      _record('session_requested', {'api': 'mining_session'});
      final gateway = await MiningGatewayService(_client).connect(deviceId: deviceId);
      _gateway = gateway;
      _stage = 'gateway_websocket';
      _record('gateway_connected');
      await AndroidMiningService.start();
      _setState(NativeMiningState.connecting);
      _gatewaySubscription = gateway.messages.listen(
        _onGatewayMessage,
        onError: (Object error) {
          _fail('Connexion au service de calcul interrompue.',
              code: 'gateway_stream_error');
        },
        onDone: () {
          unawaited(_worker?.stop());
          unawaited(AndroidMiningService.stop());
          _worker = null;
          if (state != NativeMiningState.paused &&
              state != NativeMiningState.error &&
              state != NativeMiningState.stopping) {
            _record('worker_disconnected', {'reason': 'gateway_stream_closed'});
            activeDeviceId = null;
            _setState(NativeMiningState.idle);
          }
        },
      );
    } catch (error) {
      if (error is MiningGatewayException) {
        _fail(error.message,
            code: error.code,
            httpStatus: error.httpStatus,
            contentType: error.contentType);
      } else {
        _fail('Préparation du minage impossible.', code: 'start_unexpected_error');
      }
    }
  }

  void _onGatewayMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'ready':
        workerCode = message['workerCode'] as String?;
        _stage = 'gateway_authenticated';
        _record('gateway_ready');
        break;
      case 'job':
        final job = Map<String, dynamic>.from(message['job'] as Map);
        _stage = 'pool_job';
        _record('pool_job_received', {'job_id': job['jobId']?.toString()});
        unawaited(_installJob(job));
        break;
      case 'share-result':
        final accepted = message['accepted'] == true;
        if (accepted) {
          acceptedShares += 1;
          _record('share_accepted', {'share_ref': message['shareRef']?.toString()});
        } else {
          rejectedShares += 1;
          _record('share_rejected', {
            'share_ref': message['shareRef']?.toString(),
            'reason': 'pool_rejected',
          });
        }
        _notify();
        break;
      case 'heartbeat-ack':
        break;
      case 'control-ack':
        if (message['status'] == 'paused') {
          _record('paused');
          _setState(NativeMiningState.paused);
        } else {
          _record('stopped');
          activeDeviceId = null;
          _setState(NativeMiningState.idle);
        }
        break;
      case 'error':
        _fail(
          (message['message'] as String?) ?? 'Le service de calcul a refusé la session.',
          code: 'gateway_rejected_session',
        );
        break;
    }
  }

  Future<void> _installJob(Map<String, dynamic> job) async {
    try {
      if (_worker == null) {
        _stage = 'randomx_initialization';
        _record('randomx_initializing');
        _setState(NativeMiningState.initialising);
        final worker = await NativeRandomXWorker.start(
          job: job,
          intensityPercent: _requestedIntensity,
        );
        _worker = worker;
        _workerSubscription = worker.events.listen(_onWorkerMessage);
      } else {
        _worker!.setJob(job);
      }
    } catch (error) {
      _fail('Le moteur RandomX n’a pas pu traiter le travail reçu.',
          code: 'randomx_job_install_failed');
    }
  }

  void _onWorkerMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'ready':
        randomXMode = message['mode'] as String?;
        _stage = 'randomx_running';
        _record('randomx_ready', {'mode': randomXMode});
        _setState(NativeMiningState.running);
        break;
      case 'new-job':
        break;
      case 'share-found':
        try {
          _gateway?.submitShare(
            jobId: message['jobId'] as String,
            nonce: message['nonce'] as String,
            result: message['result'] as String,
          );
          _record('share_submitted');
        } catch (_) {
          _fail('Transmission de la part au pool impossible.',
              code: 'share_submit_failed');
        }
        break;
      case 'hashrate':
        hashesPerSecond = (message['hashesPerSecond'] as num).toDouble();
        _gateway?.reportTelemetry(
          hashesPerSecond: hashesPerSecond,
          hashesComputed: message['hashesComputed'] as int,
          sampleSeconds: (message['sampleSeconds'] as num).toDouble(),
        );
        unawaited(AndroidMiningService.update(
          'Calcul en cours · ${hashesPerSecond.toStringAsFixed(1)} H/s',
        ));
        _notify();
        break;
      case 'paused':
        _record('paused');
        _setState(NativeMiningState.paused);
        break;
      case 'nonce-exhausted':
        _record('error', {'error_code': 'job_nonce_space_exhausted'});
        break;
      case 'error':
        _fail(
          (message['message'] as String?) ?? 'Erreur du moteur RandomX.',
          code: 'randomx_engine_error',
        );
        break;
      case 'stopped':
        if (state == NativeMiningState.stopping) {
          _record('stopped');
          activeDeviceId = null;
          _setState(NativeMiningState.idle);
        }
        break;
    }
  }

  void pause() {
    if (state != NativeMiningState.running &&
        state != NativeMiningState.initialising) return;
    _stage = 'pause_requested';
    _record('paused', {'source': 'member_action'});
    _setState(NativeMiningState.stopping);
    _worker?.pause();
    _gateway?.pause();
    unawaited(AndroidMiningService.stop());
  }

  void stop() {
    if (state == NativeMiningState.idle) return;
    _stage = 'stop_requested';
    _record('stopped', {'source': 'member_action'});
    _setState(NativeMiningState.stopping);
    _worker?.stop();
    _gateway?.stop();
    unawaited(AndroidMiningService.stop());
  }

  Future<void> disposeSession() async {
    await _workerSubscription?.cancel();
    await _gatewaySubscription?.cancel();
    await _worker?.stop();
    await _gateway?.close();
    await AndroidMiningService.stop();
    _worker = null;
    _gateway = null;
    activeDeviceId = null;
    _setState(NativeMiningState.idle);
  }

  void _fail(
    String message, {
    required String code,
    int? httpStatus,
    String? contentType,
  }) {
    _stage = 'failed';
    errorMessage = message;
    final event = code.startsWith('session_http')
        ? 'session_http_error'
        : code.startsWith('gateway')
            ? 'gateway_error'
            : code.startsWith('randomx')
                ? 'randomx_error'
                : 'error';
    _record(event, {
      'error_code': code,
      if (httpStatus != null) 'http_status': httpStatus,
      if (contentType != null) 'content_type': contentType,
    });
    _worker?.stop();
    _gateway?.close();
    AndroidMiningService.stop();
    _worker = null;
    _gateway = null;
    _setState(NativeMiningState.error);
  }

  void _setState(NativeMiningState next) {
    state = next;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disposeSession());
    super.dispose();
  }
}
