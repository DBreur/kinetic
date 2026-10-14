// finger_reminder_service.dart — periodieke herinnering om handmatig te
// meten (vingerprik), los van het hypo-alarm. Komt ook binnen als de app
// gesloten is (via het OS, niet via de achtergrondservice), en is geen
// alarm: gewoon volume/kanaal, geen FLAG_INSISTENT, geen full-screen intent.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_router.dart';
import 'notification_style.dart';

import '../models/app_profile.dart';

class FingerReminderService {
  FingerReminderService._();
  static final FingerReminderService instance = FingerReminderService._();

  static const channelId = 'uchivo_finger_reminder';
  static const _notificationId = 2001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Voorkomt dat elke onbeduidende profielwijziging de teller opnieuw laat
  /// beginnen — alleen echt herplannen als deze instellingen veranderd zijn.
  String? _lastSignature;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    try {
      const androidInit = AndroidInitializationSettings(
        '@mipmap/ic_notification',
      );
      await _plugin.initialize(
        settings: const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: NotificationRouter.handle,
      );
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          'Vingerprik-herinnering',
          description:
              'Herinnert je om je glucose handmatig te meten — geen alarm.',
          importance: Importance.defaultImportance,
          playSound: true,
          enableVibration: true,
        ),
      );
      await _android?.requestNotificationsPermission();
    } catch (_) {
      // Geen blokkerende fout — de app blijft verder gewoon werken.
    }
  }

  /// Plant de herinnering opnieuw als de relevante instellingen (aan/uit,
  /// bereik, interval) of de actieve glucosebron veranderd zijn; annuleert
  /// 'm als hij niet (meer) van toepassing is.
  Future<void> sync(AppProfile? profile) async {
    try {
      final shouldRun =
          profile != null &&
          profile.fingerReminderEnabled &&
          profile.fingerReminderScope.matches(profile.glucoseSource);

      final signature = shouldRun
          ? '${profile.fingerReminderIntervalMinutes}-${profile.fingerReminderScope.name}-${profile.glucoseSource.name}'
          : null;
      if (signature == _lastSignature) return;
      _lastSignature = signature;

      if (!shouldRun) {
        await _plugin.cancel(id: _notificationId);
        return;
      }

      await _ensureInit();
      await _plugin.periodicallyShowWithDuration(
        id: _notificationId,
        title: 'Tijd voor een vingerprik',
        body: 'Meet je glucose en noteer hem in Kinetic.',
        repeatDurationInterval: Duration(
          minutes: profile.fingerReminderIntervalMinutes,
        ),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            color: kNotificationColor,
            channelId,
            'Vingerprik-herinnering',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            playSound: true,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      // Zie docstring bij _ensureInit().
    }
  }
}
