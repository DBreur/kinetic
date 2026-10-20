// food_wait_reminder_service.dart — eenmalige melding die afgaat zodra de
// ingestelde wachttijd na insuline (vóór het eten) om is. Anders dan
// finger_reminder_service.dart (herhalend, inexact) is dit een precieze
// eenmalige planning op een vast moment in de nabije toekomst.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_router.dart';
import 'notification_style.dart';

import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class FoodWaitReminderService {
  FoodWaitReminderService._();
  static final FoodWaitReminderService instance = FoodWaitReminderService._();

  // Twee kanalen omdat Android-kanalen na aanmaken onveranderlijk zijn — of
  // een melding geluid maakt, staat vast bij de eerste keer aanmaken en kan
  // daarna niet meer per melding worden omgezet op hetzelfde kanaal.
  // v2: het geluidskanaal kreeg een eigen geluidsbestand (uchivo_alarm) in
  // plaats van het systeemstandaard-meldingsgeluid — een nieuwe kanaal-ID is
  // nodig omdat bestaande installaties het oude, geluidloos-ingestelde
  // kanaal anders nooit zouden bijwerken.
  // v3: het geluidsbestand zat niet in de release-build (zie
  // res/raw/keep.xml), dus het v2-kanaal verwees naar niets.
  static const _soundChannelId = 'uchivo_food_wait_reminder_v3';
  static const _silentChannelId = 'uchivo_food_wait_reminder_silent_v3';
  static const _staleChannelIds = [
    'uchivo_food_wait_reminder',
    'uchivo_food_wait_reminder_silent',
    'uchivo_food_wait_reminder_v2',
    'uchivo_food_wait_reminder_silent_v2',
  ];
  static const _notificationId = 3001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _timeZonesInitialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> _ensureInit() async {
    if (!_timeZonesInitialized) {
      tz_data.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings(
        '@mipmap/ic_notification',
      );
      await _plugin.initialize(
        settings: const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: NotificationRouter.handle,
      );
      await deleteStaleChannels(_android, _staleChannelIds);
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _soundChannelId,
          'Tijd om te eten',
          description: 'Herinnert je dat de wachttijd na insuline om is.',
          importance: Importance.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('uchivo_alarm'),
          enableVibration: true,
        ),
      );
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _silentChannelId,
          'Tijd om te eten (stil)',
          description:
              'Herinnert je dat de wachttijd na insuline om is — zonder '
              'geluid.',
          importance: Importance.high,
          playSound: false,
          enableVibration: true,
        ),
      );
      _initialized = true;
      await _android?.requestNotificationsPermission();
    } catch (e) {
      // Geen blokkerende fout — het eetlogboek blijft gewoon opgeslagen.
      debugPrint('Eet-herinnering initialiseren mislukt: $e');
    }
  }

  /// Vraagt (indien nodig) toestemming voor exacte alarmen — alleen relevant
  /// op Android 12-13, en alleen aangeroepen op het moment dat je zelf voor
  /// het eerst een wachttijd instelt, niet bij elke appstart.
  Future<void> requestExactAlarmPermissionIfNeeded() async {
    await _ensureInit();
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {
      // Niet beschikbaar/nodig op deze Android-versie — negeren.
    }
  }

  /// Plant een eenmalige melding op [waitMinutes] na [loggedAt] (het moment
  /// waarop de eetlogboek-regel staat, meestal nu). Doet niets als dat
  /// moment al voorbij is — bv. bij het terugwerkend loggen van een oud
  /// moment, of bij het aanpassen van een eerdere regel. [withSound] volgt
  /// de instelling uit de instellingenpagina.
  Future<void> scheduleReminder(
    DateTime loggedAt,
    double waitMinutes, {
    bool withSound = true,
  }) async {
    if (waitMinutes <= 0) return;
    final fireAt = loggedAt.add(
      Duration(milliseconds: (waitMinutes * 60000).round()),
    );
    if (!fireAt.isAfter(DateTime.now())) return;
    await _ensureInit();
    try {
      final channelId = withSound ? _soundChannelId : _silentChannelId;
      final channelName = withSound
          ? 'Tijd om te eten'
          : 'Tijd om te eten (stil)';
      await _plugin.zonedSchedule(
        id: _notificationId,
        title: 'Tijd om te eten',
        body: 'De wachttijd na je insuline is om.',
        scheduledDate: tz.TZDateTime.from(fireAt, tz.UTC),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            color: kNotificationColor,
            channelId,
            channelName,
            importance: Importance.high,
            priority: Priority.high,
            playSound: withSound,
            sound: withSound
                ? const RawResourceAndroidNotificationSound('uchivo_alarm')
                : null,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      // Geen blokkerende fout — het eetlogboek blijft gewoon opgeslagen.
      debugPrint('Eet-herinnering inplannen mislukt: $e');
    }
  }
}
