// alarm_notification_service.dart — toont het hypo/hyper-alarm ook als het
// scherm uit staat of de app op de achtergrond draait, via een systeem-
// notificatie (FLAG_INSISTENT: herhaalt tot je 'm wegtikt of de sheet zelf
// sluit).
//
// Kanalen:
// (v3: de eerdere kanalen verwezen naar een geluidsbestand dat de release-
// build had weggegooid — zie res/raw/keep.xml — en trilden dus alleen.)
//
//   uchivo_glucose_alarm        — geluid + trilling, via het alarmvolume
//                                 (breekt de stille modus/DND)
//   uchivo_glucose_alarm_normal — geluid + trilling, via het gewone
//                                 notificatievolume (respecteert de stille
//                                 modus) — gebruikt als "Doorbreek stille
//                                 modus" uit staat. Android-kanalen zijn na
//                                 aanmaken onveranderlijk, dus dit kan geen
//                                 los alarmvolume-vlaggetje op hetzelfde
//                                 kanaal zijn — vandaar dit aparte kanaal.
//   uchivo_glucose_alarm_silent — alleen trilling, geen geluid
// Een vierde, minder opdringerig kanaal voor de "geen data"-waarschuwing en
// de "meet opnieuw"-herinnering, die geen hypo-styling hebben.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_router.dart';
import 'notification_style.dart';

/// Wat `GlucoseAlarmGuard` nodig heeft om een systeemnotificatie te tonen —
/// als interface, zodat een test een neppe implementatie kan geven in
/// plaats van het echte platformkanaal aan te roken.
abstract class GlucoseAlarmNotifier {
  Future<void> showAlarm({
    required bool withSound,
    required bool breakSilentMode,
    required bool isHigh,
    required double mmol,
  });
  Future<void> cancelAlarm();
  Future<void> showRemeasureReminder({
    required bool withSound,
    required double currentValue,
  });
  Future<void> showStaleWarning({required bool withSound});
}

class AlarmNotificationService implements GlucoseAlarmNotifier {
  AlarmNotificationService._();
  static final AlarmNotificationService instance = AlarmNotificationService._();

  static const soundChannelId = 'uchivo_glucose_alarm_v3';
  static const normalSoundChannelId = 'uchivo_glucose_alarm_normal_v3';
  static const _staleChannelIds = [
    'uchivo_glucose_alarm',
    'uchivo_glucose_alarm_normal',
  ];
  static const silentChannelId = 'uchivo_glucose_alarm_silent';
  static const infoChannelId = 'uchivo_glucose_info';

  static const _alarmNotificationId = 1001;
  static const _infoNotificationId = 1002;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Maakt de kanalen aan en vraagt de nodige runtime-toestemming (Android
  /// 13+ voor notificaties, Android 14+ voor full-screen intents). Wordt
  /// pas aangeroepen op het moment dat het alarm voor het eerst nodig is —
  /// niet al bij het opstarten van de app.
  ///
  /// Faalt hier bewust nooit hardop: dit is altijd een aanvulling op de
  /// alarmsheet in de app zelf, nooit de enige plek waar het alarm vandaan
  /// komt. Zonder platformkanaal (bv. in een test, of op een niet-Android
  /// platform) blijft de sheet gewoon werken.
  Future<void> init() async {
    if (_initialized) return;

    try {
      const androidInit = AndroidInitializationSettings(
        '@mipmap/ic_notification',
      );
      await _plugin.initialize(
        settings: const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: NotificationRouter.handle,
      );

      final android = _android;
      if (android == null) {
        _initialized = true;
        return;
      }
      await deleteStaleChannels(android, _staleChannelIds);

      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          soundChannelId,
          'Glucose-alarm',
          description:
              'Hypo- of hyper-alarm met geluid — gaat over de stille modus '
              'heen.',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('uchivo_alarm'),
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableVibration: true,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          normalSoundChannelId,
          'Glucose-alarm (normaal volume)',
          description:
              'Hypo- of hyper-alarm met geluid, via het gewone '
              'notificatievolume — respecteert de stille modus.',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('uchivo_alarm'),
          enableVibration: true,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          silentChannelId,
          'Glucose-alarm (stil)',
          description:
              'Hypo- of hyper-alarm zonder geluid — scherm en trilling.',
          importance: Importance.max,
          playSound: false,
          enableVibration: true,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          infoChannelId,
          'Sensor- en hermeet-meldingen',
          description:
              'Waarschuwt als er geen glucosedata binnenkomt, of herinnert '
              'je aan een hermeting — geen hypo-styling.',
          importance: Importance.high,
        ),
      );

      _initialized = true;
      await android.requestNotificationsPermission();
      await android.requestFullScreenIntentPermission();
    } catch (e) {
      // Zie docstring — de in-app alarmsheet blijft de bron van waarheid.
      // Niet als geïnitialiseerd gemarkeerd: de volgende keer opnieuw.
      debugPrint('Alarmmeldingen initialiseren mislukt: $e');
    }
  }

  @override
  Future<void> showAlarm({
    required bool withSound,
    required bool breakSilentMode,
    required bool isHigh,
    required double mmol,
  }) async {
    try {
      await init();
      final String channelId;
      final String channelName;
      if (!withSound) {
        channelId = silentChannelId;
        channelName = 'Glucose-alarm (stil)';
      } else if (breakSilentMode) {
        channelId = soundChannelId;
        channelName = 'Glucose-alarm';
      } else {
        channelId = normalSoundChannelId;
        channelName = 'Glucose-alarm (normaal volume)';
      }
      final title = isHigh ? 'Glucose te hoog' : 'Hypo dreigt';
      final value = mmol.toStringAsFixed(1).replaceAll('.', ',');
      final details = AndroidNotificationDetails(
        color: kNotificationColor,
        channelId,
        channelName,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        playSound: withSound,
        enableVibration: true,
        // FLAG_INSISTENT: het geluid/de trilling herhaalt tot de notificatie
        // wordt geannuleerd (getikt, of de sheet zelf gaat dicht).
        additionalFlags: Int32List.fromList(<int>[4]),
        actions: const [
          // Opent de app (daar loopt de sluimer-timer) en sluit de melding.
          AndroidNotificationAction(
            kSnoozeAlarmActionId,
            'Sluimeren',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );
      await _plugin.show(
        id: _alarmNotificationId,
        title: title,
        body: '$value mmol/L — tik om te openen',
        notificationDetails: NotificationDetails(android: details),
        payload: AlarmSnoozeRequest.payloadFor(isHigh: isHigh, mmol: mmol),
      );
    } catch (e) {
      // Zie docstring bij init().
      debugPrint('Alarmmelding mislukt: $e');
    }
  }

  @override
  Future<void> cancelAlarm() async {
    try {
      await _plugin.cancel(id: _alarmNotificationId);
    } catch (e) {
      // Zie docstring bij init().
      debugPrint('Alarmmelding mislukt: $e');
    }
  }

  @override
  Future<void> showRemeasureReminder({
    required bool withSound,
    required double currentValue,
  }) async {
    try {
      await init();
      final value = currentValue.toStringAsFixed(1).replaceAll('.', ',');
      final details = AndroidNotificationDetails(
        color: kNotificationColor,
        infoChannelId,
        'Sensor- en hermeet-meldingen',
        importance: Importance.high,
        priority: Priority.high,
        playSound: withSound,
        enableVibration: true,
      );
      await _plugin.show(
        id: _infoNotificationId,
        title: 'Meet opnieuw',
        body: 'Huidige waarde: $value mmol/L',
        notificationDetails: NotificationDetails(android: details),
      );
    } catch (e) {
      // Zie docstring bij init().
      debugPrint('Alarmmelding mislukt: $e');
    }
  }

  @override
  Future<void> showStaleWarning({required bool withSound}) async {
    try {
      await init();
      final details = AndroidNotificationDetails(
        color: kNotificationColor,
        infoChannelId,
        'Sensor- en hermeet-meldingen',
        importance: Importance.high,
        priority: Priority.high,
        playSound: withSound,
        enableVibration: true,
      );
      await _plugin.show(
        id: _infoNotificationId,
        title: 'Kinetic',
        body:
            'Geen glucosedata ontvangen — controleer je sensor of meet met '
            'een vingerprik.',
        notificationDetails: NotificationDetails(android: details),
      );
    } catch (e) {
      // Zie docstring bij init().
      debugPrint('Alarmmelding mislukt: $e');
    }
  }
}
