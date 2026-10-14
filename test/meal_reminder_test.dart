import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/models/meal_reminder.dart';
import 'package:kinetic/services/meal_reminder_service.dart';

void main() {
  final now = DateTime(2026, 10, 14, 10, 0);
  const meals = [
    MealReminder(label: 'Ontbijt', time: '07:30'),
    MealReminder(label: 'Lunch', time: '12:30'),
  ];

  test('uit of geen eetmomenten: niets plannen', () {
    expect(
      planMealNotifications(enabled: false, meals: meals, offsetMinutes: 0, now: now),
      isEmpty,
    );
    expect(
      planMealNotifications(enabled: true, meals: const [], offsetMinutes: 0, now: now),
      isEmpty,
    );
  });

  test('elke dag per eetmoment, alleen in de toekomst', () {
    final plan = planMealNotifications(
      enabled: true,
      meals: meals,
      offsetMinutes: 0,
      now: now,
      days: 2,
    );
    // Vandaag is ontbijt al voorbij: lunch vandaag + 2× morgen + 2× overmorgen.
    expect(plan.map((p) => p.at), [
      DateTime(2026, 10, 14, 12, 30),
      DateTime(2026, 10, 15, 7, 30),
      DateTime(2026, 10, 15, 12, 30),
      DateTime(2026, 10, 16, 7, 30),
      DateTime(2026, 10, 16, 12, 30),
    ]);
    expect(plan.first.title, 'Tijd voor lunch');
    expect(plan.map((p) => p.id).toSet().length, plan.length);
  });

  test('melding vooraf schuift het tijdstip en de tekst', () {
    final plan = planMealNotifications(
      enabled: true,
      meals: meals,
      offsetMinutes: 15,
      now: now,
      days: 0,
    );
    expect(plan.single.at, DateTime(2026, 10, 14, 12, 15));
    expect(plan.single.title, 'Over 15 min: Lunch');
    expect(plan.single.body, contains('12:30'));
  });

  test('instellingen staan in het profiel', () {
    final p = AppProfile.defaults('u').copyWith(
      mealRemindersEnabled: true,
      mealReminders: meals,
      mealReminderOffset: 10,
      mealOneOffEnabled: false,
    );
    final back = AppProfile.fromJson(p.toJson());
    expect(back.mealRemindersEnabled, isTrue);
    expect(back.mealReminders.map((m) => m.label), ['Ontbijt', 'Lunch']);
    expect(back.mealReminders.last.time, '12:30');
    expect(back.mealReminderOffset, 10);
    expect(back.mealOneOffEnabled, isFalse);
    final fresh = AppProfile.fromJson({'id': 'u'});
    expect(fresh.mealRemindersEnabled, isFalse);
    expect(fresh.mealOneOffEnabled, isTrue);
  });
}
