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

  // Spotify — Client ID van je app op developer.spotify.com. De Redirect URI
  // staat vast (zie AndroidManifest.xml) en moet daar ook zo ingesteld zijn.
  static const spotifyClientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
  static const spotifyRedirectUri = 'kinetic://spotify-auth';

  static bool get hasSpotify => spotifyClientId.trim().isNotEmpty;
}
