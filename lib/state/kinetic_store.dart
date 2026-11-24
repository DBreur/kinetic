// kinetic_store.dart: de centrale app-state, het Flutter-equivalent van
// `useKineticStore.ts` uit de spec. Eén ChangeNotifier voor telemetrie
// (Dexcom/Polar), fight prep, sparring-timer, voeding en focus-technieken.
//
// Alles wat de gebruiker vastlegt (maaltijden, inwegingen, sessies, focus,
// vingerprik) gaat direct naar Supabase. De UI wordt meteen bijgewerkt met
// de opgeslagen rij, zodat macrobarometer en gewichtscurve live meebewegen.
// Puur lokale zaken (vocht, checklist, macrodoelen, timerinstellingen) staan
// in SharedPreferences.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/app_config.dart';
import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/iob.dart';
import '../core/meal_impact.dart';
import '../core/sparring_timer.dart';
import '../models/competition.dart';
import '../models/food_log_entry.dart';
import '../models/glucose.dart';
import '../models/kinetic_profile.dart';
import '../models/technique.dart';
import '../models/training_session.dart';
import '../models/weigh_in.dart';
import '../repositories/food_log_repository.dart';
import '../repositories/kinetic_repositories.dart';
import '../repositories/weigh_in_repository.dart';
import '../services/dexcom_credentials.dart';
import '../services/glucose_provider.dart';
import '../services/heart_rate_source.dart';
import '../services/nightscout_credentials.dart';
import '../services/telemetry_export.dart';

enum BootState { loading, needsConfig, signedOut, ready }

/// Tabs van de bottom navigation (index 2 is de centrale '+').
abstract final class KTab {
  static const vandaag = 0;
  static const training = 1;
  static const technieken = 3;
  static const eten = 4;
}

/// Sleutels van het T1D-weegprotocol.
const weighInChecklistKeys = ['hydration', 'glycogen', 'calibration'];

class KineticStore extends ChangeNotifier with WidgetsBindingObserver {
  KineticStore({
    DateTime Function()? clock,
    HeartRateSource? heartRateSource,
    this.enableWakelock = true,
  }) : now = clock ?? DateTime.now,
       heartRate = heartRateSource ?? SimulatedPolarH10();

  /// Injecteerbare klok (tests en screenshots).
  final DateTime Function() now;
  final HeartRateSource heartRate;
  final bool enableWakelock;

  SupabaseClient? _client;
  SharedPreferences? _prefs;

  // ---------------------------------------------------------------- boot/auth
  BootState state = BootState.loading;
  String? authError;
  bool busy = false;
  KineticProfile? profile;
  String? _demoEmail;

  User? get user => _client?.auth.currentUser;
  String? get email => _demoEmail ?? user?.email;
  String? get _uid => profile?.id ?? user?.id;
  bool get isConnected => _client != null;

  DateTime? lastSyncAt;
  String? syncError;

  Future<void> boot() async {
    state = BootState.loading;
    notifyListeners();
    _prefs = await SharedPreferences.getInstance();
    _loadLocalPrefs();
    if (!AppConfig.hasSupabase) {
      state = BootState.needsConfig;
      notifyListeners();
      return;
    }
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
    _client = Supabase.instance.client;
    WidgetsBinding.instance.addObserver(this);
    _client!.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut ||
          event.event == AuthChangeEvent.signedIn) {
        _onAuthChanged();
      }
    });
    await _onAuthChanged();
  }

  Future<void> _onAuthChanged() async {
    final u = _client?.auth.currentUser;
    if (u == null) {
      profile = null;
      _stopPolling();
      state = BootState.signedOut;
      notifyListeners();
      return;
    }
    if (state == BootState.ready && profile?.id == u.id) return;
    try {
      profile = await ProfileRepository(_client!).getOrCreate(u.id);
      state = BootState.ready;
      notifyListeners();
      await _restoreSparring();
      await refreshAll();
      _startPolling();
    } catch (e) {
      authError = 'Je profiel kon niet worden geladen. Probeer opnieuw in te loggen.';
      state = BootState.signedOut;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) => _auth(() async {
    await _client!.auth.signInWithPassword(email: email.trim(), password: password);
  });

  /// true = meteen ingelogd, false = bevestigingsmail verstuurd.
  Future<bool?> register(String email, String password) async {
    bool? signedIn;
    await _auth(() async {
      final res = await _client!.auth.signUp(email: email.trim(), password: password);
      signedIn = res.session != null;
    });
    return signedIn;
  }

  Future<bool> resetPassword(String email) async {
    var ok = false;
    await _auth(() async {
      await _client!.auth.resetPasswordForEmail(email.trim());
      ok = true;
    });
    return ok;
  }

  Future<void> signOut() async {
    if (sparring != null) await finishSparring(save: false);
    await _client?.auth.signOut();
  }

  Future<void> _auth(Future<void> Function() action) async {
    busy = true;
    authError = null;
    notifyListeners();
    try {
      await action();
    } on AuthException catch (e) {
      authError = _friendlyAuthError(e);
    } catch (_) {
      authError = 'Geen verbinding met Supabase. Controleer je internet.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static String _friendlyAuthError(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'E-mail of wachtwoord klopt niet.';
    if (m.contains('not confirmed')) return 'Bevestig eerst je e-mailadres via de link in je mail.';
    if (m.contains('already registered')) return 'Er bestaat al een account met dit e-mailadres.';
    if (m.contains('rate limit')) return 'Te veel pogingen. Wacht even en probeer opnieuw.';
    return e.message;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && this.state == BootState.ready) {
      unawaited(refreshGlucose());
      _onTick();
    }
  }

  // ------------------------------------------------------------- navigatie
  int tab = KTab.vandaag;
  bool _mealSheetRequested = false;

  void selectTab(int index) {
    if (index == 2 || index == tab) return;
    tab = index;
    notifyListeners();
  }

  /// "Eten & Carbs" / "Snelle Carbs": naar Eten en daar meteen de sheet open.
  void requestMealSheet() {
    tab = KTab.eten;
    _mealSheetRequested = true;
    notifyListeners();
  }

  bool consumeMealSheetRequest() {
    final r = _mealSheetRequested;
    _mealSheetRequested = false;
    return r;
  }

  Future<void> refreshAll() async {
    final uid = _uid;
    final c = _client;
    if (uid == null || c == null) return;
    try {
      final start = dayStart(now());
      final results = await Future.wait([
        FoodLogRepository(c).listForUser(uid, since: start.subtract(const Duration(days: 7))),
        WeighInRepository(c).listForUser(uid),
        CompetitionRepository(c).upcoming(uid),
        TechniqueRepository(c).listForUser(uid),
        SessionRepository(c).listForUser(uid),
      ]);
      foodEntries = results[0] as List<FoodLogEntry>;
      weighIns = results[1] as List<WeighIn>;
      competitions = results[2] as List<Competition>;
      techniques = results[3] as List<Technique>;
      sessions = results[4] as List<TrainingSession>;
      _draftWeightKg = null;
      loadChecklist();
      lastSyncAt = now();
      syncError = null;
    } catch (e) {
      syncError = 'Synchronisatie met Supabase mislukt.';
    }
    notifyListeners();
    await refreshGlucose();
  }

  // -------------------------------------------------------------- telemetrie
  GlucoseSnapshot? glucose;
  List<GlucosePoint> glucoseHistory = const [];
  DateTime? lastGlucoseFetch;
  Timer? _poller;
  Future<void>? _glucoseInFlight;
  GlucoseProvider? _provider;
  String? _providerKey;

  GlucoseReading? get reading => glucose?.reading;

  /// Rood alarm in de app: actuele meting onder de hypogrens.
  bool get hypoAlert {
    final r = reading;
    return r != null && !r.isStale && r.mmol < hypoBelow;
  }

  bool get glucoseConfigured =>
      profile != null && profile!.glucoseSource != GlucoseSource.finger;

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 60), (_) => refreshGlucose());
  }

  void _stopPolling() {
    _poller?.cancel();
    _poller = null;
  }

  Future<void> refreshGlucose() {
    return _glucoseInFlight ??= _fetchGlucose().whenComplete(() => _glucoseInFlight = null);
  }

  Future<void> _fetchGlucose() async {
    final p = profile;
    if (p == null) return;
    final from = now().subtract(const Duration(hours: 12));
    if (p.glucoseSource == GlucoseSource.finger) {
      final c = _client;
      if (c == null) return;
      try {
        final points = await GlucoseEntryRepository(c).since(p.id, from);
        glucoseHistory = points;
        if (points.isEmpty) {
          glucose = const GlucoseSnapshot(reading: null, history: [], message: 'Nog geen vingerprik vandaag.');
        } else {
          final last = points.last;
          final prev = points.length > 1 ? points[points.length - 2] : null;
          glucose = GlucoseSnapshot(
            reading: GlucoseReading(
              last.mmol,
              prev == null ? Trend.flat : trendFromDelta(last.mmol - prev.mmol),
              last.at,
            ),
            history: points,
          );
        }
      } catch (_) {}
    } else {
      final key = '${p.glucoseSource.name}|${p.dexcomUsername}|${p.dexcomServer}|${p.nightscoutUrl}';
      if (_provider == null || _providerKey != key) {
        _provider = await resolveGlucoseProvider(p);
        _providerKey = key;
      }
      final provider = _provider;
      if (provider == null) {
        glucose = const GlucoseSnapshot.unconfigured();
      } else {
        final snap = await provider.fetch(count: 144);
        glucose = snap;
        if (snap.history.isNotEmpty) {
          glucoseHistory = snap.history.where((g) => g.at.isAfter(from)).toList();
        }
      }
    }
    lastGlucoseFetch = now();
    _sampleSessionGlucose();
    notifyListeners();
  }

  /// Insuline actief, geschat uit het eetlogboek.
  double get iob => insulinOnBoard(
    foodEntries
        .where((e) => (e.insulinUnits ?? 0) > 0)
        .map((e) => InsulinDose(e.at, e.insulinUnits!)),
    now: now(),
  );

  int get heartRateBpm => heartRate.bpm;
  HeartRateZone get currentHeartRateZone => heartRateZone(heartRate.bpm);

  /// Vingerprik vastleggen (Sensor Kalibratie-check). Geeft het verschil met
  /// de CGM terug, of null als er geen recente CGM-waarde was.
  Future<double?> addFingerstick(double mmol) async {
    final uid = _uid;
    final c = _client;
    final cgm = reading;
    if (uid != null && c != null) {
      await GlucoseEntryRepository(c).add(uid, mmol, now());
    }
    if (profile?.glucoseSource == GlucoseSource.finger) await refreshGlucose();
    if (cgm == null || cgm.isStale) return null;
    return mmol - cgm.mmol;
  }

  // ------------------------------------------------------------------ voeding
  List<FoodLogEntry> foodEntries = const [];
  double carbsTarget = 210;
  double proteinTarget = 170;
  double fatTarget = 65;

  List<FoodLogEntry> get todayEntries {
    final start = dayStart(now());
    return foodEntries.where((e) => !e.at.isBefore(start)).toList();
  }

  double _sum(double? Function(FoodLogEntry) f) =>
      todayEntries.fold(0.0, (s, e) => s + (f(e) ?? 0));

  double get carbsToday => _sum((e) => e.carbs);
  double get proteinToday => _sum((e) => e.protein);
  double get fatToday => _sum((e) => e.fat);
  double get carbsRemaining => carbsTarget - carbsToday;

  Future<FoodLogEntry?> logFood({
    required String description,
    double? carbs,
    double? protein,
    double? fat,
    MealContext? context,
    double? insulinUnits,
  }) async {
    final uid = _uid;
    final c = _client;
    final r = reading;
    final mmol = (r != null && !r.isStale) ? double.parse(r.mmol.toStringAsFixed(1)) : null;
    FoodLogEntry entry;
    if (uid == null || c == null) {
      entry = FoodLogEntry(
        id: 'local-${now().microsecondsSinceEpoch}',
        at: now(),
        description: description,
        carbs: carbs,
        protein: protein,
        fat: fat,
        context: context,
        mmol: mmol,
        insulinUnits: insulinUnits,
      );
    } else {
      try {
        entry = await FoodLogRepository(c).create(
          userId: uid,
          at: now(),
          description: description,
          carbs: carbs,
          protein: protein,
          fat: fat,
          context: context,
          mmol: mmol,
          insulinUnits: insulinUnits,
        );
        lastSyncAt = now();
      } catch (_) {
        syncError = 'Maaltijd kon niet worden opgeslagen.';
        notifyListeners();
        return null;
      }
    }
    foodEntries = [entry, ...foodEntries];
    notifyListeners();
    return entry;
  }

  Future<bool> deleteFood(FoodLogEntry entry) async {
    final c = _client;
    try {
      if (c != null && !entry.id.startsWith('local-')) {
        await FoodLogRepository(c).delete(entry.id);
      }
      foodEntries = foodEntries.where((e) => e.id != entry.id).toList();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setMacroTargets({double? carbs, double? protein, double? fat}) async {
    if (carbs != null) carbsTarget = carbs;
    if (protein != null) proteinTarget = protein;
    if (fat != null) fatTarget = fat;
    await _prefs?.setString('macro_targets', jsonEncode({
      'carbs': carbsTarget, 'protein': proteinTarget, 'fat': fatTarget,
    }));
    notifyListeners();
  }

  // ------------------------------------------------------------------- vocht
  int waterMlToday = 0;
  String get _waterKey => 'water_${dayStart(now()).toIso8601String().substring(0, 10)}';

  Future<void> addWater(int ml) async {
    waterMlToday = (waterMlToday + ml).clamp(0, 20000);
    await _prefs?.setInt(_waterKey, waterMlToday);
    notifyListeners();
  }

  // ----------------------------------------------------- gewicht & fight prep
  List<WeighIn> weighIns = const [];
  List<Competition> competitions = const [];
  double? _draftWeightKg;
  Map<String, bool> _checklist = {};

  Competition? get nextCompetition =>
      competitions.isEmpty ? null : competitions.first;

  double? get currentWeightKg =>
      weighIns.isNotEmpty ? weighIns.first.weightKg : profile?.weightKg;

  double? get targetWeightKg => nextCompetition?.effectiveTargetKg;

  /// Gewicht in de inweeg-calculator (begint bij de laatste weging).
  double get draftWeightKg => _draftWeightKg ?? currentWeightKg ?? 75.0;

  void adjustWeight(double delta) {
    _draftWeightKg = double.parse((draftWeightKg + delta).clamp(20.0, 300.0).toStringAsFixed(1));
    notifyListeners();
  }

  Future<bool> registerWeight() async {
    final kg = draftWeightKg;
    final uid = _uid;
    final c = _client;
    WeighIn saved;
    try {
      if (uid == null || c == null) {
        saved = WeighIn(id: 'local-${now().microsecondsSinceEpoch}', measuredAt: now(), weightKg: kg);
      } else {
        saved = await WeighInRepository(c).create(
          WeighIn(id: '', measuredAt: now(), weightKg: kg),
          uid,
        );
        // Het actuele gewicht staat ook in profiles.weight_kg (zoals in de
        // oude app), voor de gewichtsklasse bij wedstrijden.
        await ProfileRepository(c).updateFields(uid, {'weight_kg': kg});
        lastSyncAt = now();
      }
    } catch (_) {
      syncError = 'Weging kon niet worden opgeslagen.';
      notifyListeners();
      return false;
    }
    weighIns = [saved, ...weighIns]..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    profile = profile?.copyWith(weightKg: kg);
    _draftWeightKg = null;
    notifyListeners();
    return true;
  }

  Future<bool> setTargetWeight(double? kg) async {
    final comp = nextCompetition;
    final c = _client;
    if (comp == null) return false;
    try {
      if (c != null) await CompetitionRepository(c).setTargetWeight(comp.id, kg);
    } catch (_) {
      return false;
    }
    competitions = [
      for (final x in competitions)
        x.id == comp.id
            ? Competition(
                id: x.id,
                name: x.name,
                startsAt: x.startsAt,
                discipline: x.discipline,
                location: x.location,
                weightClass: x.weightClass,
                weightLimitType: x.weightLimitType,
                weightLimitKg: x.weightLimitKg,
                targetWeightKg: kg,
              )
            : x,
    ];
    notifyListeners();
    return true;
  }

  String get _checklistKey => 'checklist_${nextCompetition?.id ?? 'none'}';

  bool checklistDone(String key) => _checklist[key] ?? false;
  int get checklistCount => weighInChecklistKeys.where(checklistDone).length;

  Future<void> toggleChecklist(String key) async {
    _checklist = {..._checklist, key: !checklistDone(key)};
    await _prefs?.setString(_checklistKey, jsonEncode(_checklist));
    notifyListeners();
  }

  // -------------------------------------------------------------- technieken
  List<Technique> techniques = const [];

  List<Technique> get focusTechniques => techniques.where((t) => t.isInFocus).toList();

  Future<bool> toggleFocus(Technique t) async {
    final on = !t.isInFocus;
    final c = _client;
    try {
      if (c != null) await TechniqueRepository(c).setFocus(t.id, on);
    } catch (_) {
      return false;
    }
    techniques = [
      for (final x in techniques) x.id == t.id ? x.copyWith(focusMode: on ? 'next' : 'none') : x,
    ];
    notifyListeners();
    return true;
  }

  Future<Technique?> createTechnique(String name, TechniqueGroup group) async {
    final uid = _uid;
    final c = _client;
    try {
      final t = (uid == null || c == null)
          ? Technique(id: 'local-${now().microsecondsSinceEpoch}', name: name, category: group.defaultCategory)
          : await TechniqueRepository(c).create(uid, name, group.defaultCategory);
      techniques = [...techniques, t];
      notifyListeners();
      return t;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- sessies
  List<TrainingSession> sessions = const [];

  /// Minuten op de mat vandaag (opgeslagen sessies + lopende sessie).
  int get matMinutesToday {
    final start = dayStart(now());
    final saved = sessions
        .where((s) => !s.startedAt.isBefore(start))
        .fold(0, (sum, s) => sum + s.durationMinutes);
    final live = sparring == null ? 0 : now().difference(sparring!.startedAt).inMinutes;
    return saved + live;
  }

  int get kcalToday => estimateKcal(
    minutes: matMinutesToday,
    weightKg: currentWeightKg ?? 75,
  );

  // ----------------------------------------------------------------- sparring
  SparringConfig sparringConfig = const SparringConfig();
  SparringTimer? sparring;
  List<String> sessionTechniqueIds = const [];
  Map<String, TechniqueCounts> sessionCounts = {};
  List<GlucosePoint> sessionGlucose = [];
  Map<int, String> coachFocus = {};
  List<String> voiceMemos = [];
  int? _hrAtRestStart;
  DateTime? _restStartedAt;
  Timer? _ticker;

  /// Laatste fase-overgang, voor schermnavigatie (live ↔ rust).
  final ValueNotifier<SparringEvent?> sparringEvents = ValueNotifier(null);

  bool get isSparringActive => sparring != null && !sparring!.isDone;
  int get roundSecondsRemaining => sparring?.remaining(now()) ?? 0;

  List<Technique> get sessionTechniques => [
    for (final id in sessionTechniqueIds)
      ...techniques.where((t) => t.id == id),
  ];

  /// Herstelsnelheid in de rust: BPM-verschil sinds het begin van de rust.
  (int delta, int seconds)? get heartRateRecovery {
    final start = _hrAtRestStart;
    final at = _restStartedAt;
    if (start == null || at == null) return null;
    return (heartRate.bpm - start, now().difference(at).inSeconds);
  }

  MatClearance clearanceForNextRound() {
    final t = sparring;
    final next = t == null ? 1 : (t.phase == SparringPhase.rest ? t.round + 1 : t.round);
    return matClearance(
      reading: reading,
      roundLabel: 'R$next',
      trainingLimit: profile?.trainingLimit ?? 5.0,
      now: now(),
    );
  }

  Future<void> setSparringConfig(SparringConfig config) async {
    sparringConfig = config;
    await _prefs?.setString('sparring_config', jsonEncode(config.toJson()));
    notifyListeners();
  }

  void startSparring() {
    if (isSparringActive) return;
    final t = now();
    sparring = SparringTimer(config: sparringConfig, now: t);
    sessionTechniqueIds = focusTechniques.map((x) => x.id).toList();
    sessionCounts = {for (final id in sessionTechniqueIds) id: const TechniqueCounts()};
    sessionGlucose = [];
    coachFocus = {};
    voiceMemos = [];
    _hrAtRestStart = null;
    _restStartedAt = null;
    _sampleSessionGlucose();
    _startTicker();
    if (enableWakelock) unawaited(WakelockPlus.enable().catchError((_) {}));
    unawaited(refreshGlucose());
    _persistSparring();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    final t = sparring;
    heartRate.update(t == null || t.isPaused ? null : t.phase, now());
    if (t == null) return;
    final event = t.tick(now(), holdRest: clearanceForNextRound().blocksNextRound);
    if (event != null) _onSparringEvent(event);
    notifyListeners();
  }

  void _onSparringEvent(SparringEvent e) {
    if (e == SparringEvent.restStarted) {
      _hrAtRestStart = heartRate.bpm;
      _restStartedAt = now();
    }
    if (e == SparringEvent.finished) _stopTicker();
    _persistSparring();
    sparringEvents.value = e;
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void toggleSparringTimer() {
    sparring?.togglePause(now());
    _persistSparring();
    notifyListeners();
  }

  /// VOLGENDE: huidige ronde afronden en naar de rust (of afronden).
  void advanceToRestPhase() {
    final t = sparring;
    if (t == null || t.phase != SparringPhase.work) return;
    t.toRest(now());
    _onSparringEvent(t.isDone ? SparringEvent.finished : SparringEvent.restStarted);
    notifyListeners();
  }

  void addRestSeconds(int seconds) {
    sparring?.addRest(seconds, now());
    _persistSparring();
    notifyListeners();
  }

  void startNextRound() {
    final t = sparring;
    if (t == null || t.isDone) return;
    t.startNextRound(now());
    _hrAtRestStart = null;
    _restStartedAt = null;
    _onSparringEvent(SparringEvent.roundStarted);
    notifyListeners();
  }

  void incrementTechniqueStat(String id, TechniqueStat stat, {int delta = 1}) {
    final current = sessionCounts[id] ?? const TechniqueCounts();
    sessionCounts = {...sessionCounts, id: current.add(stat, delta)};
    _persistSparring();
    notifyListeners();
  }

  /// Techniek tijdens de sessie toevoegen aan of weghalen uit de mat-tellers.
  void toggleSessionTechnique(String id) {
    if (sessionTechniqueIds.contains(id)) {
      sessionTechniqueIds = sessionTechniqueIds.where((x) => x != id).toList();
    } else {
      sessionTechniqueIds = [...sessionTechniqueIds, id];
      sessionCounts = {...sessionCounts, id: sessionCounts[id] ?? const TechniqueCounts()};
    }
    _persistSparring();
    notifyListeners();
  }

  void setCoachFocus(int round, String text) {
    coachFocus = {...coachFocus, round: text};
    _persistSparring();
    notifyListeners();
  }

  /// Standaardinstructie: combineer de focus-technieken.
  String coachFocusFor(int round) {
    final custom = coachFocus[round];
    if (custom != null && custom.trim().isNotEmpty) return custom;
    final names = sessionTechniques.map((t) => t.name).toList();
    if (names.isEmpty) return 'Tik om een instructie voor ronde $round te noteren';
    return names.take(2).join(' ➔ ');
  }

  void addVoiceMemo(String path) {
    voiceMemos = [...voiceMemos, path];
    _persistSparring();
    notifyListeners();
  }

  void _sampleSessionGlucose() {
    final r = reading;
    if (sparring == null || r == null || r.isStale) return;
    if (sessionGlucose.isNotEmpty && !r.at.isAfter(sessionGlucose.last.at)) return;
    sessionGlucose = [...sessionGlucose, GlucosePoint(r.at, r.mmol)];
    _persistSparring();
  }

  /// Rondt de sessie af. Met [save] gaat hij als training naar Supabase.
  Future<TrainingSession?> finishSparring({bool save = true}) async {
    final t = sparring;
    if (t == null) return null;
    final end = now();
    if (!t.isDone) t.finish(end);
    _stopTicker();
    if (enableWakelock) unawaited(WakelockPlus.disable().catchError((_) {}));
    TrainingSession? saved;
    if (save) {
      final minutes = end.difference(t.startedAt).inMinutes.clamp(1, 24 * 60);
      final roundsDone = t.round;
      final blocks = <Map<String, dynamic>>[
        {
          'kind': 'sparring',
          'name': 'Live sparring',
          'meta': t.config.summary,
          'note': '',
          'rounds': roundsDone,
          'minutes': (roundsDone * t.config.workSeconds / 60).round(),
          'round_minutes': List.filled(roundsDone, (t.config.workSeconds / 60).round()),
          'rest_seconds': List.filled(roundsDone > 1 ? roundsDone - 1 : 0, t.config.restSeconds),
          'covered': true,
          'logged_at': end.toUtc().toIso8601String(),
        },
        for (final tech in sessionTechniques)
          {
            'kind': 'technique',
            'name': tech.name,
            'meta': tech.category,
            'note': _countsNote(tech, sessionCounts[tech.id] ?? const TechniqueCounts()),
            'covered': true,
            'reps': (sessionCounts[tech.id] ?? const TechniqueCounts()).total,
            'counts': (sessionCounts[tech.id] ?? const TechniqueCounts()).toJson(),
            'striking': tech.group.isStriking,
            'logged_at': end.toUtc().toIso8601String(),
          },
      ];
      final notes = <String>[
        for (final e in coachFocus.entries) 'R${e.key}: ${e.value}',
        if (voiceMemos.isNotEmpty) '${voiceMemos.length} spraakmemo(s) lokaal op dit toestel',
      ];
      final session = TrainingSession(
        id: '',
        kind: 'sambo',
        title: 'Live sparring',
        startedAt: t.startedAt,
        durationMinutes: minutes,
        note: notes.join('\n'),
        glucoseSeries: sessionGlucose,
        blocks: blocks,
      );
      final uid = _uid;
      final c = _client;
      try {
        saved = (uid == null || c == null)
            ? session
            : await SessionRepository(c).create(session, uid);
        sessions = [saved, ...sessions];
        lastSyncAt = now();
      } catch (_) {
        syncError = 'Sessie kon niet worden opgeslagen.';
        saved = null;
      }
    }
    sparring = null;
    sparringEvents.value = null;
    await _prefs?.remove('sparring_state');
    notifyListeners();
    return saved;
  }

  static String _countsNote(Technique t, TechniqueCounts c) {
    final s = t.group.isStriking;
    return [
      for (final stat in TechniqueStat.values) '${statLabel(stat, striking: s)} ${c[stat]}',
    ].join(' · ');
  }

  void _persistSparring() {
    final t = sparring;
    final prefs = _prefs;
    if (t == null || prefs == null) return;
    unawaited(prefs.setString('sparring_state', jsonEncode({
      'timer': t.toJson(),
      'techniques': sessionTechniqueIds,
      'counts': sessionCounts.map((k, v) => MapEntry(k, v.toJson())),
      'glucose': sessionGlucose.map((g) => g.toJson()).toList(),
      'coach': coachFocus.map((k, v) => MapEntry('$k', v)),
      'memos': voiceMemos,
    })));
  }

  /// Herstelt een sessie die nog liep toen de app werd afgesloten.
  Future<void> _restoreSparring() async {
    final raw = _prefs?.getString('sparring_state');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final t = SparringTimer.fromJson(j['timer'] as Map<String, dynamic>);
      if (t.isDone || now().difference(t.startedAt) > const Duration(hours: 4)) {
        await _prefs?.remove('sparring_state');
        return;
      }
      sparring = t;
      sessionTechniqueIds = ((j['techniques'] as List?) ?? []).cast<String>();
      sessionCounts = ((j['counts'] as Map?) ?? {}).map(
        (k, v) => MapEntry(k as String, TechniqueCounts.fromJson(v as Map<String, dynamic>)),
      );
      sessionGlucose = [
        for (final g in (j['glucose'] as List?) ?? []) GlucosePoint.fromJson(g as Map<String, dynamic>),
      ];
      coachFocus = ((j['coach'] as Map?) ?? {}).map((k, v) => MapEntry(int.parse(k as String), v as String));
      voiceMemos = ((j['memos'] as List?) ?? []).cast<String>();
      _startTicker();
      if (enableWakelock) unawaited(WakelockPlus.enable().catchError((_) {}));
    } catch (_) {
      await _prefs?.remove('sparring_state');
    }
  }

  // -------------------------------------------------------- instellingen
  Future<bool> saveGlucoseSettings({
    required GlucoseSource source,
    String? dexcomUsername,
    String? dexcomPassword,
    String? dexcomServer,
    String? nightscoutUrl,
    String? nightscoutToken,
  }) async {
    final p = profile;
    final c = _client;
    if (p == null) return false;
    try {
      if (dexcomPassword != null && dexcomPassword.isNotEmpty) {
        await DexcomCredentials.write(dexcomPassword);
      }
      if (nightscoutToken != null) await NightscoutCredentials.write(nightscoutToken);
      final next = p.copyWith(
        glucoseSource: source,
        dexcomUsername: dexcomUsername?.trim(),
        dexcomServer: dexcomServer?.trim(),
        nightscoutUrl: nightscoutUrl?.trim(),
        nightscoutToken: nightscoutToken?.trim(),
      );
      if (c != null) {
        await ProfileRepository(c).updateFields(p.id, {
          'glucose_source': next.glucoseSource.dbName,
          'dexcom_username': next.dexcomUsername,
          'dexcom_server': next.dexcomServer,
          'nightscout_url': next.nightscoutUrl,
        });
      }
      profile = next;
      _provider = null;
      _providerKey = null;
      notifyListeners();
      await refreshGlucose();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------- export
  /// Alle data vanaf [since] (null = alles), vers uit Supabase. Glucose
  /// combineert vingerprikken, de reeksen uit sessies en de CGM-tijdlijn.
  Future<ExportData> collectExport({DateTime? since}) async {
    bool inRange(DateTime t) => since == null || !t.isBefore(since);
    final uid = _uid;
    final c = _client;
    var meals = foodEntries;
    var weights = weighIns;
    var allSessions = sessions;
    var finger = const <GlucosePoint>[];
    if (uid != null && c != null) {
      final r = await Future.wait([
        FoodLogRepository(c).listForUser(uid, since: since),
        WeighInRepository(c).listForUser(uid, limit: 2000),
        SessionRepository(c).listForUser(uid),
        GlucoseEntryRepository(c).since(uid, since ?? DateTime(2000)),
      ]);
      meals = r[0] as List<FoodLogEntry>;
      weights = r[1] as List<WeighIn>;
      allSessions = r[2] as List<TrainingSession>;
      finger = r[3] as List<GlucosePoint>;
    }
    final glucoseByTime = <DateTime, GlucosePoint>{
      for (final g in [
        ...finger,
        ...allSessions.expand((s) => s.glucoseSeries),
        ...glucoseHistory,
      ])
        if (inRange(g.at)) g.at: g,
    };
    final glucosePoints = glucoseByTime.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    return ExportData(
      meals: meals.where((e) => inRange(e.at)).toList(),
      weighIns: weights.where((w) => inRange(w.measuredAt)).toList(),
      sessions: allSessions.where((s) => inRange(s.startedAt)).toList(),
      glucose: glucosePoints,
    );
  }

  // ------------------------------------------------------------ lokaal
  void _loadLocalPrefs() {
    final prefs = _prefs;
    if (prefs == null) return;
    waterMlToday = prefs.getInt(_waterKey) ?? 0;
    try {
      final m = prefs.getString('macro_targets');
      if (m != null) {
        final j = jsonDecode(m) as Map<String, dynamic>;
        carbsTarget = (j['carbs'] as num).toDouble();
        proteinTarget = (j['protein'] as num).toDouble();
        fatTarget = (j['fat'] as num).toDouble();
      }
      final s = prefs.getString('sparring_config');
      if (s != null) sparringConfig = SparringConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {}
  }

  /// Checklist hoort bij de eerstvolgende wedstrijd; laden na refreshAll.
  void loadChecklist() {
    try {
      final raw = _prefs?.getString(_checklistKey);
      _checklist = raw == null
          ? {}
          : (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as bool));
    } catch (_) {
      _checklist = {};
    }
  }

  // ------------------------------------------------------- demo/screenshots
  /// Vult de store met data zonder Supabase (tests en design-screenshots).
  @visibleForTesting
  void seedForPreview({
    required KineticProfile profile,
    GlucoseSnapshot? glucose,
    List<FoodLogEntry> food = const [],
    List<WeighIn> weighIns = const [],
    List<Competition> competitions = const [],
    List<Technique> techniques = const [],
    List<TrainingSession> sessions = const [],
    int waterMl = 0,
    String? email,
  }) {
    this.profile = profile;
    this.glucose = glucose;
    glucoseHistory = glucose?.history ?? const [];
    foodEntries = food;
    this.weighIns = weighIns;
    this.competitions = competitions;
    this.techniques = techniques;
    this.sessions = sessions;
    waterMlToday = waterMl;
    _demoEmail = email;
    loadChecklist();
    lastSyncAt = now();
    lastGlucoseFetch = now();
    state = BootState.ready;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPolling();
    _stopTicker();
    WidgetsBinding.instance.removeObserver(this);
    sparringEvents.dispose();
    super.dispose();
  }
}
