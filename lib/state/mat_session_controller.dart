// mat_session_controller.dart — houdt een live sambo-sessie draaiend, ook als
// je naar een ander tabblad navigeert. Bewust géén State-object: dit is een
// gewoon Dart-object dat door ShellScreen wordt vastgehouden zolang de sessie
// actief is, zodat de klok, de Nightscout-polling en het glucose-alarm
// gewoon doorlopen terwijl MatModeScreen niet gemount is.

import 'dart:async';
import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/combination.dart';
import '../core/session_glucose.dart';
import '../models/glucose.dart';
import '../models/glucose_entry.dart';
import '../models/technique.dart';
import '../models/training_session.dart';
import '../repositories/combination_repository.dart';
import '../repositories/glucose_entry_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/technique_repository.dart';
import '../services/alarm_notification_service.dart';
import '../services/glucose_provider.dart';
import '../state/app_controller.dart';
import '../state/live_session_controller.dart';
import '../widgets/block_widgets.dart';
import '../widgets/glucose_alarm.dart';
import '../widgets/manual_glucose.dart';

class MatSessionController extends ChangeNotifier
    implements LiveSessionController {
  MatSessionController({
    required this.title,
    required this.appController,
    required this.contextOf,
    this.provider,
    List<TechniqueEntry> planned = const [],
    GlucoseReading? initialReading,
    DateTime? startedAt,
    Duration pausedAccum = Duration.zero,
    DateTime? pauseStartedAt,
    List<GlucosePoint> restoredSeries = const [],
    List<NutritionEntry> restoredNutrition = const [],
  }) {
    blocks = List<TechniqueEntry>.from(planned);
    for (final b in blocks) {
      b.ensureRoundsSynthesized();
    }
    reading = initialReading ?? GlucoseReading(7.4, Trend.flat, DateTime.now());
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
      notifyListeners();
    });
    // Elke minuut kijken: een sensor meet elke ~5 minuten, zo zie je een
    // nieuwe waarde binnen een minuut (in plaats van tot 5 minuten later).
    _poller = Timer.periodic(
      const Duration(minutes: 1),
      (_) => refreshReading(),
    );
    refreshReading();
    _loadKnownTechniques();
    _loadKnownCombinations();
    if (isFinger) _loadFingerEntries();
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
  bool saving = false;
  @override
  bool isPaused = false;

  late GlucoseReading reading;
  final List<GlucosePoint> series = [];

  late List<TechniqueEntry> blocks;
  String mode = 'list'; // list | focus
  int focusIndex = 0;
  bool adding = false;
  List<Technique> knownTechniques = [];
  List<Combination> knownCombinations = [];
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

  Future<void> _loadKnownTechniques() async {
    final userId = appController.user?.id;
    final client = appController.client;
    if (userId == null || client == null) return;
    try {
      final techniques = await TechniqueRepository(client).listForUser(userId);
      knownTechniques = techniques;
      notifyListeners();
    } catch (_) {
      // Autocomplete blijft leeg; typen van een nieuwe naam werkt gewoon.
    }
  }

  Future<void> _loadKnownCombinations() async {
    final userId = appController.user?.id;
    final client = appController.client;
    if (userId == null || client == null) return;
    try {
      final combos = await CombinationRepository(client).listForUser(userId);
      knownCombinations = combos;
      notifyListeners();
    } catch (_) {
      // Combinaties blijven leeg; losse technieken loggen werkt gewoon.
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
      // Meting telt al mee in deze sessie; de log op de "Nu"-pagina kan
      // hem missen als dit mislukt, maar dat blokkeert de training niet.
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

  // ── lijst: wat heb je vanavond gedaan ─────────────────────────────────────

  List<int> get coveredIdx => [
    for (var i = 0; i < blocks.length; i++)
      if (blocks[i].covered) i,
  ];

  void openFocus(int i) {
    blocks[i].covered = true;
    blocks[i].loggedAt ??= DateTime.now();
    focusIndex = i;
    mode = 'focus';
    notifyListeners();
  }

  void toggleCovered(int i) {
    final next = !blocks[i].covered;
    blocks[i].covered = next;
    if (next) blocks[i].loggedAt ??= DateTime.now();
    notifyListeners();
  }

  void removeBlockAt(int i) {
    blocks.removeAt(i);
    notifyListeners();
  }

  void insertBlockAt(int i, TechniqueEntry entry) {
    blocks.insert(i.clamp(0, blocks.length), entry);
    notifyListeners();
  }

  void addBlock(TechniqueEntry entry, {required bool openAfter}) {
    blocks.add(entry);
    adding = false;
    if (openAfter) {
      focusIndex = blocks.length - 1;
      mode = 'focus';
    }
    notifyListeners();
  }

  void setAdding(bool value) {
    adding = value;
    notifyListeners();
  }

  /// Zet een techniek op een andere plek tussen de andere technieken —
  /// warming-up/sparren blijven op hun eigen plek staan. [oldIndex]/
  /// [newIndex] zijn indices binnen de subset van technieken, zoals
  /// ReorderableListView.onReorderItem ze doorgeeft (newIndex is al
  /// gecorrigeerd voor het verwijderde item op oldIndex).
  void reorderTechnique(int oldIndex, int newIndex) {
    final techIdx = [
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].kind == BlockKind.technique) i,
    ];
    final moved = blocks.removeAt(techIdx[oldIndex]);
    final techIdxAfter = [
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].kind == BlockKind.technique) i,
    ];
    final target = newIndex >= techIdxAfter.length
        ? blocks.length
        : techIdxAfter[newIndex];
    blocks.insert(target, moved);
    notifyListeners();
  }

  void backToList() {
    mode = 'list';
    notifyListeners();
  }

  void nextFocus() {
    final covered = coveredIdx;
    final pos = covered.indexOf(focusIndex);
    if (pos >= 0 && pos < covered.length - 1) {
      focusIndex = covered[pos + 1];
      notifyListeners();
    } else {
      backToList();
    }
  }

  void prevFocus() {
    final covered = coveredIdx;
    final pos = covered.indexOf(focusIndex);
    if (pos > 0) {
      focusIndex = covered[pos - 1];
      notifyListeners();
    } else {
      backToList();
    }
  }

  void touch() => notifyListeners();

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
    ..._snapshotBase('sambo'),
    'blocks': blocks.map((b) => b.toBlock().toJson()).toList(),
  };

  /// Bouwt een sessie terug uit [toSnapshot].
  factory MatSessionController.restore(
    Map<String, dynamic> json, {
    required AppController appController,
    required BuildContext Function() contextOf,
    GlucoseProvider? provider,
  }) => MatSessionController(
    title: (json['title'] as String?) ?? 'Combat sambo',
    appController: appController,
    contextOf: contextOf,
    provider: provider,
    planned: [
      for (final b in (json['blocks'] as List? ?? const []))
        TechniqueEntry.fromBlock(SessionBlock.fromJson(b as Map<String, dynamic>)),
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

  // ── opslaan ────────────────────────────────────────────────────────────────

  Future<bool> saveSession(String note) async {
    final userId = appController.user?.id;
    final client = appController.client;
    if (userId == null || client == null) return false;

    saving = true;
    notifyListeners();

    final covered = blocks.where((t) => t.covered).toList();
    final session = TrainingSession(
      id: '',
      kind: SessionKind.sambo,
      title: title,
      startedAt: _startedAt,
      durationMinutes: elapsed.inMinutes,
      note: note,
      glucoseSeries: series,
      blocks: covered.map((t) => t.toBlock()).toList(),
      nutrition: nutrition,
    );
    try {
      final techniqueRepo = TechniqueRepository(client);
      final knownNames = knownTechniques.map((t) => t.name).toSet();
      final newNames = covered
          .where((t) => t.kind == BlockKind.technique && !t.catalogLinked)
          .map((t) => t.name)
          .where((name) => !knownNames.contains(name))
          .toSet();
      await SessionRepository(client).create(session, userId);
      for (final name in newNames) {
        final source = covered.firstWhere((t) => t.name == name);
        await techniqueRepo.create(
          Technique(
            id: '',
            name: name,
            category: source.meta.split(' · ').first.isNotEmpty
                ? source.meta.split(' · ').first
                : 'Overig',
          ),
          userId,
        );
      }
      // Een geplande techniek die in deze sessie behandeld is, gaat van
      // "gepland" naar "bezig met leren".
      final coveredTechniqueNames = covered
          .where((b) => b.kind == BlockKind.technique)
          .map((b) => b.name)
          .toList();
      for (final t in techniquesToStartLearning(
        knownTechniques,
        coveredTechniqueNames,
      )) {
        await techniqueRepo.updateContent(
          t.copyWith(
            learningStatus: LearningStatus.learning,
            learningStartedAt: t.learningStartedAt ?? DateTime.now(),
          ),
        );
      }
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
