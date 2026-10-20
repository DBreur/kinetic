// spotify_panel.dart — de Spotify-knop tijdens een training en het paneel
// dat hij opent: wat er nu speelt met vorige/afspelen/volgende, shuffle en
// herhalen, en daaronder je playlists (tik = afspelen) of je wachtrij. De
// logica zit in services/spotify_service.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:spotify_sdk/spotify_sdk.dart' show SpotifyRepeatMode;

import '../services/spotify_service.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic.dart';

const _spotifyGreen = Color(0xFF1DB954);

/// Het Spotify-logo: de officiële vorm (Simple Icons, CC0) — een groene
/// cirkel waar de drie bogen uit zijn gesneden, met zwart erachter zodat de
/// bogen op elke achtergrond zwart zijn.
class SpotifyLogo extends StatelessWidget {
  const SpotifyLogo({super.key, this.size = 22});

  final double size;

  static const _svg =
      '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
      '<path fill="#1DB954" d="M12 0C5.4 0 0 5.4 0 12s5.4 12 12 12 12-5.4 '
      '12-12S18.66 0 12 0zm5.521 17.34c-.24.359-.66.48-1.021.24-2.82-1.74-'
      '6.36-2.101-10.561-1.141-.418.122-.779-.179-.899-.539-.12-.421.18-.78'
      '.54-.9 4.56-1.021 8.52-.6 11.64 1.32.42.18.479.659.301 1.02zm1.44-3.3'
      'c-.301.42-.841.6-1.262.3-3.239-1.98-8.159-2.58-11.939-1.38-.479.12-'
      '1.02-.12-1.14-.6-.12-.48.12-1.021.6-1.141C9.6 9.9 15 10.561 18.72 '
      '12.84c.361.181.54.78.241 1.2zm.12-3.36C15.24 8.4 8.82 8.16 5.16 9.301'
      'c-.6.179-1.2-.181-1.38-.721-.18-.601.18-1.2.72-1.381 4.26-1.26 11.28-'
      '1.02 15.721 1.621.539.3.719 1.02.419 1.56-.299.421-1.02.599-1.559.3z"/>'
      '</svg>';

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(size * .08),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        SvgPicture.string(_svg, width: size, height: size),
      ],
    ),
  );
}

/// Zwevende knop rechtsonder tijdens een training — opent
/// [showSpotifyPanel].
class SpotifyFab extends StatelessWidget {
  const SpotifyFab({super.key});

  @override
  Widget build(BuildContext context) => FloatingActionButton.small(
    tooltip: 'Spotify',
    heroTag: 'spotify',
    backgroundColor: Colors.black,
    shape: const CircleBorder(),
    onPressed: () => showSpotifyPanel(context),
    child: const SpotifyLogo(size: 28),
  );
}

Future<void> showSpotifyPanel(BuildContext context) {
  unawaited(SpotifyService.instance.connect());
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColor.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (_) => const _SpotifyPanel(),
  );
}

enum _Tab { playlists, search, queue }

/// Eén nummer: tik = afspelen, + = in wachtrij. Het nummer dat nu speelt is
/// groen.
class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.track,
    required this.onTap,
    required this.onQueue,
    this.playing = false,
    this.queued = false,
  });

  final SpotifyTrackResult track;
  final VoidCallback onTap;
  final VoidCallback onQueue;
  final bool playing;
  final bool queued;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    onTap: onTap,
    leading: _Cover(url: track.imageUrl, icon: Icons.music_note),
    title: Text(
      track.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.bodyStrong.copyWith(color: playing ? _spotifyGreen : null),
    ),
    subtitle: Text(
      track.artists,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.caption,
    ),
    trailing: queued
        ? const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.check, color: _spotifyGreen),
          )
        : IconButton(
            tooltip: 'In wachtrij',
            icon: const Icon(Icons.playlist_add),
            onPressed: onQueue,
          ),
  );
}

class _SpotifyPanel extends StatefulWidget {
  const _SpotifyPanel();

  @override
  State<_SpotifyPanel> createState() => _SpotifyPanelState();
}

class _SpotifyPanelState extends State<_SpotifyPanel> {
  final _service = SpotifyService.instance;

  _Tab _tab = _Tab.playlists;
  bool get _showQueue => _tab == _Tab.queue;

  /// Ververst de tijdbalk elke seconde zolang het paneel open is.
  Timer? _ticker;

  // ── Zoeken ──
  final _query = TextEditingController();
  Timer? _debounce;
  List<SpotifyTrackResult> _results = const [];
  bool _searching = false;
  String? _searchError;

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String value) async {
    if (value.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await _service.searchTracks(value);
      if (!mounted || _query.text != value) return;
      setState(() => _results = results);
    } on SpotifyWebApiException catch (e) {
      if (mounted) setState(() => _searchError = e.message);
    } catch (e) {
      if (mounted) setState(() => _searchError = 'Zoeken is niet gelukt: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  List<Widget> _searchItems() => [
    TextField(
      controller: _query,
      onChanged: _onQueryChanged,
      textInputAction: TextInputAction.search,
      onSubmitted: _search,
      style: AppText.body,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: 'Zoek een nummer of artiest',
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
    ),
    if (_searchError != null)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _searchError!,
          style: AppText.caption.copyWith(color: AppColor.redBright),
        ),
      ),
    const SizedBox(height: 8),
    for (final t in _results)
      _SongTile(
        track: t,
        playing: _service.player?.track?.uri == t.uri,
        queued: _queued.contains(t.uri),
        onTap: () => _service.playTrack(t.uri),
        onQueue: () => _queueTrack(t),
      ),
    // Spotify geeft er per keer hooguit 10; meer = de volgende 10 ophalen.
    if (_results.length >= 10 && _results.length % 10 == 0 && !_searching)
      TextButton(onPressed: _searchMore, child: const Text('Meer resultaten')),
  ];

  Future<void> _searchMore() async {
    final query = _query.text;
    setState(() => _searching = true);
    try {
      final more = await _service.searchTracks(query, offset: _results.length);
      if (!mounted || _query.text != query) return;
      setState(() => _results = [..._results, ...more]);
    } on SpotifyWebApiException catch (e) {
      if (mounted) setState(() => _searchError = e.message);
    } catch (_) {
      // Laat de huidige resultaten staan.
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  List<SpotifyPlaylistResult>? _playlists;
  SpotifyPlaylistResult? _liked;

  /// Jouw Spotify-id — bepaalt welke playlists je kunt openen.
  String? _me;

  /// Geopende playlist (met zijn nummers), of null in het overzicht.
  SpotifyPlaylistResult? _open;
  List<SpotifyTrackResult>? _openTracks;
  String? _openError;
  final Set<String> _queued = {};

  Future<void> _openPlaylist(SpotifyPlaylistResult playlist) async {
    setState(() {
      _open = playlist;
      _openTracks = null;
      _openError = null;
    });
    try {
      final tracks = await _service.tracksOf(playlist);
      if (mounted && _open == playlist) setState(() => _openTracks = tracks);
    } on SpotifyWebApiException catch (e) {
      if (mounted) setState(() => _openError = e.message);
    } catch (e) {
      if (mounted) setState(() => _openError = 'Laden is niet gelukt: $e');
    }
  }

  Future<void> _queueTrack(SpotifyTrackResult track) async {
    final ok = await _service.addToQueue(track.uri);
    if (!mounted) return;
    if (ok) setState(() => _queued.add(track.uri));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '"${track.name}" staat in je wachtrij'
              : 'In de wachtrij zetten is niet gelukt',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Een geopende playlist: terug, afspelen, en de nummers (tik = vanaf
  /// daar afspelen, + = in wachtrij).
  List<Widget> _openItems(SpotifyPlaylistResult playlist) {
    final tracks = _openTracks;
    return [
      Row(
        children: [
          IconButton(
            tooltip: 'Terug',
            onPressed: () => setState(() => _open = null),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.cardTitle,
            ),
          ),
          IconButton(
            tooltip: 'Shuffle afspelen',
            onPressed: () async {
              if (!_service.shuffling) await _service.toggleShuffle();
              await _play(playlist);
            },
            icon: const Icon(Icons.shuffle, color: _spotifyGreen),
          ),
          IconButton(
            tooltip: 'Afspelen',
            onPressed: () => _play(playlist),
            icon: const Icon(
              Icons.play_circle_fill,
              size: 32,
              color: _spotifyGreen,
            ),
          ),
        ],
      ),
      if (_openError != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _openError!,
            style: AppText.caption.copyWith(color: AppColor.redBright),
          ),
        )
      else if (tracks == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (tracks.isEmpty)
        Text('Deze playlist is leeg.', style: AppText.caption)
      else
        for (var i = 0; i < tracks.length; i++)
          _SongTile(
            track: tracks[i],
            playing: _service.player?.track?.uri == tracks[i].uri,
            queued: _queued.contains(tracks[i].uri),
            onTap: () => _service.playFrom(playlist.uri, tracks[i].uri, i),
            onQueue: () => _queueTrack(tracks[i]),
          ),
    ];
  }

  Set<String> _pinned = {};
  SpotifyQueue? _queue;
  bool _loading = false;
  String? _listError;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onService);
    _onService();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _service.connected) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _debounce?.cancel();
    _query.dispose();
    _service.removeListener(_onService);
    super.dispose();
  }

  /// Zodra de verbinding er is: meteen de playlists laden.
  void _onService() {
    if (_service.connected && _playlists == null && !_loading) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _listError = null;
    });
    try {
      if (_showQueue) {
        final q = await _service.queue();
        if (mounted) setState(() => _queue = q);
      } else {
        final pinned = await _service.pinnedPlaylists();
        final me = await _service.myId();
        final list = await _service.myPlaylists();
        SpotifyPlaylistResult? liked;
        try {
          liked = await _service.likedSongs();
        } catch (_) {
          // Zonder gelikte nummers gaan de playlists gewoon door.
        }
        if (mounted) {
          setState(() {
            _me = me;
            _pinned = pinned;
            _playlists = list;
            _liked = liked;
          });
        }
      }
    } on SpotifyWebApiException catch (e) {
      if (mounted) setState(() => _listError = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _listError = 'Ophalen bij Spotify is niet gelukt: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _togglePin(SpotifyPlaylistResult playlist) {
    setState(() {
      if (!_pinned.remove(playlist.uri)) _pinned.add(playlist.uri);
    });
    _service.setPinned(_pinned);
  }

  /// Gelikte nummers bovenaan, dan vastgepinde playlists, dan de rest.
  List<Widget> _playlistItems() {
    final all = _playlists ?? const <SpotifyPlaylistResult>[];
    final pinned = [
      for (final p in all)
        if (_pinned.contains(p.uri)) p,
    ];
    final rest = [
      for (final p in all)
        if (!_pinned.contains(p.uri)) p,
    ];
    final liked = _liked;
    return [
      if (liked != null)
        _PlaylistTile(
          playlist: liked,
          onOpen: () => _openPlaylist(liked),
          onPlay: () => _play(liked),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF450AF5), Color(0xFFC4EFD9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.favorite, color: Colors.white),
          ),
        ),
      if (pinned.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('VASTGEPIND', style: AppText.overline),
      ],
      for (final p in pinned)
        _PlaylistTile(
          playlist: p,
          openable: p.openableBy(_me),
          pinned: true,
          onOpen: () => _openPlaylist(p),
          onPlay: () => _play(p),
          onTogglePin: () => _togglePin(p),
        ),
      if (pinned.isNotEmpty && rest.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('PLAYLISTS', style: AppText.overline),
      ],
      for (final p in rest)
        _PlaylistTile(
          playlist: p,
          openable: p.openableBy(_me),
          onOpen: () => _openPlaylist(p),
          onPlay: () => _play(p),
          onTogglePin: () => _togglePin(p),
        ),
    ];
  }

  Future<void> _play(SpotifyPlaylistResult playlist) async {
    await _service.play(playlist.uri);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _service.error == null
              ? 'Speelt nu: ${playlist.name}'
              : 'Afspelen is niet gelukt',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      minChildSize: .35,
      maxChildSize: .95,
      builder: (context, scroll) => AnimatedBuilder(
        animation: _service,
        builder: (context, _) => ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + insets.padding.bottom),
          children: [
            Row(
              children: [
                const SpotifyLogo(size: 26),
                const SizedBox(width: 10),
                Text('Spotify', style: AppText.title),
              ],
            ),
            const SizedBox(height: 16),
            if (_service.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _service.error!,
                  style: AppText.caption.copyWith(color: AppColor.redBright),
                ),
              ),
            if (_service.connecting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!_service.connected)
              FilledButton.icon(
                onPressed: _service.connect,
                style: FilledButton.styleFrom(
                  backgroundColor: _spotifyGreen,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.link),
                label: const Text('Verbinden met Spotify'),
              )
            else ...[
              _NowPlaying(service: _service),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: KSegmented<_Tab>(
                      options: const [
                        (
                          _Tab.playlists,
                          'Playlists',
                          Icons.library_music_outlined,
                        ),
                        (_Tab.search, 'Zoeken', Icons.search),
                        (_Tab.queue, 'Wachtrij', Icons.queue_music),
                      ],
                      selected: _tab,
                      onChanged: (v) {
                        setState(() => _tab = v);
                        if (v != _Tab.search) _load();
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Vernieuwen',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_listError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _listError!,
                    style: AppText.caption.copyWith(color: AppColor.redBright),
                  ),
                )
              else if (_tab == _Tab.search)
                ..._searchItems()
              else if (_showQueue)
                ..._queueItems()
              else if (_open case final open?)
                ..._openItems(open)
              else if ((_playlists?.isEmpty ?? false) && _liked == null)
                Text('Je hebt nog geen playlists.', style: AppText.caption)
              else
                ..._playlistItems(),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _queueItems() {
    final q = _queue;
    if (q == null) return const [];
    if (q.current == null && q.upNext.isEmpty) {
      return [Text('Je wachtrij is leeg.', style: AppText.caption)];
    }
    return [
      if (q.current != null) ...[
        Text('NU', style: AppText.overline),
        _TrackTile(track: q.current!, playing: true),
        const SizedBox(height: 8),
      ],
      if (q.upNext.isNotEmpty) Text('HIERNA', style: AppText.overline),
      for (final t in q.upNext) _TrackTile(track: t),
    ];
  }
}

/// Eén nummer in de wachtrij.
class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, this.playing = false});

  final SpotifyTrackResult track;
  final bool playing;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    leading: _Cover(url: track.imageUrl, icon: Icons.music_note),
    title: Text(
      track.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.bodyStrong.copyWith(color: playing ? _spotifyGreen : null),
    ),
    subtitle: Text(
      track.artists,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.caption,
    ),
  );
}

/// Kleine hoes (of een icoon als er geen is).
class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.icon});

  final String? url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null) {
      return SizedBox.square(dimension: 44, child: Icon(icon));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        u,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            SizedBox.square(dimension: 44, child: Icon(icon)),
      ),
    );
  }
}

/// Eén playlist: tik = openen (nummers bekijken), ▶ = afspelen, speld =
/// vastpinnen bovenaan.
class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.playlist,
    required this.onOpen,
    required this.onPlay,
    this.onTogglePin,
    this.pinned = false,
    this.openable = true,
    this.leading,
  });

  /// Nummers in te lezen (eigen of samenwerk-playlist)? Anders speelt een
  /// tik hem meteen af.
  final bool openable;

  final SpotifyPlaylistResult playlist;

  /// Tik op de regel: de nummers bekijken.
  final VoidCallback onOpen;
  final VoidCallback onPlay;
  final VoidCallback? onTogglePin;
  final bool pinned;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    // Spotify-lijsten kun je niet openen (Spotify blokkeert dat), wel
    // afspelen.
    onTap: openable ? onOpen : onPlay,
    leading: leading ?? _Cover(url: playlist.imageUrl, icon: Icons.queue_music),
    title: Text(
      playlist.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.bodyStrong,
    ),
    subtitle: Text(
      [
        if (playlist.owner.isNotEmpty) playlist.owner,
        if (!openable) 'tik om af te spelen',
        if (playlist.tracks > 0) '${playlist.tracks} nummers',
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.caption,
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onTogglePin != null)
          IconButton(
            tooltip: pinned ? 'Losmaken' : 'Vastpinnen',
            onPressed: onTogglePin,
            icon: Icon(
              pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 20,
              color: pinned ? _spotifyGreen : AppColor.inkFaint,
            ),
          ),
        IconButton(
          tooltip: 'Afspelen',
          icon: const Icon(Icons.play_circle_fill, color: _spotifyGreen),
          onPressed: onPlay,
        ),
      ],
    ),
  );
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.service});

  final SpotifyService service;

  @override
  Widget build(BuildContext context) {
    final track = service.player?.track;
    final paused = service.player?.isPaused ?? true;
    final cover = service.cover;
    return Column(
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                width: 64,
                height: 64,
                child: cover == null
                    ? Container(
                        color: AppColor.surfaceHigh,
                        child: const Icon(Icons.music_note),
                      )
                    : Image.memory(cover, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track?.name ?? 'Er speelt niets',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyStrong,
                  ),
                  if (track != null)
                    Text(
                      track.artist.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ProgressBar(service: service),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Shuffle',
              onPressed: service.toggleShuffle,
              icon: Icon(
                Icons.shuffle,
                color: service.shuffling ? _spotifyGreen : AppColor.inkFaint,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Vorige',
              iconSize: 34,
              onPressed: service.previous,
              icon: const Icon(Icons.skip_previous),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              tooltip: paused ? 'Afspelen' : 'Pauzeren',
              iconSize: 40,
              style: IconButton.styleFrom(
                backgroundColor: _spotifyGreen,
                foregroundColor: Colors.black,
              ),
              onPressed: service.togglePlay,
              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Volgende',
              iconSize: 34,
              onPressed: service.next,
              icon: const Icon(Icons.skip_next),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Herhalen',
              onPressed: service.toggleRepeat,
              icon: Icon(
                service.repeatMode == SpotifyRepeatMode.track
                    ? Icons.repeat_one
                    : Icons.repeat,
                color: service.repeatMode == SpotifyRepeatMode.off
                    ? AppColor.inkFaint
                    : _spotifyGreen,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Tijdbalk zoals in Spotify: verstreken tijd, slepen om te spoelen, en de
/// totale duur.
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.service});

  final SpotifyService service;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  /// Positie tijdens het slepen (ms); null = volg Spotify.
  double? _dragging;

  static String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.service.durationMs;
    if (duration <= 0) return const SizedBox(height: 8);
    final position = (_dragging ?? widget.service.positionMs.toDouble()).clamp(
      0.0,
      duration.toDouble(),
    );
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: position,
            max: duration.toDouble(),
            activeColor: Colors.white,
            inactiveColor: Colors.white.withValues(alpha: .2),
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              widget.service.seek(v.round());
              setState(() => _dragging = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(_fmt(position.round()), style: AppText.caption),
              const Spacer(),
              Text(_fmt(duration), style: AppText.caption),
            ],
          ),
        ),
      ],
    );
  }
}
