// video_player_page.dart: video's in de app zelf afspelen. Links van
// YouTube, Instagram, TikTok en Vimeo laden we via hun insluit-versie (alleen
// de video, zonder de hele site); eigen video's (privé-bucket) en losse
// mp4-links spelen in een eenvoudige HTML5-speler. Een knop rechtsboven opent
// de video alsnog in de app van het platform, mocht insluiten niet werken.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic_widgets.dart';

/// Insluitbare variant van een videolink, of null als die er niet is.
String? embedUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (host.contains('youtu.be') && segs.isNotEmpty) {
    return 'https://www.youtube.com/embed/${segs.first}?autoplay=1&playsinline=1';
  }
  if (host.contains('youtube.com')) {
    final id = uri.queryParameters['v'] ??
        (segs.length >= 2 && (segs.first == 'shorts' || segs.first == 'embed' || segs.first == 'live') ? segs[1] : null);
    if (id != null) return 'https://www.youtube.com/embed/$id?autoplay=1&playsinline=1';
  }
  if (host.contains('instagram.com') && segs.length >= 2 && ['p', 'reel', 'reels', 'tv'].contains(segs.first)) {
    return 'https://www.instagram.com/${segs.first == 'reels' ? 'reel' : segs.first}/${segs[1]}/embed';
  }
  if (host.contains('tiktok.com')) {
    final i = segs.indexOf('video');
    if (i >= 0 && i + 1 < segs.length) return 'https://www.tiktok.com/embed/v2/${segs[i + 1]}';
  }
  if (host.contains('vimeo.com') && segs.isNotEmpty && int.tryParse(segs.last) != null) {
    return 'https://player.vimeo.com/video/${segs.last}?autoplay=1';
  }
  return null;
}

/// Korte deellinks (vm.tiktok.com, instagr.am, fb.watch...) volgen tot de
/// echte video-link, zodat we de insluit-versie kunnen gebruiken.
Future<String> resolveShortLink(String url) async {
  if (embedUrl(url) != null) return url;
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  const shortHosts = ['vm.tiktok.com', 'vt.tiktok.com', 'instagr.am', 'fb.watch'];
  final isShort = shortHosts.any(host.contains) || (host.contains('tiktok.com') && url.contains('/t/'));
  if (!isShort) return url;
  final client = http.Client();
  try {
    var current = Uri.parse(url);
    for (var i = 0; i < 5; i++) {
      final req = http.Request('GET', current)
        ..followRedirects = false
        ..headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36';
      final res = await client.send(req).timeout(const Duration(seconds: 8));
      final location = res.headers['location'];
      if (!res.isRedirect || location == null) break;
      current = current.resolve(location);
      if (embedUrl(current.toString()) != null) break;
    }
    return current.toString();
  } catch (_) {
    return url;
  } finally {
    client.close();
  }
}

bool _isDirectFile(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  return ['.mp4', '.mov', '.webm', '.m4v', '.3gp'].any(path.endsWith);
}

/// Opent de video in de app (volledig scherm).
Future<void> playVideoInApp(BuildContext context, String url, {String title = 'Video'}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => VideoPlayerPage(url: url, title: title)),
    );

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.url, required this.title});
  final String url;
  final String title;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  WebViewController? _controller;
  String? _openUrl;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = KineticScope.read(context);
    var url = widget.url;
    if (url.startsWith(KineticStore.storageVideoPrefix)) {
      final signed = await store.signedVideoUrl(url);
      if (signed == null) {
        if (mounted) setState(() => _error = 'Video kon niet worden geladen. Controleer je verbinding.');
        return;
      }
      url = signed;
    }
    _openUrl = url;
    url = await resolveShortLink(url);
    if (!mounted) return;
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Doorsturen naar een app (tiktok://, intent://...) tegenhouden:
          // we willen de video hier in de app afspelen.
          onNavigationRequest: (req) {
            final scheme = Uri.tryParse(req.url)?.scheme ?? '';
            return scheme == 'http' || scheme == 'https' || scheme == 'about' || scheme == 'data'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            if (mounted && e.isForMainFrame == true) setState(() => _error = 'Video kon niet worden geladen.');
          },
        ),
      );
    final embed = embedUrl(url);
    if (embed != null) {
      await c.loadRequest(Uri.parse(embed));
    } else if (widget.url.startsWith(KineticStore.storageVideoPrefix) || _isDirectFile(url)) {
      // Eigen video of losse mp4: eenvoudige HTML5-speler.
      await c.loadHtmlString('''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;display:flex;align-items:center;justify-content:center}video{width:100%;max-height:100%}</style>
</head><body><video src="${const HtmlEscape(HtmlEscapeMode.attribute).convert(url)}" controls autoplay playsinline></video></body></html>''');
    } else {
      await c.loadRequest(Uri.parse(url));
    }
    if (mounted) setState(() => _controller = c);
  }

  Future<void> _openExternally() async {
    final u = Uri.tryParse(_openUrl ?? widget.url);
    if (u == null) return;
    final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showToast(context, 'Kon de video niet openen', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Openen in de app van het platform',
            onPressed: _openExternally,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: k.warning, size: 40),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center, style: context.t.body.copyWith(color: Colors.white)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _openExternally,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Extern openen'),
                      ),
                    ],
                  ),
                ),
              )
            : Stack(
                children: [
                  if (_controller != null) WebViewWidget(controller: _controller!),
                  if (_loading) const Center(child: CircularProgressIndicator()),
                ],
              ),
      ),
    );
  }
}
