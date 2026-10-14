class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const _supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get supabasePublishableKey =>
      _supabasePublishableKey.trim().isNotEmpty
      ? _supabasePublishableKey
      : _supabaseAnonKey;

  static bool get hasSupabase =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;

  // Nightscout
  static const nightscoutUrl = String.fromEnvironment('NIGHTSCOUT_URL');

  static bool get hasNightscout => nightscoutUrl.trim().isNotEmpty;
}
