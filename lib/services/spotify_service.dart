// spotify_service.dart — Spotify bedienen tijdens een training, via de
// Spotify-app op de telefoon (App Remote, package spotify_sdk): afspelen,
// pauzeren, volgende/vorige, shuffle en herhalen; plus je playlists en je
// wachtrij (Web API). Vereist de Spotify-app, Spotify Premium en een Client
// ID in dart_defines.json (SPOTIFY_CLIENT_ID) — zie RUN_COMMANDS.md.
//
// Inloggen gebeurt maar één keer: de koppeling met de Spotify-app onthoudt
// Spotify zelf, en het token voor de Web API (playlists, wachtrij) wordt
// veilig bewaard en pas vernieuwd als het verlopen is.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotify_sdk/spotify_sdk.dart';

import '../core/app_config.dart';

/// Eén zoekresultaat uit de Web API.
class SpotifyTrackResult {
  final String uri;
  final String name;
  final String artists;
  final String? imageUrl;
  const SpotifyTrackResult({
    required this.uri,
    required this.name,
    required this.artists,
    this.imageUrl,
  });

  /// Null voor iets dat geen nummer is (bv. een lege plek in de lijst).
  static SpotifyTrackResult? tryFromJson(Object? json) =>
      json is Map<String, dynamic> && json['uri'] is String
      ? SpotifyTrackResult.fromJson(json)
      : null;

  factory SpotifyTrackResult.fromJson(Map<String, dynamic> json) {
    final images =
        (json['album']?['images'] as List?) ??
        (json['images'] as List?) ??
        const [];
    return SpotifyTrackResult(
      uri: json['uri'] as String,
      name: (json['name'] as String?) ?? '',
      // Een podcast-aflevering heeft geen artiesten, wel een show.
      artists: [
        for (final a in (json['artists'] as List? ?? const []))
          (a as Map)['name'] as String? ?? '',
        if (json['show'] is Map) (json['show']['name'] as String?) ?? '',
      ].where((n) => n.isNotEmpty).join(', '),
      // De kleinste hoes is genoeg voor een lijst.
      imageUrl: images.isEmpty ? null : (images.last as Map)['url'] as String?,
    );
  }
}

/// Eén playlist (eigen lijst of zoekresultaat).
class SpotifyPlaylistResult {
  final String uri;
  final String name;
  final String owner;
  final int tracks;
  final String? imageUrl;

  /// Spotify-account-id van de eigenaar ("spotify" voor hun eigen lijsten).
  final String ownerId;

  /// Een playlist waar je aan meewerkt.
  final bool collaborative;
  const SpotifyPlaylistResult({
    required this.uri,
    required this.name,
    required this.owner,
    required this.tracks,
    this.imageUrl,
    this.ownerId = '',
    this.collaborative = false,
  });

  /// Kan Kinetic de nummers inlezen? Sinds februari 2026 alleen voor
  /// playlists die je zelf maakte of waar je aan meewerkt — andere
  /// (gevolgde) playlists kun je wel afspelen, niet openen.
  bool openableBy(String? myId) =>
      uri.endsWith(':collection') ||
      collaborative ||
      (myId != null && ownerId == myId);

  /// Door Spotify zelf gemaakt (bv. "Songs you never skip", Discover
  /// Weekly). Sinds eind 2024 mogen nieuwe apps de nummers daarvan niet
  /// inlezen — afspelen mag wel.
  bool get bySpotify => ownerId == 'spotify';

  /// Null voor lege plekken in de lijst (de Web API geeft soms `null`).
  static SpotifyPlaylistResult? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final uri = json['uri'] as String?;
    if (uri == null) return null;
    final images = (json['images'] as List?) ?? const [];
    final tracks = json['tracks'] ?? json['items'];
    return SpotifyPlaylistResult(
      uri: uri,
      name: (json['name'] as String?) ?? '',
      owner: (json['owner']?['display_name'] as String?) ?? '',
      ownerId: (json['owner']?['id'] as String?) ?? '',
      collaborative: json['collaborative'] == true,
      tracks: (tracks is Map ? tracks['total'] as num? : null)?.toInt() ?? 0,
      imageUrl: images.isEmpty ? null : (images.last as Map)['url'] as String?,
    );
  }
}

/// Wat er nu speelt en wat er in de wachtrij staat.
class SpotifyQueue {
  final SpotifyTrackResult? current;
  final List<SpotifyTrackResult> upNext;
  const SpotifyQueue({this.current, this.upNext = const []});
}

/// Een fout van de Web API, met een uitleg die je zelf kunt oplossen.
class SpotifyWebApiException implements Exception {
  final int statusCode;
  const SpotifyWebApiException(this.statusCode);

  /// Eigen code: Spotify laat deze playlist niet inlezen.
  static const playlistBlocked = -1;

  String get message => switch (statusCode) {
    playlistBlocked =>
      'Spotify laat apps alleen de nummers van je eigen playlists inlezen. '
          'Met ▶ kun je deze wel gewoon afspelen.',
    401 => 'Je Spotify-login is verlopen. Probeer het nog een keer.',
    403 =>
      'Spotify weigert de toegang (403). Staat je Spotify-account bij '
          '"User Management" van je app op developer.spotify.com? Een app '
          'in ontwikkelmodus werkt alleen voor accounts die daar staan.',
    429 => 'Even te veel verzoeken naar Spotify — probeer het zo opnieuw.',
    _ => 'Spotify gaf een fout ($statusCode).',
  };

  @override
  String toString() => message;
}

class SpotifyService extends ChangeNotifier {
  SpotifyService._();
  static final SpotifyService instance = SpotifyService._();

  static const _scopes =
      'app-remote-control,user-read-playback-state,user-modify-playback-state,'
      'playlist-read-private,playlist-read-collaborative,user-library-read';

  bool connecting = false;
  bool get connected => _connected;
  bool _connected = false;

  /// Uitleg als verbinden of een actie mislukte — getoond in het paneel.
  String? error;

  PlayerState? player;

  /// Wanneer [player] binnenkwam — de positie loopt vanaf daar door zolang
  /// er gespeeld wordt (Spotify stuurt niet elke seconde een update).
  DateTime? _stateAt;
  Uint8List? cover;
  String? _coverFor;

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'spotify_access_token';
  static const _tokenExpiresKey = 'spotify_token_expires';

  /// Met welke rechten het bewaarde token is opgehaald — komen er rechten
  /// bij (bv. gelikte nummers), dan is een nieuw token nodig.
  static const _tokenScopesKey = 'spotify_token_scopes';

  String? _token;
  DateTime? _tokenExpires;
  bool _tokenLoaded = false;
  StreamSubscription<PlayerState>? _playerSub;
  StreamSubscription<ConnectionStatus>? _connectionSub;

  /// Verbindt met de Spotify-app (en logt de eerste keer in).
  Future<void> connect() async {
    if (_connected || connecting) return;
    if (!AppConfig.hasSpotify) {
      error =
          'Spotify is nog niet ingesteld: zet je Client ID in '
          'dart_defines.json (SPOTIFY_CLIENT_ID) en bouw de app opnieuw.';
      notifyListeners();
      return;
    }
    connecting = true;
    error = null;
    notifyListeners();
    try {
      // Geen aparte SpotifySdk.isSpotifyInstalled()-check vooraf: die gaf
      // op een telefoon mét Spotify toch "niet geïnstalleerd". Verbinden
      // gooit zelf SpotifyNotInstalledException als de app echt ontbreekt.
      //
      // Bewust géén getAccessToken hier: dat opent elke keer het
      // Spotify-inlogscherm. De koppeling met de app vraagt alleen de
      // allereerste keer om akkoord; het token voor playlists/wachtrij
      // wordt pas opgehaald als je die opent.
      _connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: AppConfig.spotifyClientId,
        redirectUrl: AppConfig.spotifyRedirectUri,
        scope: _scopes,
        playerName: 'Kinetic',
      );
      if (_connected) _subscribe();
    } on SpotifyNotInstalledException {
      error = 'De Spotify-app staat niet op deze telefoon.';
    } on SpotifyAuthenticationException catch (e) {
      error = 'Inloggen bij Spotify is niet gelukt (${e.message}).';
    } on SpotifyException catch (e) {
      error = 'Verbinden met Spotify is niet gelukt: ${e.message}';
    } catch (e) {
      error = 'Verbinden met Spotify is niet gelukt: $e';
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  void _subscribe() {
    _playerSub?.cancel();
    _playerSub = SpotifySdk.subscribePlayerState().listen((state) {
      player = state;
      _stateAt = DateTime.now();
      _loadCover(state);
      notifyListeners();
    });
    _connectionSub?.cancel();
    _connectionSub = SpotifySdk.subscribeConnectionStatus().listen((status) {
      _connected = status.connected;
      notifyListeners();
    });
  }

  Future<void> _loadCover(PlayerState state) async {
    final track = state.track;
    if (track == null || track.uri == _coverFor) return;
    _coverFor = track.uri;
    try {
      cover = await SpotifySdk.getImage(imageUri: track.imageUri);
      notifyListeners();
    } catch (_) {
      cover = null;
    }
  }

  /// Token voor de Web API: uit het geheugen, anders uit de veilige opslag
  /// (overleeft het sluiten van de app), en pas als het verlopen is een
  /// nieuw ophalen bij Spotify.
  Future<void> _ensureToken({bool force = false}) async {
    if (!_tokenLoaded) {
      _tokenLoaded = true;
      try {
        final scopes = await _storage.read(key: _tokenScopesKey);
        if (scopes == _scopes) {
          _token = await _storage.read(key: _tokenKey);
          final raw = await _storage.read(key: _tokenExpiresKey);
          _tokenExpires = raw == null ? null : DateTime.tryParse(raw);
        }
      } catch (_) {
        // Geen opslag beschikbaar: gewoon een nieuw token ophalen.
      }
    }
    final expires = _tokenExpires;
    if (!force &&
        _token != null &&
        expires != null &&
        DateTime.now().isBefore(expires)) {
      return;
    }
    _token = await SpotifySdk.getAccessToken(
      clientId: AppConfig.spotifyClientId,
      redirectUrl: AppConfig.spotifyRedirectUri,
      scope: _scopes,
    );
    // Spotify-tokens gelden een uur; iets eerder vernieuwen.
    _tokenExpires = DateTime.now().add(const Duration(minutes: 55));
    try {
      await _storage.write(key: _tokenKey, value: _token);
      await _storage.write(key: _tokenScopesKey, value: _scopes);
      await _storage.write(
        key: _tokenExpiresKey,
        value: _tokenExpires!.toIso8601String(),
      );
    } catch (_) {
      // Niet bewaard: volgende keer opnieuw ophalen.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      error = null;
    } on SpotifyException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> togglePlay() => _run(() async {
    if (player?.isPaused ?? true) {
      await SpotifySdk.resume();
    } else {
      await SpotifySdk.pause();
    }
  });

  Future<void> next() => _run(SpotifySdk.skipNext);
  Future<void> previous() => _run(SpotifySdk.skipPrevious);
  Future<void> toggleShuffle() => _run(SpotifySdk.toggleShuffle);
  Future<void> toggleRepeat() => _run(SpotifySdk.toggleRepeat);

  bool get shuffling => player?.playbackOptions.isShuffling ?? false;

  /// Lengte van het huidige nummer in ms (0 als er niets speelt).
  int get durationMs => player?.track?.duration ?? 0;

  /// Huidige positie in ms, live doorgerekend tussen updates door.
  int get positionMs {
    final p = player;
    if (p == null) return 0;
    var pos = p.playbackPosition;
    final at = _stateAt;
    if (!p.isPaused && at != null) {
      pos += DateTime.now().difference(at).inMilliseconds;
    }
    final d = durationMs;
    return d > 0 ? pos.clamp(0, d) : pos;
  }

  Future<void> seek(int ms) =>
      _run(() => SpotifySdk.seekTo(positionedMilliseconds: ms));

  /// Eén los nummer afspelen (bv. uit de zoekresultaten).
  Future<void> playTrack(String uri) =>
      _run(() => SpotifySdk.play(spotifyUri: uri));

  /// Zoals in Spotify: nummer [trackUri] uit playlist [contextUri]
  /// afspelen, en daarna gaat de playlist gewoon verder. Via de Web API
  /// (die kent "begin bij dit nummer"); lukt dat niet, dan via de app met
  /// de positie [index].
  Future<void> playFrom(String contextUri, String trackUri, int index) async {
    try {
      await _send('PUT', '/v1/me/player/play', {
        'context_uri': contextUri,
        'offset': {'uri': trackUri},
      });
      error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Spotify afspelen via Web API mislukt ($e), via de app.');
      await playAt(contextUri, index);
    }
  }

  SpotifyRepeatMode get repeatMode =>
      player?.playbackOptions.repeatMode ?? SpotifyRepeatMode.off;

  /// Speelt playlist [contextUri] af vanaf nummer [index].
  Future<void> playAt(String contextUri, int index) => _run(
    () => SpotifySdk.skipToIndex(spotifyUri: contextUri, trackIndex: index),
  );

  /// Zet één nummer in de wachtrij; true als dat lukte.
  Future<bool> addToQueue(String trackUri) async {
    try {
      await SpotifySdk.queue(spotifyUri: trackUri);
      error = null;
      notifyListeners();
      return true;
    } on SpotifyException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
    return false;
  }

  /// De nummers van een playlist (of van je gelikte nummers), in volgorde.
  Future<List<SpotifyTrackResult>> tracksOf(
    SpotifyPlaylistResult playlist,
  ) async {
    final isLiked = playlist.uri.endsWith(':collection');
    final id = playlist.uri.split(':').last;
    final result = <SpotifyTrackResult>[];
    // Sinds februari 2026 heet het "items" (was "tracks").
    final path = isLiked ? '/v1/me/tracks' : '/v1/playlists/$id/items';
    var offset = 0;
    // Hooguit 300 nummers: genoeg om in te kiezen, en snel geladen.
    while (result.length < 300) {
      final Map<String, dynamic> body;
      try {
        body = await _getJson(path, {
          'limit': isLiked ? '50' : '100',
          'offset': '$offset',
        });
      } on SpotifyWebApiException catch (e) {
        // Je playlists laden wél, dus een 403/404 hier gaat over déze
        // playlist: Spotify laat alleen je eigen lijsten inlezen.
        if (e.statusCode == 403 || e.statusCode == 404) {
          throw const SpotifyWebApiException(
            SpotifyWebApiException.playlistBlocked,
          );
        }
        rethrow;
      }
      final items = (body['items'] as List?) ?? const [];
      for (final item in items) {
        if (item is Map) {
          // Playlist-items: "item" (sinds feb. 2026); opgeslagen nummers en
          // oudere antwoorden: "track".
          final track = SpotifyTrackResult.tryFromJson(
            item['item'] ?? item['track'],
          );
          if (track != null) result.add(track);
        }
      }
      offset += items.length;
      if (items.isEmpty || body['next'] == null) break;
    }
    return result;
  }

  /// Speelt een playlist (of nummer) meteen af.
  Future<void> play(String uri) => _run(() => SpotifySdk.play(spotifyUri: uri));

  /// GET op de Web API met het token; bij een verlopen token één keer
  /// opnieuw.
  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    Future<http.Response> get() => http.get(
      Uri.https('api.spotify.com', path, query),
      headers: {'Authorization': 'Bearer $_token'},
    );
    await _ensureToken();
    var response = await get();
    if (response.statusCode == 401) {
      await _ensureToken(force: true);
      response = await get();
    }
    if (response.statusCode != 200) {
      debugPrint(
        'Spotify Web API $path: ${response.statusCode} ${response.body}',
      );
      throw SpotifyWebApiException(response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// PUT/POST op de Web API (geen antwoord nodig); bij een verlopen token
  /// één keer opnieuw.
  Future<void> _send(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    Future<http.Response> go() {
      final request = http.Request(method, Uri.https('api.spotify.com', path))
        ..headers['Authorization'] = 'Bearer $_token'
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
      return request.send().then(http.Response.fromStream);
    }

    await _ensureToken();
    var response = await go();
    if (response.statusCode == 401) {
      await _ensureToken(force: true);
      response = await go();
    }
    if (response.statusCode >= 300) {
      debugPrint(
        'Spotify Web API $path: ${response.statusCode} ${response.body}',
      );
      throw SpotifyWebApiException(response.statusCode);
    }
  }

  /// Zoekt nummers via de Web API.
  Future<List<SpotifyTrackResult>> searchTracks(
    String query, {
    int offset = 0,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final body = await _getJson('/v1/search', {
      'q': q,
      'type': 'track',
      // Ontwikkelmodus: hooguit 10 per keer (sinds februari 2026).
      'limit': '10',
      'offset': '$offset',
    });
    return [
      for (final item in (body['tracks']?['items'] as List?) ?? const [])
        ?SpotifyTrackResult.tryFromJson(item),
    ];
  }

  /// Wat er nu speelt en wat er hierna komt.
  Future<SpotifyQueue> queue() async {
    final body = await _getJson('/v1/me/player/queue');
    return SpotifyQueue(
      current: SpotifyTrackResult.tryFromJson(body['currently_playing']),
      upNext: [
        for (final item in (body['queue'] as List?) ?? const [])
          ?SpotifyTrackResult.tryFromJson(item),
      ],
    );
  }

  String? _userId;

  /// Je Spotify-account-id (één keer opgehaald).
  Future<String?> myId() async {
    try {
      return _userId ??= (await _getJson('/v1/me'))['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Je gelikte nummers als afspeelbare lijst: het adres van je verzameling
  /// en hoeveel nummers erin zitten.
  Future<SpotifyPlaylistResult> likedSongs() async {
    final id = _userId ??= (await _getJson('/v1/me'))['id'] as String?;
    final body = await _getJson('/v1/me/tracks', {'limit': '1'});
    return SpotifyPlaylistResult(
      uri: 'spotify:user:$id:collection',
      name: 'Gelikte nummers',
      owner: '',
      tracks: (body['total'] as num?)?.toInt() ?? 0,
    );
  }

  // ── Vastgepinde playlists (op deze telefoon) ──
  static const _pinnedKey = 'spotify_pinned_playlists';

  Future<Set<String>> pinnedPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_pinnedKey) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> setPinned(Set<String> uris) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pinnedKey, uris.toList());
    } catch (_) {
      // Niet bewaard; blijft voor deze sessie staan.
    }
  }

  /// Je eigen (en gevolgde) playlists.
  Future<List<SpotifyPlaylistResult>> myPlaylists() async {
    final body = await _getJson('/v1/me/playlists', {'limit': '50'});
    final items = (body['items'] as List?) ?? const [];
    return [for (final item in items) ?SpotifyPlaylistResult.tryFromJson(item)];
  }
}
