import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';

class DeviceService {
  DeviceService(this._client);
  final SupabaseClient _client;
  static const _uuid = Uuid();
  static const _installationKey = 'mine-me.native-installation-id';
  static const _secureStorage = FlutterSecureStorage();

  Future<String> _installationId() async {
    final stored = await _secureStorage.read(key: _installationKey);
    if (stored != null && RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(stored)) {
      return stored;
    }
    final generated = _uuid.v4();
    await _secureStorage.write(key: _installationKey, value: generated);
    return generated;
  }

  Future<String> enroll() async {
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
    if (existing != null) return existing['id'] as String;

    final info = DeviceInfoPlugin();
    String platform;
    String label;
    if (Platform.isAndroid) {
      final data = await info.androidInfo;
      platform = 'Android';
      label = '${data.manufacturer} ${data.model}'.trim();
    } else if (Platform.isWindows) {
      final data = await info.windowsInfo;
      platform = 'Windows';
      label = data.productName;
    } else if (Platform.isMacOS) {
      final data = await info.macOsInfo;
      platform = 'macOS';
      label = data.model;
    } else if (Platform.isLinux) {
      final data = await info.linuxInfo;
      platform = 'Linux';
      label = data.prettyName;
    } else {
      platform = 'Desktop';
      label = 'MINE-ME Desktop';
    }

    final created = await _client.from('devices').insert({
      'user_id': user.id,
      'installation_id': await _installationId(),
      'label': label.isEmpty ? 'MINE-ME $platform' : label,
      'platform_family': platform,
      'browser_family': 'MINE-ME Native',
      'hardware_threads': Platform.numberOfProcessors.clamp(1, 256),
    }).select('id').single();
    return created['id'] as String;
  }

}
