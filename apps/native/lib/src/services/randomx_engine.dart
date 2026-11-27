import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _InitNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _InitDart = int Function(Pointer<Utf8>, int);
typedef _HashNative = Int32 Function(Pointer<Uint8>, IntPtr, Pointer<Uint8>);
typedef _HashDart = int Function(Pointer<Uint8>, int, Pointer<Uint8>);
typedef _ModeNative = Int32 Function();
typedef _ModeDart = int Function();
typedef _ReleaseNative = Void Function();
typedef _ReleaseDart = void Function();

class RandomXEngineException implements Exception {
  const RandomXEngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Native RandomX engine backed by the upstream RandomX C API.
/// Desktop uses fast mode (about 2.1 GiB dataset); Android defaults to light
/// mode to avoid unexpectedly reserving most of a phone's RAM.
class RandomXEngine {
  RandomXEngine._(DynamicLibrary library)
      : _init = library.lookupFunction<_InitNative, _InitDart>('mm_randomx_init'),
        _hash = library.lookupFunction<_HashNative, _HashDart>('mm_randomx_hash'),
        _mode = library.lookupFunction<_ModeNative, _ModeDart>('mm_randomx_mode'),
        _release = library.lookupFunction<_ReleaseNative, _ReleaseDart>('mm_randomx_release');

  final _InitDart _init;
  final _HashDart _hash;
  final _ModeDart _mode;
  final _ReleaseDart _release;
  bool _initialised = false;

  static RandomXEngine load() {
    final library = Platform.isAndroid
        ? DynamicLibrary.open('libmine_me_randomx.so')
        : DynamicLibrary.open(_desktopLibraryPath());
    return RandomXEngine._(library);
  }

  static String _desktopLibraryPath() {
    final executable = File(Platform.resolvedExecutable).absolute;
    final directory = executable.parent.path;
    if (Platform.isMacOS) {
      return '$directory/../Frameworks/libmine_me_randomx.dylib';
    }
    if (Platform.isWindows) return '$directory/mine_me_randomx.dll';
    return '$directory/libmine_me_randomx.so';
  }

  Future<bool> initialise(String seedHashHex, {bool? fastMode}) async {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(seedHashHex)) {
      throw const RandomXEngineException('La graine RandomX reçue du pool est invalide.');
    }
    final requestFast = fastMode ?? !Platform.isAndroid;
    final seed = seedHashHex.toNativeUtf8();
    try {
      final result = _init(seed, requestFast ? 1 : 0);
      if (result < 0) {
        throw RandomXEngineException('Initialisation RandomX impossible (code $result).');
      }
      _initialised = true;
      return result == 1;
    } finally {
      malloc.free(seed);
    }
  }

  Uint8List calculateHash(Uint8List blob) {
    if (!_initialised) throw const RandomXEngineException('Le moteur RandomX n’est pas initialisé.');
    final input = malloc<Uint8>(blob.length);
    final output = malloc<Uint8>(32);
    try {
      input.asTypedList(blob.length).setAll(0, blob);
      final result = _hash(input, blob.length, output);
      if (result != 0) throw RandomXEngineException('Calcul RandomX impossible (code $result).');
      return Uint8List.fromList(output.asTypedList(32));
    } finally {
      malloc.free(input);
      malloc.free(output);
    }
  }

  bool get isFastMode => _mode() == 1;

  void dispose() {
    if (!_initialised) return;
    _release();
    _initialised = false;
  }
}
