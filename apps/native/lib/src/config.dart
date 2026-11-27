class MineMeConfig {
  static const supabaseUrl = String.fromEnvironment(
    'MINE_ME_SUPABASE_URL',
    defaultValue: 'https://mqyqpflamkplhlphrngn.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'MINE_ME_SUPABASE_KEY',
    defaultValue: 'sb_publishable_9jRqX5-oP2nKA13G8ADBeg_OoRc4eFc',
  );
  static const apiBaseUrl = String.fromEnvironment(
    'MINE_ME_API_BASE_URL',
    defaultValue: 'https://mine-me.671btweb.workers.dev/minime',
  );
  static const consentVersion = '2026-11-19-v1';
}
