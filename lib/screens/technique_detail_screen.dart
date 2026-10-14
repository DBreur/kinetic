// technique_detail_screen.dart — een techniek bekijken
//
// Alleen-lezen: naam, categorie/transitie, beschrijving, video's die direct
// in de app afspelen, en de tijdlijn van updates (eigen updates + keren dat
// de techniek in een training is behandeld). Een update toevoegen (hoe ging
// het) kan direct hier — dat is loggen, geen structurele wijziging. Naam,
// categorie, transitie, beschrijving, video's en verwijderen gaan via
// "Aanpassen" rechtsboven, naar technique_edit_screen.dart.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../models/technique.dart';
import '../repositories/technique_repository.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/block_widgets.dart' show StarRow, NoteField;
import '../widgets/ground_position_tags.dart';
import '../widgets/inline_video_player.dart';
import 'technique_edit_screen.dart';

/// Eén keer dat deze techniek voorkwam — hetzij een losse update, hetzij
/// behandeld tijdens een training (alleen-lezen, want dat hoort bij de
/// sessie zelf).
class TechniqueOccurrence {
  final DateTime date;
  final int rating;
  final String note;
  final bool fromSession;

  /// Index in de eigen updates-lijst — alleen gezet voor updates die de
  /// gebruiker zelf kan verwijderen (niet voor sessie-historie).
  final int? manualIndex;

  const TechniqueOccurrence({
    required this.date,
    required this.rating,
    required this.note,
    this.fromSession = false,
    this.manualIndex,
  });
}

class TechniqueDetailScreen extends StatefulWidget {
  const TechniqueDetailScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.technique,
    this.sessionOccurrences = const [],
  });

  final TechniqueRepository repository;
  final String userId;
  final Technique technique;
  final List<TechniqueOccurrence> sessionOccurrences;

  @override
  State<TechniqueDetailScreen> createState() => _TechniqueDetailScreenState();
}

class _TechniqueDetailScreenState extends State<TechniqueDetailScreen> {
  late Technique _technique;
  bool _changed = false;
  bool _adding = false;
  bool _busy = false;
  late final TextEditingController _goalController;
  Timer? _goalDebounce;

  @override
  void initState() {
    super.initState();
    _technique = widget.technique;
    _goalController = TextEditingController(text: _technique.learningGoal);
  }

  @override
  void dispose() {
    _goalDebounce?.cancel();
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _updateLearning(Technique next) async {
    final previous = _technique;
    setState(() {
      _technique = next;
      _changed = true;
    });
    try {
      final saved = await widget.repository.updateContent(next);
      if (mounted) setState(() => _technique = saved);
    } catch (_) {
      if (mounted) setState(() => _technique = previous);
    }
  }

  Future<void> _setLearningStatus(LearningStatus status) async {
    if (status == LearningStatus.planned) {
      final date = await _pickDate(_technique.plannedFor);
      if (date == null) return;
      await _updateLearning(
        _technique.copyWith(
          learningStatus: LearningStatus.planned,
          plannedFor: date,
        ),
      );
      return;
    }
    await _updateLearning(_technique.copyWith(learningStatus: status));
  }

  Future<DateTime?> _pickDate(DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
  }

  Future<void> _pickPlannedDate() async {
    final date = await _pickDate(_technique.plannedFor);
    if (date == null) return;
    await _updateLearning(_technique.copyWith(plannedFor: date));
  }

  void _onGoalChanged(String value) {
    _goalDebounce?.cancel();
    _goalDebounce = Timer(const Duration(milliseconds: 500), () {
      _updateLearning(_technique.copyWith(learningGoal: value));
    });
  }

  Future<void> _maybeOfferMastered() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text('Markeren als beheerst?', style: AppText.cardTitle),
        content: Text(
          'Je hebt deze techniek net hoog beoordeeld. Wil je hem markeren als beheerst?',
          style: AppText.body.copyWith(color: AppColor.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Niet nu'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Markeer als beheerst'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _updateLearning(
        _technique.copyWith(learningStatus: LearningStatus.mastered),
      );
    }
  }

  Future<void> _toggleFavorite() async {
    final next = _technique.copyWith(favorite: !_technique.favorite);
    final previous = _technique;
    setState(() {
      _technique = next;
      _changed = true;
    });
    try {
      await widget.repository.updateContent(next);
    } catch (_) {
      if (mounted) setState(() => _technique = previous);
    }
  }

  Future<void> _addUpdate(int rating, String note) async {
    final next = _technique.copyWith(
      updates: [
        ..._technique.updates,
        TechniqueUpdate(at: DateTime.now(), rating: rating, note: note),
      ],
    );
    setState(() {
      _adding = false;
      _busy = true;
    });
    try {
      final saved = await widget.repository.updateContent(next);
      if (mounted) {
        setState(() {
          _technique = saved;
          _busy = false;
          _changed = true;
        });
        if (rating >= 4 && saved.learningStatus != LearningStatus.mastered) {
          await _maybeOfferMastered();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opslaan is niet gelukt. Probeer opnieuw.'),
          ),
        );
      }
    }
  }

  Future<void> _removeUpdate(int i) async {
    final updates = List.of(_technique.updates)..removeAt(i);
    final next = _technique.copyWith(updates: updates);
    final previous = _technique;
    setState(() {
      _technique = next;
      _busy = true;
    });
    try {
      final saved = await widget.repository.updateContent(next);
      if (mounted) {
        setState(() {
          _technique = saved;
          _busy = false;
          _changed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _technique = previous;
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verwijderen is niet gelukt. Probeer opnieuw.'),
          ),
        );
      }
    }
  }

  Future<void> _openEdit() async {
    final result = await Navigator.push<TechniqueEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => TechniqueEditScreen(
          repository: widget.repository,
          userId: widget.userId,
          technique: _technique,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (result.deleted) {
      Navigator.pop(context, true);
      return;
    }
    if (result.technique != null) {
      setState(() {
        _technique = result.technique!;
        _changed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _technique;
    final occurrences = <TechniqueOccurrence>[
      for (var i = 0; i < t.updates.length; i++)
        TechniqueOccurrence(
          date: t.updates[i].at,
          rating: t.updates[i].rating,
          note: t.updates[i].note,
          manualIndex: i,
        ),
      ...widget.sessionOccurrences,
    ]..sort((a, b) => b.date.compareTo(a.date));

    return PopScope(
      // canPop: false zodat ook het systeem-terugpijltje/-gebaar (dat via
      // maybePop loopt, niet via de BackButton hieronder) het _changed-
      // resultaat meegeeft.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppColor.bg,
        appBar: AppBar(
          backgroundColor: AppColor.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: BackButton(
            onPressed: () => Navigator.pop(context, _changed),
          ),
          title: Text(t.name, style: AppText.bodyStrong.copyWith(fontSize: 14)),
          actions: [
            IconButton(
              onPressed: _toggleFavorite,
              icon: Icon(
                t.favorite ? Icons.star : Icons.star_border,
                color: t.favorite ? AppColor.amberBright : AppColor.inkMuted,
              ),
            ),
            TextButton(onPressed: _openEdit, child: const Text('Aanpassen')),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: Opacity(
            opacity: _busy ? .6 : 1,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Badge(text: t.category),
                    if (t.transition.isNotEmpty) _Badge(text: t.transition),
                  ],
                ),
                if (t.groundPositions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  GroundPositionTags(positions: t.groundPositions),
                ],
                const SizedBox(height: 20),
                _LearningBlock(
                  technique: t,
                  goalController: _goalController,
                  onStatusChanged: _setLearningStatus,
                  onPickDate: _pickPlannedDate,
                  onGoalChanged: _onGoalChanged,
                ),
                if (t.description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(t.description, style: AppText.body),
                ],
                if (t.videoUrls.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('VIDEO\'S', style: AppText.overline),
                  const SizedBox(height: 10),
                  CollapsibleVideoList(urls: t.videoUrls),
                ],
                const SizedBox(height: 22),
                Text('UPDATES', style: AppText.overline),
                const SizedBox(height: 10),
                if (occurrences.isEmpty)
                  Text(
                    'Nog geen updates. Voeg er een toe om bij te houden hoe het ging.',
                    style: AppText.caption,
                  )
                else
                  for (final o in occurrences)
                    GestureDetector(
                      onLongPress: o.manualIndex == null
                          ? null
                          : () => _removeUpdate(o.manualIndex!),
                      child: _OccurrenceCard(occurrence: o),
                    ),
                const SizedBox(height: 8),
                if (_adding)
                  _AddUpdateForm(
                    onCancel: () => setState(() => _adding = false),
                    onSubmit: _addUpdate,
                  )
                else
                  InkWell(
                    onTap: () => setState(() => _adding = true),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .16),
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            '+',
                            style: TextStyle(
                              color: AppColor.tealBright,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Update toevoegen — hoe ging het?',
                              style: AppText.body.copyWith(
                                color: AppColor.inkMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (t.updates.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Tik een lange druk op een eigen update om hem te verwijderen.',
                    style: AppText.caption.copyWith(fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: AppColor.tealWash,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: AppText.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColor.tealBright,
        ),
      ),
    );
  }
}

/// Leerstatus/planning van een techniek: 4-weg statuskiezer, bij
/// gepland/bezig een datum + doel, bij bezig een korte statistiekregel, en
/// (zodra er genoeg beoordeelde updates zijn) een lijngrafiek van de
/// beoordelingen over tijd.
class _LearningBlock extends StatelessWidget {
  const _LearningBlock({
    required this.technique,
    required this.goalController,
    required this.onStatusChanged,
    required this.onPickDate,
    required this.onGoalChanged,
  });

  final Technique technique;
  final TextEditingController goalController;
  final ValueChanged<LearningStatus> onStatusChanged;
  final VoidCallback onPickDate;
  final ValueChanged<String> onGoalChanged;

  String? _statsLine() {
    final since = technique.learningStartedAt;
    if (technique.learningStatus != LearningStatus.learning || since == null) {
      return null;
    }
    final relevant = technique.updates.where((u) => u.at.isAfter(since)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final last = relevant.isNotEmpty ? relevant.last.rating : 0;
    final lastText = last > 0 ? ' · laatste ${'★' * last}' : '';
    return 'Bezig sinds ${dutchShortDate(since)} · ${relevant.length}× geoefend sinds start$lastText';
  }

  List<int> _ratingHistory() {
    final rated = technique.updates.where((u) => u.rating > 0).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return rated.map((u) => u.rating).toList();
  }

  @override
  Widget build(BuildContext context) {
    final showPlanning =
        technique.learningStatus == LearningStatus.planned ||
        technique.learningStatus == LearningStatus.learning;
    final stats = _statsLine();
    final ratings = _ratingHistory();

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('LEREN', style: AppText.overline),
          const SizedBox(height: 10),
          SegmentedButton<LearningStatus>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: LearningStatus.none,
                label: Text('Geen', softWrap: false, overflow: TextOverflow.ellipsis),
              ),
              ButtonSegment(
                value: LearningStatus.planned,
                label: Text('Gepland', softWrap: false, overflow: TextOverflow.ellipsis),
              ),
              ButtonSegment(
                value: LearningStatus.learning,
                label: Text('Bezig', softWrap: false, overflow: TextOverflow.ellipsis),
              ),
              ButtonSegment(
                value: LearningStatus.mastered,
                label: Text('Beheerst', softWrap: false, overflow: TextOverflow.ellipsis),
              ),
            ],
            selected: {technique.learningStatus},
            onSelectionChanged: (v) => onStatusChanged(v.first),
          ),
          if (showPlanning) ...[
            const SizedBox(height: 14),
            InkWell(
              onTap: onPickDate,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColor.tealWash,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_outlined,
                      size: 16,
                      color: AppColor.tealBright,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      technique.plannedFor != null
                          ? 'Oefenen op ${dutchShortDate(technique.plannedFor!)}'
                          : 'Kies een datum',
                      style: AppText.body.copyWith(color: AppColor.tealBright),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: goalController,
              onChanged: onGoalChanged,
              style: AppText.body,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: .05),
                hintText: 'Doel — wat wil je hiermee bereiken?',
                hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
          if (stats != null) ...[
            const SizedBox(height: 10),
            Text(stats, style: AppText.caption),
          ],
          if (ratings.length >= 2) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: CustomPaint(
                painter: _RatingTrendPainter(ratings, AppColor.teal),
                size: Size.infinite,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RatingTrendPainter extends CustomPainter {
  final List<int> ratings;
  final Color color;
  _RatingTrendPainter(this.ratings, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (ratings.length < 2) return;
    const lo = 1.0;
    const hi = 5.0;

    double y(int v) => size.height - ((v - lo) / (hi - lo)) * size.height;
    double x(int i) => size.width * i / (ratings.length - 1);

    final path = Path();
    for (var i = 0; i < ratings.length; i++) {
      final point = Offset(x(i), y(ratings[i]));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    final dotPaint = Paint()..color = color;
    for (var i = 0; i < ratings.length; i++) {
      canvas.drawCircle(Offset(x(i), y(ratings[i])), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RatingTrendPainter oldDelegate) =>
      oldDelegate.ratings != ratings;
}

class _OccurrenceCard extends StatelessWidget {
  const _OccurrenceCard({required this.occurrence});
  final TechniqueOccurrence occurrence;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: occurrence.fromSession
            ? Colors.white.withValues(alpha: .04)
            : AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: occurrence.fromSession
            ? Border(left: BorderSide(color: AppColor.teal, width: 2))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                dutchShortDate(occurrence.date),
                style: AppText.caption.copyWith(fontSize: 10),
              ),
              const SizedBox(width: 8),
              if (occurrence.fromSession)
                Text(
                  '· uit training',
                  style: AppText.caption.copyWith(fontSize: 10),
                ),
              const Spacer(),
              if (occurrence.rating > 0)
                Text(
                  '★' * occurrence.rating,
                  style: AppText.caption.copyWith(color: AppColor.amberBright),
                ),
            ],
          ),
          if (occurrence.note.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              occurrence.note,
              style: AppText.body.copyWith(
                color: AppColor.inkMuted,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddUpdateForm extends StatefulWidget {
  const _AddUpdateForm({required this.onSubmit, required this.onCancel});
  final void Function(int rating, String note) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_AddUpdateForm> createState() => _AddUpdateFormState();
}

class _AddUpdateFormState extends State<_AddUpdateForm> {
  int _rating = 0;
  String _note = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColor.surface,
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('HOE GING HET?', style: AppText.overline),
          const SizedBox(height: 10),
          StarRow(rating: _rating, onRate: (r) => setState(() => _rating = r)),
          const SizedBox(height: 12),
          NoteField(
            value: _note,
            onChanged: (n) => _note = n,
            hint: 'Notitie — wat viel op?',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  child: const Text('Annuleer'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => widget.onSubmit(_rating, _note.trim()),
                  child: const Text('Toevoegen'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
