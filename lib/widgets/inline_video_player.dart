// inline_video_player.dart — speelt een technieklink direct in de app af,
// i.p.v. een "Bekijk video"-knop die naar een externe browser/app springt.
//
// Werkt voor elke bron via een ingebedde webweergave: YouTube- en
// Instagram-links worden omgezet naar hun embed-URL; TikTok-links blijven
// bewust de gewone kijkpagina (zie videoEmbedUri) en alles anders (Google
// Drive-previews, directe videobestanden) wordt gewoon geladen zoals
// meegegeven. Na het laden zoekt een stukje JavaScript het <video>-element
// van de pagina op, verbergt de eigen interface van het platform (vergroot
// de video tot boven alles) en koppelt er onze eigen, minimale bediening aan
// — pauzeren, doorspoelen en geluid aan/uit — zodat je nooit per ongeluk op
// een like- of deelknop van het platform zelf kan drukken.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/video_labels.dart';
import '../theme/kinetic_theme.dart';
import 'video_link_row.dart' show editVideoLabel;

/// Zet bekende "kijkpagina"-links om naar hun ingebedde speler-variant, zodat
/// je een schone player krijgt i.p.v. de volledige website — YouTube en
/// Instagram worden herkend; al het andere wordt ongewijzigd teruggegeven.
///
/// TikTok is hier bewust een uitzondering: hun publieke `/embed/v2/`-speler
/// (bedoeld om op andere websites te zetten) levert merkbaar lagere
/// videokwaliteit dan de gewone kijkpagina — dezelfde pagina die je ziet als
/// je een TikTok-link in een mobiele browser opent. Daarom laten we een
/// TikTok-link zoals hij is en verbergt `_controlScript` (via het
/// wegwerken van alles behalve de video zelf) de eigen interface van díe
/// pagina in plaats van over te schakelen naar de kwalitatief mindere embed.
Uri videoEmbedUri(Uri uri) {
  final host = uri.host.replaceFirst('www.', '');
  if (host == 'youtube.com' && uri.queryParameters['v'] != null) {
    return Uri.parse(
      'https://www.youtube.com/embed/${uri.queryParameters['v']}',
    );
  }
  if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
    return Uri.parse('https://www.youtube.com/embed/${uri.pathSegments.first}');
  }
  if (host == 'instagram.com') {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final typeIndex = segments.indexWhere(
      (s) => s == 'p' || s == 'reel' || s == 'reels',
    );
    if (typeIndex != -1 && typeIndex + 1 < segments.length) {
      final type = segments[typeIndex] == 'reels' ? 'reel' : segments[typeIndex];
      final shortcode = segments[typeIndex + 1];
      return Uri.parse('https://www.instagram.com/$type/$shortcode/embed/');
    }
  }
  return uri;
}

/// Zoekt het `<video>`-element van de geladen pagina, verbergt de rest van
/// de platform-interface (door de video het hele beeld te laten vullen, met
/// de hoogste z-index) en stuurt de status (afgespeeld/gepauzeerd, geluid,
/// tijd, afmetingen) door naar Flutter via het `UchivoVideo`-kanaal.
const _controlScript = r'''
(function() {
  if (window.__uchivoSetupDone) return;
  window.__uchivoSetupDone = true;
  var tries = 0;

  // Zonder een correcte viewport-tag rendert een WebView een pagina soms op
  // een brede, "desktop"-achtige virtuele breedte en schaalt die daarna
  // omlaag naar het echte, smalle schermformaat — dat geeft blijvend wazig
  // beeld voor de hele pagina, dus ook voor de video zelf. Forceer 1-op-1
  // renderen op de echte schermbreedte, ongeacht wat de pagina zelf al had.
  var viewport = document.querySelector('meta[name="viewport"]');
  if (!viewport) {
    viewport = document.createElement('meta');
    viewport.setAttribute('name', 'viewport');
    document.head.appendChild(viewport);
  }
  viewport.setAttribute(
    'content',
    'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no'
  );

  function post() {
    var v = window.__uchivoVideo;
    if (!v || !window.UchivoVideo) return;
    window.UchivoVideo.postMessage(JSON.stringify({
      paused: v.paused,
      muted: v.muted,
      currentTime: v.currentTime || 0,
      duration: v.duration || 0,
      videoWidth: v.videoWidth || 0,
      videoHeight: v.videoHeight || 0,
      playbackRate: v.playbackRate || 1,
      ended: v.ended,
    }));
  }

  function setup() {
    var video = document.querySelector('video');
    if (!video) {
      tries += 1;
      if (tries < 25) setTimeout(setup, 300);
      return;
    }
    window.__uchivoVideo = video;
    video.removeAttribute('controls');
    video.style.position = 'fixed';
    video.style.top = '0';
    video.style.left = '0';
    video.style.width = '100%';
    video.style.height = '100%';
    video.style.objectFit = 'contain';
    video.style.zIndex = '2147483647';
    video.style.background = '#000';
    document.documentElement.style.background = '#000';
    document.body.style.margin = '0';
    document.body.style.background = '#000';
    ['play', 'pause', 'timeupdate', 'volumechange', 'loadedmetadata', 'ratechange', 'ended'].forEach(
      function(evt) { video.addEventListener(evt, post); }
    );
    post();

    // Platformen tonen vaak nog andere inhoud rond de video (cookiebanner,
    // "open in app"-melding, bijschrift/knoppenbalk) — niet per se als
    // overlay, vaak gewoon als normale broer-elementen ergens in de pagina.
    // In plaats van te gokken naar overlay-stijlen: verberg alles wat niet
    // op het rechtstreekse pad van <body> naar de video zelf ligt.
    var isolateVideo = function() {
      var node = video;
      while (node && node.parentElement) {
        var parent = node.parentElement;
        for (var i = 0; i < parent.children.length; i++) {
          var sibling = parent.children[i];
          if (sibling !== node) sibling.style.setProperty('display', 'none', 'important');
        }
        if (parent === document.body) break;
        node = parent;
      }
    };
    isolateVideo();
    setTimeout(isolateVideo, 500);
    setTimeout(isolateVideo, 1500);
    try {
      new MutationObserver(isolateVideo).observe(document.body, {
        childList: true,
        subtree: true,
      });
    } catch (e) {}
  }
  setup();
})();
''';

/// Toont een lijst techniekvideo's, elk achter een eigen titelbalk
/// ("Video 1", "Video 2", ...) die je open- of dichtklapt door erop te
/// tikken — ook bij precies één video, voor een consistente bediening. Bij
/// één video staat die balk meteen opengeklapt; bij meerdere beginnen ze
/// dicht, zodat het overzicht blijft kloppen.
class CollapsibleVideoList extends StatefulWidget {
  const CollapsibleVideoList({super.key, required this.urls});

  final List<String> urls;

  @override
  State<CollapsibleVideoList> createState() => _CollapsibleVideoListState();
}

class _CollapsibleVideoListState extends State<CollapsibleVideoList> {
  late Set<int> _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.urls.length <= 1 ? {0} : {};
  }

  @override
  void didUpdateWidget(CollapsibleVideoList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.length != widget.urls.length) {
      _expanded = widget.urls.length <= 1 ? {0} : {};
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i < widget.urls.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == widget.urls.length - 1 ? 0 : 8,
            ),
            child: _CollapsibleVideoTile(
              index: i,
              url: widget.urls[i],
              expanded: _expanded.contains(i),
              onToggle: () => setState(() {
                if (!_expanded.remove(i)) _expanded.add(i);
              }),
            ),
          ),
      ],
    );
  }
}

class _CollapsibleVideoTile extends StatelessWidget {
  const _CollapsibleVideoTile({
    required this.index,
    required this.url,
    required this.expanded,
    required this.onToggle,
  });

  final int index;
  final String url;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColor.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.play_circle_outline,
                  size: 18,
                  color: AppColor.inkMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<Map<String, String>>(
                    valueListenable: VideoLabels.labels,
                    builder: (context, labels, _) => Text(
                      VideoLabels.titleFor(url, index),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => editVideoLabel(context, url),
                  borderRadius: BorderRadius.circular(99),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 15,
                      color: AppColor.inkFaint,
                    ),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppColor.inkFaint,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          InlineVideoPlayer(url: url),
        ],
      ],
    );
  }
}

class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({super.key, required this.url});

  final String url;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;
  bool _playerReady = false;
  bool _playing = false;
  bool _muted = true;
  bool _ended = false;
  double _playbackRate = 1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _aspectRatio = 16 / 9;
  late Uri _uri;

  /// Wordt maar één keer gezet, bij de eerste bruikbare meting. Sommige
  /// bronnen schakelen tijdens het afspelen van videokwaliteit (adaptieve
  /// streaming), wat de gerapporteerde afmetingen tussentijds kan laten
  /// veranderen — bleef de beeldverhouding daarop meebewegen, dan moest de
  /// WebView continu opnieuw uitgemeten worden, wat het beeld blijvend
  /// wazig maakte in plaats van alleen even tijdens het schakelen zelf.
  bool _aspectRatioSet = false;

  /// Wordt pas waar zodra de pagina op een herkende embed-URL staat — een
  /// kortlink (bv. vm.tiktok.com) laadt eerst de kortlink zelf, en pas
  /// nadat de WebView de doorverwijzing zelf heeft gevolgd controleren we
  /// of de uiteindelijke URL alsnog naar een embed kan worden omgezet.
  bool _resolvedEmbed = false;

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  void _setUp() {
    final uri = Uri.tryParse(widget.url.trim());
    if (uri == null || !uri.hasScheme) {
      _error = 'Ongeldige videolink.';
      return;
    }
    _uri = uri;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('UchivoVideo', onMessageReceived: _onVideoMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Deelpagina's proberen vaak eerst de native app te openen via een
          // eigen url-schema (bv. TikTok's snssdk1233://) voor ze terugvallen
          // op de gewone webpagina. Zo'n schema is niet navigeerbaar in een
          // WebView — negeren voorkomt een valse foutmelding die de speler
          // zou blokkeren nog vóór de echte pagina klaar is met laden.
          onNavigationRequest: (request) {
            final scheme = Uri.tryParse(request.url)?.scheme;
            if (scheme != 'http' && scheme != 'https') {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) async {
            if (!_resolvedEmbed) {
              final landed = Uri.tryParse(url);
              final embed = landed == null ? null : videoEmbedUri(landed);
              if (embed != null && embed.toString() != url) {
                _resolvedEmbed = true;
                try {
                  await _controller!.loadRequest(embed);
                } catch (_) {}
                return;
              }
              _resolvedEmbed = true;
            }
            // YouTube's speler is bestand tegen directe DOM-manipulatie
            // (het <video>-element dat we vinden reageert niet betrouwbaar
            // op play()/pause() vanuit geïnjecteerde code) — daar laten we
            // de eigen, al minimale bediening van YouTube zelf gewoon staan
            // in plaats van een kapotte eigen bedieningsbalk te tonen.
            final host = Uri.tryParse(url)?.host ?? '';
            final isYouTube =
                host.contains('youtube.com') || host.contains('youtube-nocookie.com');
            if (!isYouTube) {
              try {
                await _controller!.runJavaScript(_controlScript);
              } catch (_) {
                // Geen blokkerende fout — de pagina blijft zichtbaar, alleen
                // zonder onze eigen bediening.
              }
            }
            if (mounted) {
              Future.delayed(Duration(seconds: isYouTube ? 1 : 6), () {
                if (mounted) setState(() => _loading = false);
              });
            }
          },
          onWebResourceError: (error) {
            // Alleen de hoofdpagina telt — een losse mislukte deelbron (een
            // trackingscript, een lettertype) is heel normaal en mag de
            // speler niet blokkeren. Een mislukte poging tot een eigen
            // app-schema (zie onNavigationRequest) is geen echte webfout.
            if (error.isForMainFrame == false) return;
            final scheme = Uri.tryParse(error.url ?? '')?.scheme;
            if (scheme != null && scheme != 'http' && scheme != 'https') {
              return;
            }
            if (mounted) {
              setState(() {
                _loading = false;
                _error = 'Video kon niet worden geladen.';
              });
            }
          },
        ),
      );
    _loadFresh(uri);
  }

  /// Wist eerst de cache, dan pas laden — zonder dit kan een eerder bezochte
  /// pagina (bv. een oudere, minder scherpe versie van dezelfde TikTok-
  /// pagina) uit de cache terugkomen i.p.v. vers geladen te worden. Elke
  /// keer dat je een video openklapt verdient dezelfde kwaliteit als de
  /// eerste keer.
  Future<void> _loadFresh(Uri uri) async {
    try {
      await _controller!.clearCache();
    } catch (_) {
      // Geen blokkerende fout — dan laadt de pagina gewoon zoals hij is.
    }
    try {
      await _controller!.loadRequest(videoEmbedUri(uri));
    } catch (_) {}
  }

  void _onVideoMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final width = (data['videoWidth'] as num?)?.toDouble() ?? 0;
      final height = (data['videoHeight'] as num?)?.toDouble() ?? 0;
      final duration = (data['duration'] as num?)?.toDouble() ?? 0;
      final current = (data['currentTime'] as num?)?.toDouble() ?? 0;
      final rate = (data['playbackRate'] as num?)?.toDouble() ?? 1;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _playerReady = true;
        _playing = data['paused'] == false;
        _muted = data['muted'] == true;
        _ended = data['ended'] == true;
        _playbackRate = rate;
        _duration = Duration(milliseconds: (duration * 1000).round());
        _position = Duration(milliseconds: (current * 1000).round());
        if (!_aspectRatioSet && width > 0 && height > 0) {
          _aspectRatio = width / height;
          _aspectRatioSet = true;
        }
      });
    } catch (_) {
      // Onverwacht berichtformaat — negeren, de video blijft gewoon spelen.
    }
  }

  void _run(String js) => _controller?.runJavaScript(js);

  void _togglePlay() {
    if (_playing) {
      _run('window.__uchivoVideo && window.__uchivoVideo.pause();');
      return;
    }
    if (_ended) {
      // Sommige platformen (zoals TikTok) wisselen bij het einde van een
      // video naar een lagere-kwaliteit "loop"-versie — gewoon opnieuw
      // play() aanroepen hervat dan die mindere kwaliteit. Alleen een
      // volledig verse laadbeurt (hetzelfde als inklappen en weer
      // openklappen) geeft de video weer in volle kwaliteit.
      setState(() {
        _playerReady = false;
        _loading = true;
        _resolvedEmbed = false;
        _aspectRatioSet = false;
        _ended = false;
      });
      _loadFresh(_uri);
      return;
    }
    // Een vanuit Flutter geïnjecteerde play()-aanroep telt voor de browser
    // niet als een echte gebruikersactie, dus een autoplay-beleid kan
    // afspelen met geluid stilzwijgend blokkeren (bv. YouTube). Gedempt
    // starten werkt wél altijd — geluid aanzetten kan daarna gewoon, dat
    // mag zodra er al wordt afgespeeld.
    _run(
      'if (window.__uchivoVideo) { '
      'window.__uchivoVideo.muted = true; '
      'window.__uchivoVideo.play(); }',
    );
  }

  void _toggleMute() {
    _run(
      'if (window.__uchivoVideo) { '
      'window.__uchivoVideo.muted = !window.__uchivoVideo.muted; }',
    );
  }

  void _toggleSpeed() {
    final next = _playbackRate == 1 ? 0.5 : 1;
    _run(
      'if (window.__uchivoVideo) { window.__uchivoVideo.playbackRate = $next; }',
    );
  }

  void _seekTo(Duration position) {
    final seconds = position.inMilliseconds / 1000;
    _run(
      'if (window.__uchivoVideo) { window.__uchivoVideo.currentTime = $seconds; }',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColor.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18, color: AppColor.inkFaint),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!, style: AppText.caption)),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            WebViewWidget(controller: _controller!),
            if (_loading)
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_playerReady)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _VideoControlBar(
                  playing: _playing,
                  muted: _muted,
                  playbackRate: _playbackRate,
                  position: _position,
                  duration: _duration,
                  onTogglePlay: _togglePlay,
                  onToggleMute: _toggleMute,
                  onToggleSpeed: _toggleSpeed,
                  onSeek: _seekTo,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Minimale bediening bovenop de video — pauzeren, doorspoelen, geluid
/// aan/uit. Geen andere platform-interface (liken, delen, reacties).
class _VideoControlBar extends StatefulWidget {
  const _VideoControlBar({
    required this.playing,
    required this.muted,
    required this.playbackRate,
    required this.position,
    required this.duration,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onToggleSpeed,
    required this.onSeek,
  });

  final bool playing;
  final bool muted;
  final double playbackRate;
  final Duration position;
  final Duration duration;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeed;
  final ValueChanged<Duration> onSeek;

  @override
  State<_VideoControlBar> createState() => _VideoControlBarState();
}

class _VideoControlBarState extends State<_VideoControlBar> {
  double? _dragValue;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds.toDouble();
    final hasDuration = totalMs > 0;
    final maxMs = hasDuration ? totalMs : 1.0;
    final currentMs = (_dragValue ?? widget.position.inMilliseconds.toDouble())
        .clamp(0, maxMs)
        .toDouble();

    return Container(
      padding: const EdgeInsets.only(left: 4, right: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              widget.playing ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: widget.onTogglePlay,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: currentMs,
                min: 0,
                max: maxMs,
                activeColor: Colors.white,
                inactiveColor: Colors.white30,
                onChanged: hasDuration
                    ? (v) => setState(() => _dragValue = v)
                    : null,
                onChangeEnd: hasDuration
                    ? (v) {
                        widget.onSeek(Duration(milliseconds: v.round()));
                        setState(() => _dragValue = null);
                      }
                    : null,
              ),
            ),
          ),
          Text(
            _fmt(widget.duration),
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: widget.onToggleSpeed,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              alignment: Alignment.center,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              child: Text(
                widget.playbackRate == 1 ? '1×' : '0,5×',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              widget.muted ? Icons.volume_off : Icons.volume_up,
              color: Colors.white,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: widget.onToggleMute,
          ),
        ],
      ),
    );
  }
}
