import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'randomx_engine.dart';

class NativeRandomXWorker {
  NativeRandomXWorker._(this._isolate, this._commands, this._events);

  final Isolate _isolate;
  final SendPort _commands;
  final Stream<Map<String, dynamic>> _events;
  Stream<Map<String, dynamic>> get events => _events;

  static Future<NativeRandomXWorker> start({
    required Map<String, dynamic> job,
    required int intensityPercent,
  }) async {
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(
      _nativeRandomXEntry,
      <String, Object>{
        'events': receive.sendPort,
        'job': job,
        'intensityPercent': intensityPercent.clamp(1, 80),
      },
      errorsAreFatal: false,
      debugName: 'MINE-ME RandomX',
    );

    final first = await receive.first.timeout(const Duration(seconds: 90));
    if (first is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      receive.close();
      throw const RandomXEngineException('Le moteur RandomX natif n’a pas pu démarrer.');
    }
    final eventStream = receive.cast<dynamic>()
        .where((value) => value is Map)
        .map((value) => Map<String, dynamic>.from(value as Map));
    return NativeRandomXWorker._(isolate, first, eventStream);
  }

  void setJob(Map<String, dynamic> job) => _commands.send({'type': 'job', 'job': job});
  void setIntensity(int value) => _commands.send({'type': 'intensity', 'value': value.clamp(1, 80)});
  void pause() => _commands.send({'type': 'pause'});
  void resume() => _commands.send({'type': 'resume'});
  Future<void> stop() async {
    _commands.send({'type': 'stop'});
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _isolate.kill(priority: Isolate.immediate);
  }
}

Future<void> _nativeRandomXEntry(Map<String, Object> initial) async {
  final mainPort = initial['events'] as SendPort;
  final commands = ReceivePort();
  final engine = RandomXEngine.load();
  var running = true;
  var paused = false;
  var intensity = initial['intensityPercent'] as int;
  var job = Map<String, dynamic>.from(initial['job'] as Map);
  var blob = _hexToBytes(job['blob'] as String);
  var target = _targetFromHex(job['target'] as String);
  var hashes = 0;
  var reportAt = DateTime.now();
  final commandSubscription = commands.listen((message) async {
    if (message is! Map) return;
    switch (message['type']) {
      case 'pause':
        paused = true;
        mainPort.send({'type': 'paused'});
        break;
      case 'resume':
        if (running) paused = false;
        break;
      case 'stop':
        running = false;
        paused = true;
        break;
      case 'intensity':
        intensity = (message['value'] as int).clamp(1, 80);
        break;
      case 'job':
        final next = Map<String, dynamic>.from(message['job'] as Map);
        try {
          if (next['seedHash'] != job['seedHash']) {
            engine.dispose();
            await engine.initialise(next['seedHash'] as String, fastMode: true);
          }
          job = next;
          blob = _hexToBytes(job['blob'] as String);
          target = _targetFromHex(job['target'] as String);
          paused = false;
          mainPort.send({'type': 'new-job', 'jobId': job['jobId']});
        } catch (error) {
          running = false;
          mainPort.send({'type': 'error', 'message': error.toString()});
        }
        break;
    }
  });

  try {
    final fastMode = await engine.initialise(
      job['seedHash'] as String,
      fastMode: true,
    );
    mainPort.send(commands.sendPort);
    mainPort.send({'type': 'ready', 'mode': fastMode ? 'fast' : 'light'});
    while (running) {
      if (paused) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }

      final currentJob = job;
      final currentBlob = blob;
      final start = DateTime.now();
      final result = engine.calculateHash(currentBlob);
      final elapsed = DateTime.now().difference(start).inMicroseconds / 1000;
      hashes += 1;

      if (!running) break;
      if (identical(currentBlob, blob) && currentJob['jobId'] == job['jobId']) {
        if (_hashMeetsTarget(result, target)) {
          mainPort.send({
            'type': 'share-found',
            'jobId': currentJob['jobId'],
            'nonce': _bytesToHex(currentBlob.sublist(39, 43)),
            'result': _bytesToHex(result),
          });
        }
        if (!_incrementNonce(currentBlob)) {
          paused = true;
          mainPort.send({'type': 'nonce-exhausted', 'jobId': currentJob['jobId']});
        }
      }

      final now = DateTime.now();
      if (now.difference(reportAt).inMilliseconds >= 2000) {
        final seconds = now.difference(reportAt).inMicroseconds / 1000000;
        mainPort.send({
          'type': 'hashrate',
          'hashesPerSecond': hashes / seconds,
          'hashesComputed': hashes,
          'sampleSeconds': seconds,
        });
        hashes = 0;
        reportAt = now;
      }

      final safeIntensity = intensity.clamp(1, 80);
      final idleMs = (elapsed * (100 / safeIntensity - 1)).round();
      if (idleMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: idleMs));
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }
  } catch (error) {
    mainPort.send({'type': 'error', 'message': error.toString()});
  } finally {
    await commandSubscription.cancel();
    commands.close();
    engine.dispose();
    mainPort.send({'type': 'stopped'});
  }
}

Uint8List _hexToBytes(String hex) {
  if (hex.isEmpty || hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
    throw const RandomXEngineException('Blob RandomX invalide.');
  }
  return Uint8List.fromList(List<int>.generate(
    hex.length ~/ 2,
    (index) => int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16),
  ));
}

String _bytesToHex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

BigInt _targetFromHex(String value) {
  final bytes = _hexToBytes(value);
  BigInt readLittleEndian(List<int> source) {
    var result = BigInt.zero;
    for (var i = source.length - 1; i >= 0; i--) {
      result = (result << 8) | BigInt.from(source[i]);
    }
    return result;
  }
  if (bytes.length == 8) return readLittleEndian(bytes);
  if (bytes.length == 4) {
    final compact = readLittleEndian(bytes);
    if (compact == BigInt.zero) throw const RandomXEngineException('Cible du pool invalide.');
    return BigInt.parse('ffffffffffffffff', radix: 16) ~/
        (BigInt.parse('ffffffff', radix: 16) ~/ compact);
  }
  throw const RandomXEngineException('Format de cible du pool non pris en charge.');
}

bool _hashMeetsTarget(Uint8List hash, BigInt target) {
  final value = BigInt.from(0);
  var littleEndian = value;
  for (var i = 31; i >= 24; i--) {
    littleEndian = (littleEndian << 8) | BigInt.from(hash[i]);
  }
  return littleEndian < target;
}

bool _incrementNonce(Uint8List blob) {
  if (blob.length < 43) throw const RandomXEngineException('Blob du pool trop court.');
  final data = ByteData.sublistView(blob);
  final current = data.getUint32(39, Endian.little);
  final fixed = current & 0xff000000;
  final counter = current & 0x00ffffff;
  if (counter == 0x00ffffff) return false;
  data.setUint32(39, fixed | (counter + 1), Endian.little);
  return true;
}
