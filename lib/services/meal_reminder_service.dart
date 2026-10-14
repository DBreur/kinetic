// meal_reminder_service.dart — eet-herinneringen:
//   • vaste eetmomenten (bv. ontbijt 07:30): elke dag een melding, eventueel
//     een paar minuten vooraf. Steeds [daysAhead] dagen vooruit ingepland en
//     bijgewerkt als de app opent of je de instellingen wijzigt.
//   • eenmalig ("Herinner me om 18:30") vanaf de Eten-pagina.
// Eigen id-bereik (70000–72000), los van de andere meldingen.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/app_profile.dart';
import '../models/meal_reminder.dart';
import 'notification_router.dart';
import 'notification_style.dart';

class MealReminderService {
  MealReminderService._();
  static final MealReminderService instance = MealReminderService._();

  static const _channelId = 'kinetic_meal_reminder';
  static const _firstDailyId = 70000;
  static const _lastDailyId = 71999;
  static const _oneOffId = 72000;
  static const _oneOffKey = 'kinetic_meal_one_off_at';
  static const daysAhead = 14;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _lastSignature;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    tz_data.initializeTimeZones();
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_notification'),
        ),
        onDidReceiveNotificationResponse: NotificationRouter.handle,
      );
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          'Eet-herinneringen',
          description: 'Herinnering voor je vaste eetmomenten.',
          importance: Importance.high,
        ),
      );
    } catch (_) {
      // Geen meldingen beschikbaar (tests/desktop).
    }
  }

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Eet-herinneringen',
      color: kNotificationColor,
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// Vaste eetmomenten opnieuw inplannen (of allemaal weghalen als ze uit
  /// staan). Doet niets als er sinds de vorige keer niets veranderd is.
  Future<void> syncDaily(AppProfile? profile, {DateTime? now}) async {
    final plan = planMealNotifications(
      enabled: profile?.mealRemindersEnabled ?? false,
      meals: profile?.mealReminders ?? const [],
      offsetMinutes: profile?.mealReminderOffset ?? 0,
      now: now ?? DateTime.now(),
    );
    final signature = [
      for (final p in plan) '${p.id}|${p.at.millisecondsSinceEpoch}|${p.title}',
    ].join(';');
    if (signature == _lastSignature) return;
    await _ensureInit();
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= _firstDailyId && p.id <= _lastDailyId) {
          await _plugin.cancel(id: p.id);
        }
      }
      for (final p in plan) {
        await _plugin.zonedSchedule(
          id: p.id,
          title: p.title,
          body: p.body,
          scheduledDate: tz.TZDateTime.from(p.at, tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      _lastSignature = signature;
    } catch (_) {
      // Niet blokkerend.
    }
  }

  /// Eenmalige herinnering op [at] ("Herinner me om …").
  Future<void> scheduleOneOff(DateTime at) async {
    if (!at.isAfter(DateTime.now())) return;
    await _ensureInit();
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {}
    Future<void> plan(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: _oneOffId,
      title: 'Tijd om te eten',
      body: 'Je had een herinnering gezet. Vergeet niet te loggen.',
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: mode,
    );
    try {
      await plan(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      try {
        await plan(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_oneOffKey, at.toUtc().toIso8601String());
    } catch (_) {}
  }

  Future<void> cancelOneOff() async {
    await _ensureInit();
    try {
      await _plugin.cancel(id: _oneOffId);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_oneOffKey);
    } catch (_) {}
  }

  bool? _lastOneOffEnabled;

  /// Eenmalige herinnering uitgezet in de instellingen → een openstaande
  /// herinnering vervalt. Alleen bij een wijziging, niet bij elke aanroep.
  Future<void> syncOneOff(bool enabled) async {
    if (_lastOneOffEnabled == enabled) return;
    _lastOneOffEnabled = enabled;
    if (!enabled && await pendingOneOff() != null) await cancelOneOff();
  }

  /// De ingestelde eenmalige herinnering, als die nog moet komen.
  Future<DateTime?> pendingOneOff() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_oneOffKey);
      final at = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
      if (at == null || !at.isAfter(DateTime.now())) return null;
      return at;
    } catch (_) {
      return null;
    }
  }
}

class PlannedMealNotification {
  final int id;
  final DateTime at;
  final String title;
  final String body;
  const PlannedMealNotification(this.id, this.at, this.title, this.body);
}

/// Pure planning (te testen zonder plugin): voor elk eetmoment een melding
/// per dag, [offsetMinutes] vooraf, alleen in de toekomst, [days] dagen.
List<PlannedMealNotification> planMealNotifications({
  required bool enabled,
  required List<MealReminder> meals,
  required int offsetMinutes,
  required DateTime now,
  int days = MealReminderService.daysAhead,
}) {
  if (!enabled || meals.isEmpty) return const [];
  final result = <PlannedMealNotification>[];
  final today = DateTime(now.year, now.month, now.day);
  var id = MealReminderService._firstDailyId;
  for (var d = 0; d <= days; d++) {
    for (final meal in meals) {
      final mealAt = DateTime(
        today.year,
        today.month,
        today.day + d,
      ).add(Duration(minutes: meal.minutesOfDay));
      final at = mealAt.subtract(Duration(minutes: offsetMinutes));
      if (!at.isAfter(now)) continue;
      if (id > MealReminderService._lastDailyId) return result;
      result.add(
        PlannedMealNotification(
          id++,
          at,
          offsetMinutes > 0
              ? 'Over $offsetMinutes min: ${meal.label}'
              : 'Tijd voor ${meal.label.toLowerCase()}',
          'Om ${meal.time}. Vergeet niet je maaltijd te loggen.',
        ),
      );
    }
  }
  return result;
}
