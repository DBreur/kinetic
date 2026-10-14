// strength_session_controller.dart — houdt een live krachttraining draaiend,
// ook als je naar een ander tabblad navigeert. Zelfde opzet als
// mat_session_controller.dart: een gewoon Dart-object dat door ShellScreen
// wordt vastgehouden zolang de sessie actief is, zodat de klok, de
// Nightscout-polling en het glucose-alarm gewoon doorlopen terwijl
// StrengthModeScreen niet gemount is.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../core/exercise_library.dart';
import '../core/interval_timer.dart';
import '../models/app_profile.dart';
import '../models/exercise.dart';
import '../core/session_glucose.dart';
import '../models/glucose.dart';
import '../models/glucose_entry.dart';
import '../models/training_session.dart';
import '../repositories/exercise_repository.dart';
import '../repositories/glucose_entry_repository.dart';
import '../repositories/session_repository.dart';
import '../services/alarm_notification_service.dart';
import '../services/glucose_provider.dart';
import '../state/app_controller.dart';
import '../state/live_session_controller.dart';
import '../widgets/glucose_alarm.dart';
import '../widgets/manual_glucose.dart';

/// Standaard rusttijd tussen sets, net als in Lyfta — telt zichtbaar af
/// zodra je een set afvinkt.
const restSeconds = 90;

class LiveSet {
  double kg;
  int reps;
  bool done = false;

  /// Tijd-gebaseerde set (bv. een plank van 45s) i.p.v. reps — `null`
  /// betekent gewoon een reps-gebaseerde set zoals voorheen.
  int? seconds;

  /// Loopt alleen als [StrengthSessionController.startSetTimer] is
  /// aangeroepen voor deze set — kloktijd-gebaseerd, zie [IntervalTimer].
  final IntervalTimer _timer = IntervalTimer();
  bool _timerStarted = false;
  bool get timerRunning => _timer.isRunning;
  Duration get timeLeft => _timer.remaining;

  LiveSet({this.kg = 0, this.reps = 8, this.seconds});
}

class LiveExercise {
  String name;
  List<LiveSet> sets;

  /// Sets van de vorige keer — ook bijgewerkt als een oefening uit een
  /// trainingsschema komt en de geschiedenis pas ná het starten binnenkomt
  /// (zie [StrengthSessionController._enrichFromHistory]).
  List<ExerciseSet>? lastPerformance;

  /// Zwaarste gewicht ooit voor deze oefening — bijgewerkt zodra je tijdens
  /// déze sessie een nieuw record zet (zie
  /// [StrengthSessionController._checkNewRecord]).
  double? personalRecord;
  final String description;
  LiveExercise({
    required this.name,
    required this.sets,
    this.lastPerformance,
    this.personalRecord,
    this.description = '',
  });
}

enum CircuitPhase { work, rest }

/// Een circuit zoals het live in een sessie draait — begint met [startCircuit]
/// en schakelt daarna zelf automatisch door (werk → rust → volgende
/// oefening → volgende ronde), aangestuurd vanuit
/// [StrengthSessionController]'s bestaande 1s-ticker.
class LiveCircuit {
  final Circuit circuit;
  int round = 0;
  int exerciseIndex = 0;
  CircuitPhase phase = CircuitPhase.work;
  bool isRunning = false;
  bool isDone = false;
  final IntervalTimer timer = IntervalTimer();

  LiveCircuit(this.circuit);

  String get currentExerciseName => circuit.exerciseNames.isEmpty
      ? ''
      : circuit.exerciseNames[exerciseIndex];
  Duration get timeLeft => timer.remaining;
}

String _fmtKg(double kg) => kg % 1 == 0 ? kg.toInt().toString() : kg.toString();

class StrengthSessionController extends ChangeNotifier
    implements LiveSessionController {
  StrengthSessionController({
    required this.title,
    required this.appController,
    required this.contextOf,
    this.provider,
    GlucoseReading? initialReading,
    List<ExerciseEntry> planned = const [],
    List<Circuit> plannedCircuits = const [],
    DateTime? startedAt,
    Duration pausedAccum = Duration.zero,
    DateTime? pauseStartedAt,
    List<GlucosePoint> restoredSeries = const [],
    List<NutritionEntry> restoredNutrition = const [],
  }) {
    reading = initialReading ?? GlucoseReading(6.8, Trend.flat, DateTime.now());
    series.add(GlucosePoint(reading.at, reading.mmol));
    // Herstel na het sluiten van de app: curve, voeding, starttijd en
    // pauze-stand terugzetten (de tijd loopt door, want je traint door).
    if (restoredSeries.isNotEmpty) {
      series
        ..clear()
        ..addAll(restoredSeries);
      final last = restoredSeries.last;
      reading = GlucoseReading(last.mmol, Trend.flat, last.at);
    }
    nutrition.addAll(restoredNutrition);
    appController.setSessionActive(true);
    _startedAt = startedAt ?? DateTime.now();
    _pausedAccum = pausedAccum;
    if (pauseStartedAt != null) {
      _pauseStartedAt = pauseStartedAt;
      isPaused = true;
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkStaleness();
      _checkSetTimers();
      _checkCircuitTimers();
      notifyListeners();
    });
    // Elke minuut kijken: een sensor meet elke ~5 minuten, zo zie je een
    // nieuwe waarde binnen een minuut (in plaats van tot 5 minuten later).
    _poller = Timer.periodic(
      const Duration(minutes: 1),
      (_) => refreshReading(),
    );
    refreshReading();
    if (isFinger) _loadFingerEntries();
    _loadCustomExercises();
    if (planned.isNotEmpty) {
      for (final e in planned) {
        exercises.add(
          LiveExercise(
            name: e.name,
            sets: e.sets
                .map(
                  (s) =>
                      LiveSet(kg: s.kg, reps: s.reps, seconds: s.seconds)
                        ..done = s.done,
                )
                .toList(),
          ),
        );
        unawaited(ensureCustomExercise(e.name));
      }
      _enrichFromHistory();
    }
    for (final c in plannedCircuits) {
      circuits.add(LiveCircuit(c));
    }
  }

  @override
  final String title;
  final GlucoseProvider? provider;
  final AppController appController;

  /// Geeft altijd een gemounte context terug — meegegeven door ShellScreen,
  /// die zolang je bent ingelogd nooit verdwijnt. Nodig om het glucose-alarm
  /// te kunnen tonen terwijl deze sessie op de achtergrond draait.
  final BuildContext Function() contextOf;

  // Duur wordt uit DateTime.now() herberekend, niet uit een Stopwatch —
  // Android pauzeert de monotone klok achter Stopwatch zodra het scherm uit
  // is en er geen wakelock is (CPU-doze), waardoor de duur dan echt stopt
  // met lopen in plaats van alleen de weergave even niet te verversen.
  late DateTime _startedAt;
  Duration _pausedAccum = Duration.zero;
  DateTime? _pauseStartedAt;
  Timer? _tick;
  Timer? _poller;
  Timer? _restTimer;
  DateTime? _restEndAt;
  bool saving = false;
  @override
  bool isPaused = false;

  late GlucoseReading reading;
  final List<GlucosePoint> series = [];

  final List<LiveExercise> exercises = [];
  final List<LiveCircuit> circuits = [];
  final Map<String, List<ExercisePerformance>> _performanceHistory = {};
  List<Exercise> customExercises = [];
  bool adding = false;
  List<ManualGlucoseEntry> fingerEntries = [];
  final List<NutritionEntry> nutrition = [];

  @override
  Duration get elapsed {
    final pausedSoFar =
        _pausedAccum +
        (_pauseStartedAt != null
            ? DateTime.now().difference(_pauseStartedAt!)
            : Duration.zero);
    return DateTime.now().difference(_startedAt) - pausedSoFar;
  }

  /// Resterende rust in seconden, live herberekend uit [_restEndAt] zodat
  /// hij net als [elapsed] doorloopt ook als het scherm even uit is geweest.
  int get restLeft {
    if (_restEndAt == null) return 0;
    final left = _restEndAt!.difference(DateTime.now()).inSeconds;
    return left > 0 ? left : 0;
  }

  @override
  double get glucoseMmol => reading.mmol;

  bool get isFinger =>
      appController.profile?.glucoseSource == GlucoseSource.finger;

  bool get showPauseButton => appController.profile?.showPauseButton ?? true;

  bool _disposed = false;

  /// Netwerkverzoeken (glucose, prestaties) kunnen binnenkomen nadat de
  /// sessie al is opgeslagen of weggegooid — dan niets meer melden in
  /// plaats van te crashen.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    _poller?.cancel();
    _restTimer?.cancel();
    appController.setSessionActive(false);
    super.dispose();
  }

  /// Alleen zinvol bij CGM: waarschuwt eenmalig (niet bij elke seconde
  /// opnieuw) als de laatste meting 15 minuten of langer oud is.
  void _checkStaleness() {
    if (isFinger) return;
    final stale = appController.checkStaleness(
      GlucoseSnapshot(reading: reading, history: series),
    );
    if (!stale) return;
    AlarmNotificationService.instance.showStaleWarning(
      withSound: appController.alarmDecision().withSound,
    );
    final ctx = contextOf();
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text(
            'Geen glucosedata ontvangen — controleer je sensor of meet met '
            'een vingerprik.',
          ),
        ),
      );
    }
  }

  void pause() {
    if (isPaused) return;
    _pauseStartedAt = DateTime.now();
    isPaused = true;
    notifyListeners();
  }

  void resume() {
    if (!isPaused) return;
    _pausedAccum += DateTime.now().difference(_pauseStartedAt!);
    _pauseStartedAt = null;
    isPaused = false;
    notifyListeners();
    // Meteen een verse waarde: tijdens de pauze lag de app vaak stil.
    refreshReading();
  }

  Future<void> _loadCustomExercises() async {
    final userId = appController.user?.id;
    final client = appController.client;
    if (userId == null || client == null) return;
    try {
      final list = await ExerciseRepository(client).listForUser(userId);
      customExercises = list;
      notifyListeners();
    } catch (_) {
      // Eigen oefeningen blijven ongebruikt voor autocomplete; een nieuwe
      // naam typen blijft gewoon werken.
    }
  }

  Exercise? matchingCustomExercise(String name) {
    for (final e in customExercises) {
      if (e.name.toLowerCase() == name.toLowerCase()) return e;
    }
    return null;
  }

  /// Slaat een net getypte, nog onbekende naam op in de oefeningcatalogus,
  /// zodat je 'm later een beschrijving kunt geven en hij in de lijst blijft
  /// staan voor volgende trainingen.
  Future<void> ensureCustomExercise(String name) async {
    if (matchingCustomExercise(name) != null) return;
    if (kExerciseLibrary.any((n) => n.toLowerCase() == name.toLowerCase())) {
      return;
    }
    final userId = appController.user?.id;
    final client = appController.client;
    if (userId == null || client == null) return;
    try {
      final created = await ExerciseRepository(
        client,
      ).create(Exercise(id: '', name: name), userId);
      customExercises = [...customExercises, created];
      notifyListeners();
    } catch (_) {
      // Oefening telt al mee in deze sessie; alleen het los opslaan in de
      // catalogus (voor een beschrijving/hergebruik) is mislukt.
    }
  }

  Future<void> _loadFingerEntries() async {
    final userId = appController.user?.id;
    final client = appController.client;
    if (userId == null || client == null) return;
    try {
      final entries = await GlucoseEntryRepository(
        client,
      ).recentForUser(userId);
      fingerEntries = entries;
      notifyListeners();
    } catch (_) {
      // Strip blijft leeg; invoeren blijft gewoon werken.
    }
  }

  Future<void> recordManualReading(BuildContext context) async {
    final value = await showManualGlucoseDialog(context);
    if (value == null) return;
    final now = DateTime.now();
    onReading(GlucoseReading(value, trendFromDelta(value - reading.mmol), now));
    final userId = appController.user?.id;
    final client = appController.client;
    if (userId == null || client == null) return;
    try {
      final entry = await GlucoseEntryRepository(
        client,
      ).create(userId, value, now);
      fingerEntries = [entry, ...fingerEntries].take(5).toList();
      notifyListeners();
    } catch (_) {
      // Meting telt al mee in deze sessie; de log op de "Nu"-pagina kan hem
      // missen als dit mislukt, maar dat blokkeert de training niet.
    }
  }

  Future<void> editFingerEntry(
    BuildContext context,
    ManualGlucoseEntry entry,
  ) async {
    final result = await showManualGlucoseEditDialog(context, entry);
    if (result == null) return;
    final userId = appController.user?.id;
    final client = appController.client;
    try {
      if (client != null && userId != null) {
        if (result.deleted) {
          await GlucoseEntryRepository(client).delete(entry.id);
        } else if (result.mmol != null) {
          await GlucoseEntryRepository(client).update(entry.id, result.mmol!);
        }
      }
    } catch (_) {
      // Lokale meting hieronder wordt sowieso bijgewerkt; volgende
      // verversing probeert opnieuw met de server te synchroniseren.
    }
    final idx = series.indexWhere(
      (p) => p.at.difference(entry.at).abs() < const Duration(seconds: 2),
    );
    if (result.deleted) {
      fingerEntries.removeWhere((e) => e.id == entry.id);
      if (idx != -1) series.removeAt(idx);
    } else if (result.mmol != null) {
      final i = fingerEntries.indexWhere((e) => e.id == entry.id);
      if (i != -1) {
        fingerEntries[i] = ManualGlucoseEntry(
          id: entry.id,
          mmol: result.mmol!,
          at: entry.at,
        );
      }
      if (idx != -1) series[idx] = GlucosePoint(entry.at, result.mmol!);
    }
    if (fingerEntries.isNotEmpty) {
      final latest = fingerEntries.first;
      final trend = fingerEntries.length > 1
          ? trendFromDelta(latest.mmol - fingerEntries[1].mmol)
          : Trend.flat;
      reading = GlucoseReading(latest.mmol, trend, latest.at);
    }
    notifyListeners();
  }

  NutritionEntry logNutrition(String label) {
    final entry = NutritionEntry(
      label: label,
      at: DateTime.now(),
      mmol: reading.mmol,
    );
    nutrition.add(entry);
    notifyListeners();
    return entry;
  }

  void removeNutrition(int i) {
    nutrition.removeAt(i);
    notifyListeners();
  }

  Future<void> refreshReading() async {
    final profile = appController.profile;
    final p = provider;
    if (profile == null ||
        p == null ||
        profile.glucoseSource == GlucoseSource.finger) {
      return;
    }
    final snapshot = await p.fetch(
      count: countToFill(
        series.isEmpty ? null : series.last.at,
        DateTime.now(),
      ),
    );
    final latest = snapshot.reading;
    if (latest == null || _disposed) return;
    // Alleen echt nieuwe metingen toevoegen — en metingen die gemist zijn
    // terwijl de app stil lag (scherm uit, gepauzeerd) alsnog aanvullen.
    final fresh = newSessionPoints(series, [
      ...snapshot.history,
      GlucosePoint(latest.at, latest.mmol),
    ], sessionStart: _startedAt);
    if (fresh.isEmpty) return;
    series.addAll(fresh);
    reading = latest;
    notifyListeners();
    appController.checkGlucoseReading(
      contextOf,
      latest,
      onManualEntry: (ctx) => handleManualEntryFromAlarm(ctx, onReading),
    );
  }

  /// Aanroepen bij elke nieuwe meting (sensor of handmatig) — ook als het
  /// scherm niet actief in beeld is.
  void onReading(GlucoseReading r) {
    reading = r;
    series.add(GlucosePoint(r.at, r.mmol));
    notifyListeners();
    appController.checkGlucoseReading(
      contextOf,
      r,
      onManualEntry: (ctx) => handleManualEntryFromAlarm(ctx, onReading),
    );
  }

  void setAdding(bool value) {
    adding = value;
    notifyListeners();
  }

  /// Alle keren dat je deze oefening eerder deed — gebruikt om een nieuwe
  /// oefening voor te vullen (net als in Lyfta) en om het persoonlijk record
  /// te tonen.
  Future<List<ExercisePerformance>> fetchPerformanceHistory(String name) async {
    if (_performanceHistory.containsKey(name)) {
      return _performanceHistory[name]!;
    }
    final userId = appController.user?.id;
    final client = appController.client;
    if (userId == null || client == null) return const [];
    final history = await SessionRepository(
      client,
    ).performanceHistory(userId, name);
    _performanceHistory[name] = history;
    return history;
  }

  Future<void> pickExercise(String name) async {
    adding = false;
    notifyListeners();
    final history = await fetchPerformanceHistory(name);
    // Best-effort, niet blokkerend voor het toevoegen aan de sessie.
    unawaited(ensureCustomExercise(name));
    final last = history.isNotEmpty ? history.first.sets : null;
    final pr = history.isEmpty
        ? null
        : history.map((p) => p.heaviest).reduce((a, b) => a > b ? a : b);
    exercises.add(
      LiveExercise(
        name: name,
        sets: last != null && last.isNotEmpty
            ? last
                  .map((s) => LiveSet(kg: s.kg, reps: s.reps, seconds: s.seconds))
                  .toList()
            : [LiveSet()],
        lastPerformance: last,
        personalRecord: pr,
        description: matchingCustomExercise(name)?.description ?? '',
      ),
    );
    notifyListeners();
  }

  /// Vult "vorige keer"/record aan voor oefeningen die al met vaste sets
  /// zijn gestart (bv. vanuit een trainingsschema) — de sets zelf blijven
  /// zoals het schema ze meegaf, dit voegt alleen de context toe die je ook
  /// krijgt als je een oefening via de zoekfunctie toevoegt.
  Future<void> _enrichFromHistory() async {
    for (final exercise in List.of(exercises)) {
      final history = await fetchPerformanceHistory(exercise.name);
      if (history.isEmpty) continue;
      exercise.lastPerformance = history.first.sets;
      exercise.personalRecord = history
          .map((p) => p.heaviest)
          .reduce((a, b) => a > b ? a : b);
    }
    notifyListeners();
  }

  void removeExercise(int i) {
    exercises.removeAt(i);
    notifyListeners();
  }

  void addSet(int i) {
    final sets = exercises[i].sets;
    sets.add(
      LiveSet(
        kg: sets.isEmpty ? 0 : sets.last.kg,
        reps: sets.isEmpty ? 8 : sets.last.reps,
        seconds: sets.isEmpty ? null : sets.last.seconds,
      ),
    );
    notifyListeners();
  }

  /// Zet een set om tussen reps- en tijd-gebaseerd — het andere veld blijft
  /// staan maar wordt genegeerd zolang [LiveSet.seconds] niet null is.
  void setSetMode(int ei, int si, {required bool timeBased}) {
    final set = exercises[ei].sets[si];
    set.seconds = timeBased ? (set.seconds ?? 30) : null;
    notifyListeners();
  }

  void updateSet(int ei, int si, LiveSet Function(LiveSet) patch) {
    final exercise = exercises[ei];
    final sets = exercise.sets;
    final wasDone = sets[si].done;
    sets[si] = patch(sets[si]);
    if (!wasDone && sets[si].done) {
      _startRestTimer();
      _checkNewRecord(exercise, sets[si].kg);
    }
    notifyListeners();
  }

  /// Start de aftelklok van een tijd-gebaseerde set (bv. een plank van 45s)
  /// — bij het aflopen wordt de set automatisch afgevinkt via hetzelfde pad
  /// als handmatig afvinken, dus de rust-timer gaat daarna gewoon aan.
  void startSetTimer(int ei, int si) {
    final set = exercises[ei].sets[si];
    final seconds = set.seconds;
    if (seconds == null || set.done) return;
    set._timer.start(Duration(seconds: seconds));
    set._timerStarted = true;
    notifyListeners();
  }

  /// Vinkt een tijd-gebaseerde set automatisch af zodra de aftelklok (die
  /// met [startSetTimer] is gestart) op nul staat.
  void _checkSetTimers() {
    for (var ei = 0; ei < exercises.length; ei++) {
      final sets = exercises[ei].sets;
      for (var si = 0; si < sets.length; si++) {
        final set = sets[si];
        if (set._timerStarted && !set.done && !set.timerRunning) {
          updateSet(ei, si, (s) => s..done = true);
        }
      }
    }
  }

  /// Voegt een circuit toe aan de sessie, nog niet gestart — zie
  /// [startCircuit].
  void addCircuit(Circuit c) {
    circuits.add(LiveCircuit(c));
    notifyListeners();
  }

  void removeCircuit(int i) {
    circuits.removeAt(i);
    notifyListeners();
  }

  /// Start (of herstart) een circuit vanaf ronde 1, oefening 1, werkfase —
  /// schakelt daarna zelf automatisch door (zie [_checkCircuitTimers]).
  void startCircuit(int i) {
    final lc = circuits[i];
    if (lc.circuit.exerciseNames.isEmpty) return;
    lc.isRunning = true;
    lc.isDone = false;
    lc.round = 0;
    lc.exerciseIndex = 0;
    lc.phase = CircuitPhase.work;
    lc.timer.start(Duration(seconds: lc.circuit.workSeconds));
    notifyListeners();
  }

  void stopCircuit(int i) {
    final lc = circuits[i];
    lc.isRunning = false;
    lc.timer.cancel();
    notifyListeners();
  }

  /// Handmatig naar de volgende fase — zelfde geest als [skipRest].
  void skipCircuitPhase(int i) {
    final lc = circuits[i];
    if (!lc.isRunning) return;
    _advanceCircuit(lc);
    notifyListeners();
  }

  /// Schakelt elk lopend circuit automatisch door zodra de huidige fase is
  /// afgelopen, met een trilsignaal bij elke overgang — zodat je niet op je
  /// telefoon hoeft te tikken middenin een burpee.
  void _checkCircuitTimers() {
    for (final lc in circuits) {
      if (lc.isRunning && !lc.isDone && !lc.timer.isRunning) {
        _advanceCircuit(lc);
      }
    }
  }

  void _advanceCircuit(LiveCircuit lc) {
    HapticFeedback.mediumImpact();
    final c = lc.circuit;
    if (lc.phase == CircuitPhase.work) {
      final isLastExercise = lc.exerciseIndex == c.exerciseNames.length - 1;
      final isLastRound = lc.round == c.rounds - 1;
      if (isLastExercise && isLastRound) {
        lc.isRunning = false;
        lc.isDone = true;
        lc.timer.cancel();
        return;
      }
      if (c.restSeconds > 0) {
        lc.phase = CircuitPhase.rest;
        lc.timer.start(Duration(seconds: c.restSeconds));
        return;
      }
    }
    // Rust is om (of er is geen rust ingesteld): door naar de volgende
    // oefening, of naar de volgende ronde als dit de laatste oefening was.
    if (lc.exerciseIndex == c.exerciseNames.length - 1) {
      lc.round += 1;
      lc.exerciseIndex = 0;
    } else {
      lc.exerciseIndex += 1;
    }
    lc.phase = CircuitPhase.work;
    lc.timer.start(Duration(seconds: c.workSeconds));
  }

  /// Toont een korte melding zodra een afgevinkte set het bestaande record
  /// van deze oefening verslaat — de meeste sessies zetten geen record, dus
  /// dit blijft onopvallend als er niets te vieren valt.
  void _checkNewRecord(LiveExercise exercise, double kg) {
    if (kg <= 0) return;
    final current = exercise.personalRecord;
    if (current != null && kg <= current) return;
    exercise.personalRecord = kg;
    final ctx = contextOf();
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text('Nieuw record: ${exercise.name} — ${_fmtKg(kg)}kg!'),
      ),
    );
  }

  void reorderExercise(int oldIndex, int newIndex) {
    final moved = exercises.removeAt(oldIndex);
    exercises.insert(newIndex, moved);
    notifyListeners();
  }

  void _startRestTimer() {
    _restTimer?.cancel();
    _restEndAt = DateTime.now().add(Duration(seconds: restSeconds));
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (restLeft <= 0) {
        _restEndAt = null;
        _restTimer?.cancel();
      }
      notifyListeners();
    });
  }

  void skipRest() {
    _restTimer?.cancel();
    _restEndAt = null;
    notifyListeners();
  }

  // ── opslaan ────────────────────────────────────────────────────────────────

  /// Momentopname om lokaal te bewaren (zie LiveSessionStore), zodat de
  /// training terugkomt als de app per ongeluk sluit.
  Map<String, dynamic> _snapshotBase(String kind) => {
    'kind': kind,
    'title': title,
    'startedAt': _startedAt.toUtc().toIso8601String(),
    'pausedAccumMs': _pausedAccum.inMilliseconds,
    'pauseStartedAt': _pauseStartedAt?.toUtc().toIso8601String(),
    'series': series.map((p) => p.toJson()).toList(),
    'nutrition': nutrition.map((n) => n.toJson()).toList(),
  };

  Map<String, dynamic> toSnapshot() => {
    ..._snapshotBase('kracht'),
    'exercises': [
      for (final e in exercises)
        ExerciseEntry(
          name: e.name,
          sets: [
            for (final s in e.sets)
              ExerciseSet(kg: s.kg, reps: s.reps, done: s.done, seconds: s.seconds),
          ],
        ).toJson(),
    ],
    'circuits': circuits.map((c) => c.circuit.toJson()).toList(),
  };

  /// Bouwt een sessie terug uit [toSnapshot]. Afgevinkte sets komen terug;
  /// lopende set-/circuittimers beginnen opnieuw.
  factory StrengthSessionController.restore(
    Map<String, dynamic> json, {
    required AppController appController,
    required BuildContext Function() contextOf,
    GlucoseProvider? provider,
  }) => StrengthSessionController(
    title: (json['title'] as String?) ?? 'Krachttraining',
    appController: appController,
    contextOf: contextOf,
    provider: provider,
    planned: [
      for (final e in (json['exercises'] as List? ?? const []))
        ExerciseEntry.fromJson(e as Map<String, dynamic>),
    ],
    plannedCircuits: [
      for (final c in (json['circuits'] as List? ?? const []))
        Circuit.fromJson(c as Map<String, dynamic>),
    ],
    startedAt: DateTime.parse(json['startedAt'] as String).toLocal(),
    pausedAccum: Duration(milliseconds: (json['pausedAccumMs'] as num?)?.toInt() ?? 0),
    pauseStartedAt: json['pauseStartedAt'] == null
        ? null
        : DateTime.parse(json['pauseStartedAt'] as String).toLocal(),
    restoredSeries: [
      for (final p in (json['series'] as List? ?? const []))
        GlucosePoint.fromJson(p as Map<String, dynamic>),
    ],
    restoredNutrition: [
      for (final n in (json['nutrition'] as List? ?? const []))
        NutritionEntry.fromJson(n as Map<String, dynamic>),
    ],
  );

  Future<bool> saveSession() async {
    final userId = appController.user?.id;
    final client = appController.client;
    if (userId == null || client == null) return false;

    saving = true;
    notifyListeners();

    final session = TrainingSession(
      id: '',
      kind: SessionKind.kracht,
      title: title,
      startedAt: _startedAt,
      durationMinutes: elapsed.inMinutes,
      glucoseSeries: series,
      exercises: exercises
          .where((e) => e.sets.any((s) => s.done))
          .map(
            (e) => ExerciseEntry(
              name: e.name,
              sets: e.sets
                  .where((s) => s.done)
                  .map(
                    (s) => ExerciseSet(
                      kg: s.kg,
                      reps: s.reps,
                      done: true,
                      seconds: s.seconds,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
      nutrition: nutrition,
      circuits: circuits.map((lc) => lc.circuit).toList(),
    );
    try {
      await SessionRepository(client).create(session, userId);
      return true;
    } catch (_) {
      // Sessie blijft in de UI beschikbaar; de gebruiker kan het opnieuw
      // proberen door de trainingen-tab te verversen.
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
