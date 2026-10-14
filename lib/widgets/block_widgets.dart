// block_widgets.dart — gedeelde bouwstenen voor "blokken" binnen een sambo-
// sessie: technieken, warming-up en sparren. Gebruikt door mat_mode_screen
// (live, tijdens de training) en session_edit_screen (achteraf aanpassen).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/combination.dart';
import '../models/technique.dart';
import '../models/training_session.dart';
import '../theme/kinetic_theme.dart';

const kBlockCategories = ['Takedown', 'Submission', 'Strike', 'Overig'];

/// Positiewisseling die een techniek maakt, bv. "Staand -> Grond". Optioneel
/// — leeg laten als de techniek geen positie wijzigt.
const kTransitionOptions = [
  'Staand -> Staand',
  'Staand -> Grond',
  'Grond -> Staand',
  'Grond -> Grond',
];

const kBlockKindLabel = {
  BlockKind.technique: 'Techniek',
  BlockKind.warmup: 'Warming-up',
  BlockKind.sparring: 'Sparren',
};

const kBlockKindDefaultName = {
  BlockKind.technique: '',
  BlockKind.warmup: 'Warming-up',
  BlockKind.sparring: 'Sparren (randori)',
};

const kBlockKindAccent = {
  BlockKind.technique: AppColor.teal,
  BlockKind.warmup: AppColor.inkMuted,
  BlockKind.sparring: AppColor.tealBright,
};

const kBlockKindNoun = {
  BlockKind.technique: 'deze techniek',
  BlockKind.warmup: 'de warming-up',
  BlockKind.sparring: 'het sparren',
};

/// Muteerbare werkkopie van een [SessionBlock] — zowel tijdens een live
/// sessie als in het aanpassingsscherm werk je op deze vorm, en pas bij
/// opslaan zet je hem om naar het onveranderlijke [SessionBlock].
class TechniqueEntry {
  final Object id;
  BlockKind kind;
  String name;
  String meta;
  String note;

  /// Positiewisseling, bv. "Staand -> Grond" — alleen voor technique.
  String transition;
  int rating; // 0 = nog niet beoordeeld — alleen voor technique
  bool covered;
  int minutes; // alleen warmup/sparring (legacy totaal, zie roundMinutes)
  int rounds; // alleen sparring (legacy aantal, zie roundMinutes)

  /// Duur per ronde — alleen sparring. Elke ronde is apart aanpasbaar en
  /// verwijderbaar in plaats van één totaal aantal rondes.
  List<int> roundMinutes;

  /// Algemene doelen voor het sparren, zelf ingevoerd — alleen sparring.
  List<SparGoal> goals;

  /// Doelen per ronde (index-gelijk aan [roundMinutes]) — alleen sparring.
  List<List<SparGoal>> roundGoals;

  /// Beperkingen per ronde (index-gelijk aan [roundMinutes]) — startpositie
  /// of wat niet mag. Alleen sparring.
  List<List<SparGoal>> roundRestrictions;

  /// Rust in seconden na elke ronde (index-gelijk aan [roundMinutes]) —
  /// alleen sparring.
  List<int> restSeconds;

  /// Wanneer dit blok tijdens de training is gedaan.
  DateTime? loggedAt;

  /// True zodra deze techniek gekoppeld is aan een bestaande catalogus-
  /// techniek (gekozen uit de lijst, niet zelf getypt). Voorkomt dat een
  /// latere naamswijziging (bv. via het potloodje) een dubbele techniek in
  /// de catalogus aanmaakt bij het opslaan.
  bool catalogLinked;

  /// Id van de combinatie waaruit dit blok is "uitgeklapt" (zie
  /// `_buildComboEntries`) — alleen in het geheugen tijdens een live sessie,
  /// zodat bv. de combinatie-video's erbij gezocht kunnen worden. Niet
  /// opgeslagen: [toBlock]/[SessionBlock] kennen dit veld niet.
  final String? comboId;

  TechniqueEntry({
    Object? id,
    this.kind = BlockKind.technique,
    required this.name,
    this.meta = '',
    this.note = '',
    this.transition = '',
    this.rating = 0,
    this.covered = false,
    this.minutes = 0,
    this.rounds = 0,
    List<int>? roundMinutes,
    List<SparGoal>? goals,
    List<List<SparGoal>>? roundGoals,
    List<List<SparGoal>>? roundRestrictions,
    List<int>? restSeconds,
    this.loggedAt,
    this.catalogLinked = false,
    this.comboId,
  }) : id = id ?? UniqueKey(),
       roundMinutes = roundMinutes ?? [],
       goals = goals ?? [],
       roundGoals = roundGoals ?? [],
       roundRestrictions = roundRestrictions ?? [],
       restSeconds = restSeconds ?? [];

  factory TechniqueEntry.fromBlock(SessionBlock b) => TechniqueEntry(
    kind: b.kind,
    name: b.name,
    meta: b.meta,
    note: b.note,
    transition: b.transition,
    rating: b.rating,
    covered: b.covered,
    minutes: b.minutes,
    rounds: b.rounds,
    roundMinutes: List.of(b.roundMinutes),
    goals: List.of(b.goals),
    roundGoals: b.roundGoals.map((g) => List<SparGoal>.of(g)).toList(),
    roundRestrictions: b.roundRestrictions
        .map((g) => List<SparGoal>.of(g))
        .toList(),
    restSeconds: List.of(b.restSeconds),
    loggedAt: b.loggedAt,
    catalogLinked: b.catalogLinked,
  )..ensureRoundsSynthesized();

  /// Sparblokken van vóór deze feature hebben alleen een totale duur en een
  /// aantal rondes — zet die om naar losse rondes zodat je ze alsnog apart
  /// kunt aanpassen of verwijderen. Vult ook rust aan tot 60s per ronde als
  /// die nog ontbreekt.
  void ensureRoundsSynthesized() {
    if (kind == BlockKind.sparring && roundMinutes.isEmpty && rounds > 0) {
      roundMinutes = List.filled(
        rounds,
        (minutes / rounds).round().clamp(1, 60),
      );
    }
    while (restSeconds.length < roundMinutes.length) {
      restSeconds.add(defaultRestSeconds);
    }
  }

  SessionBlock toBlock() => SessionBlock(
    kind: kind,
    name: name,
    meta: meta,
    note: note,
    transition: transition,
    rating: rating,
    covered: covered,
    minutes: kind == BlockKind.sparring && roundMinutes.isNotEmpty
        ? roundMinutes.fold(0, (a, b) => a + b)
        : minutes,
    rounds: kind == BlockKind.sparring && roundMinutes.isNotEmpty
        ? roundMinutes.length
        : rounds,
    roundMinutes: roundMinutes,
    goals: goals,
    roundGoals: roundGoals,
    roundRestrictions: roundRestrictions,
    restSeconds: restSeconds,
    loggedAt: loggedAt,
    catalogLinked: catalogLinked,
  );
}

/// Standaard rust tussen rondes — een gebruikelijke pauze bij randori.
const defaultRestSeconds = 60;

/// Metaregel onder de naam: vaste tekst voor techniek, duur (+rondes) voor
/// warming-up/sparren, en het tijdstip waarop het is gelogd als dat bekend
/// is — die kunnen immers achteraf nog wijzigen.
String blockMetaLine(TechniqueEntry t) {
  final String base;
  if (t.kind == BlockKind.technique) {
    final withTransition = t.transition.isNotEmpty
        ? (t.meta.isNotEmpty ? '${t.transition} · ${t.meta}' : t.transition)
        : t.meta;
    base = t.minutes > 0
        ? (withTransition.isNotEmpty
              ? '$withTransition · ${t.minutes} min'
              : '${t.minutes} min')
        : withTransition;
  } else if (t.kind == BlockKind.sparring && t.roundMinutes.isNotEmpty) {
    final total = t.roundMinutes.fold(0, (a, b) => a + b);
    base = '$total min · ${t.roundMinutes.length} rondes';
  } else {
    base = t.rounds > 0
        ? '${t.minutes} min · ${t.rounds} rondes'
        : '${t.minutes} min';
  }
  if (t.loggedAt == null) return base;
  final time = DateFormat('HH:mm', 'nl_NL').format(t.loggedAt!);
  return base.isEmpty ? 'Gelogd om $time' : '$base · $time';
}

/// Vijf vakken van 46 dp hoog — bedoeld voor natte handen, niet voor precisie.
class StarRow extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onRate;
  const StarRow({super.key, required this.rating, required this.onRate});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final n = i + 1;
        final on = rating >= n;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 4 ? 8 : 0),
            child: InkWell(
              onTap: () => onRate(n),
              borderRadius: BorderRadius.circular(AppRadius.md - 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                height: 46,
                decoration: BoxDecoration(
                  color: on
                      ? AppColor.amber
                      : Colors.white.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(AppRadius.md - 2),
                ),
                child: Icon(
                  Icons.star,
                  size: 19,
                  color: on ? AppColor.amberInk : AppColor.inkGhost,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class NoteField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;
  const NoteField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = 'Wat viel op? Wat moet volgende keer anders?',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: TextFormField(
        initialValue: value,
        onChanged: onChanged,
        maxLines: 4,
        minLines: 2,
        style: AppText.body.copyWith(color: AppColor.ink.withValues(alpha: .8)),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
        ),
      ),
    );
  }
}

/// Plus/min stappenteller, gebruikt voor duur en rondes.
class NumberStepper extends StatelessWidget {
  final String label;
  final int value;
  final String suffix;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final Color accent;
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onDown,
    required this.onUp,
    this.suffix = '',
    this.accent = AppColor.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppText.overline)),
        _btn('−', onDown),
        SizedBox(
          width: 70,
          child: Text(
            '$value$suffix',
            textAlign: TextAlign.center,
            style: AppText.display.copyWith(fontSize: 22, color: accent),
          ),
        ),
        _btn('+', onUp),
      ],
    );
  }

  Widget _btn(String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: AppText.body.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColor.inkMuted,
        ),
      ),
    ),
  );
}

/// Rondes van een sparsessie: elke ronde heeft een eigen duur en is apart
/// verwijderbaar — "3 rondes van 3 minuten" zijn dus drie losse dingen,
/// niet één totaal. Gebruikt bij het toevoegen en bij het aanpassen (live en
/// achteraf) van een sparblok.
class RoundsEditor extends StatelessWidget {
  final List<int> roundMinutes;
  final List<List<SparGoal>> roundGoals;
  final List<int> restSeconds;
  final void Function(List<int> minutes, List<List<SparGoal>> goals) onChanged;
  final ValueChanged<List<int>> onRestChanged;
  final Color accent;

  /// Beperkingen per ronde (startpositie, wat niet mag). Null = de
  /// beperkingen-knop wordt niet getoond.
  final List<List<SparGoal>>? roundRestrictions;
  final ValueChanged<List<List<SparGoal>>>? onRestrictionsChanged;

  const RoundsEditor({
    super.key,
    required this.roundMinutes,
    required this.onChanged,
    required this.onRestChanged,
    this.roundGoals = const [],
    this.restSeconds = const [],
    this.accent = AppColor.ink,
    this.roundRestrictions,
    this.onRestrictionsChanged,
  });

  List<SparGoal> _goalsFor(int i) =>
      i < roundGoals.length ? roundGoals[i] : const [];

  List<SparGoal> _restrictionsFor(int i) {
    final r = roundRestrictions;
    return r != null && i < r.length ? r[i] : const [];
  }

  bool get _withRestrictions =>
      roundRestrictions != null && onRestrictionsChanged != null;

  int _restFor(int i) =>
      i < restSeconds.length ? restSeconds[i] : defaultRestSeconds;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < roundMinutes.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Ronde ${i + 1}', style: AppText.body),
                    ),
                    _stepBtn('−', () {
                      final next = List<int>.of(roundMinutes);
                      next[i] = (next[i] - 1).clamp(1, 60);
                      onChanged(next, roundGoals);
                    }),
                    SizedBox(
                      width: 62,
                      child: Text(
                        '${roundMinutes[i]} min',
                        textAlign: TextAlign.center,
                        style: AppText.bodyStrong.copyWith(color: accent),
                      ),
                    ),
                    _stepBtn('+', () {
                      final next = List<int>.of(roundMinutes);
                      next[i] = (next[i] + 1).clamp(1, 60);
                      onChanged(next, roundGoals);
                    }),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        final nextMinutes = List<int>.of(roundMinutes)
                          ..removeAt(i);
                        final nextGoals = List<List<SparGoal>>.of(roundGoals);
                        if (i < nextGoals.length) nextGoals.removeAt(i);
                        final nextRest = List<int>.of(restSeconds);
                        if (i < nextRest.length) nextRest.removeAt(i);
                        onChanged(nextMinutes, nextGoals);
                        onRestChanged(nextRest);
                        if (_withRestrictions) {
                          final nextR = List<List<SparGoal>>.of(
                            roundRestrictions!,
                          );
                          if (i < nextR.length) nextR.removeAt(i);
                          onRestrictionsChanged!(nextR);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.close,
                          size: 15,
                          color: AppColor.inkFaint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: AppColor.inkFaint,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Rust na deze ronde',
                        style: AppText.caption.copyWith(fontSize: 11),
                      ),
                    ),
                    _stepBtn('−', () {
                      final next = List<int>.of(restSeconds);
                      while (next.length <= i) {
                        next.add(defaultRestSeconds);
                      }
                      next[i] = (next[i] - 15).clamp(0, 300);
                      onRestChanged(next);
                    }),
                    SizedBox(
                      width: 50,
                      child: Text(
                        '${_restFor(i)}s',
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _stepBtn('+', () {
                      final next = List<int>.of(restSeconds);
                      while (next.length <= i) {
                        next.add(defaultRestSeconds);
                      }
                      next[i] = (next[i] + 15).clamp(0, 300);
                      onRestChanged(next);
                    }),
                  ],
                ),
                if (_withRestrictions) ...[
                  if (_restrictionsFor(i).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    for (var r = 0; r < _restrictionsFor(i).length; r++)
                      RestrictionRow(
                        restriction: _restrictionsFor(i)[r],
                        onToggle: () {
                          final list = List<SparGoal>.of(_restrictionsFor(i));
                          list[r] = list[r].copyWith(
                            achieved: !list[r].achieved,
                          );
                          _updateRestrictions(i, list);
                        },
                        onRemove: () {
                          final list = List<SparGoal>.of(_restrictionsFor(i))
                            ..removeAt(r);
                          _updateRestrictions(i, list);
                        },
                      ),
                  ],
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _addRestriction(context, i),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '+ beperking / startpositie',
                        style: AppText.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColor.ice,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_goalsFor(i).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  for (var g = 0; g < _goalsFor(i).length; g++)
                    GoalRow(
                      goal: _goalsFor(i)[g],
                      onToggle: () {
                        final list = List<SparGoal>.of(_goalsFor(i));
                        list[g] = list[g].copyWith(achieved: !list[g].achieved);
                        _updateGoals(i, list);
                      },
                      onEdit: () => _editGoal(context, i, g),
                      onRemove: () {
                        final list = List<SparGoal>.of(_goalsFor(i))
                          ..removeAt(g);
                        _updateGoals(i, list);
                      },
                    ),
                ],
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _addGoal(context, i),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '+ doel voor deze ronde',
                      style: AppText.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColor.tealBright,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        InkWell(
          onTap: () {
            final nextMinutes = List<int>.of(roundMinutes)
              ..add(roundMinutes.isNotEmpty ? roundMinutes.last : 3);
            final nextGoals = List<List<SparGoal>>.of(roundGoals)..add([]);
            final nextRest = List<int>.of(restSeconds)
              ..add(
                restSeconds.isNotEmpty ? restSeconds.last : defaultRestSeconds,
              );
            onChanged(nextMinutes, nextGoals);
            onRestChanged(nextRest);
            if (_withRestrictions) {
              final nextR = List<List<SparGoal>>.of(roundRestrictions!);
              while (nextR.length < roundMinutes.length) {
                nextR.add([]);
              }
              onRestrictionsChanged!(nextR..add([]));
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppColor.lineStrong),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '+ ronde',
              style: AppText.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColor.inkMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addGoal(BuildContext context, int i) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text('Doel voor ronde ${i + 1}', style: AppText.cardTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.body,
          decoration: InputDecoration(
            hintText: 'Bijv. Tempo hoog houden',
            filled: true,
            fillColor: Colors.white.withValues(alpha: .05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuleer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Toevoegen'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    _updateGoals(i, [..._goalsFor(i), SparGoal(text: result)]);
  }

  Future<void> _editGoal(BuildContext context, int i, int g) async {
    final result = await _editGoalTextDialog(
      context,
      _goalsFor(i)[g].text,
      title: 'Doel voor ronde ${i + 1} aanpassen',
    );
    if (result == null || result.isEmpty) return;
    final list = List<SparGoal>.of(_goalsFor(i));
    list[g] = list[g].copyWith(text: result);
    _updateGoals(i, list);
  }

  Future<void> _addRestriction(BuildContext context, int i) async {
    final result = await showRestrictionDialog(context, round: i + 1);
    if (result == null || result.isEmpty) return;
    _updateRestrictions(i, [..._restrictionsFor(i), SparGoal(text: result)]);
  }

  void _updateRestrictions(int i, List<SparGoal> forRound) {
    final next = List<List<SparGoal>>.of(roundRestrictions ?? const []);
    while (next.length <= i) {
      next.add([]);
    }
    next[i] = forRound;
    onRestrictionsChanged?.call(next);
  }

  void _updateGoals(int i, List<SparGoal> goalsForRound) {
    final nextGoals = List<List<SparGoal>>.of(roundGoals);
    while (nextGoals.length <= i) {
      nextGoals.add([]);
    }
    nextGoals[i] = goalsForRound;
    onChanged(roundMinutes, nextGoals);
  }

  Widget _stepBtn(String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppText.body.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColor.inkMuted,
        ),
      ),
    ),
  );
}

/// Veelgebruikte beperkingen — één tik in de dialoog, of zelf typen.
const kRestrictionPresets = [
  'Start: staand',
  'Start: grond boven',
  'Start: grond onder',
  'Start: vanuit guard',
  'Start: vanuit de grip',
  'Geen worpen',
  'Geen klemmen',
  'Geen beenklemmen',
  'Geen verwurgingen',
  'Alleen grondwerk',
  'Alleen worpen',
];

/// Kiest of typt een beperking voor een ronde. Geeft null bij annuleren.
Future<String?> showRestrictionDialog(
  BuildContext context, {
  required int round,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Beperking voor ronde $round', style: AppText.cardTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Startpositie of iets wat deze ronde niet mag.',
              style: AppText.caption,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in kRestrictionPresets)
                  ActionChip(
                    label: Text(p, style: AppText.caption.copyWith(
                      color: AppColor.ink,
                    )),
                    onPressed: () => Navigator.pop(c, p),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: AppText.body,
              decoration: const InputDecoration(
                hintText: 'Of typ zelf, bv. Geen grips op de mouw',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Annuleer'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: const Text('Toevoegen'),
        ),
      ],
    ),
  );
}

/// Eén beperking — tik op het schildje om aan te geven dat je je eraan
/// hebt gehouden, op het kruisje om hem te verwijderen.
class RestrictionRow extends StatelessWidget {
  final SparGoal restriction;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  const RestrictionRow({
    super.key,
    required this.restriction,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final kept = restriction.achieved;
    final isStart = restriction.text.toLowerCase().startsWith('start');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                kept
                    ? Icons.verified
                    : (isStart ? Icons.flag_outlined : Icons.block),
                size: 18,
                color: kept ? AppColor.ice : AppColor.coralSoft,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              restriction.text,
              style: AppText.caption.copyWith(
                color: AppColor.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 15, color: AppColor.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eén doel — tik op het rondje om aan/uit te vinken of je het hebt gehaald,
/// tik op het kruisje om hem te verwijderen. Gebruikt voor zowel de
/// algemene doelen als de doelen per ronde.
class GoalRow extends StatelessWidget {
  final SparGoal goal;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final VoidCallback? onEdit;
  const GoalRow({
    super.key,
    required this.goal,
    required this.onToggle,
    required this.onRemove,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(99),
            child: Icon(
              goal.achieved ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: goal.achieved ? AppColor.greenBright : AppColor.inkFaint,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onEdit,
              child: Text(
                goal.text,
                style: AppText.body.copyWith(
                  fontSize: 12,
                  color: goal.achieved
                      ? AppColor.inkFaint
                      : AppColor.ink.withValues(alpha: .85),
                  decoration: goal.achieved ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
          if (onEdit != null)
            InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: AppColor.inkFaint,
                ),
              ),
            ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: AppColor.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialoog om de tekst van een bestaand doel te wijzigen — zowel live
/// tijdens het sparren als achteraf, wanneer de sessie al is opgeslagen.
Future<String?> _editGoalTextDialog(
  BuildContext context,
  String initial, {
  required String title,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: AppColor.surface,
      title: Text(title, style: AppText.cardTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: AppText.body,
        decoration: InputDecoration(
          hintText: 'Bijv. Tempo hoog houden',
          filled: true,
          fillColor: Colors.white.withValues(alpha: .05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Annuleer'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: const Text('Opslaan'),
        ),
      ],
    ),
  );
}

/// Doelen voor het sparren, zelf ingevoerd — bv. "tempo hoog houden" of
/// "alleen grondwerk". Elk doel kan je tijdens (of na) de sessie afvinken
/// als bereikt of niet.
class GoalsEditor extends StatefulWidget {
  final List<SparGoal> goals;
  final ValueChanged<List<SparGoal>> onChanged;
  const GoalsEditor({super.key, required this.goals, required this.onChanged});

  @override
  State<GoalsEditor> createState() => _GoalsEditorState();
}

class _GoalsEditorState extends State<GoalsEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    widget.onChanged([...widget.goals, SparGoal(text: v)]);
    _controller.clear();
  }

  Future<void> _edit(int i) async {
    final result = await _editGoalTextDialog(
      context,
      widget.goals[i].text,
      title: 'Doel aanpassen',
    );
    if (result == null || result.isEmpty) return;
    final next = List<SparGoal>.of(widget.goals);
    next[i] = next[i].copyWith(text: result);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.goals.length; i++)
          GoalRow(
            goal: widget.goals[i],
            onToggle: () {
              final next = List<SparGoal>.of(widget.goals);
              next[i] = next[i].copyWith(achieved: !next[i].achieved);
              widget.onChanged(next);
            },
            onEdit: () => _edit(i),
            onRemove: () {
              final next = List<SparGoal>.of(widget.goals)..removeAt(i);
              widget.onChanged(next);
            },
          ),
        if (widget.goals.isNotEmpty) const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: AppText.body,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: 'Bijv. Tempo hoog houden',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
          ],
        ),
      ],
    );
  }
}

/// Formulier om een techniek, warming-up of sparren toe te voegen — zowel
/// live tijdens de training als achteraf in het aanpassingsscherm.
class BlockAddForm extends StatefulWidget {
  final void Function(TechniqueEntry entry, {required bool openAfter}) onSubmit;
  final VoidCallback onCancel;
  final bool showOpenButton;

  /// Technieken die al in de catalogus staan (Technieken-tabblad) — getypt
  /// wordt gefilterd op deze lijst zodat je een bestaande kunt kiezen in
  /// plaats van per ongeluk een dubbele aan te maken.
  final List<Technique> existingTechniques;

  /// Opgeslagen combinaties — laat je een combo in één keer als losse,
  /// gekoppelde technieken loggen in plaats van los te typen.
  final List<Combination> existingCombinations;

  const BlockAddForm({
    super.key,
    required this.onSubmit,
    required this.onCancel,
    this.showOpenButton = true,
    this.existingTechniques = const [],
    this.existingCombinations = const [],
  });

  @override
  State<BlockAddForm> createState() => _BlockAddFormState();
}

class _BlockAddFormState extends State<BlockAddForm> {
  BlockKind _kind = BlockKind.technique;
  String _category = kBlockCategories.first;
  String _transition = '';
  bool _comboMode = false;
  Combination? _selectedCombo;
  int _minutes = 12; // alleen warming-up
  List<int> _roundMinutes = [3, 3, 3]; // alleen sparren
  List<SparGoal> _goals = []; // alleen sparren, algemeen
  List<List<SparGoal>> _roundGoals = []; // alleen sparren, per ronde
  List<List<SparGoal>> _roundRestrictions = []; // idem, beperkingen
  List<int> _restSeconds = [60, 60, 60]; // alleen sparren, per ronde
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _nameFocus = FocusNode();

  Technique? _matchingTechnique(String name) {
    for (final t in widget.existingTechniques) {
      if (t.name.toLowerCase() == name.toLowerCase()) return t;
    }
    return null;
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _pickKind(BlockKind k) {
    setState(() => _kind = k);
  }

  TechniqueEntry _build() {
    final trimmed = _name.text.trim();
    final name = trimmed.isNotEmpty ? trimmed : kBlockKindDefaultName[_kind]!;
    final existing = _kind == BlockKind.technique
        ? _matchingTechnique(name)
        : null;
    return TechniqueEntry(
      kind: _kind,
      name: name.isNotEmpty ? name : kBlockKindLabel[_kind]!,
      meta: _kind == BlockKind.technique
          ? '${existing?.category ?? _category} · ${existing != null ? 'uit bibliotheek' : 'eigen invoer'}'
          : '',
      transition: _kind == BlockKind.technique ? _transition : '',
      note: _note.text.trim(),
      // Iets dat je hier zelf toevoegt, voegde je toe omdat je het deed —
      // net als warming-up/sparren. De checkbox in de lijst kan dit alsnog
      // uitzetten als het toch niet doorging.
      covered: true,
      minutes: _kind == BlockKind.warmup
          ? _minutes
          : (_kind == BlockKind.sparring
                ? _roundMinutes.fold(0, (a, b) => a + b)
                : 0),
      rounds: _kind == BlockKind.sparring ? _roundMinutes.length : 0,
      roundMinutes: _kind == BlockKind.sparring
          ? List.of(_roundMinutes)
          : const [],
      goals: _kind == BlockKind.sparring ? List.of(_goals) : const [],
      roundGoals: _kind == BlockKind.sparring
          ? _roundGoals.map((g) => List<SparGoal>.of(g)).toList()
          : const [],
      roundRestrictions: _kind == BlockKind.sparring
          ? _roundRestrictions.map((g) => List<SparGoal>.of(g)).toList()
          : const [],
      restSeconds: _kind == BlockKind.sparring
          ? List.of(_restSeconds)
          : const [],
      loggedAt: DateTime.now(),
      catalogLinked: existing != null,
    );
  }

  /// Eén techniek-blok per techniek in de combinatie — zo blijft elke
  /// techniek los aan te passen en telt hij ook los mee in de catalogus,
  /// maar zie je via de meta-regel dat hij bij deze combo hoort.
  List<TechniqueEntry> _buildComboEntries(Combination combo) {
    final now = DateTime.now();
    return [
      for (final name in combo.techniques)
        TechniqueEntry(
          kind: BlockKind.technique,
          name: name,
          meta:
              '${_matchingTechnique(name)?.category ?? 'Overig'} · combo: ${combo.name} (${combo.type.label})',
          transition: _matchingTechnique(name)?.transition ?? '',
          note: _note.text.trim(),
          covered: true,
          loggedAt: now,
          catalogLinked: _matchingTechnique(name) != null,
          comboId: combo.id,
        ),
    ];
  }

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
          Row(
            children: [
              for (final k in BlockKind.values)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: k != BlockKind.values.last ? 6 : 0,
                    ),
                    child: InkWell(
                      onTap: () => _pickKind(k),
                      borderRadius: BorderRadius.circular(11),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _kind == k
                              ? Colors.white.withValues(alpha: .12)
                              : Colors.white.withValues(alpha: .04),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          kBlockKindLabel[k]!,
                          style: AppText.bodyStrong.copyWith(
                            fontSize: 12,
                            color: _kind == k
                                ? kBlockKindAccent[k]
                                : AppColor.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_kind == BlockKind.technique &&
              widget.existingCombinations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ModeChip(
                    label: 'Losse techniek',
                    selected: !_comboMode,
                    onTap: () => setState(() => _comboMode = false),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ModeChip(
                    label: 'Combinatie',
                    selected: _comboMode,
                    onTap: () => setState(() => _comboMode = true),
                  ),
                ),
              ],
            ),
          ],
          if (_kind == BlockKind.technique && _comboMode) ...[
            const SizedBox(height: 10),
            if (widget.existingCombinations.isEmpty)
              Text(
                'Nog geen combinaties gemaakt. Maak er eerst een aan bij Technieken.',
                style: AppText.caption.copyWith(fontSize: 11),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  shrinkWrap: true,
                  children: [
                    for (final c in widget.existingCombinations)
                      InkWell(
                        onTap: () => setState(() => _selectedCombo = c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _selectedCombo == c
                                ? AppColor.tealWash
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name, style: AppText.body),
                              const SizedBox(height: 2),
                              Text(
                                '${c.type.label} · ${c.techniques.join(' → ')}',
                                style: AppText.caption.copyWith(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ] else ...[
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              focusNode: _nameFocus,
              style: AppText.body,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: .06),
                hintText: _kind == BlockKind.technique
                    ? 'Naam van de techniek — of kies uit je lijst'
                    : 'Naam (optioneel)',
                hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
          if (_kind == BlockKind.technique &&
              !_comboMode &&
              widget.existingTechniques.isNotEmpty) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final q = _name.text.trim().toLowerCase();
                final options = widget.existingTechniques
                    .where((t) => q.isEmpty || t.name.toLowerCase().contains(q))
                    .toList();
                if (options.isEmpty) {
                  return Text(
                    'Geen bestaande techniek gevonden — hij wordt nieuw aangemaakt.',
                    style: AppText.caption.copyWith(fontSize: 11),
                  );
                }
                return Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    shrinkWrap: true,
                    children: [
                      for (final t in options)
                        InkWell(
                          onTap: () => setState(() {
                            _name.text = t.name;
                            _category = t.category;
                            _transition = t.transition;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _name.text.trim() == t.name
                                  ? AppColor.tealWash
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(t.name, style: AppText.body),
                                ),
                                Text(
                                  t.category,
                                  style: AppText.caption.copyWith(fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
          if (_kind == BlockKind.technique && !_comboMode) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in kBlockCategories)
                  InkWell(
                    onTap: () => setState(() => _category = c),
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _category == c
                            ? AppColor.tealWash
                            : Colors.white.withValues(alpha: .05),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        c,
                        style: AppText.caption.copyWith(
                          fontWeight: FontWeight.w500,
                          color: _category == c
                              ? AppColor.tealBright
                              : AppColor.inkMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text('TRANSITIE (OPTIONEEL)', style: AppText.overline),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tr in kTransitionOptions)
                  InkWell(
                    onTap: () => setState(
                      () => _transition = _transition == tr ? '' : tr,
                    ),
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _transition == tr
                            ? AppColor.tealWash
                            : Colors.white.withValues(alpha: .05),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        tr,
                        style: AppText.caption.copyWith(
                          fontWeight: FontWeight.w500,
                          color: _transition == tr
                              ? AppColor.tealBright
                              : AppColor.inkMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (_kind == BlockKind.warmup) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(13),
              ),
              child: NumberStepper(
                label: 'DUUR',
                value: _minutes,
                suffix: ' min',
                onDown: () =>
                    setState(() => _minutes = (_minutes - 2).clamp(2, 180)),
                onUp: () =>
                    setState(() => _minutes = (_minutes + 2).clamp(2, 180)),
              ),
            ),
          ],
          if (_kind == BlockKind.sparring) ...[
            const SizedBox(height: 12),
            Text('RONDES', style: AppText.overline),
            const SizedBox(height: 8),
            RoundsEditor(
              roundMinutes: _roundMinutes,
              roundGoals: _roundGoals,
              restSeconds: _restSeconds,
              roundRestrictions: _roundRestrictions,
              onRestrictionsChanged: (r) =>
                  setState(() => _roundRestrictions = r),
              onChanged: (m, g) => setState(() {
                _roundMinutes = m;
                _roundGoals = g;
              }),
              onRestChanged: (r) => setState(() => _restSeconds = r),
            ),
            const SizedBox(height: 14),
            Text('ALGEMENE DOELEN', style: AppText.overline),
            const SizedBox(height: 8),
            GoalsEditor(
              goals: _goals,
              onChanged: (g) => setState(() => _goals = g),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(13),
            ),
            child: TextField(
              controller: _note,
              maxLines: 2,
              minLines: 2,
              style: AppText.body.copyWith(fontSize: 12),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Notitie — hoe voelde het, wat viel op?',
                hintStyle: AppText.caption.copyWith(color: AppColor.inkGhost),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final isCombo = _kind == BlockKind.technique && _comboMode;
              return Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Annuleer', maxLines: 1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isCombo
                          ? (_selectedCombo == null
                                ? null
                                : () {
                                    for (final e in _buildComboEntries(
                                      _selectedCombo!,
                                    )) {
                                      widget.onSubmit(e, openAfter: false);
                                    }
                                  })
                          : () => widget.onSubmit(_build(), openAfter: false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isCombo ? 'Combinatie loggen' : 'Toevoegen',
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                  if (widget.showOpenButton && !isCombo) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            widget.onSubmit(_build(), openAfter: true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColor.teal,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Open', maxLines: 1),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColor.tealWash
              : Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? AppColor.tealBright : AppColor.inkMuted,
          ),
        ),
      ),
    );
  }
}

class AddBlockButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  const AddBlockButton({
    super.key,
    required this.onTap,
    this.label = 'Techniek, warming-up of sparren toevoegen',
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            const Text(
              '+',
              style: TextStyle(color: AppColor.tealBright, fontSize: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: AppText.body.copyWith(
                  color: AppColor.inkMuted,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
