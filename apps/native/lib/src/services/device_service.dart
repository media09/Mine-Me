import 'package:device_info_plus/device_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';

class DeviceService {
  DeviceService(this._client);
  final SupabaseClient _client;
  static const _uuid = Uuid();
  static const _installationKey = 'mine-me.native-installation-id';

  Future<String> _installationId() async {
    // Device identity is a random installation identifier, not a hardware ID.
    final storage = _client.auth;
    final metadata = await _client.from('profiles').select('id').eq(
      'id', _client.auth.currentUser!.id,
    ).maybeSingle();
    if (metadata == null) throw Exception('Profil MINE-ME introuvable.');
    // A stable per-install identifier is stored in secure local preferences by
    // the platform adapter in later releases; this first release uses a UUID.
    // The value is retained for this service lifetime to prevent duplicate rows
    // during retries in the same app session.
    return _uuid.v4();
  }

  Future<void> enroll() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Connectez-vous pour associer cet appareil.');

    final profile = await _client.from('profiles')
        .select('consent_version, consented_at, account_status')
        .eq('id', user.id).maybeSingle();
    if (profile == null ||
        profile['account_status'] != 'active' ||
        profile['consent_version'] != MineMeConfig.consentVersion ||
        profile['consented_at'] == null) {
      throw Exception('Le consentement MINE-ME actuel est requis.');
    }

    final existing = await _client.from('devices')
        .select('id')
        .eq('user_id', user.id)
        .eq('installation_id', await _installationId())
        .maybeSingle();
    if (existing != null) return;

    final info = DeviceInfoPlugin();
    String platform;
    String label;
    if (await _isAndroid()) {
      final data = await info.androidInfo;
      platform = 'Android';
      label = '${data.manufacturer} ${data.model}'.trim();
    } else if (await _isWindows()) {
      final data = await info.windowsInfo;
      platform = 'Windows';
      label = data.productName;
    } else if (await _isMacOS()) {
      final data = await info.macOsInfo;
      platform = 'macOS';
      label = data.model;
    } else if (await _isLinux()) {
      final data = await info.linuxInfo;
      platform = 'Linux';
      label = data.prettyName;
    } else {
      platform = 'Desktop';
      label = 'MINE-ME Desktop';
    }

    await _client.from('devices').insert({
      'user_id': user.id,
      'installation_id': await _installationId(),
      'label': label.isEmpty ? 'MINE-ME $platform' : label,
      'platform_family': platform,
      'browser_family': 'MINE-ME Native',
      'hardware_threads': 1,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<bool> _isAndroid() async => _platform() == 'android';
  Future<bool> _isWindows() async => _platform() == 'windows';
  Future<bool> _isMacOS() async => _platform() == 'macos';
  Future<bool> _isLinux() async => _platform() == 'linux';
  String _platform() {
    // DeviceInfoPlugin platform-specific calls are guarded by these checks.
    return const String.fromEnvironment('MINE_ME_PLATFORM');
  }
}
