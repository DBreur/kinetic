import 'dart:async';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/error_messages.dart';
import '../models/app_profile.dart';
import '../models/circuit.dart';
import '../models/glucose.dart';
import '../models/glucose_entry.dart';
import '../models/weigh_in.dart';
import '../repositories/glucose_entry_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/weigh_in_repository.dart';
import '../services/background_glucose_service.dart';
import '../services/glucose_provider.dart';
import '../services/notification_router.dart';
import '../services/video_labels.dart';
import '../services/weigh_in_reminder_service.dart';
import '../widgets/glucose_alarm.dart';
import '../widgets/muscle_figure.dart';

enum AppBootState { loading, needsConfig, signedOut, needsOnboarding, ready }

/// Wat er gebeurde bij "Account maken".
enum RegisterOutcome {
  /// Account gemaakt en meteen ingelogd (bevestiging staat uit).
  signedIn,

  /// Account gemaakt; eerst de link in de bevestigingsmail aanklikken.
  confirmEmail,

  /// Er bestond al een account met dit e-mailadres.
  alreadyExists,

  /// Fout (zie [AppController.authError]).
  failed,
}

/// Leidt de uitkomst af uit het antwoord van Supabase. Bestaat het
/// e-mailadres al, dan geeft Supabase (om accounts niet te verraden) géén
/// fout maar een gebruiker zonder inlogmethodes terug.
RegisterOutcome registerOutcomeFor({
  required bool hasSession,
  required List<Object>? identities,
}) {
  if (hasSession) return RegisterOutcome.signedIn;
  if (identities != null && identities.isEmpty) {
    return RegisterOutcome.alreadyExists;
  }
  return RegisterOutcome.confirmEmail;
}

/// Uitkomst van `AppController.alarmDecision()` — de enige plek in de app
/// die bepaalt of, en hoe, het hypo-alarm mag afgaan. Niets anders in de
/// app mag zelf een grens of een aan/uit-check bijhouden.
class AlarmDecision {
  /// Mag er überhaupt een alarm komen.
  final bool enabled;

  /// Geluid ja/nee — alleen relevant als [enabled] waar is.
  final bool withSound;

  /// De actieve ondergrens: trainingsgrens tijdens een sessie, anders de
  /// dagelijkse grens. Er is nooit meer dan één tegelijk actief.
  final double lowBelow;

  /// Waar zodra [lowBelow] de trainingsgrens is (er loopt een sessie).
  final bool isTrainingLimit;

  const AlarmDecision({
    required this.enabled,
    required this.withSound,
    required this.lowBelow,
    required this.isTrainingLimit,
  });
}

class AppController extends ChangeNotifier {
  AppController() {
    alarmGuard.onSnoozeChanged = BackgroundGlucoseWatcher.instance.saveSnooze;
    NotificationRouter.pendingSnooze.addListener(_onSnoozeRequest);
  }

  /// Verzoek om een circuit als losse training te starten (vanuit de
  /// bibliotheek of de circuit-editor) — de shell luistert en start hem.
  final ValueNotifier<Circuit?> pendingCircuitStart = ValueNotifier(null);

  void startCircuitTraining(Circuit circuit) =>
      pendingCircuitStart.value = circuit;

  /// Navigator van de hele app — zodat het glucose-alarm ook buiten een
  /// training zijn paneel kan tonen, op welk scherm je ook zit.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Context bovenop alle schermen (de overlay van de app-navigator), of
  /// null zolang de app nog niet getekend is.
  BuildContext? get _overlayContext =>
      navigatorKey.currentState?.overlay?.context;

  void _onSnoozeRequest() {
    final request = NotificationRouter.pendingSnooze.value;
    if (request == null) return;
    NotificationRouter.pendingSnooze.value = null;
    alarmGuard.snoozeFromNotification(
      isHigh: request.isHigh,
      mmol: request.mmol,
    );
  }

  SupabaseClient? _client;
  ProfileRepository? _profiles;

  AppBootState state = AppBootState.loading;
  AppProfile? _profile;
  AppProfile? get profile => _profile;
  set profile(AppProfile? next) {
    _profile = next;
    MuscleFigure.female.value = next?.sex == 'female';
    VideoLabels.attach(
      next?.videoLabels ?? const {},
      next == null ? null : _saveVideoLabels,
    );
  }

  /// Bewaart videonamen stil op de achtergrond — zonder de busy-status van
  /// [saveProfile], want je zit dan gewoon in een techniek of sessie.
  Future<void> _saveVideoLabels(Map<String, String> labels) async {
    final p = _profile;
    if (p == null || _profiles == null) return;
    try {
      _profile = await _profiles!.upsert(p.copyWith(videoLabels: labels));
    } catch (_) {
      // Naam blijft lokaal staan tot de volgende keer opslaan lukt.
    }
  }

  String? authError;
  bool busy = false;

  /// Laatst bekende glucosewaarde/-lijst — overleeft het heropbouwen van
  /// NowScreen (bv. bij het wisselen van tabblad), zodat de glucosekaart
  /// meteen de vorige waarde toont in plaats van eerst kort "laden" te tonen
  /// terwijl er op de achtergrond ververst wordt.
  GlucoseSnapshot? get cachedGlucose => glucose.value;
  set cachedGlucose(GlucoseSnapshot? next) => glucose.value = next;

  /// Zelfde waarde als [cachedGlucose], maar luisterbaar — voor de
  /// glucosepil in de Kinetic-topbalk.
  final ValueNotifier<GlucoseSnapshot?> glucose = ValueNotifier(null);

  /// Recente vingerprikken (nieuwste eerst), luisterbaar.
  final ValueNotifier<List<ManualGlucoseEntry>> fingerEntries = ValueNotifier(
    const [],
  );
  List<ManualGlucoseEntry> get cachedFingerEntries => fingerEntries.value;
  set cachedFingerEntries(List<ManualGlucoseEntry> next) =>
      fingerEntries.value = next;

  // ── Live glucose voor de hele app ──
  // Eén ophaler (elke minuut, en meteen bij terugkomen in de app), zodat
  // elk scherm — topbalk, Vandaag, Eten — dezelfde, verse waarde ziet. Was
  // eerder alleen actief zolang het tabblad Vandaag open stond.
  Timer? _glucosePoller;
  Future<void>? _glucoseInFlight;
  bool _glucoseAgain = false;
  static const glucosePollInterval = Duration(minutes: 1);

  bool get isPollingGlucose => _glucosePoller != null;

  /// Start het elke-minuut-ophalen (en haalt meteen op).
  void startGlucosePolling() {
    _glucosePoller ??= Timer.periodic(
      glucosePollInterval,
      (_) => refreshGlucose(),
    );
    refreshGlucose();
  }

  void stopGlucosePolling() {
    _glucosePoller?.cancel();
    _glucosePoller = null;
  }

  /// Haalt de nieuwste glucose op uit de gekozen bron (sensor of
  /// vingerprikken). Loopt er al een ophaalactie, dan wordt die gedeeld en
  /// daarna nog één keer opnieuw gehaald — zo mist een net ingevoerde
  /// vingerprik nooit.
  Future<void> refreshGlucose() {
    final running = _glucoseInFlight;
    if (running != null) {
      _glucoseAgain = true;
      return running;
    }
    final future = _refreshGlucoseLoop();
    _glucoseInFlight = future;
    return future.whenComplete(() => _glucoseInFlight = null);
  }

  Future<void> _refreshGlucoseLoop() async {
    do {
      _glucoseAgain = false;
      try {
        await _fetchGlucoseOnce();
      } catch (_) {
        // Oude waarde blijft staan; volgende ronde probeert het opnieuw.
      }
    } while (_glucoseAgain);
  }

  Future<void> _fetchGlucoseOnce() async {
    final p = _profile;
    if (p == null) return;
    if (p.glucoseSource == GlucoseSource.finger) {
      final userId = user?.id;
      final client = _client;
      if (userId == null || client == null) return;
      final entries = await GlucoseEntryRepository(client)
          .recentForUser(userId);
      cachedFingerEntries = entries;
      cachedGlucose = snapshotFromFingerEntries(entries);
      return;
    }
    final provider = await resolveGlucoseProvider(p);
    if (provider == null) {
      cachedGlucose = const GlucoseSnapshot.unconfigured();
      return;
    }
    final current = cachedGlucose;
    if (current != null) {
      cachedGlucose = current.copyWith(
        isLoading: true,
        message: current.message,
      );
    }
    final snapshot = await provider.fetch();
    cachedGlucose = snapshot;
    _checkPolledReading(snapshot);
  }

  /// Buiten een training het alarm laten meekijken met de minuut-poll. Een
  /// lopende sessie controleert zelf (met de trainingsgrens), dus dan niet.
  void _checkPolledReading(GlucoseSnapshot snapshot) {
    final reading = snapshot.reading;
    final context = _overlayContext;
    if (_sessionActive || reading == null || snapshot.isStale) return;
    if (context == null) return;
    checkGlucoseReading(
      () => _overlayContext ?? context,
      reading,
      onManualEntry: (ctx) => handleManualEntryFromAlarm(ctx, (r) {
        offerGlucoseReading(r);
        checkGlucoseReading(() => _overlayContext ?? context, r);
      }),
    );
  }

  /// Een nieuwere meting van elders (bv. een lopende training) — alleen
  /// overnemen als hij echt nieuwer is.
  void offerGlucoseReading(GlucoseReading reading) {
    final current = cachedGlucose?.reading;
    if (current != null && !reading.at.isAfter(current.at)) return;
    final snapshot = cachedGlucose;
    cachedGlucose = GlucoseSnapshot(
      reading: reading,
      history: [
        ...?snapshot?.history.where((p) => p.at.isBefore(reading.at)),
        GlucosePoint(reading.at, reading.mmol),
      ],
    );
  }

  /// Waar zolang een sambo- of krachtsessie loopt (ook op de achtergrond,
  /// bv. geminimaliseerd naar een ander tabblad) — bepaalt in
  /// [alarmDecision] of de training- of de dagelijkse ondergrens geldt.
  bool _sessionActive = false;

  void setSessionActive(bool active) {
    if (_sessionActive == active) return;
    _sessionActive = active;
  }

  /// Enige gedeelde alarm-guard in de app — voorkomt dat twee plekken
  /// (bv. een sessie én de achtergrondbewaking) tegelijk een sheet tonen.
  final GlucoseAlarmGuard alarmGuard = GlucoseAlarmGuard();

  /// Waar zodra de vorige gecontroleerde meting oud was — voorkomt dat de
  /// "geen data"-waarschuwing bij elke poll opnieuw afgaat.
  bool _staleWarned = false;

  /// De enige plek die bepaalt of, en hoe, het hypo-alarm mag afgaan. Elke
  /// plek die een alarm kan tonen, geluid kan maken of een notificatie kan
  /// sturen, gebruikt uitsluitend deze functie.
  AlarmDecision alarmDecision() => _decisionFor(_sessionActive);

  /// Zelfde beslissing, maar altijd uitgaand van "geen sessie" — gebruikt om
  /// te bepalen of de achtergrondbewaking (buiten training) zou mogen
  /// draaien, ongeacht of er op dit moment toevallig wel een sessie loopt.
  AlarmDecision alarmDecisionOutsideSession() => _decisionFor(false);

  AlarmDecision _decisionFor(bool sessionActive) {
    final p = profile;
    final lowBelow = sessionActive
        ? (p?.trainingLimit ?? 5.0)
        : (p?.dailyLowBelow ?? 3.9);

    // 1. Vingerprik: geen doorlopende data, dus geen alarm op verouderde
    //    waarden.
    if (p == null || p.glucoseSource == GlucoseSource.finger) {
      return AlarmDecision(
        enabled: false,
        withSound: false,
        lowBelow: lowBelow,
        isTrainingLimit: sessionActive,
      );
    }

    // 2. Alarm helemaal uit. Tijdens een training geldt de eigen
    //    trainingsstand (als die is ingesteld), anders de dagelijkse.
    final mode = sessionActive
        ? (p.trainingAlarmMode ?? p.alarmMode)
        : p.alarmMode;
    if (mode == AlarmMode.off) {
      return AlarmDecision(
        enabled: false,
        withSound: false,
        lowBelow: lowBelow,
        isTrainingLimit: sessionActive,
      );
    }

    // 3. Sessie loopt: alleen de trainingsgrens telt, altijd aan zolang het
    //    alarm niet helemaal uit staat.
    if (sessionActive) {
      return AlarmDecision(
        enabled: true,
        withSound: mode == AlarmMode.sound,
        lowBelow: p.trainingLimit,
        isTrainingLimit: true,
      );
    }

    // 4. Geen sessie: de dagelijkse grens telt, en kan los uitgezet worden.
    if (!p.dailyLowEnabled) {
      return AlarmDecision(
        enabled: false,
        withSound: false,
        lowBelow: p.dailyLowBelow,
        isTrainingLimit: false,
      );
    }
    return AlarmDecision(
      enabled: true,
      withSound: p.alarmMode == AlarmMode.sound,
      lowBelow: p.dailyLowBelow,
      isTrainingLimit: false,
    );
  }

  /// Enige plek die een meting daadwerkelijk tegen het alarm aanhoudt en de
  /// sheet toont — gebruikt door elke live sessie én door het Nu-scherm.
  /// Bouwt zelf de beslissing via [alarmDecision]; de aanroeper geeft alleen
  /// de meting en een context door.
  Future<void> checkGlucoseReading(
    BuildContext Function() contextOf,
    GlucoseReading reading, {
    Future<void> Function(BuildContext)? onManualEntry,
  }) {
    _staleWarned = false;
    final decision = alarmDecision();
    return alarmGuard.check(
      contextOf,
      reading,
      lowBelow: decision.lowBelow,
      lowEnabled: decision.enabled,
      withSound: decision.withSound,
      breakSilentMode: profile?.breakSilentMode ?? true,
      isTrainingLimit: decision.isTrainingLimit,
      highAbove: profile?.hyperLimit,
      highEnabled: profile?.hyperAlarmEnabled ?? true,
      snoozeMinutes: profile?.alarmSnoozeMinutes ?? 15,
      onManualEntry: onManualEntry,
    );
  }

  /// Controleert of de laatst bekende meting te oud is (alleen zinvol bij
  /// CGM). Geeft precies één keer `true` terug op het moment dat het oud
  /// wordt — niet bij elke volgende poll opnieuw — zodat de aanroeper dan
  /// een waarschuwing kan tonen (bv. een SnackBar in de sessie). Reset
  /// zichzelf zodra er weer verse data binnenkomt.
  bool checkStaleness(GlucoseSnapshot snapshot) {
    if (profile?.glucoseSource == GlucoseSource.finger) return false;
    if (!snapshot.isStale) {
      _staleWarned = false;
      return false;
    }
    if (_staleWarned || !alarmDecision().enabled) return false;
    _staleWarned = true;
    return true;
  }

  /// Alleen voor tests: koppelt een client en profiel zonder [boot], zodat
  /// schermen zonder netwerk/inlog opgebouwd kunnen worden.
  @visibleForTesting
  void debugAttach(SupabaseClient client, AppProfile profile, {User? user}) {
    _debugUser = user;
    _client = client;
    _profiles = ProfileRepository(client);
    this.profile = profile;
    state = AppBootState.ready;
  }

  SupabaseClient? get client => _client;

  /// Naam om te tonen: de zelfgekozen gebruikersnaam, anders afgeleid van
  /// het e-mailadres ("d.breur" → "D Breur").
  String get displayName {
    final chosen = profile?.username.trim() ?? '';
    if (chosen.isNotEmpty) return chosen;
    final local = (user?.email ?? '').split('@').first;
    final parts = local
        .split(RegExp(r'[._-]'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1));
    return parts.isEmpty ? 'Atleet' : parts.join(' ');
  }

  /// Eén of twee letters voor als er geen profielfoto is.
  String get initials {
    final words = displayName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  /// Uploadt een nieuwe profielfoto naar `avatars/<user-id>/avatar.<ext>`
  /// en bewaart de openbare URL (met versie-suffix, zodat de nieuwe foto
  /// niet uit de cache van de oude komt) in het profiel.
  Future<void> updateAvatar(Uint8List bytes, String extension) async {
    final uid = user?.id;
    final p = profile;
    if (uid == null || p == null || _client == null) return;
    final ext = extension.toLowerCase() == 'png' ? 'png' : 'jpg';
    final path = '$uid/avatar.$ext';
    final bucket = _client!.storage.from('avatars');
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: true,
        contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
      ),
    );
    final url = bucket.getPublicUrl(path);
    await saveProfile(
      p.copyWith(avatarUrl: '$url?v=${DateTime.now().millisecondsSinceEpoch}'),
    );
  }

  /// Verwijdert de profielfoto (bestand en verwijzing).
  Future<void> removeAvatar() async {
    final uid = user?.id;
    final p = profile;
    if (uid == null || p == null || _client == null) return;
    try {
      await _client!.storage.from('avatars').remove([
        '$uid/avatar.jpg',
        '$uid/avatar.png',
      ]);
    } catch (_) {
      // Bestand bestond al niet meer — de verwijzing gaat hoe dan ook weg.
    }
    await saveProfile(p.copyWith(avatarUrl: ''));
  }

  User? _debugUser;
  User? get user => _debugUser ?? _client?.auth.currentUser;
  bool get hasSupabase => AppConfig.hasSupabase;

  Future<void> boot() async {
    state = AppBootState.loading;
    notifyListeners();

    if (!AppConfig.hasSupabase) {
      state = AppBootState.needsConfig;
      notifyListeners();
      return;
    }

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
    _client = Supabase.instance.client;
    _profiles = ProfileRepository(_client!);
    _client!.auth.onAuthStateChange.listen((_) => refresh());
    await refresh();
  }

  Future<void> refresh() async {
    final current = _client?.auth.currentUser;
    if (current == null) {
      profile = null;
      state = AppBootState.signedOut;
      notifyListeners();
      return;
    }

    try {
      profile = await _profiles!.getOrCreate(current.id);
      state = profile!.onboardingCompleted
          ? AppBootState.ready
          : AppBootState.needsOnboarding;
    } catch (error) {
      authError = friendlyErrorMessage(
        error,
        fallback:
            'Je profiel kon niet worden geladen. Probeer opnieuw in te loggen.',
      );
      state = AppBootState.signedOut;
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    await _authAction(() async {
      await _client!.auth.signInWithPassword(email: email, password: password);
      await refresh();
    });
  }

  /// Maakt een account aan. Staat e-mailbevestiging aan in Supabase (zo
  /// staat het nu ingesteld), dan is er daarna nog geen sessie: dan moet je
  /// eerst op de link in de mail klikken — de aanroeper toont dat.
  Future<RegisterOutcome> register(String email, String password) async {
    var outcome = RegisterOutcome.failed;
    await _authAction(() async {
      final res = await _client!.auth.signUp(email: email, password: password);
      outcome = registerOutcomeFor(
        hasSession: res.session != null,
        identities: res.user?.identities,
      );
      if (outcome == RegisterOutcome.signedIn) await refresh();
    });
    return outcome;
  }

  /// Bevestigingsmail van het aanmaken van een account opnieuw sturen.
  Future<bool> resendConfirmation(String email) async {
    var ok = false;
    await _authAction(() async {
      await _client!.auth.resend(type: OtpType.signup, email: email);
      ok = true;
    });
    return ok;
  }

  Future<void> resetPassword(String email) async {
    await _authAction(() => _client!.auth.resetPasswordForEmail(email));
  }

  Future<void> signOut() async {
    await _authAction(() async {
      await _client!.auth.signOut();
      profile = null;
      state = AppBootState.signedOut;
    });
  }

  static String _glucoseSourceKey(AppProfile? p) => p == null
      ? ''
      : '${p.glucoseSource.name}|${p.nightscoutUrl}|${p.nightscoutToken}|'
            '${p.dexcomUsername}|${p.dexcomServer}';

  // ── Wegen ──────────────────────────────────────────────────────────────

  /// Wegingen, nieuwste eerst — geladen met [loadWeighIns].
  final ValueNotifier<List<WeighIn>> weighIns = ValueNotifier(const []);

  DateTime? get lastWeighInAt =>
      weighIns.value.isEmpty ? null : weighIns.value.first.measuredAt;

  Future<void> loadWeighIns() async {
    final userId = user?.id;
    final c = _client;
    if (userId == null || c == null) return;
    try {
      weighIns.value = await WeighInRepository(c).listForUser(userId);
    } catch (_) {
      // Tabel nog niet gemigreerd of geen verbinding: lijst blijft leeg.
    }
    unawaited(WeighInReminderService.instance.sync(_profile, lastWeighInAt));
  }

  /// Bewaart een weging en zet hem ook als actueel gewicht in het profiel.
  /// Geeft false terug als opslaan niet lukte.
  Future<bool> addWeighIn(double kg, {DateTime? at}) async {
    final userId = user?.id;
    final c = _client;
    final p = _profile;
    if (userId == null || c == null) return false;
    try {
      final saved = await WeighInRepository(c).create(
        WeighIn(id: '', measuredAt: at ?? DateTime.now(), weightKg: kg),
        userId,
      );
      weighIns.value = [saved, ...weighIns.value]
        ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
      if (p != null && p.weightKg != kg && weighIns.value.first == saved) {
        await saveProfile(p.copyWith(weightKg: kg));
      }
      unawaited(WeighInReminderService.instance.sync(_profile, lastWeighInAt));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteWeighIn(WeighIn weighIn) async {
    final c = _client;
    if (c == null) return;
    try {
      await WeighInRepository(c).delete(weighIn.id);
      weighIns.value = [
        for (final w in weighIns.value)
          if (w.id != weighIn.id) w,
      ];
      unawaited(WeighInReminderService.instance.sync(_profile, lastWeighInAt));
    } catch (_) {
      // Blijft staan; volgende keer opnieuw proberen.
    }
  }

  Future<void> saveProfile(AppProfile next) async {
    busy = true;
    authError = null;
    notifyListeners();
    try {
      final before = _profile;
      profile = await _profiles!.upsert(next);
      // Bron of koppeling veranderd (of Dexcom-wachtwoord net bewaard):
      // meteen opnieuw ophalen in plaats van tot de volgende minuut wachten.
      if (isPollingGlucose &&
          _glucoseSourceKey(before) != _glucoseSourceKey(profile)) {
        refreshGlucose();
      }
      state = profile!.onboardingCompleted
          ? AppBootState.ready
          : AppBootState.needsOnboarding;
    } catch (error) {
      authError = friendlyErrorMessage(
        error,
        fallback:
            'Instellingen konden niet worden opgeslagen. Probeer opnieuw.',
      );
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _authAction(Future<void> Function() action) async {
    busy = true;
    authError = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      authError = friendlyErrorMessage(error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
