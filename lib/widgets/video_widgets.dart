// video_widgets.dart: video's bij technieken en combinaties. Elke video is
// een uitklapbaar kopje met de eigen titel ("Gripping", "Uitvoering") of
// "Video 1", "Video 2"... Links (YouTube, Instagram, TikTok, Facebook,
// Vimeo, X...) openen in de bijbehorende app; eigen video's staan in de
// privé-bucket `technique-videos` en openen via een tijdelijke link.

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic_widgets.dart';
import 'video_player_page.dart';

/// Platform van een videolink, voor het icoon en de ondertitel.
(String, IconData) videoPlatform(String url) {
  if (url.startsWith(KineticStore.storageVideoPrefix)) return ('Eigen video', Icons.video_file_outlined);
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  bool has(String s) => host.contains(s);
  if (has('youtube') || has('youtu.be')) return ('YouTube', Icons.smart_display_outlined);
  if (has('instagram')) return ('Instagram', Icons.camera_alt_outlined);
  if (has('tiktok')) return ('TikTok', Icons.music_note_outlined);
  if (has('facebook') || has('fb.watch')) return ('Facebook', Icons.facebook);
  if (has('vimeo')) return ('Vimeo', Icons.play_circle_outline);
  if (has('twitter') || has('x.com')) return ('X', Icons.alternate_email);
  if (has('drive.google')) return ('Google Drive', Icons.add_to_drive);
  if (has('photos.app.goo.gl') || has('photos.google')) return ("Google Foto's", Icons.photo_library_outlined);
  return (host.isEmpty ? 'Link' : host.replaceFirst('www.', ''), Icons.link);
}

/// Video openen: links in de app van het platform, eigen video's via een
/// tijdelijke beveiligde link.
Future<void> openVideo(BuildContext context, String url) async {
  final store = KineticScope.read(context);
  var target = url;
  if (url.startsWith(KineticStore.storageVideoPrefix)) {
    final signed = await store.signedVideoUrl(url);
    if (signed == null) {
      if (context.mounted) showToast(context, 'Video kon niet worden geladen', error: true);
      return;
    }
    target = signed;
  }
  final uri = Uri.tryParse(target);
  final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showToast(context, 'Kon de video niet openen', error: true);
}

/// Lijst met video's als uitklapbare kopjes. Met [onRemove] zijn titel
/// wijzigen en verwijderen mogelijk; zonder alleen openen.
class VideoList extends StatelessWidget {
  const VideoList({super.key, required this.urls, this.onRemove, this.dense = false});
  final List<String> urls;
  final Future<bool> Function(String url)? onRemove;
  final bool dense;

  Future<void> _rename(BuildContext context, String url, String current) async {
    final store = KineticScope.read(context);
    final ctrl = TextEditingController(text: store.videoLabels[url] ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Titel van de video'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: current),
          onSubmitted: (s) => Navigator.pop(ctx, s),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Opslaan')),
        ],
      ),
    );
    ctrl.dispose();
    if (v != null) await store.setVideoLabel(url, v);
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < urls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: k.well,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.md)),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: PageStorageKey('video-${urls[i]}'),
                  dense: dense,
                  leading: Icon(videoPlatform(urls[i]).$2, color: k.accent),
                  title: Text(store.videoTitle(urls[i], i), style: context.t.bodyStrong),
                  subtitle: Text(videoPlatform(urls[i]).$1, style: context.t.caption),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => playVideoInApp(context, urls[i], title: store.videoTitle(urls[i], i)),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Afspelen'),
                          ),
                        ),
                        if (onRemove != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Titel wijzigen',
                            onPressed: () => _rename(context, urls[i], store.videoTitle(urls[i], i)),
                            icon: Icon(Icons.edit_outlined, color: k.textSecondary),
                          ),
                          IconButton(
                            tooltip: 'Video verwijderen',
                            onPressed: () async {
                              final ok = await onRemove!(urls[i]);
                              if (!ok && context.mounted) showToast(context, 'Verwijderen mislukt', error: true);
                            },
                            icon: Icon(Icons.delete_outline, color: k.dangerInk),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Video toevoegen: een link plakken of een video uit je galerij uploaden.
/// [onAdd] krijgt de link (of interne opslaglink) en de titel.
Future<void> showAddVideoSheet(BuildContext context, {required Future<bool> Function(String url, String label) onAdd}) =>
    showKineticSheet<void>(context, builder: (_) => _AddVideoSheet(onAdd: onAdd));

class _AddVideoSheet extends StatefulWidget {
  const _AddVideoSheet({required this.onAdd});
  final Future<bool> Function(String url, String label) onAdd;

  @override
  State<_AddVideoSheet> createState() => _AddVideoSheetState();
}

class _AddVideoSheetState extends State<_AddVideoSheet> {
  final _title = TextEditingController();
  final _link = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _addLink() async {
    var url = _link.text.trim();
    if (url.isEmpty) return setState(() => _error = 'Plak een link naar de video.');
    if (!url.startsWith('http')) url = 'https://$url';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return setState(() => _error = 'Dit lijkt geen geldige link.');
    await _finish(url);
  }

  Future<void> _upload() async {
    final store = KineticScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (file == null) {
        setState(() => _busy = false);
        return;
      }
      final size = await file.length();
      if (size > 300 * 1024 * 1024) {
        setState(() {
          _busy = false;
          _error = 'Deze video is groter dan 300 MB. Kies een kortere video.';
        });
        return;
      }
      final ext = file.name.contains('.') ? file.name.split('.').last : 'mp4';
      final url = await store.uploadOwnVideo(await file.readAsBytes(), ext);
      if (url == null) {
        setState(() {
          _busy = false;
          _error = 'Uploaden mislukt. Staat de opslag (technique-videos) al aan in Supabase?';
        });
        return;
      }
      await _finish(url);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Kon de galerij niet openen.';
        });
      }
    }
  }

  Future<void> _finish(String url) async {
    setState(() => _busy = true);
    final ok = await widget.onAdd(url, _title.text.trim());
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Opslaan mislukt. Controleer je verbinding.';
      });
      return;
    }
    Navigator.of(context).pop();
    showToast(context, 'Video toegevoegd');
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Video toevoegen', style: context.t.headline),
        const SizedBox(height: 4),
        Text('Een link van YouTube, Instagram, TikTok, Facebook... of een eigen video.', style: context.t.caption),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Titel (optioneel)', hintText: 'Gripping, Uitvoering...'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _link,
          keyboardType: TextInputType.url,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Link', hintText: 'https://youtu.be/...', prefixIcon: Icon(Icons.link)),
        ),
        const SizedBox(height: 12),
        BigButton(label: 'Link toevoegen', icon: Icons.add_link, height: 52, onPressed: _busy ? null : _addLink),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Divider(color: k.border)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('of', style: context.t.caption)),
            Expanded(child: Divider(color: k.border)),
          ],
        ),
        const SizedBox(height: 12),
        BigButton(
          label: _busy ? 'Bezig met uploaden…' : 'Eigen video uit galerij',
          icon: Icons.video_library_outlined,
          style: KButtonStyle.secondary,
          height: 52,
          onPressed: _busy ? null : _upload,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: context.t.caption.copyWith(color: k.danger)),
        ],
      ],
    );
  }
}
