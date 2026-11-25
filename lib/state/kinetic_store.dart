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
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/app_config.dart';
import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/iob.dart';
import '../core/meal_impact.dart';
import '../core/preset_text.dart';
import '../core/sparring_timer.dart';
import '../core/training_blocks.dart';
import '../models/combination.dart';
import '../models/competition.dart';
import '../models/food_log_entry.dart';
import '../models/food_preset.dart';
import '../models/glucose.dart';
import '../models/kinetic_profile.dart';
import '../models/library.dart';
import '../models/live_training.dart';
import '../models/planned_training.dart';
import '../models/technique.dart';
import '../models/technique_system.dart';
import '../models/training_session.dart';
import '../models/weigh_in.dart';
import '../repositories/food_log_repository.dart';
import '../repositories/kinetic_repositories.dart';
import '../repositories/system_repository.dart';
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

  /// Gebruikersnaam uit het profiel, anders het deel voor de @.
  String get displayName {
    final u = profile?.username.trim() ?? '';
    if (u.isNotEmpty) return u;
    final local = (email ?? '').split('@').first;
    if (local.isEmpty) return '';
    final word = local
        .split(RegExp(r'[._\-0-9]+'))
        .firstWhere((w) => w.isNotEmpty, orElse: () => local);
    return word[0].toUpperCase() + word.substring(1);
  }

  String get initials {
    final n = displayName.trim();
    if (n.isEmpty) return 'K';
    final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    return parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : (parts.first[0] + parts.last[0]).toUpperCase();
  }

  // ------------------------------------------------------------------ thema
  /// Dark = "Kinetic Metabolic Combat", light = "Kinetic". Standaard donker.
  /// Apart luisterbaar, zodat alleen een themawissel de app herbouwt.
  final ValueNotifier<bool> darkModeNotifier = ValueNotifier(true);
  bool get darkMode => darkModeNotifier.value;
  set darkMode(bool v) => darkModeNotifier.value = v;

  Future<void> toggleTheme() async {
    darkMode = !darkMode;
    await _prefs?.setString('theme_mode', darkMode ? 'dark' : 'light');
    notifyListeners();
  }

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
      await _restoreTraining();
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
    if (training != null) await finishTraining(save: false);
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
        CompetitionRepository(c).all(uid),
        PlannedTrainingRepository(c).upcoming(uid, start),
        SystemRepository(c).listForUser(uid),
        CombinationRepository(c).listForUser(uid).catchError((_) => const <Combination>[]),
      ]);
      foodEntries = results[0] as List<FoodLogEntry>;
      weighIns = results[1] as List<WeighIn>;
      competitions = results[2] as List<Competition>;
      techniques = results[3] as List<Technique>;
      sessions = results[4] as List<TrainingSession>;
      allCompetitions = results[5] as List<Competition>;
      plannedTrainings = results[6] as List<PlannedTraining>;
      systems = results[7] as List<TechniqueSystem>;
      combinations = results[8] as List<Combination>;
      if (library.isEmpty) {
        try {
          library = await LibraryRepository(c).techniques();
        } catch (_) {}
      }
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
    return r != null && !r.isStaleAt(now()) && r.mmol < hypoBelow;
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
    // Zonder Supabase (tests/screenshots) blijft de geseede data staan.
    if (p == null || _client == null) return;
    final from = now().subtract(const Duration(hours: 24));
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
        final snap = await provider.fetch(count: 288);
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
    if (cgm == null || cgm.isStaleAt(now())) return null;
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
    Map<String, int> presetCounts = const {},
  }) async {
    final uid = _uid;
    final c = _client;
    final r = reading;
    final mmol = (r != null && !r.isStaleAt(now())) ? double.parse(r.mmol.toStringAsFixed(1)) : null;
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
        presetCounts: presetCounts,
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
          presetCounts: presetCounts,
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

  /// Wedstrijd in beide lijsten (komend + alles) vervangen of toevoegen.
  void _replaceCompetition(Competition c) {
    List<Competition> put(List<Competition> list) {
      final has = list.any((x) => x.id == c.id);
      return has ? [for (final x in list) x.id == c.id ? c : x] : [...list, c];
    }

    final today = dayStart(now());
    final upcoming = !c.startsAt.isBefore(today);
    competitions = (upcoming ? put(competitions) : competitions.where((x) => x.id != c.id).toList())
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    allCompetitions = put(allCompetitions)..sort((a, b) => b.startsAt.compareTo(a.startsAt));
  }

  /// Nieuwe wedstrijd (id leeg) of bestaande aanpassen.
  Future<Competition?> saveCompetition(Competition c) async {
    final uid = _uid;
    final client = _client;
    try {
      final Competition saved;
      if (c.id.isEmpty) {
        saved = (uid == null || client == null)
            ? c.copyWith(id: 'local-${now().microsecondsSinceEpoch}')
            : await CompetitionRepository(client).create(uid, c);
      } else {
        saved = (client == null || c.id.startsWith('local')) ? c : await CompetitionRepository(client).update(c);
      }
      _replaceCompetition(saved);
      loadChecklist();
      notifyListeners();
      return saved;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteCompetition(Competition c) async {
    try {
      final client = _client;
      if (client != null && !c.id.startsWith('local')) await CompetitionRepository(client).delete(c.id);
    } catch (_) {
      return false;
    }
    competitions = competitions.where((x) => x.id != c.id).toList();
    allCompetitions = allCompetitions.where((x) => x.id != c.id).toList();
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
    _replaceCompetition(comp.copyWith(targetWeightKg: kg, clearTarget: kg == null));
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

  // ------------------------------------------------ video's, notities, beoordeling

  Map<String, String> get videoLabels => profile?.videoLabels ?? const {};

  /// Titel van een video: eigen titel, anders "Video 1", "Video 2"...
  String videoTitle(String url, int index) {
    final l = videoLabels[url]?.trim() ?? '';
    return l.isEmpty ? 'Video ${index + 1}' : l;
  }

  /// Techniek lokaal én in Supabase bijwerken.
  Future<bool> _patchTechnique(String id, Map<String, dynamic> fields, Technique Function(Technique t) local) async {
    try {
      final c = _client;
      if (c != null && !id.startsWith('local')) await TechniqueRepository(c).updateFields(id, fields);
    } catch (_) {
      return false;
    }
    techniques = [for (final x in techniques) x.id == id ? local(x) : x];
    notifyListeners();
    return true;
  }

  Technique? _technique(String id) => techniques.where((t) => t.id == id).firstOrNull;

  Future<bool> setVideoLabel(String url, String label) async {
    final p = profile;
    if (p == null) return false;
    final next = {...p.videoLabels};
    if (label.trim().isEmpty) {
      next.remove(url);
    } else {
      next[url] = label.trim();
    }
    try {
      final c = _client;
      if (c != null) await ProfileRepository(c).updateFields(p.id, {'video_labels': next});
    } catch (_) {
      return false;
    }
    profile = p.copyWith(videoLabels: next);
    notifyListeners();
    return true;
  }

  Future<bool> addTechniqueVideo(String techniqueId, String url, {String label = ''}) async {
    final t = _technique(techniqueId);
    if (t == null || t.videoUrls.contains(url)) return t != null;
    final urls = [...t.videoUrls, url];
    final ok = await _patchTechnique(techniqueId, {'video_urls': urls}, (x) => x.copyWith(videoUrls: urls));
    if (ok && label.trim().isNotEmpty) await setVideoLabel(url, label);
    return ok;
  }

  Future<bool> removeTechniqueVideo(String techniqueId, String url) async {
    final t = _technique(techniqueId);
    if (t == null) return false;
    final urls = t.videoUrls.where((u) => u != url).toList();
    final ok = await _patchTechnique(techniqueId, {'video_urls': urls, 'video_url': ''}, (x) => x.copyWith(videoUrls: urls));
    if (ok && url.startsWith(storageVideoPrefix)) await deleteOwnVideo(url);
    return ok;
  }

  /// Algemene notities bij een techniek (kolom `description`).
  Future<bool> setTechniqueNotes(String techniqueId, String notes) =>
      _patchTechnique(techniqueId, {'description': notes.trim()}, (x) => x.copyWith(description: notes.trim()));

  /// Beoordeling (sterren, wat ging goed/minder, notitie) toevoegen.
  Future<bool> addTechniqueReview(String techniqueId, TechniqueUpdate review) async {
    final t = _technique(techniqueId);
    if (t == null) return false;
    final updates = [...t.updates, review];
    return _patchTechnique(
      techniqueId,
      {'updates': [for (final u in updates) u.toJson()]},
      (x) => x.copyWith(updates: updates),
    );
  }

  Future<bool> deleteTechniqueReview(String techniqueId, TechniqueUpdate review) async {
    final t = _technique(techniqueId);
    if (t == null) return false;
    final updates = t.updates.where((u) => !identical(u, review)).toList();
    return _patchTechnique(
      techniqueId,
      {'updates': [for (final u in updates) u.toJson()]},
      (x) => x.copyWith(updates: updates),
    );
  }

  // ------------------------------------------------------------ combinaties
  List<Combination> combinations = const [];

  Future<Combination?> saveCombination(Combination combo) async {
    final uid = _uid;
    final c = _client;
    try {
      Combination saved;
      if (combo.id.isEmpty) {
        saved = (uid == null || c == null)
            ? combo.copyWith(id: 'local-${now().microsecondsSinceEpoch}')
            : await CombinationRepository(c).create(uid, combo);
        combinations = [...combinations, saved];
      } else {
        if (c != null && !combo.id.startsWith('local')) await CombinationRepository(c).update(combo);
        saved = combo;
        combinations = [for (final x in combinations) x.id == combo.id ? combo : x];
      }
      combinations.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      notifyListeners();
      return saved;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteCombination(Combination combo) async {
    try {
      final c = _client;
      if (c != null && !combo.id.startsWith('local')) await CombinationRepository(c).delete(combo.id);
    } catch (_) {
      return false;
    }
    combinations = combinations.where((x) => x.id != combo.id).toList();
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------ eigen video's
  static const storageVideoPrefix = 'storage://technique-videos/';

  /// Uploadt een videobestand naar de privé-bucket `technique-videos` en
  /// geeft de interne link terug (`storage://technique-videos/<uid>/...`).
  Future<String?> uploadOwnVideo(List<int> bytes, String extension) async {
    final uid = _uid;
    final c = _client;
    if (uid == null || c == null) return null;
    final path = '$uid/${now().millisecondsSinceEpoch}.${extension.toLowerCase()}';
    try {
      await c.storage.from('technique-videos').uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: FileOptions(contentType: 'video/${extension.toLowerCase() == 'mov' ? 'quicktime' : 'mp4'}'),
      );
      return '$storageVideoPrefix$path';
    } catch (_) {
      return null;
    }
  }

  /// Tijdelijke (1 uur) afspeellink voor een eigen video.
  Future<String?> signedVideoUrl(String url) async {
    final c = _client;
    if (c == null || !url.startsWith(storageVideoPrefix)) return null;
    try {
      return await c.storage.from('technique-videos').createSignedUrl(url.substring(storageVideoPrefix.length), 3600);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteOwnVideo(String url) async {
    final c = _client;
    if (c == null || !url.startsWith(storageVideoPrefix)) return;
    try {
      await c.storage.from('technique-videos').remove([url.substring(storageVideoPrefix.length)]);
    } catch (_) {}
  }

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

  /// De gedeelde bibliotheek (134 technieken).
  List<LibraryTechnique> library = const [];

  /// Alle technieken: eigen + bibliotheek (zie [buildVault]).
  List<VaultEntry> get vault => buildVault(techniques, library);

  /// Zorgt dat een vault-regel een eigen techniek heeft (kopie van de
  /// bibliotheek), zodat focus en herhalingen opgeslagen kunnen worden.
  Future<Technique?> ensureOwnTechnique(VaultEntry e) async {
    final own = e.own;
    if (own != null) return own;
    final lib = e.library!;
    final uid = _uid;
    final c = _client;
    try {
      final t = (uid == null || c == null)
          ? Technique(
              id: 'local-${now().microsecondsSinceEpoch}',
              name: lib.name,
              category: lib.category,
              description: lib.description,
              libraryId: lib.id,
            )
          : await TechniqueRepository(c).createFromLibrary(uid, lib);
      techniques = [...techniques, t];
      notifyListeners();
      return t;
    } catch (_) {
      return null;
    }
  }

  Future<bool> toggleVaultFocus(VaultEntry e) async {
    final t = await ensureOwnTechnique(e);
    if (t == null) return false;
    return toggleFocus(t);
  }

  /// "+1 Rep" (of meer) op een techniek in de vault.
  Future<bool> addVaultReps(VaultEntry e, {int reps = 1}) async {
    final t = await ensureOwnTechnique(e);
    if (t == null) return false;
    final c = _client;
    try {
      final saved = (c == null || t.id.startsWith('local-'))
          ? t.copyWith(loggedReps: t.loggedReps + reps)
          : await TechniqueRepository(c).addReps(t.id, reps, now());
      techniques = [for (final x in techniques) x.id == t.id ? saved : x];
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- systemen
  List<TechniqueSystem> systems = const [];

  /// Nieuw systeem (lege id) of bijwerken. Geeft de opgeslagen versie terug.
  Future<TechniqueSystem?> saveSystem(TechniqueSystem system) async {
    final uid = _uid;
    final c = _client;
    try {
      TechniqueSystem saved;
      if (uid == null || c == null) {
        saved = system.id.isEmpty
            ? TechniqueSystem(
                id: 'local-${now().microsecondsSinceEpoch}',
                name: system.name,
                notes: system.notes,
                nodes: system.nodes,
                edges: system.edges,
                tags: system.tags,
                favorite: system.favorite,
                createdAt: now(),
              )
            : system;
      } else {
        saved = system.id.isEmpty
            ? await SystemRepository(c).create(system, uid)
            : await SystemRepository(c).update(system);
      }
      final exists = systems.any((x) => x.id == saved.id);
      systems = exists
          ? [for (final x in systems) x.id == saved.id ? saved : x]
          : [saved, ...systems];
      notifyListeners();
      return saved;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteSystem(String id) async {
    final c = _client;
    try {
      if (c != null && !id.startsWith('local-')) await SystemRepository(c).delete(id);
      systems = systems.where((x) => x.id != id).toList();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------ agenda/planning
  List<PlannedTraining> plannedTrainings = const [];
  List<Competition> allCompetitions = const [];

  /// Eerstvolgende geplande training (ook als die net begonnen is).
  PlannedTraining? get nextPlannedTraining {
    final from = now().subtract(const Duration(hours: 2));
    for (final p in plannedTrainings) {
      if (p.startsAt.isAfter(from)) return p;
    }
    return null;
  }

  // ---------------------------------------------------------------- sessies
  List<TrainingSession> sessions = const [];

  /// CGM-punten in een tijdvak (voor het glucoseverloop van een training).
  List<GlucosePoint> glucoseBetween(DateTime from, DateTime to) => [
    for (final g in glucoseHistory)
      if (!g.at.isBefore(from) && !g.at.isAfter(to)) g,
  ];

  /// Training achteraf loggen ("Log Training"): discipline, focus, duur,
  /// RPE, technieken en notities. Het glucoseverloop komt uit de CGM-data
  /// van het tijdvak dat net is afgelopen.
  Future<TrainingSession?> logTrainingSession({
    required String discipline,
    required String focus,
    required int minutes,
    int? rpe,
    List<String> techniqueNames = const [],
    String notes = '',
  }) async {
    final end = now();
    final start = end.subtract(Duration(minutes: minutes));
    final strength = discipline.toLowerCase().contains('kracht') ||
        focus.toLowerCase().contains('condition');
    final session = TrainingSession(
      id: '',
      kind: strength ? 'kracht' : 'sambo',
      title: discipline,
      startedAt: start,
      durationMinutes: minutes,
      note: [
        'Focus: $focus${rpe == null ? '' : ' • RPE $rpe/5'}',
        if (notes.trim().isNotEmpty) notes.trim(),
      ].join('\n'),
      glucoseSeries: glucoseBetween(start, end),
      blocks: [
        if (focus.toLowerCase().contains('sparring'))
          {'kind': 'sparring', 'name': 'Sparring', 'meta': '', 'note': '', 'minutes': minutes, 'rounds': 0, 'covered': true},
        for (final n in techniqueNames)
          {'kind': 'technique', 'name': n, 'meta': '', 'note': '', 'covered': true, 'logged_at': end.toUtc().toIso8601String()},
      ],
    );
    final uid = _uid;
    final c = _client;
    try {
      final saved = (uid == null || c == null) ? session : await SessionRepository(c).create(session, uid);
      sessions = [saved, ...sessions]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      lastSyncAt = now();
      notifyListeners();
      return saved;
    } catch (_) {
      syncError = 'Training kon niet worden opgeslagen.';
      notifyListeners();
      return null;
    }
  }

  /// Minuten op de mat vandaag (opgeslagen sessies + lopende sessie).
  int get matMinutesToday {
    final start = dayStart(now());
    final saved = sessions
        .where((s) => !s.startedAt.isBefore(start))
        .fold(0, (sum, s) => sum + s.durationMinutes);
    final live = training == null ? 0 : (training!.elapsedSeconds(now()) ~/ 60);
    return saved + live;
  }

  int get kcalToday => estimateKcal(
    minutes: matMinutesToday,
    weightKg: currentWeightKg ?? 75,
  );

  // ----------------------------------------------------------------- training
  /// Standaard voor een nieuw sparblok (rondes × werk / rust).
  SparringConfig sparringConfig = const SparringConfig();

  /// De lopende training (null = geen training).
  LiveTraining? training;

  /// Rondeklok van het sparblok dat nu loopt (null = niet aan het sparren).
  SparringTimer? sparring;

  /// Rust tussen sparrondes als aflopende timer (instelling). Uit = de rust
  /// duurt tot je zelf de volgende ronde start.
  bool restTimerEnabled = true;

  int? _hrAtRestStart;
  DateTime? _restStartedAt;
  Timer? _ticker;
  int _idSeq = 0;

  /// Laatste fase-overgang, voor schermnavigatie (live ↔ rust).
  final ValueNotifier<SparringEvent?> sparringEvents = ValueNotifier(null);

  bool get isTrainingActive => training != null;
  bool get isSparringActive => sparring != null && !sparring!.isDone;
  int get roundSecondsRemaining => sparring?.remaining(now()) ?? 0;

  String get sessionTitle => training?.displayTitle ?? 'Training';
  List<String> get sessionTechniqueIds => training?.techniqueIds ?? const [];
  List<GlucosePoint> get sessionGlucose => training?.glucose ?? const [];

  List<Technique> get sessionTechniques => [
    for (final id in sessionTechniqueIds) ...techniques.where((t) => t.id == id),
  ];

  /// Tellers van het lopende sparblok (Geslaagd/Poging/Gecounterd).
  Map<String, TechniqueCounts> get sessionCounts => training?.activeSparring?.counts ?? const {};

  String _newId(String prefix) => '$prefix-${now().microsecondsSinceEpoch}-${_idSeq++}';

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

  /// Hartslag (Polar H10) tonen tijdens trainingen. Standaard uit: er is
  /// nog geen echte koppeling, alleen een simulatie.
  bool showHeartRate = false;

  Future<void> setShowHeartRate(bool on) async {
    showHeartRate = on;
    await _prefs?.setBool('show_heart_rate', on);
    notifyListeners();
  }

  /// Dagdoel voeding (macro-barometer, "x / 210 g") tonen.
  bool nutritionGoalsEnabled = true;

  /// Vocht bijhouden (tegel op Vandaag).
  bool waterEnabled = true;

  Future<void> setNutritionGoalsEnabled(bool on) async {
    nutritionGoalsEnabled = on;
    await _prefs?.setBool('nutrition_goals_enabled', on);
    notifyListeners();
  }

  Future<void> setWaterEnabled(bool on) async {
    waterEnabled = on;
    await _prefs?.setBool('water_enabled', on);
    notifyListeners();
  }

  Future<void> setRestTimerEnabled(bool on) async {
    restTimerEnabled = on;
    await _prefs?.setBool('rest_timer_enabled', on);
    notifyListeners();
  }

  /// Start een training. De klok loopt pas vanaf [startsAt].
  void startTraining({
    required String discipline,
    required DateTime startsAt,
    required DateTime endsAt,
    String title = '',
    List<String>? techniqueIds,
  }) {
    if (isTrainingActive) return;
    training = LiveTraining(
      discipline: discipline,
      title: title,
      startsAt: startsAt,
      endsAt: endsAt.isAfter(startsAt) ? endsAt : startsAt.add(const Duration(minutes: 90)),
      techniqueIds: techniqueIds ?? focusTechniques.map((x) => x.id).toList(),
    );
    _hrAtRestStart = null;
    _restStartedAt = null;
    _sampleSessionGlucose();
    _startTicker();
    if (enableWakelock) unawaited(WakelockPlus.enable().catchError((_) {}));
    unawaited(refreshGlucose());
    _persistTraining();
    notifyListeners();
  }

  void _update(LiveTraining Function(LiveTraining t) change) {
    final t = training;
    if (t == null) return;
    training = change(t);
    _persistTraining();
    notifyListeners();
  }

  void setTrainingTimes({DateTime? startsAt, DateTime? endsAt}) =>
      _update((t) => t.copyWith(startsAt: startsAt, endsAt: endsAt));

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    final t = sparring;
    final tr = training;
    final phase = t == null || t.isPaused
        ? (tr != null && tr.hasStarted(now()) ? SparringPhase.rest : null)
        : t.phase;
    heartRate.update(phase, now());
    if (t != null) {
      final hold = !restTimerEnabled || clearanceForNextRound().blocksNextRound;
      final event = t.tick(now(), holdRest: hold);
      if (event != null) _onSparringEvent(event);
    }
    notifyListeners();
  }

  void _onSparringEvent(SparringEvent e) {
    if (e == SparringEvent.restStarted) {
      _hrAtRestStart = heartRate.bpm;
      _restStartedAt = now();
    }
    if (e == SparringEvent.finished) {
      final t = sparring;
      if (t != null) _closeSparringBlock(t.config.rounds);
      sparring = null;
    }
    _persistTraining();
    sparringEvents.value = e;
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // ------------------------------------------------------------ sparblokken
  /// Een sparblok toevoegen en meteen starten.
  void startSparringBlock({required List<SparRound> rounds, String goal = ''}) {
    final tr = training;
    if (tr == null || rounds.isEmpty || isSparringActive) return;
    final block = SparringBlock(
      id: _newId('spar'),
      rounds: rounds,
      goal: goal.trim(),
      startedAt: now(),
      counts: {for (final id in tr.techniqueIds) id: const TechniqueCounts()},
    );
    sparring = SparringTimer(config: _configFor(rounds), now: now());
    _hrAtRestStart = null;
    _restStartedAt = null;
    _update((t) => t.copyWith(sparrings: [...t.sparrings, block]));
  }

  static SparringConfig _configFor(List<SparRound> rounds) => SparringConfig(
    rounds: rounds.length,
    workSeconds: rounds.first.workSeconds,
    restSeconds: rounds.first.restSeconds,
    roundWork: [for (final r in rounds) r.workSeconds],
    roundRest: [for (final r in rounds) r.restSeconds],
  );

  /// Sparblok aanpassen, ook als het al loopt (rondes, duur, doelen) of al
  /// is afgerond (dan ook het aantal gedane rondes).
  void updateSparringBlock(String id, {required List<SparRound> rounds, required String goal, int? roundsDone}) {
    if (rounds.isEmpty) return;
    final active = training?.activeSparring?.id == id;
    _replaceBlock(id, (b) => b.copyWith(
      rounds: rounds,
      goal: goal.trim(),
      roundsDone: roundsDone?.clamp(0, rounds.length) ?? b.roundsDone.clamp(0, rounds.length),
    ));
    final t = sparring;
    if (active && t != null) {
      t.reconfigure(_configFor(rounds), now());
      _persistTraining();
      notifyListeners();
    }
  }

  void _replaceBlock(String id, SparringBlock Function(SparringBlock b) change) => _update(
    (t) => t.copyWith(sparrings: [for (final b in t.sparrings) b.id == id ? change(b) : b]),
  );

  /// Zet het lopende blok op afgerond met [roundsDone] gedane rondes.
  void _closeSparringBlock(int roundsDone) {
    final b = training?.activeSparring;
    if (b == null) return;
    final rounds = roundsDone.clamp(0, b.rounds.length);
    _replaceBlock(b.id, (x) => x.copyWith(endedAt: now(), roundsDone: rounds));
  }

  /// Sparblok vroegtijdig (of na de laatste ronde) afronden.
  void finishSparringBlock() {
    final t = sparring;
    if (t == null) return;
    // Een lopende (of net afgeronde) ronde telt mee als gedaan.
    final done = t.isDone ? t.config.rounds : t.round;
    if (!t.isDone) t.finish(now());
    _closeSparringBlock(done);
    sparring = null;
    sparringEvents.value = null;
    _persistTraining();
    notifyListeners();
  }

  /// Een gelogd sparblok opnieuw starten als nieuw blok: zelfde rondes,
  /// tijden en doelen, met lege vinkjes. Het oude blok blijft staan.
  void repeatSparringBlock(String blockId) {
    final b = training?.sparrings.where((x) => x.id == blockId).firstOrNull;
    if (b == null || isSparringActive) return;
    startSparringBlock(rounds: [for (final r in b.rounds) r.copyWith(goalDone: false)], goal: b.goal);
  }

  void toggleRoundGoal(String blockId, int roundIndex) => _replaceBlock(blockId, (b) {
    final rounds = [...b.rounds];
    if (roundIndex < 0 || roundIndex >= rounds.length) return b;
    rounds[roundIndex] = rounds[roundIndex].copyWith(goalDone: !rounds[roundIndex].goalDone);
    return b.copyWith(rounds: rounds);
  });

  void toggleSparringGoal(String blockId) => _replaceBlock(blockId, (b) => b.copyWith(goalDone: !b.goalDone));

  void setSparringGoal(String blockId, String goal) => _replaceBlock(blockId, (b) => b.copyWith(goal: goal.trim()));

  void setRoundGoal(String blockId, int roundIndex, String goal) => _replaceBlock(blockId, (b) {
    final rounds = [...b.rounds];
    if (roundIndex < 0 || roundIndex >= rounds.length) return b;
    rounds[roundIndex] = rounds[roundIndex].copyWith(goal: goal.trim());
    return b.copyWith(rounds: rounds);
  });

  void removeSparringBlock(String blockId) {
    if (training?.activeSparring?.id == blockId) finishSparringBlock();
    _update((t) => t.copyWith(sparrings: t.sparrings.where((b) => b.id != blockId).toList()));
  }

  void toggleSparringTimer() {
    sparring?.togglePause(now());
    _persistTraining();
    notifyListeners();
  }

  /// VOLGENDE: huidige ronde afronden en naar de rust (of afronden).
  void advanceToRestPhase() {
    final t = sparring;
    if (t == null || t.phase != SparringPhase.work) return;
    t.toRest(now());
    _onSparringEvent(t.isDone ? SparringEvent.finished : SparringEvent.restStarted);
    if (t.isDone) {
      sparring = null;
      _persistTraining();
    }
    notifyListeners();
  }

  void addRestSeconds(int seconds) {
    sparring?.addRest(seconds, now());
    _persistTraining();
    notifyListeners();
  }

  void startNextRound() {
    final t = sparring;
    if (t == null || t.isDone) return;
    t.startNextRound(now());
    _hrAtRestStart = null;
    _restStartedAt = null;
    final b = training?.activeSparring;
    if (b != null) _replaceBlock(b.id, (x) => x.copyWith(roundsDone: math.max(x.roundsDone, t.round - 1)));
    _onSparringEvent(SparringEvent.roundStarted);
    notifyListeners();
  }

  /// Geslaagd/Poging/Gecounterd tijdens het sparren.
  void incrementTechniqueStat(String id, TechniqueStat stat, {int delta = 1}) {
    final b = training?.activeSparring;
    if (b == null) return;
    final current = b.counts[id] ?? const TechniqueCounts();
    _replaceBlock(b.id, (x) => x.copyWith(counts: {...x.counts, id: current.add(stat, delta)}));
  }

  // ------------------------------------------------------------ warming-up
  void addWarmup({int minutes = 15}) =>
      _update((t) => t.copyWith(warmups: [...t.warmups, WarmupLog(id: _newId('wu'), at: now(), minutes: minutes)]));

  void updateWarmup(String id, int minutes) => _update(
    (t) => t.copyWith(warmups: [for (final w in t.warmups) w.id == id ? w.copyWith(minutes: minutes.clamp(1, 120)) : w]),
  );

  void removeWarmup(String id) => _update((t) => t.copyWith(warmups: t.warmups.where((w) => w.id != id).toList()));

  // ------------------------------------------------------------ technieken
  /// Techniek tijdens de sessie toevoegen of weghalen.
  void toggleSessionTechnique(String id) => _update((t) {
    if (t.techniqueIds.contains(id)) {
      return t.copyWith(techniqueIds: t.techniqueIds.where((x) => x != id).toList());
    }
    final active = t.activeSparring;
    return t.copyWith(
      techniqueIds: [...t.techniqueIds, id],
      sparrings: active == null
          ? null
          : [
              for (final b in t.sparrings)
                b.id == active.id ? b.copyWith(counts: {...b.counts, id: b.counts[id] ?? const TechniqueCounts()}) : b,
            ],
    );
  });

  /// Techniek (en zijn log) uit de training halen. Geeft de log terug voor "Ongedaan".
  TechniqueLog? removeSessionTechnique(String id) {
    final log = training?.techniqueLogs[id];
    _update((t) => t.copyWith(
      techniqueIds: t.techniqueIds.where((x) => x != id).toList(),
      techniqueLogs: {...t.techniqueLogs}..remove(id),
    ));
    return log;
  }

  void restoreSessionTechnique(String id, TechniqueLog? log) => _update((t) => t.copyWith(
    techniqueIds: t.techniqueIds.contains(id) ? null : [...t.techniqueIds, id],
    techniqueLogs: log == null ? null : {...t.techniqueLogs, id: log},
  ));

  TechniqueLog techniqueLog(String id) => training?.techniqueLogs[id] ?? const TechniqueLog();

  void setTechniqueLog(String id, TechniqueLog log) =>
      _update((t) => t.copyWith(techniqueLogs: {...t.techniqueLogs, id: log}));

  // ------------------------------------------------------------ combinaties
  void logCombo(List<String> steps, {String? combinationId}) {
    if (steps.isEmpty || (steps.length < 2 && combinationId == null)) return;
    _update((t) {
      final label = steps.join(' → ');
      final existing = t.combos.where((c) => c.label == label).firstOrNull;
      if (existing != null) {
        return t.copyWith(combos: [for (final c in t.combos) c.id == existing.id ? c.copyWith(count: c.count + 1) : c]);
      }
      return t.copyWith(
        combos: [...t.combos, ComboLog(id: _newId('combo'), steps: steps, at: now(), combinationId: combinationId)],
      );
    });
  }

  void changeComboCount(String id, int delta) => _update((t) => t.copyWith(
    combos: [
      for (final c in t.combos)
        if (c.id != id) c else if (c.count + delta > 0) c.copyWith(count: c.count + delta),
    ],
  ));

  // ------------------------------------------------------------ voeding
  /// Logt de gekozen presets (enkelvoud → aantal) met het huidige tijdstip.
  void logNutrition(Map<String, int> counts, {String freeLabel = '', double freeCarbs = 0}) {
    final at = now();
    final r = reading;
    final mmol = (r != null && !r.isStaleAt(at)) ? double.parse(r.mmol.toStringAsFixed(1)) : null;
    final byName = {for (final p in trainingPresets) p.singular: p};
    final logs = <NutritionLog>[
      for (final e in counts.entries)
        if (e.value > 0 && byName[e.key] != null)
          NutritionLog(
            id: _newId('nut'),
            at: at,
            label: byName[e.key]!.label(e.value),
            count: e.value,
            carbs: byName[e.key]!.carbs * e.value,
            preset: e.key,
            mmol: mmol,
          ),
      if (freeLabel.trim().isNotEmpty || freeCarbs > 0)
        NutritionLog(
          id: _newId('nut'),
          at: at,
          label: freeLabel.trim().isEmpty ? '${grams(freeCarbs)} g koolhydraten' : freeLabel.trim(),
          carbs: freeCarbs,
          mmol: mmol,
        ),
    ];
    if (logs.isEmpty) return;
    _update((t) => t.copyWith(nutrition: [...t.nutrition, ...logs]));
  }

  /// Aantal/tijd aanpassen; label en koolhydraten schalen mee met de preset.
  NutritionLog _rescale(NutritionLog n, {int? count, DateTime? at}) {
    final c = (count ?? n.count).clamp(1, 99);
    final preset = trainingPresets.where((p) => p.singular == n.preset).firstOrNull;
    if (preset == null) {
      final perItem = n.count > 0 ? n.carbs / n.count : n.carbs;
      return n.copyWith(count: c, at: at, carbs: perItem * c);
    }
    return n.copyWith(count: c, at: at, label: preset.label(c), carbs: preset.carbs * c);
  }

  void updateNutrition(String id, {int? count, DateTime? at}) => _update(
    (t) => t.copyWith(nutrition: [for (final n in t.nutrition) n.id == id ? _rescale(n, count: count, at: at) : n]),
  );

  void deleteNutrition(String id) => _update((t) => t.copyWith(nutrition: t.nutrition.where((n) => n.id != id).toList()));

  /// Voeding van een al opgeslagen sessie aanpassen of verwijderen.
  Future<bool> updateSessionNutrition(String sessionId, {String? id, int? count, DateTime? at, bool delete = false}) async {
    final s = sessions.where((x) => x.id == sessionId).firstOrNull;
    if (s == null) return false;
    final next = [
      for (final n in s.nutrition)
        if (n.id != id) n else if (!delete) _rescale(n, count: count, at: at),
    ];
    try {
      final c = _client;
      if (c != null && !sessionId.startsWith('local')) await SessionRepository(c).updateNutrition(sessionId, next);
      sessions = [for (final x in sessions) x.id == sessionId ? x.copyWith(nutrition: next) : x];
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _sampleSessionGlucose() {
    final r = reading;
    final tr = training;
    if (tr == null || r == null || r.isStaleAt(now())) return;
    if (tr.glucose.isNotEmpty && !r.at.isAfter(tr.glucose.last.at)) return;
    training = tr.copyWith(glucose: [...tr.glucose, GlucosePoint(r.at, r.mmol)]);
    _persistTraining();
  }

  /// Rondt de training af. Met [save] gaat hij als sessie naar Supabase.
  Future<TrainingSession?> finishTraining({bool save = true}) async {
    if (sparring != null) finishSparringBlock();
    final tr = training;
    if (tr == null) return null;
    final end = now();
    _stopTicker();
    if (enableWakelock) unawaited(WakelockPlus.disable().catchError((_) {}));
    TrainingSession? saved;
    if (save) {
      final started = tr.hasStarted(end) ? tr.startsAt : end;
      final minutes = end.difference(started).inMinutes.clamp(1, 24 * 60);
      final session = TrainingSession(
        id: '',
        kind: tr.discipline.toLowerCase().contains('kracht') ? 'kracht' : 'sambo',
        title: tr.displayTitle,
        startedAt: started,
        durationMinutes: minutes,
        glucoseSeries: tr.glucose,
        blocks: trainingBlocks(tr, techniques, end),
        nutrition: tr.nutrition,
      );
      final uid = _uid;
      final c = _client;
      try {
        saved = (uid == null || c == null)
            ? session.copyWithId('local-${end.microsecondsSinceEpoch}')
            : await SessionRepository(c).create(session, uid);
        sessions = [saved, ...sessions];
        lastSyncAt = now();
      } catch (_) {
        syncError = 'Training kon niet worden opgeslagen.';
        notifyListeners();
        return null;
      }
    }
    training = null;
    sparring = null;
    sparringEvents.value = null;
    await _prefs?.remove('training_state');
    notifyListeners();
    return saved;
  }

  void _persistTraining() {
    final tr = training;
    final prefs = _prefs;
    if (tr == null || prefs == null) return;
    unawaited(prefs.setString('training_state', jsonEncode({
      'training': tr.toJson(),
      'timer': ?sparring?.toJson(),
    })));
  }

  /// Herstelt een training die nog liep toen de app werd afgesloten.
  Future<void> _restoreTraining() async {
    await _prefs?.remove('sparring_state'); // formaat van vóór trainingen
    final raw = _prefs?.getString('training_state');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final tr = LiveTraining.fromJson(j['training'] as Map<String, dynamic>);
      if (now().difference(tr.endsAt) > const Duration(hours: 6)) {
        await _prefs?.remove('training_state');
        return;
      }
      training = tr;
      final timer = j['timer'];
      if (timer is Map<String, dynamic>) {
        final t = SparringTimer.fromJson(timer);
        if (!t.isDone) sparring = t;
      }
      _startTicker();
      if (enableWakelock) unawaited(WakelockPlus.enable().catchError((_) {}));
    } catch (_) {
      await _prefs?.remove('training_state');
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

  /// Metabole drempels uit Instellingen (profiles.daily_low_below 3-6,
  /// profiles.hyper_limit 7-20, zoals de database-constraints).
  Future<bool> updateThresholds({double? lowBelow, double? hyperLimit}) async {
    final p = profile;
    if (p == null) return false;
    final low = lowBelow == null ? null : double.parse(lowBelow.clamp(3.0, 6.0).toStringAsFixed(1));
    final hyper = hyperLimit == null ? null : double.parse(hyperLimit.clamp(7.0, 20.0).toStringAsFixed(1));
    try {
      final c = _client;
      if (c != null) {
        await ProfileRepository(c).updateFields(p.id, {
          'daily_low_below': ?low,
          'hyper_limit': ?hyper,
        });
      }
      profile = p.copyWith(dailyLowBelow: low, hyperLimit: hyper);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------- voedingspresets

  /// Maaltijdpresets, alfabetisch.
  List<FoodPreset> get foodPresets => sortedPresets(profile?.foodPresets ?? const []);

  /// Trainingspresets (voeding tijdens een training), alfabetisch.
  List<FoodPreset> get trainingPresets => sortedPresets(profile?.trainingPresets ?? const []);

  List<FoodPreset> presetsFor({required bool training}) => training ? trainingPresets : foodPresets;

  /// Presets die je vaak gebruikt, als snelknop buiten de lijst.
  List<FoodPreset> frequentPresetsFor({required bool training}) {
    if (!training) return frequentPresets(foodPresets, presetUsage(foodEntries.map((e) => e.presetCounts)));
    final logs = _trainingNutritionHistory();
    return frequentPresets(trainingPresets, presetUsage([for (final n in logs) if (n.preset != null) {n.preset!: n.count}]));
  }

  /// Voeding uit eerdere trainingen + de lopende, voor de veelgebruikt-lijst.
  List<NutritionLog> _trainingNutritionHistory() => [
    for (final s in sessions) ...s.nutrition,
    ...?training?.nutrition,
  ];

  /// Slaat een hele presetlijst op (maaltijd: `food_checklist`, training: `carb_presets`).
  Future<bool> savePresets(List<FoodPreset> presets, {required bool training}) async {
    final p = profile;
    if (p == null) return false;
    try {
      final c = _client;
      if (c != null) {
        await ProfileRepository(c).updateFields(p.id, {
          training ? 'carb_presets' : 'food_checklist': [for (final x in presets) x.toJson()],
        });
      }
      profile = training ? p.copyWith(trainingPresets: presets) : p.copyWith(foodPresets: presets);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  List<FoodPreset> _rawPresets(bool training) =>
      (training ? profile?.trainingPresets : profile?.foodPresets) ?? const <FoodPreset>[];

  /// Voegt toe of vervangt (op enkelvoud; [replacing] is de oude naam bij hernoemen).
  Future<bool> upsertPreset(FoodPreset preset, {required bool training, String? replacing}) {
    final key = (replacing ?? preset.singular).toLowerCase();
    final list = [
      for (final x in _rawPresets(training))
        if (x.singular.toLowerCase() != key && x.singular.toLowerCase() != preset.singular.toLowerCase()) x,
      preset,
    ];
    return savePresets(list, training: training);
  }

  Future<bool> deletePreset(FoodPreset preset, {required bool training}) => savePresets([
    for (final x in _rawPresets(training))
      if (x.singular != preset.singular) x,
  ], training: training);

  /// Grootte van de snelle-koolhydraten-noodknop (10/15/20 g).
  int fastCarbGrams = 15;

  Future<void> setFastCarbGrams(int grams) async {
    fastCarbGrams = grams;
    await _prefs?.setInt('fast_carb_grams', grams);
    notifyListeners();
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
    darkMode = prefs.getString('theme_mode') != 'light';
    fastCarbGrams = prefs.getInt('fast_carb_grams') ?? 15;
    try {
      final m = prefs.getString('macro_targets');
      if (m != null) {
        final j = jsonDecode(m) as Map<String, dynamic>;
        carbsTarget = (j['carbs'] as num).toDouble();
        proteinTarget = (j['protein'] as num).toDouble();
        fatTarget = (j['fat'] as num).toDouble();
      }
      restTimerEnabled = prefs.getBool('rest_timer_enabled') ?? true;
      showHeartRate = prefs.getBool('show_heart_rate') ?? false;
      nutritionGoalsEnabled = prefs.getBool('nutrition_goals_enabled') ?? true;
      waterEnabled = prefs.getBool('water_enabled') ?? true;
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
    List<LibraryTechnique> library = const [],
    List<TechniqueSystem> systems = const [],
    List<PlannedTraining> plannedTrainings = const [],
    List<Competition>? allCompetitions,
    bool darkMode = true,
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
    this.library = library;
    this.systems = systems;
    this.plannedTrainings = plannedTrainings;
    this.allCompetitions = allCompetitions ?? competitions;
    this.darkMode = darkMode;
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
    darkModeNotifier.dispose();
    super.dispose();
  }
}
