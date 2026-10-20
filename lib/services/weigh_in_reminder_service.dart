// weigh_in_reminder_service.dart — één melding "Tijd om te wegen", op de
// geplande volgende weging (laatste weging + interval, zie
// core/weigh_in_plan.dart). Wordt opnieuw ingepland bij elke weging en elke
// wijziging van het interval. Eigen id (74000), los van de andere meldingen.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/weigh_in_plan.dart';
import '../models/app_profile.dart';
import 'notification_router.dart';
import 'notification_style.dart';

class WeighInReminderService {
  WeighInReminderService._();
  static final WeighInReminderService instance = WeighInReminderService._();

  static const _channelId = 'kinetic_weigh_in';
  static const _notificationId = 74000;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _lastSignature;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_notification'),
        ),
        onDidReceiveNotificationResponse: NotificationRouter.handle,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              'Wegen',
              description: 'Herinnering als het tijd is om te wegen.',
              importance: Importance.high,
            ),
          );
      _initialized = true;
    } catch (e) {
      debugPrint('Weeg-herinnering initialiseren mislukt: $e');
    }
  }

  /// Plant de herinnering (opnieuw) in, of haalt hem weg als er geen
  /// interval is. Doet niets als er sinds de vorige keer niets veranderd is.
  Future<void> sync(AppProfile? profile, DateTime? lastWeighIn) async {
    final now = DateTime.now();
    final next = nextWeighIn(
      last: lastWeighIn,
      intervalDays: profile?.weighInIntervalDays ?? 0,
      reminderTime: profile?.weighInReminderTime ?? '08:00',
      now: now,
    );
    final at = weighInReminderAt(
      next: next,
      reminderTime: profile?.weighInReminderTime ?? '08:00',
      now: now,
    );
    final signature = at?.toIso8601String() ?? 'none';
    if (signature == _lastSignature) return;
    await _ensureInit();
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _notificationId);
      if (at != null) {
        await _plugin.zonedSchedule(
          id: _notificationId,
          title: 'Tijd om te wegen',
          body: 'Weeg jezelf en vul het in bij je profiel.',
          scheduledDate: tz.TZDateTime.from(at, tz.UTC),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'Wegen',
              color: kNotificationColor,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      _lastSignature = signature;
    } catch (e) {
      debugPrint('Weeg-herinnering inplannen mislukt: $e');
    }
  }
}
