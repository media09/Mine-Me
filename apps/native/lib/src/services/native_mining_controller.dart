import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'android_mining_service.dart';
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
  NativeMiningController(this._client);
  final SupabaseClient _client;

  NativeMiningState state = NativeMiningState.idle;
  String? errorMessage;
  String? activeDeviceId;
  String? workerCode;
  String? randomXMode;
  double hashesPerSecond = 0;
  int acceptedShares = 0;
  int rejectedShares = 0;

  int _requestedIntensity = 20;
  MiningGatewayConnection? _gateway;
  NativeRandomXWorker? _worker;
  StreamSubscription<Map<String, dynamic>>? _gatewaySubscription;
  StreamSubscription<Map<String, dynamic>>? _workerSubscription;
  bool _disposed = false;

  Future<void> start(String deviceId, {int intensityPercent = 20}) async {
    if (state != NativeMiningState.idle &&
        state != NativeMiningState.paused &&
        state != NativeMiningState.error) return;
    activeDeviceId = deviceId;
    _requestedIntensity = intensityPercent.clamp(1, 80);
    _setState(NativeMiningState.authorising);
    errorMessage = null;
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw const MiningGatewayException('Connectez-vous avant de démarrer.');

      // A paused/stopped member device must be explicitly re-enrolled.
      await _client.from('devices')
          .update({'status': 'enrolled'})
          .eq('id', deviceId)
          .eq('user_id', user.id)
          .inFilter('status', ['paused', 'stopped']);

      final gateway = await MiningGatewayService(_client).connect(deviceId: deviceId);
      _gateway = gateway;
      await AndroidMiningService.start();
      _setState(NativeMiningState.connecting);
      _gatewaySubscription = gateway.messages.listen(
        _onGatewayMessage,
        onError: (Object error) => _fail('Connexion au service de calcul interrompue.'),
        onDone: () {
          unawaited(_worker?.stop());
          unawaited(AndroidMiningService.stop());
          _worker = null;
          if (state == NativeMiningState.running ||
              state == NativeMiningState.initialising ||
              state == NativeMiningState.connecting) {
            _setState(NativeMiningState.idle);
          }
        },
      );
    } catch (error) {
      _fail(error.toString());
    }
  }

  void _onGatewayMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'ready':
        workerCode = message['workerCode'] as String?;
        break;
      case 'job':
        final job = Map<String, dynamic>.from(message['job'] as Map);
        unawaited(_installJob(job));
        break;
      case 'share-result':
        if (message['accepted'] == true) {
          acceptedShares += 1;
        } else {
          rejectedShares += 1;
        }
        _notify();
        break;
      case 'heartbeat-ack':
        break;
      case 'control-ack':
        _setState(message['status'] == 'paused'
            ? NativeMiningState.paused
            : NativeMiningState.idle);
        break;
      case 'error':
        _fail((message['message'] as String?) ?? 'Le service de calcul a refusé la session.');
        break;
    }
  }

  Future<void> _installJob(Map<String, dynamic> job) async {
    try {
      if (_worker == null) {
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
      _fail(error.toString());
    }
  }

  void _onWorkerMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'ready':
        randomXMode = message['mode'] as String?;
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
        } catch (error) {
          _fail(error.toString());
        }
        break;
      case 'hashrate':
        hashesPerSecond = (message['hashesPerSecond'] as num).toDouble();
        _gateway?.reportTelemetry(
          hashesPerSecond: hashesPerSecond,
          hashesComputed: message['hashesComputed'] as int,
          sampleSeconds: (message['sampleSeconds'] as num).toDouble(),
        );
        unawaited(AndroidMiningService.update('Calcul en cours · ${hashesPerSecond.toStringAsFixed(1)} H/s'));
        _notify();
        break;
      case 'paused':
        _setState(NativeMiningState.paused);
        break;
      case 'nonce-exhausted':
        break;
      case 'error':
        _fail((message['message'] as String?) ?? 'Erreur du moteur RandomX.');
        break;
      case 'stopped':
        if (state == NativeMiningState.stopping) _setState(NativeMiningState.idle);
        break;
    }
  }

  void pause() {
    if (state != NativeMiningState.running &&
        state != NativeMiningState.initialising) return;
    _setState(NativeMiningState.stopping);
    _worker?.pause();
    _gateway?.pause();
    unawaited(AndroidMiningService.stop());
  }

  void stop() {
    if (state == NativeMiningState.idle) return;
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

  void _fail(String message) {
    errorMessage = message;
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
