import 'package:flutter_test/flutter_test.dart';
import 'package:mine_me_native/src/config.dart';

void main() {
  group('MINE-ME native configuration', () {
    test('uses the linked Supabase project by default', () {
      expect(MineMeConfig.supabaseUrl,
          'https://mqyqpflamkplhlphrngn.supabase.co');
      expect(MineMeConfig.supabasePublishableKey, startsWith('sb_publishable_'));
    });

    test('keeps the current consent contract version', () {
      expect(MineMeConfig.consentVersion, '2026-11-19-v1');
    });
  });
}
