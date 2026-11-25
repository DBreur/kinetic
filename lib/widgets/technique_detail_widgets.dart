// technique_detail_widgets.dart: notities, beoordelingen (sterren + wat
// ging goed / wat ging minder) en video's bij een techniek. Gebruikt in de
// techniek-sheet (vault), tijdens trainingen en in de sessiedetails.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../models/technique.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic_widgets.dart';
import 'video_widgets.dart';

/// Kop van een sectie met optionele actieknop rechts.
class DetailHeader extends StatelessWidget {
  const DetailHeader({super.key, required this.icon, required this.title, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Row(
      children: [
        Icon(icon, size: 18, color: k.accent),
        const SizedBox(width: 8),
        Expanded(child: Text(title.toUpperCase(), style: context.t.label.copyWith(color: k.text))),
        if (action != null)
          TextButton.icon(onPressed: onAction, icon: const Icon(Icons.add, size: 18), label: Text(action!)),
      ],
    );
  }
}

/// Alles over één eigen techniek: notities, beoordelingen en video's.
/// [compact] laat de beoordelingshistorie weg (tijdens een training).
class TechniqueDetails extends StatelessWidget {
  const TechniqueDetails({super.key, required this.techniqueId, this.compact = false});
  final String techniqueId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final t = store.techniques.where((x) => x.id == techniqueId).firstOrNull;
    if (t == null) return const SizedBox.shrink();
    final reviews = t.reviews;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailHeader(
          icon: Icons.ondemand_video,
          title: "Video's",
          action: 'Video',
          onAction: () => showAddVideoSheet(context, onAdd: (url, label) => store.addTechniqueVideo(t.id, url, label: label)),
        ),
        if (t.videoUrls.isEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Nog geen video\'s.', style: context.t.caption))
        else
          VideoList(urls: t.videoUrls, onRemove: (url) => store.removeTechniqueVideo(t.id, url)),
        if (!compact) ...[
          const SizedBox(height: 12),
          DetailHeader(icon: Icons.sticky_note_2_outlined, title: 'Notities', action: 'Bewerken', onAction: () => editTechniqueNotes(context, t)),
          KWell(
            onTap: () => editTechniqueNotes(context, t),
            child: Text(
              t.description.trim().isEmpty ? 'Tik om notities toe te voegen (setup, grips, details...).' : t.description.trim(),
              style: context.t.body.copyWith(color: t.description.trim().isEmpty ? k.textMuted : k.text),
            ),
          ),
          const SizedBox(height: 12),
        ],
        DetailHeader(
          icon: Icons.star_outline,
          title: 'Beoordeling',
          action: 'Beoordelen',
          onAction: () => showReviewSheet(context, t),
        ),
        if (reviews.isEmpty)
          Text('Nog geen beoordelingen.', style: context.t.caption)
        else
          for (final r in compact ? reviews.take(1) : reviews.take(10))
            Padding(padding: const EdgeInsets.only(bottom: 8), child: ReviewCard(technique: t, review: r)),
      ],
    );
  }
}

Future<void> editTechniqueNotes(BuildContext context, Technique t) async {
  final store = KineticScope.read(context);
  final ctrl = TextEditingController(text: t.description);
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Notities • ${t.name}'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Setup, grips, details, valkuilen...'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Opslaan')),
      ],
    ),
  );
  ctrl.dispose();
  if (v == null) return;
  final ok = await store.setTechniqueNotes(t.id, v);
  if (!ok && context.mounted) showToast(context, 'Opslaan mislukt', error: true);
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.technique, required this.review});
  final Technique technique;
  final TechniqueUpdate review;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final r = review;
    Widget line(IconData icon, Color color, String label, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$label: ', style: context.t.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
                TextSpan(text: text, style: context.t.caption.copyWith(color: k.text)),
              ]),
            ),
          ),
        ],
      ),
    );
    return KWell(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (r.rating > 0) StarRow(value: r.rating, size: 16),
              if (r.rating > 0) const SizedBox(width: 8),
              Expanded(child: Text(shortDate(r.at), style: context.t.caption)),
              IconButton(
                tooltip: 'Beoordeling verwijderen',
                visualDensity: VisualDensity.compact,
                onPressed: () => KineticScope.read(context).deleteTechniqueReview(technique.id, r),
                icon: Icon(Icons.delete_outline, size: 18, color: k.textMuted),
              ),
            ],
          ),
          if (r.wentWell.trim().isNotEmpty) line(Icons.thumb_up_alt_outlined, k.successInk, 'Ging goed', r.wentWell.trim()),
          if (r.toImprove.trim().isNotEmpty) line(Icons.trending_up, k.warningInk, 'Ging minder', r.toImprove.trim()),
          if (r.note.trim().isNotEmpty) line(Icons.notes, k.textSecondary, 'Notitie', r.note.trim()),
        ],
      ),
    );
  }
}

/// 1-5 sterren; met [onChanged] aantikbaar.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.value, this.onChanged, this.size = 32});
  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          onChanged == null
              ? Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: i <= value ? k.warning : k.textMuted)
              : Semantics(
                  button: true,
                  label: '$i ${i == 1 ? 'ster' : 'sterren'}',
                  selected: i == value,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onChanged!(i == value ? 0 : i);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: i <= value ? k.warning : k.textMuted),
                    ),
                  ),
                ),
      ],
    );
  }
}

/// Beoordeling toevoegen: sterren, wat ging goed, wat ging minder, notitie.
Future<void> showReviewSheet(BuildContext context, Technique t) =>
    showKineticSheet<void>(context, builder: (_) => _ReviewSheet(technique: t));

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.technique});
  final Technique technique;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 0;
  final _good = TextEditingController();
  final _less = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_good, _less, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final store = KineticScope.read(context);
    final review = TechniqueUpdate(
      at: store.now(),
      rating: _rating,
      wentWell: _good.text.trim(),
      toImprove: _less.text.trim(),
      note: _note.text.trim(),
    );
    if (!review.isReview) return;
    setState(() => _saving = true);
    final ok = await store.addTechniqueReview(widget.technique.id, review);
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      showToast(context, 'Opslaan mislukt', error: true);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    InputDecoration deco(String label, IconData icon, Color color) =>
        InputDecoration(labelText: label, prefixIcon: Icon(icon, color: color));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Beoordelen', style: context.t.headline),
        Text(widget.technique.name, style: context.t.caption),
        const SizedBox(height: 16),
        Center(child: StarRow(value: _rating, onChanged: (v) => setState(() => _rating = v), size: 40)),
        const SizedBox(height: 16),
        TextField(
          controller: _good,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: deco('Wat ging goed?', Icons.thumb_up_alt_outlined, k.successInk),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _less,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: deco('Wat ging minder?', Icons.trending_up, k.warningInk),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: deco('Notitie (optioneel)', Icons.notes, k.textSecondary),
        ),
        const SizedBox(height: 20),
        BigButton(label: _saving ? 'Opslaan…' : 'Beoordeling opslaan', icon: Icons.check, height: 56, onPressed: _saving ? null : _save),
      ],
    );
  }
}
