// spotify_results_test.dart — playlists, nummers en de wachtrij uit de
// Spotify Web API inlezen, ook met de lege plekken (null) die de API soms
// teruggeeft, en de uitleg bij een fout.

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/services/spotify_service.dart';

void main() {
  test('playlist uit /v1/me/playlists', () {
    final p = SpotifyPlaylistResult.tryFromJson({
      'uri': 'spotify:playlist:abc',
      'name': 'Gym',
      'owner': {'display_name': 'Dion'},
      'tracks': {'total': 42},
      'images': [
        {'url': 'https://i/large'},
        {'url': 'https://i/small'},
      ],
    })!;
    expect(p.name, 'Gym');
    expect(p.owner, 'Dion');
    expect(p.tracks, 42);
    expect(p.imageUrl, 'https://i/small');
  });

  test('lege of onvolledige playlist wordt overgeslagen', () {
    expect(SpotifyPlaylistResult.tryFromJson(null), isNull);
    expect(SpotifyPlaylistResult.tryFromJson({'name': 'zonder uri'}), isNull);
    final noImages = SpotifyPlaylistResult.tryFromJson({
      'uri': 'spotify:playlist:x',
      'images': null,
    })!;
    expect(noImages.imageUrl, isNull);
    expect(noImages.tracks, 0);
  });

  test('nummer met artiesten', () {
    final t = SpotifyTrackResult.fromJson({
      'uri': 'spotify:track:1',
      'name': 'Song',
      'artists': [
        {'name': 'A'},
        {'name': 'B'},
      ],
      'album': {'images': []},
    });
    expect(t.artists, 'A, B');
    expect(t.imageUrl, isNull);
  });

  test(
    'wachtrij-items: nummers en podcast-afleveringen, lege plekken eruit',
    () {
      expect(SpotifyTrackResult.tryFromJson(null), isNull);
      final episode = SpotifyTrackResult.tryFromJson({
        'uri': 'spotify:episode:1',
        'name': 'Aflevering',
        'show': {'name': 'Podcast'},
        'images': [
          {'url': 'https://i/ep'},
        ],
      })!;
      expect(episode.artists, 'Podcast');
      expect(episode.imageUrl, 'https://i/ep');
    },
  );

  test('403 legt uit dat het account bij User Management moet staan', () {
    expect(
      const SpotifyWebApiException(403).message,
      contains('User Management'),
    );
    expect(const SpotifyWebApiException(500).message, contains('500'));
  });

  test('playlists van Spotify zelf worden herkend', () {
    final own = SpotifyPlaylistResult.tryFromJson({
      'uri': 'spotify:playlist:a',
      'owner': {'id': 'dion123', 'display_name': 'Dion'},
    })!;
    final spotify = SpotifyPlaylistResult.tryFromJson({
      'uri': 'spotify:playlist:b',
      'owner': {'id': 'spotify', 'display_name': 'Spotify'},
    })!;
    expect(own.bySpotify, isFalse);
    expect(spotify.bySpotify, isTrue);
    expect(
      const SpotifyWebApiException(SpotifyWebApiException.playlistBlocked)
          .message,
      contains('afspelen'),
    );
  });
}
