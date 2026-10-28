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
import '../models/training_session.dart' show PositionPractice, TrainingSession;
import '../models/technique.dart';
import '../repositories/agenda_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/technique_repository.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/position_practice_editor.dart';
import '../widgets/block_widgets.dart' show StarRow, NoteField;
import '../widgets/ground_position_tags.dart';
import '../widgets/inline_video_player.dart';
import '../widgets/practice_at_training.dart';
import 'technique_edit_screen.dart';

/// Eén keer dat deze techniek voorkwam — hetzij een losse update, hetzij
/// behandeld tijdens een training (alleen-lezen, want dat hoort bij de
/// sessie zelf).
class TechniqueOccurrence {
  final DateTime date;
  final int rating;
  final String note;
  final bool fromSession;

  /// Per positie hoe het ging (alleen uit een training).
  final List<PositionPractice> positions;

  /// Hoe vaak geoefend in die training (0 = niet geteld).
  final int reps;

  /// De training waar deze beoordeling uit komt (alleen [fromSession]).
  final TrainingSession? session;

  /// Welk blok in [session] (om de beoordeling daar aan te passen).
  final int? blockIndex;

  /// Index in de eigen updates-lijst — alleen gezet voor updates die de
  /// gebruiker zelf kan verwijderen (niet voor sessie-historie).
  final int? manualIndex;

  const TechniqueOccurrence({
    required this.date,
    required this.rating,
    required this.note,
    this.fromSession = false,
    this.manualIndex,
    this.positions = const [],
    this.reps = 0,
    this.session,
    this.blockIndex,
  });
}

class TechniqueDetailScreen extends StatefulWidget {
  const TechniqueDetailScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.technique,
    this.sessionOccurrences = const [],
    this.onOpenSession,
  });

  final TechniqueRepository repository;
  final String userId;
  final Technique technique;
  final List<TechniqueOccurrence> sessionOccurrences;

  /// Opent de training waar een beoordeling uit komt (om hem daar te
  /// bekijken of aan te passen).
  final Future<void> Function(TrainingSession session)? onOpenSession;

  @override
  State<TechniqueDetailScreen> createState() => _TechniqueDetailScreenState();
}

class _TechniqueDetailScreenState extends State<TechniqueDetailScreen> {
  late Technique _technique;
  bool _changed = false;
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

  /// Een update maken: sterren, per positie hoe het ging, en een notitie.
  /// [rating] = vooraf gekozen sterren (uit de kaart bovenaan).
  Future<void> _openUpdate({int rating = 0}) async {
    final t = _technique;
    final result = await showModalBottomSheet<_UpdateResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UpdateSheet(
        initialRating: rating,
        suggestedPositions: t.groundPositions,
        showPositions: t.category != 'Takedown',
      ),
    );
    final update = result?.update;
    if (update != null && mounted) {
      await _addUpdate(update.rating, update.note, update.positions);
    }
  }

  /// Eén update in de lijst. Eigen update: tikken = aanpassen of
  /// verwijderen (lang indrukken verwijderde hem vroeger zonder vragen).
  /// Uit een training: openen, beoordeling aanpassen of wissen.
  Widget _occurrenceTile(TechniqueOccurrence o) => GestureDetector(
    onTap: _busy
        ? null
        : o.manualIndex != null
        ? () => _editUpdate(o.manualIndex!)
        : o.session != null
        ? () => _sessionActions(o)
        : null,
    child: _OccurrenceCard(occurrence: o),
  );

  /// Beoordelingen uit trainingen — lokaal bij te werken na aanpassen of
  /// wissen (de training zelf wordt opgeslagen).
  late List<TechniqueOccurrence> _sessionOccurrences = List.of(
    widget.sessionOccurrences,
  );

  /// Tik op een update uit een training: openen, aanpassen of wissen.
  Future<void> _sessionActions(TechniqueOccurrence o) async {
    final canEdit = o.session != null && o.blockIndex != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                'Uit de training van ${dutchShortDate(o.date)}',
                style: AppText.cardTitle,
              ),
            ),
            if (widget.onOpenSession != null)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Training openen'),
                onTap: () => Navigator.pop(c, 'open'),
              ),
            if (canEdit) ...[
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: const Text('Beoordeling aanpassen'),
                subtitle: const Text('Sterren, posities en notitie'),
                onTap: () => Navigator.pop(c, 'edit'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColor.redBright,
                ),
                title: const Text(
                  'Oordeel wissen',
                  style: TextStyle(color: AppColor.redBright),
                ),
                subtitle: const Text(
                  'Sterren en notities weg; posities en aantal blijven',
                ),
                onTap: () => Navigator.pop(c, 'wipe'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open':
        await widget.onOpenSession?.call(o.session!);
      case 'edit':
        final t = _technique;
        final result = await showModalBottomSheet<_UpdateResult>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _UpdateSheet(
            initialRating: o.rating,
            initialNote: o.note,
            initialPositions: o.positions,
            suggestedPositions: t.groundPositions,
            showPositions: t.category != 'Takedown',
          ),
        );
        final u = result?.update;
        if (u == null || !mounted) return;
        await _saveSessionFeedback(
          o,
          rating: u.rating,
          note: u.note,
          positions: u.positions,
        );
      case 'wipe':
        final sure = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Oordeel wissen?', style: AppText.cardTitle),
            content: Text(
              'De sterren en notities (ook per positie) gaan uit deze '
              'training. Vanuit welke posities je oefende en hoe vaak blijven '
              'staan — dat is wat je echt deed. Een positie weghalen kan via '
              '"Beoordeling aanpassen".',
              style: AppText.body.copyWith(color: AppColor.inkMuted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Annuleer'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                style: TextButton.styleFrom(
                  foregroundColor: AppColor.redBright,
                ),
                child: const Text('Wissen'),
              ),
            ],
          ),
        );
        if (sure == true && mounted) {
          // Alleen het oordeel weg; de feiten (posities, aantal) blijven.
          await _saveSessionFeedback(
            o,
            rating: 0,
            note: '',
            positions: [
              for (final p in o.positions)
                PositionPractice(position: p.position, reps: p.reps),
            ],
          );
        }
    }
  }

  /// Zet de beoordeling terug in het blok van de training en slaat die op.
  Future<void> _saveSessionFeedback(
    TechniqueOccurrence o, {
    required int rating,
    required String note,
    required List<PositionPractice> positions,
    int? reps,
  }) async {
    final session = o.session!;
    final idx = o.blockIndex!;
    if (idx < 0 || idx >= session.blocks.length) return;
    final block = session.blocks[idx].copyWith(
      rating: rating,
      note: note,
      positions: positions,
      reps: reps,
    );
    final next = session.copyWith(
      blocks: [
        for (var i = 0; i < session.blocks.length; i++)
          i == idx ? block : session.blocks[i],
      ],
    );
    setState(() => _busy = true);
    try {
      final saved = await SessionRepository(widget.repository.client)
          .updateContent(next);
      if (!mounted) return;
      final empty =
          rating == 0 &&
          note.trim().isEmpty &&
          positions.isEmpty &&
          (reps ?? block.reps) == 0;
      setState(() {
        _busy = false;
        _changed = true;
        _sessionOccurrences = [
          for (final x in _sessionOccurrences)
            if (!identical(x, o))
              // Andere beoordelingen uit dezelfde training: verwijzen nu
              // naar de opgeslagen versie.
              x.session?.id == saved.id
                  ? TechniqueOccurrence(
                      date: x.date,
                      rating: x.rating,
                      note: x.note,
                      fromSession: true,
                      positions: x.positions,
                      reps: x.reps,
                      session: saved,
                      blockIndex: x.blockIndex,
                    )
                  : x
            else if (!empty)
              TechniqueOccurrence(
                date: o.date,
                rating: rating,
                note: note,
                fromSession: true,
                positions: positions,
                reps: reps ?? block.reps,
                session: saved,
                blockIndex: idx,
              ),
        ];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opslaan is niet gelukt. Probeer opnieuw.'),
        ),
      );
    }
  }

  /// Tik op een eigen update: aanpassen, of verwijderen (met bevestiging).
  Future<void> _editUpdate(int i) async {
    final t = _technique;
    final existing = t.updates[i];
    final result = await showModalBottomSheet<_UpdateResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UpdateSheet(
        initialRating: existing.rating,
        initialNote: existing.note,
        initialPositions: existing.positions,
        suggestedPositions: t.groundPositions,
        showPositions: t.category != 'Takedown',
        canDelete: true,
      ),
    );
    if (result == null || !mounted) return;
    if (result.delete) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Update verwijderen?', style: AppText.cardTitle),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuleer'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              style: TextButton.styleFrom(foregroundColor: AppColor.redBright),
              child: const Text('Verwijder'),
            ),
          ],
        ),
      );
      if (sure == true && mounted) await _removeUpdate(i);
      return;
    }
    final edited = result.update;
    if (edited == null) return;
    await _saveUpdates([
      for (var k = 0; k < t.updates.length; k++)
        // Het moment blijft dat van de oorspronkelijke update.
        k == i
            ? TechniqueUpdate(
                at: existing.at,
                rating: edited.rating,
                note: edited.note,
                positions: edited.positions,
              )
            : t.updates[k],
    ]);
  }

  Future<void> _saveUpdates(List<TechniqueUpdate> updates) async {
    final previous = _technique;
    setState(() {
      _technique = _technique.copyWith(updates: updates);
      _busy = true;
    });
    try {
      final saved = await widget.repository.updateContent(_technique);
      if (mounted) {
        setState(() {
          _technique = saved;
          _busy = false;
          _changed = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _technique = previous;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opslaan is niet gelukt. Probeer opnieuw.'),
        ),
      );
    }
  }

  Future<void> _addUpdate(
    int rating,
    String note, [
    List<PositionPractice> positions = const [],
  ]) async {
    final next = _technique.copyWith(
      updates: [
        ..._technique.updates,
        TechniqueUpdate(
          at: DateTime.now(),
          rating: rating,
          note: note,
          positions: positions,
        ),
      ],
    );
    setState(() {
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
          positions: t.updates[i].positions,
        ),
      ..._sessionOccurrences,
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
                  children: [_Badge(text: t.category)],
                ),
                if (t.groundPositions.isNotEmpty ||
                    t.transition.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  GroundPositionTags(
                    transition: t.transition,
                    positions: t.groundPositions,
                  ),
                ],
                const SizedBox(height: 20),
                _LearningBlock(
                  technique: t,
                  goalController: _goalController,
                  onStatusChanged: _setLearningStatus,
                  onPickDate: _pickPlannedDate,
                  onGoalChanged: _onGoalChanged,
                ),
                const SizedBox(height: 12),
                _RateNowCard(
                  lastRating: [
                    for (final o in occurrences)
                      if (o.rating > 0) o.rating,
                  ].firstOrNull,
                  onRate: _busy ? null : (r) => _openUpdate(rating: r),
                ),
                const SizedBox(height: 12),
                PracticeAtTrainingCard(
                  technique: t,
                  techniqueRepository: widget.repository,
                  agendaRepository: AgendaRepository(widget.repository.client),
                  userId: widget.userId,
                  onTechniqueChanged: (next) => setState(() {
                    _technique = next;
                    _changed = true;
                  }),
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
                else if (occurrences.length <= 7)
                  for (final o in occurrences) _occurrenceTile(o)
                else
                  // Veel updates: precies de eerste 7 zichtbaar, de rest via
                  // scrollen in dit vak.
                  _FirstNThenScroll(
                    visible: 7,
                    children: [for (final o in occurrences) _occurrenceTile(o)],
                  ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _busy ? null : () => _openUpdate(),
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
                    'Tik op een update om hem aan te passen of te '
                    'verwijderen — één uit een training opent die training.',
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
    final relevant =
        technique.updates.where((u) => u.at.isAfter(since)).toList()
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
                label: Text(
                  'Geen',
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ButtonSegment(
                value: LearningStatus.planned,
                label: Text(
                  'Gepland',
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ButtonSegment(
                value: LearningStatus.learning,
                label: Text(
                  'Bezig',
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ButtonSegment(
                value: LearningStatus.mastered,
                label: Text(
                  'Beheerst',
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
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
        // Uit een training: blauwe streep (niet rood — er is niets mis).
        border: occurrence.fromSession
            ? const Border(left: BorderSide(color: AppColor.ice, width: 2))
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
                  style: AppText.caption.copyWith(
                    fontSize: 10,
                    color: AppColor.ice,
                  ),
                ),
              const Spacer(),
              if (occurrence.reps > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('${occurrence.reps}×', style: AppText.caption),
                ),
              if (occurrence.rating > 0)
                Text(
                  '★' * occurrence.rating,
                  style: AppText.caption.copyWith(color: AppColor.amberBright),
                ),
            ],
          ),
          for (final p in occurrence.positions) ...[
            const SizedBox(height: 4),
            Text(
              p.summary,
              style: AppText.caption.copyWith(color: AppColor.inkMuted),
            ),
          ],
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

/// "Hoe gaat het nu?" — bovenaan het detailscherm, zodat beoordelen niet
/// onderaan onder de video's verstopt zit. Tik op een ster om een update te
/// maken.
class _RateNowCard extends StatelessWidget {
  const _RateNowCard({required this.lastRating, required this.onRate});

  /// Laatste beoordeling (uit een update of training), of null.
  final int? lastRating;
  final ValueChanged<int>? onRate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_outline, size: 18, color: AppColor.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Hoe gaat het nu?', style: AppText.bodyStrong),
              ),
              Text(
                lastRating == null
                    ? 'nog niet beoordeeld'
                    : 'laatst: ${'★' * lastRating!}',
                style: AppText.caption,
              ),
            ],
          ),
          const SizedBox(height: 10),
          StarRow(rating: 0, onRate: onRate ?? (_) {}),
        ],
      ),
    );
  }
}

/// Paneel voor een update: sterren, per positie hoe het ging, en een
/// notitie. Geeft de update terug bij "Opslaan".
/// Uitkomst van [_UpdateSheet]: een (aangepaste) update, of verwijderen.
class _UpdateResult {
  final TechniqueUpdate? update;
  final bool delete;
  const _UpdateResult({this.update, this.delete = false});
}

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({
    required this.initialRating,
    required this.suggestedPositions,
    required this.showPositions,
    this.initialNote = '',
    this.initialPositions = const [],
    this.canDelete = false,
  });

  final int initialRating;
  final String initialNote;
  final List<PositionPractice> initialPositions;
  final List<String> suggestedPositions;
  final bool showPositions;

  /// Bestaande update: ook een knop "Verwijderen".
  final bool canDelete;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  late int _rating = widget.initialRating;
  late String _note = widget.initialNote;
  late List<PositionPractice> _positions = List.of(widget.initialPositions);

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context);
    final empty = _rating == 0 && _note.trim().isEmpty && _positions.isEmpty;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      maxChildSize: .95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + insets.viewInsets.bottom + insets.padding.bottom,
        ),
        children: [
          Text(
            widget.canDelete ? 'Update aanpassen' : 'Hoe ging het?',
            style: AppText.title,
          ),
          const SizedBox(height: 12),
          StarRow(rating: _rating, onRate: (r) => setState(() => _rating = r)),
          if (widget.showPositions) ...[
            const SizedBox(height: 18),
            PositionPracticeEditor(
              value: _positions,
              suggested: widget.suggestedPositions,
              onChanged: (p) => setState(() => _positions = p),
            ),
          ],
          const SizedBox(height: 18),
          NoteField(
            value: _note,
            hint: 'Algemene notitie (optioneel)',
            onChanged: (v) => setState(() => _note = v),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: empty
                ? null
                : () => Navigator.pop(
                    context,
                    _UpdateResult(
                      update: TechniqueUpdate(
                        at: DateTime.now(),
                        rating: _rating,
                        note: _note.trim(),
                        positions: _positions,
                      ),
                    ),
                  ),
            child: const Text('Opslaan'),
          ),
          if (widget.canDelete) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () =>
                  Navigator.pop(context, const _UpdateResult(delete: true)),
              style: TextButton.styleFrom(foregroundColor: AppColor.redBright),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Update verwijderen'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Toont [children] in een scrollvak dat precies zo hoog is als de eerste
/// [visible] items samen — hoe groot elk item ook is. Truc: een onzichtbare
/// kolom met die eerste items bepaalt de hoogte, de echte (scrollende)
/// lijst ligt eroverheen.
class _FirstNThenScroll extends StatelessWidget {
  const _FirstNThenScroll({required this.visible, required this.children});

  final int visible;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Bepaalt alleen de hoogte; niet zichtbaar en niet aan te tikken.
        IgnorePointer(
          child: ExcludeSemantics(
            child: Opacity(
              opacity: 0,
              child: Column(children: children.take(visible).toList()),
            ),
          ),
        ),
        Positioned.fill(
          child: Scrollbar(
            child: ListView(padding: EdgeInsets.zero, children: children),
          ),
        ),
      ],
    );
  }
}
