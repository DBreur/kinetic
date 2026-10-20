// strength_session_controller.dart — houdt een live krachttraining draaiend,
// ook als je naar een ander tabblad navigeert. Zelfde opzet als
// mat_session_controller.dart: een gewoon Dart-object dat door ShellScreen
// wordt vastgehouden zolang de sessie actief is, zodat de klok, de
// Nightscout-polling en het glucose-alarm gewoon doorlopen terwijl
// StrengthModeScreen niet gemount is.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../core/rest_blocks.dart';
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

/// Standaard rusttijd tussen sets als er geen profiel is — normaal komt die
/// uit de instellingen (AppProfile.defaultRestSeconds).
const defaultRestFallback = 90;

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

  /// "Tot verzuring" — zie [ExerciseSet.toBurn].
  bool toBurn;
  String extraTarget;
  int? extraReps;

  /// Gelukt / niet gelukt (null = niet aangegeven), met waarom.
  bool? completed;
  String note;

  LiveSet({
    this.kg = 0,
    this.reps = 8,
    this.seconds,
    this.toBurn = false,
    this.extraTarget = '',
    this.extraReps,
    this.completed,
    this.note = '',
  });

  SetMode get mode => toBurn
      ? SetMode.burn
      : seconds != null
      ? SetMode.time
      : SetMode.reps;

  /// Nieuwe set met dezelfde opzet (gewicht, reps/tijd/verzuring) — zonder
  /// uitkomst, voor "+ set" en "vorige keer".
  factory LiveSet.like(ExerciseSet s) => LiveSet(
    kg: s.kg,
    reps: s.reps,
    seconds: s.seconds,
    toBurn: s.toBurn,
    extraTarget: s.extraTarget,
  );

  /// Volledige kopie inclusief uitkomst (gepland of hersteld na afsluiten).
  factory LiveSet.from(ExerciseSet s) => LiveSet(
    kg: s.kg,
    reps: s.reps,
    seconds: s.seconds,
    toBurn: s.toBurn,
    extraTarget: s.extraTarget,
    extraReps: s.extraReps,
    completed: s.completed,
    note: s.note,
  )..done = s.done;

  ExerciseSet toExerciseSet() => ExerciseSet(
    kg: kg,
    reps: reps,
    done: done,
    seconds: seconds,
    toBurn: toBurn,
    extraTarget: extraTarget,
    extraReps: extraReps,
    completed: completed,
    note: note,
  );

  /// Telt mee bij opslaan: afgevinkt, of je hebt er iets over genoteerd
  /// (ook "niet gelukt, want ..." is het bewaren waard).
  bool get worthSaving => done || completed != null || note.isNotEmpty;
}

enum SetMode { reps, time, burn }

/// Een lopende tijd-set (of zijn voorbereiding), voor de aftelbalk bovenin.
class ActiveTimedSet {
  final int exerciseIndex;
  final int setIndex;
  final String name;
  final bool preparing;
  final Duration left;
  final Duration total;
  const ActiveTimedSet({
    required this.exerciseIndex,
    required this.setIndex,
    required this.name,
    required this.preparing,
    required this.left,
    required this.total,
  });
}

class LiveExercise implements BlockMember {
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

  /// Zie [ExerciseEntry.block] en [ExerciseEntry.restSeconds].
  @override
  int? block;
  @override
  int? restSeconds;
  LiveExercise({
    required this.name,
    required this.sets,
    this.lastPerformance,
    this.personalRecord,
    this.description = '',
    this.block,
    this.restSeconds,
  });

  ExerciseEntry toEntry({bool onlyWorthSaving = false}) => ExerciseEntry(
    name: name,
    sets: [
      for (final s in sets)
        if (!onlyWorthSaving || s.worthSaving) s.toExerciseSet(),
    ],
    block: block,
    restSeconds: restSeconds,
  );
}

enum CircuitPhase { prep, work, rest }

/// Een circuit zoals het live in een sessie draait — begint met [startCircuit]
/// en schakelt daarna zelf automatisch door (voorbereiden → werk → rust →
/// volgende oefening → volgende ronde → volgend blok), aangestuurd vanuit
/// [StrengthSessionController]'s bestaande 1s-ticker.
class LiveCircuit {
  final Circuit circuit;

  /// Ronde binnen het huidige deel (blok), vanaf 0.
  int round = 0;
  int exerciseIndex = 0;
  int segmentIndex = 0;
  CircuitPhase phase = CircuitPhase.work;
  bool isRunning = false;
  bool isDone = false;
  bool isPaused = false;
  final IntervalTimer timer = IntervalTimer();

  /// Seconden aftellen vóór elke oefening (halters afstellen) — gezet door
  /// de controller uit de instellingen. 0 = meteen beginnen.
  int prepSeconds = 0;

  /// Lengte van de lopende rust (verschilt per stap) — voor de voortgangsbalk.
  int restTotal = 0;

  LiveCircuit(this.circuit);

  late final List<CircuitStep> steps = circuit.effectiveSteps;
  late final List<CircuitSegment> segments = circuit.segments;

  CircuitSegment get segment => segments[segmentIndex];

  CircuitStep? get currentStep =>
      exerciseIndex < steps.length ? steps[exerciseIndex] : null;
  String get currentExerciseName => currentStep?.name ?? '';

  /// De oefening die na de huidige komt (voor tijdens rust en voorbereiden).
  CircuitStep? get nextStep {
    final next = _nextPosition();
    return next == null ? null : steps[next.$3];
  }

  /// Een herhalingen-stap ("10× push-up") telt niet af — je tikt "Klaar".
  bool get waitingForTap =>
      isRunning &&
      !isPaused &&
      phase == CircuitPhase.work &&
      currentStep?.isTimed == false;
  Duration get timeLeft => timer.remaining;

  /// Lengte van de lopende fase, voor de voortgangsbalk.
  int get phaseTotal => switch (phase) {
    CircuitPhase.prep => prepSeconds,
    CircuitPhase.rest => restTotal,
    CircuitPhase.work => currentStep?.seconds ?? circuit.workSeconds,
  };

  /// Begint (of herstart) het circuit bij het eerste deel.
  void start() {
    isRunning = true;
    isDone = false;
    isPaused = false;
    segmentIndex = 0;
    round = 0;
    exerciseIndex = 0;
    startStep();
  }

  /// Begint de huidige oefening: eerst voorbereiden (als ingesteld), dan
  /// werken.
  void startStep() {
    if (prepSeconds > 0) {
      phase = CircuitPhase.prep;
      timer.start(Duration(seconds: prepSeconds));
    } else {
      startWork();
    }
  }

  /// Start de werkfase van de huidige stap: aftellen bij een tijd-stap,
  /// wachten op "Klaar" bij een herhalingen-stap.
  void startWork() {
    phase = CircuitPhase.work;
    final step = currentStep;
    if (step != null && step.isTimed) {
      timer.start(Duration(seconds: step.seconds ?? circuit.workSeconds));
    } else {
      timer.cancel();
    }
  }

  void pause() {
    if (!isRunning || isPaused) return;
    timer.pause();
    isPaused = true;
  }

  void resume() {
    if (!isPaused) return;
    isPaused = false;
    timer.resume();
  }

  /// Volgende positie (deel, ronde, oefening), of null als dit de laatste
  /// oefening van het hele circuit was.
  (int, int, int)? _nextPosition() {
    final seg = segment;
    if (exerciseIndex < seg.end - 1) {
      return (segmentIndex, round, exerciseIndex + 1);
    }
    if (round < seg.rounds - 1) return (segmentIndex, round + 1, seg.start);
    if (segmentIndex < segments.length - 1) {
      return (segmentIndex + 1, 0, segments[segmentIndex + 1].start);
    }
    return null;
  }

  /// Zet het circuit één fase verder. Geeft `true` als het circuit klaar is.
  bool advance() {
    if (phase == CircuitPhase.prep) {
      startWork();
      return false;
    }
    final next = _nextPosition();
    if (phase == CircuitPhase.work) {
      if (next == null) {
        isRunning = false;
        isDone = true;
        timer.cancel();
        return true;
      }
      final rest = circuit.restAfter(exerciseIndex);
      if (rest > 0) {
        phase = CircuitPhase.rest;
        restTotal = rest;
        timer.start(Duration(seconds: rest));
        return false;
      }
    }
    // Rust is om (of er is geen rust ingesteld): door naar de volgende
    // oefening, ronde of blok.
    if (next == null) {
      isRunning = false;
      isDone = true;
      timer.cancel();
      return true;
    }
    segmentIndex = next.$1;
    round = next.$2;
    exerciseIndex = next.$3;
    startStep();
    return false;
  }
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
    this.circuitOnly = false,
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
            sets: e.sets.map(LiveSet.from).toList(),
            block: e.block,
            restSeconds: e.restSeconds,
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

  /// Losse circuittraining (gestart vanuit een circuit): alleen dat
  /// circuit, zonder knoppen om oefeningen of andere circuits toe te voegen.
  final bool circuitOnly;
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
  final IntervalTimer _rest = IntervalTimer();

  /// Voorbereiden vóór een tijd-set (bv. plank): eerst dit aftellen, dan
  /// start de klok van de set zelf.
  final IntervalTimer _setPrep = IntervalTimer();
  (int, int)? _prepFor;

  /// Lengte van de lopende rust (voor de voortgangsbalk) en wat er daarna
  /// komt, bv. "Ronde 2 · Goblet squat".
  int restTotal = defaultRestFallback;
  String? restNext;
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

  /// Resterende rust in seconden, live herberekend (kloktijd) zodat hij net
  /// als [elapsed] doorloopt ook als het scherm even uit is geweest.
  int get restLeft => _rest.remaining.inSeconds;

  /// De tijd-set die nu loopt of zich voorbereidt — voor de grote
  /// aftelbalk bovenin. Null als er geen loopt.
  ActiveTimedSet? get activeTimedSet {
    final prep = _prepFor;
    if (prep != null && _setPrep.isRunning) {
      final e = exercises[prep.$1];
      return ActiveTimedSet(
        exerciseIndex: prep.$1,
        setIndex: prep.$2,
        name: e.name,
        preparing: true,
        left: _setPrep.remaining,
        total: Duration(seconds: prepSeconds),
      );
    }
    for (var ei = 0; ei < exercises.length; ei++) {
      final sets = exercises[ei].sets;
      for (var si = 0; si < sets.length; si++) {
        final set = sets[si];
        if (set._timerStarted && !set.done && set.timerRunning) {
          return ActiveTimedSet(
            exerciseIndex: ei,
            setIndex: si,
            name: exercises[ei].name,
            preparing: false,
            left: set.timeLeft,
            total: Duration(seconds: set.seconds ?? 0),
          );
        }
      }
    }
    return null;
  }

  /// Voorbereidingstijd vóór een tijd-set of circuitoefening (instelling).
  int get prepSeconds => appController.profile?.circuitPrepSeconds ?? 0;

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

  /// Circuits die door de sessiepauze zijn stilgezet (niet die je zelf al
  /// had gepauzeerd) — alleen die gaan bij hervatten weer lopen.
  final Set<LiveCircuit> _pausedBySession = {};

  void pause() {
    if (isPaused) return;
    _pauseStartedAt = DateTime.now();
    isPaused = true;
    // Alles wat aftelt staat stil: rust, voorbereiden, tijd-sets, circuits.
    _rest.pause();
    _setPrep.pause();
    for (final e in exercises) {
      for (final set in e.sets) {
        set._timer.pause();
      }
    }
    for (final lc in circuits) {
      if (lc.isRunning && !lc.isPaused) {
        lc.pause();
        _pausedBySession.add(lc);
      }
    }
    notifyListeners();
  }

  void resume() {
    if (!isPaused) return;
    _pausedAccum += DateTime.now().difference(_pauseStartedAt!);
    _pauseStartedAt = null;
    isPaused = false;
    _rest.resume();
    _setPrep.resume();
    for (final e in exercises) {
      for (final set in e.sets) {
        set._timer.resume();
      }
    }
    for (final lc in _pausedBySession) {
      lc.resume();
    }
    _pausedBySession.clear();
    notifyListeners();
    // Meteen een verse waarde: tijdens de pauze lag de app vaak stil.
    refreshReading();
  }

  /// Het laden van de catalogus — [ensureCustomExercise] wacht hierop, anders
  /// denkt hij dat een oefening nog niet bestaat terwijl de lijst er gewoon
  /// nog niet is (zo ontstonden er bij elke trainingsstart kopieën).
  Future<void>? _customLoad;

  /// Oefeningen die nu worden aangemaakt (op naam, kleine letters) — twee
  /// gelijktijdige aanroepen voor dezelfde naam maken er maar één.
  final Map<String, Future<void>> _creating = {};

  Future<void> _loadCustomExercises() => _customLoad ??= _fetchCustomExercises();

  Future<void> _fetchCustomExercises() async {
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
      // Zelfde vergelijking als de database: hoofdletters en spaties aan
      // het begin/eind tellen niet.
      if (e.name.trim().toLowerCase() == name.trim().toLowerCase()) return e;
    }
    return null;
  }

  /// Video's voor een stap in een circuit: die van de stap zelf, anders die
  /// van de oefening met dezelfde naam in je oefeningen.
  List<String> videosForStep(CircuitStep step) => step.videoUrls.isNotEmpty
      ? step.videoUrls
      : (matchingCustomExercise(step.name)?.videoUrls ?? const []);

  /// Bewaart een video bij oefening [name] in je oefeningen (en maakt die
  /// oefening aan als hij er nog niet is), zodat hij er ook de volgende
  /// keer bij staat.
  Future<void> addExerciseVideo(String name, String url) async {
    final client = appController.client;
    if (client == null) return;
    await ensureCustomExercise(name);
    final existing = matchingCustomExercise(name);
    if (existing == null || existing.videoUrls.contains(url)) return;
    try {
      final saved = await ExerciseRepository(client).updateContent(
        existing.copyWith(videoUrls: [...existing.videoUrls, url]),
      );
      customExercises = [
        for (final e in customExercises) e.id == saved.id ? saved : e,
      ];
      notifyListeners();
    } catch (_) {
      // Video blijft in deze sessie zichtbaar in het paneel; opslaan in de
      // catalogus kan later vanuit de oefeningenlijst.
    }
  }

  /// Slaat een net getypte, nog onbekende naam op in de oefeningcatalogus,
  /// zodat je 'm later een beschrijving kunt geven en hij in de lijst blijft
  /// staan voor volgende trainingen.
  Future<void> ensureCustomExercise(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _loadCustomExercises();
    if (matchingCustomExercise(trimmed) != null) return;
    if (kExerciseLibrary.any((n) => n.toLowerCase() == trimmed.toLowerCase())) {
      return;
    }
    final key = trimmed.toLowerCase();
    final running = _creating[key];
    if (running != null) return running;
    final future = _createCustomExercise(trimmed);
    _creating[key] = future;
    try {
      await future;
    } finally {
      _creating.remove(key);
    }
  }

  Future<void> _createCustomExercise(String name) async {
    final userId = appController.user?.id;
    final client = appController.client;
    if (userId == null || client == null) return;
    try {
      final created = await ExerciseRepository(client)
          .create(Exercise(id: '', name: name), userId);
      customExercises = [...customExercises, created];
      notifyListeners();
    } catch (_) {
      // Bestaat al (de database staat geen dubbele namen toe — bv. net op
      // een ander toestel aangemaakt): de lijst opnieuw ophalen. Anders
      // telt de oefening gewoon mee in deze sessie, zonder catalogus.
      _customLoad = null;
      await _loadCustomExercises();
    }
  }

  Future<void> _loadFingerEntries() async {
    final userId = appController.user?.id;
    final client = appController.client;
    if (userId == null || client == null) return;
    try {
      final entries = await GlucoseEntryRepository(client)
          .recentForUser(userId);
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
      final entry = await GlucoseEntryRepository(client)
          .create(userId, value, now);
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
    // Ook de rest van de app (topbalk, Eten) de nieuwste waarde geven.
    appController.offerGlucoseReading(latest);
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
    final history = await SessionRepository(client)
        .performanceHistory(userId, name);
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
            ? last.map(LiveSet.like).toList()
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
    _normalizeBlocks();
    notifyListeners();
  }

  /// Haalt één set weg, ook midden in een lopende training.
  void removeSet(int ei, int si) {
    final sets = exercises[ei].sets;
    if (si < 0 || si >= sets.length) return;
    sets.removeAt(si);
    notifyListeners();
  }

  // ── rust en blokken ────────────────────────────────────────────────────────

  int get defaultRest =>
      appController.profile?.defaultRestSeconds ?? defaultRestFallback;

  List<int?> get _blocks => [for (final e in exercises) e.block];

  /// Bereik van het blok waar oefening [ei] in zit (los = alleen zichzelf).
  ({int start, int end}) blockOf(int ei) => blockRange(_blocks, ei);

  /// Rust na een set van [ei] (los) of na een ronde van zijn blok.
  int restAfter(int ei) => restAfterIn(exercises, ei, defaultRest);

  /// Koppelt oefening [ei] aan de oefening erboven: samen één blok.
  void linkWithPrevious(int ei) {
    linkWithPreviousIn(exercises, ei);
    notifyListeners();
  }

  /// Haalt oefening [ei] uit zijn blok.
  void unlink(int ei) {
    unlinkIn(exercises, ei);
    notifyListeners();
  }

  /// Zet de rust van het hele blok waar [ei] in zit (of van de losse
  /// oefening). Null = terug naar de standaard.
  void setRest(int ei, int? seconds) {
    setBlockRestIn(exercises, ei, seconds);
    notifyListeners();
  }

  void _normalizeBlocks() => normalizeBlocksIn(exercises);

  /// Na het afvinken van set [si] van [ei]: rust, maar in een blok pas als
  /// set [si] van álle oefeningen in het blok af is (de ronde is klaar).
  void _restAfterSet(int ei, int si) {
    final r = blockOf(ei);
    for (var i = r.start; i < r.end; i++) {
      final sets = exercises[i].sets;
      if (si < sets.length && !sets[si].done) return;
    }
    final inBlock = r.end - r.start > 1;
    String? next;
    if (inBlock) {
      final more = [
        for (var i = r.start; i < r.end; i++)
          if (exercises[i].sets.length > si + 1) i,
      ];
      if (more.isNotEmpty) {
        next = 'Ronde ${si + 2} · ${exercises[more.first].name}';
      }
    } else if (exercises[ei].sets.length > si + 1) {
      next = 'Set ${si + 2} · ${exercises[ei].name}';
    }
    if (next == null && r.end < exercises.length) {
      next = 'Volgende: ${exercises[r.end].name}';
    }
    _startRestTimer(restAfter(ei), next: next);
  }

  void addSet(int i) {
    final sets = exercises[i].sets;
    sets.add(
      sets.isEmpty ? LiveSet() : LiveSet.like(sets.last.toExerciseSet()),
    );
    notifyListeners();
  }

  /// Zet een set om naar reps, tijd of "tot verzuring" — reps en gewicht
  /// blijven staan.
  void setSetMode(int ei, int si, SetMode mode) {
    final set = exercises[ei].sets[si];
    set.seconds = mode == SetMode.time ? (set.seconds ?? 30) : null;
    set.toBurn = mode == SetMode.burn;
    if (!set.toBurn) set.extraReps = null;
    notifyListeners();
  }

  void updateSet(int ei, int si, LiveSet Function(LiveSet) patch) {
    final exercise = exercises[ei];
    final sets = exercise.sets;
    final wasDone = sets[si].done;
    sets[si] = patch(sets[si]);
    final set = sets[si];
    if (wasDone != set.done) {
      // De klok van een tijd-set hoort bij één poging: afgevinkt (door de
      // klok of met de hand) of weer uitgevinkt — dan is hij klaar. Anders
      // vinkt _checkSetTimers een uitgevinkte set meteen weer aan.
      set._timer.cancel();
      set._timerStarted = false;
      if (_prepFor == (ei, si)) {
        _prepFor = null;
        _setPrep.cancel();
      }
    }
    if (!wasDone && set.done) {
      _restAfterSet(ei, si);
      _checkNewRecord(exercise, set.kg);
    }
    notifyListeners();
  }

  /// Start de aftelklok van een tijd-gebaseerde set (bv. een plank van 45s)
  /// — bij het aflopen wordt de set automatisch afgevinkt via hetzelfde pad
  /// als handmatig afvinken, dus de rust-timer gaat daarna gewoon aan.
  void startSetTimer(int ei, int si) {
    final set = exercises[ei].sets[si];
    if (set.seconds == null || set.done) return;
    if (prepSeconds > 0) {
      _prepFor = (ei, si);
      _setPrep.start(Duration(seconds: prepSeconds));
    } else {
      _startSetClock(set);
    }
    notifyListeners();
  }

  void _startSetClock(LiveSet set) {
    final seconds = set.seconds;
    if (seconds == null) return;
    set._timer.start(Duration(seconds: seconds));
    set._timerStarted = true;
  }

  /// Een lopende tijd-set (of zijn voorbereiding) stoppen zonder af te
  /// vinken.
  void stopSetTimer() {
    _prepFor = null;
    _setPrep.cancel();
    for (final e in exercises) {
      for (final set in e.sets) {
        if (set._timerStarted && !set.done) {
          set._timer.cancel();
          set._timerStarted = false;
        }
      }
    }
    notifyListeners();
  }

  /// Voorbereiden overslaan: de klok van de set zelf begint meteen.
  void skipSetPrep() {
    final prep = _prepFor;
    if (prep == null) return;
    _prepFor = null;
    _setPrep.cancel();
    if (prep.$1 < exercises.length &&
        prep.$2 < exercises[prep.$1].sets.length) {
      _startSetClock(exercises[prep.$1].sets[prep.$2]);
    }
    notifyListeners();
  }

  /// Vinkt een tijd-gebaseerde set automatisch af zodra de aftelklok (die
  /// met [startSetTimer] is gestart) op nul staat.
  void _checkSetTimers() {
    // Voorbereiding om? Dan begint de klok van de set zelf.
    final prep = _prepFor;
    if (prep != null && !_setPrep.isRunning && !isPaused) {
      _prepFor = null;
      HapticFeedback.mediumImpact();
      if (prep.$1 < exercises.length &&
          prep.$2 < exercises[prep.$1].sets.length) {
        _startSetClock(exercises[prep.$1].sets[prep.$2]);
      }
    }
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
    if (lc.steps.isEmpty) return;
    // Zonder profiel (bv. in tests) geen voorbereiding; anders de instelling
    // (standaard 10 s).
    lc.prepSeconds = prepSeconds;
    lc.start();
    notifyListeners();
  }

  void stopCircuit(int i) {
    final lc = circuits[i];
    lc.isRunning = false;
    lc.isPaused = false;
    lc.timer.cancel();
    notifyListeners();
  }

  /// Zet een lopend circuit stil of laat het verder lopen — de aftelklok
  /// gaat verder waar hij was.
  void togglePauseCircuit(int i) {
    final lc = circuits[i];
    if (lc.isPaused) {
      lc.resume();
    } else {
      lc.pause();
    }
    notifyListeners();
  }

  /// Handmatig naar de volgende fase — zelfde geest als [skipRest].
  void skipCircuitPhase(int i) {
    final lc = circuits[i];
    if (!lc.isRunning) return;
    if (lc.isPaused) lc.resume();
    _advanceCircuit(lc);
    notifyListeners();
  }

  /// Schakelt elk lopend circuit automatisch door zodra de huidige fase is
  /// afgelopen, met een trilsignaal bij elke overgang — zodat je niet op je
  /// telefoon hoeft te tikken middenin een burpee.
  void _checkCircuitTimers() {
    for (final lc in circuits) {
      if (lc.isRunning &&
          !lc.isDone &&
          !lc.isPaused &&
          !lc.waitingForTap &&
          !lc.timer.isRunning) {
        _advanceCircuit(lc);
      }
    }
  }

  void _advanceCircuit(LiveCircuit lc) {
    HapticFeedback.mediumImpact();
    lc.advance();
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
    _normalizeBlocks();
    notifyListeners();
  }

  void _startRestTimer(int seconds, {String? next}) {
    _restTimer?.cancel();
    if (seconds <= 0) {
      _rest.cancel();
      return;
    }
    restTotal = seconds;
    restNext = next;
    _rest.start(Duration(seconds: seconds));
    if (isPaused) _rest.pause();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_rest.isRunning) {
        _rest.cancel();
        _restTimer?.cancel();
      }
      notifyListeners();
    });
  }

  void skipRest() {
    _restTimer?.cancel();
    _rest.cancel();
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
    'circuitOnly': circuitOnly,
    'exercises': [for (final e in exercises) e.toEntry().toJson()],
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
    circuitOnly: (json['circuitOnly'] as bool?) ?? false,
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
    pausedAccum: Duration(
      milliseconds: (json['pausedAccumMs'] as num?)?.toInt() ?? 0,
    ),
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
          .where((e) => e.sets.any((s) => s.worthSaving))
          .map((e) => e.toEntry(onlyWorthSaving: true))
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
