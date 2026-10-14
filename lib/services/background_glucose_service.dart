// background_glucose_service.dart — bewaakt de dagelijkse ondergrens ook als
// het scherm uit staat of de app op de achtergrond draait, via een Android
// foreground service (flutter_foreground_task) die elke 5 minuten Nightscout
// pollt.
//
// De service-handler draait in een eigen isolate en heeft dus geen toegang
// tot AppController — instellingen (Nightscout-URL/token, dagelijkse grens,
// alarmmodus) worden bij elke wijziging weggeschreven via
// FlutterForegroundTask.saveData en in de handler weer uitgelezen.
//
// De service draait alleen als AppController.alarmDecisionOutsideSession()
// waar is — bij vingerprik of een uitgeschakeld alarm start hij niet, en
// stopt hij zodra die instelling verandert (zie [BackgroundGlucoseWatcher]).

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/app_profile.dart';
import '../services/alarm_notification_service.dart';
import '../services/dexcom_credentials.dart';
import '../services/dexcom_share_service.dart';
import '../services/glucose_provider.dart';
import '../services/nightscout_service.dart';
import '../state/app_controller.dart';
import 'notification_style.dart';

const _kGlucoseSourceKey = 'bg_glucose_source';
const _kNightscoutUrlKey = 'bg_nightscout_url';
const _kNightscoutTokenKey = 'bg_nightscout_token';
const _kDexcomUsernameKey = 'bg_dexcom_username';
const _kDexcomServerKey = 'bg_dexcom_server';
const _kDailyLowBelowKey = 'bg_daily_low_below';
const _kDailyLowEnabledKey = 'bg_daily_low_enabled';
const _kAlarmModeKey = 'bg_alarm_mode';
const _kBreakSilentModeKey = 'bg_break_silent_mode';

/// Startpunt van de achtergrondtaak — draait in een eigen isolate. Moet een
/// top-level functie zijn met deze pragma, anders vindt Android hem niet
/// terug na een herstart van het proces.
@pragma('vm:entry-point')
void startBackgroundGlucoseCallback() {
  FlutterForegroundTask.setTaskHandler(_GlucoseWatchTaskHandler());
}

class _GlucoseWatchTaskHandler extends TaskHandler {
  bool _staleWarned = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // onRepeatEvent is synchroon; de eigenlijke poll is async en mag de
    // aanroep niet blokkeren.
    _poll();
  }

  /// Bouwt de provider op basis van de laatst gesynchroniseerde bron — het
  /// Dexcom-wachtwoord komt rechtstreeks uit secure storage (werkt binnen
  /// deze isolate, want die draait in hetzelfde proces als de voorgrondtaak)
  /// in plaats van via `FlutterForegroundTask.saveData`, zodat het
  /// wachtwoord nooit in die (minder beveiligde) opslag belandt.
  Future<GlucoseProvider?> _resolveProvider() async {
    final sourceName =
        await FlutterForegroundTask.getData<String>(key: _kGlucoseSourceKey) ??
        'nightscout';
    if (sourceName == 'dexcomShare') {
      final username = await FlutterForegroundTask.getData<String>(
        key: _kDexcomUsernameKey,
      );
      if (username == null || username.trim().isEmpty) return null;
      final server =
          await FlutterForegroundTask.getData<String>(key: _kDexcomServerKey) ??
          'shareous1.dexcom.com';
      final password = await DexcomCredentials.read();
      if (password == null || password.isEmpty) return null;
      return DexcomShareService(
        username: username,
        password: password,
        server: server,
      );
    }
    final url = await FlutterForegroundTask.getData<String>(
      key: _kNightscoutUrlKey,
    );
    if (url == null || url.trim().isEmpty) return null;
    final token = await FlutterForegroundTask.getData<String>(
      key: _kNightscoutTokenKey,
    );
    return NightscoutService(baseUrl: url, token: token);
  }

  Future<void> _poll() async {
    final provider = await _resolveProvider();
    if (provider == null) return;
    final dailyLowBelow =
        await FlutterForegroundTask.getData<double>(key: _kDailyLowBelowKey) ??
        3.9;
    final dailyLowEnabled =
        await FlutterForegroundTask.getData<bool>(key: _kDailyLowEnabledKey) ??
        true;
    final alarmModeName =
        await FlutterForegroundTask.getData<String>(key: _kAlarmModeKey) ??
        'sound';
    final alarmMode = AlarmMode.fromName(alarmModeName);
    final breakSilentMode =
        await FlutterForegroundTask.getData<bool>(key: _kBreakSilentModeKey) ??
        true;

    final snapshot = await provider.fetch();
    final reading = snapshot.reading;
    if (reading == null) return;

    FlutterForegroundTask.updateService(
      notificationTitle: 'Kinetic bewaakt je glucose',
      notificationText: 'Laatste meting: ${_fmt(reading.mmol)} mmol/L',
      notificationIcon: _notificationIcon,
    );

    if (alarmMode == AlarmMode.off || !dailyLowEnabled) return;
    final withSound = alarmMode == AlarmMode.sound;

    if (snapshot.isStale) {
      if (!_staleWarned) {
        _staleWarned = true;
        await AlarmNotificationService.instance.showStaleWarning(
          withSound: withSound,
        );
      }
      return;
    }
    _staleWarned = false;

    if (reading.mmol <= dailyLowBelow) {
      await AlarmNotificationService.instance.showAlarm(
        withSound: withSound,
        breakSilentMode: breakSilentMode,
        isHigh: false,
        mmol: reading.mmol,
      );
    }
  }

  String _fmt(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Beheert de foreground service vanuit de hoofd-isolate: initialiseren,
/// instellingen doorgeven, en starten/stoppen op basis van
/// `AppController.alarmDecisionOutsideSession()`.
/// Wit Kinetic-logo uit het manifest (meta-data → @mipmap/ic_notification).
const _notificationIcon = NotificationIcon(
  metaDataName: 'kinetic.service.NOTIFICATION_ICON',
  backgroundColor: kNotificationColor,
);

class BackgroundGlucoseWatcher {
  BackgroundGlucoseWatcher._();
  static final instance = BackgroundGlucoseWatcher._();

  bool _initialized = false;
  bool _restartedThisRun = false;

  void _ensureInit() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        // Nieuw kanaal (kanalen zijn na aanmaken niet meer te wijzigen) op
        // de laagste prioriteit: Android vereist deze vaste melding om op de
        // achtergrond te mogen meten, maar zo zakt hij weg onder "stille
        // meldingen" — geen icoon in de statusbalk, nooit opspringen. Het
        // hypo-alarm zelf komt via een eigen, luid kanaal.
        channelId: 'kinetic_background_watch_quiet',
        channelName: 'Kinetic achtergrondbewaking',
        channelDescription:
            'Vaste, stille melding zodat Kinetic je glucose ook met het '
            'scherm uit kan bewaken. Het alarm komt via een aparte melding.',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5 * 60 * 1000),
        autoRunOnBoot: false,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _syncSettings(AppProfile profile) async {
    await FlutterForegroundTask.saveData(
      key: _kGlucoseSourceKey,
      value: profile.glucoseSource.name,
    );
    await FlutterForegroundTask.saveData(
      key: _kNightscoutUrlKey,
      value: profile.nightscoutUrl,
    );
    await FlutterForegroundTask.saveData(
      key: _kNightscoutTokenKey,
      value: profile.nightscoutToken,
    );
    await FlutterForegroundTask.saveData(
      key: _kDexcomUsernameKey,
      value: profile.dexcomUsername,
    );
    await FlutterForegroundTask.saveData(
      key: _kDexcomServerKey,
      value: profile.dexcomServer,
    );
    await FlutterForegroundTask.saveData(
      key: _kDailyLowBelowKey,
      value: profile.dailyLowBelow,
    );
    await FlutterForegroundTask.saveData(
      key: _kDailyLowEnabledKey,
      value: profile.dailyLowEnabled,
    );
    await FlutterForegroundTask.saveData(
      key: _kBreakSilentModeKey,
      value: profile.breakSilentMode,
    );
    await FlutterForegroundTask.saveData(
      key: _kAlarmModeKey,
      value: profile.alarmMode.name,
    );
  }

  /// Start of stopt de service zodat die alleen draait wanneer
  /// `alarmDecisionOutsideSession().enabled` waar is — bv. niet bij
  /// vingerprik of een uitgeschakeld alarm, en stopt zodra dat verandert.
  /// Faalt nooit hardop: de app blijft bruikbaar als de service niet kan
  /// starten (bv. ontbrekende toestemming).
  Future<void> sync(AppController controller) async {
    try {
      final profile = controller.profile;
      final sourceConfigured = switch (profile?.glucoseSource) {
        GlucoseSource.nightscout => profile!.nightscoutUrl.trim().isNotEmpty,
        GlucoseSource.dexcomShare =>
          profile!.dexcomUsername.trim().isNotEmpty &&
              await DexcomCredentials.read() != null,
        GlucoseSource.finger || null => false,
      };
      final shouldRun =
          profile != null &&
          sourceConfigured &&
          controller.alarmDecisionOutsideSession().enabled;

      if (!shouldRun) {
        if (await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.stopService();
        }
        return;
      }

      _ensureInit();
      await _syncSettings(profile);

      // Draait de dienst al (bv. nog uit een vorige versie van de app — hij
      // overleeft een herinstallatie), dan zijn titel en icoon bijwerken in
      // plaats van niets doen; anders blijft de oude melding met het oude
      // icoon staan.
      if (await FlutterForegroundTask.isRunningService) {
        if (_restartedThisRun) {
          await FlutterForegroundTask.updateService(
            notificationTitle: 'Kinetic bewaakt je glucose',
            notificationIcon: _notificationIcon,
          );
          return;
        }
        // Eén keer per app-start herstarten: een dienst uit een vorige
        // versie houdt anders zijn oude (luidere) meldingskanaal en icoon.
        await FlutterForegroundTask.stopService();
      }
      _restartedThisRun = true;
      await FlutterForegroundTask.startService(
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: 'Kinetic bewaakt je glucose',
        notificationText: 'Wordt gestart...',
        notificationIcon: _notificationIcon,
        callback: startBackgroundGlucoseCallback,
      );
    } catch (_) {
      // Zie docstring — de app zelf (met CGM-polling op de voorgrond) blijft
      // gewoon werken als de achtergrondservice niet lukt te starten.
    }
  }
}
