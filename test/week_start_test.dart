import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:kinetic/core/kinetic_localizations.dart';
import 'package:kinetic/models/app_profile.dart';

void main() {
  setUpAll(() => initializeDateFormatting('nl_NL'));

  Future<MaterialLocalizations> loc(WidgetTester tester, int weekStart) async {
    late MaterialLocalizations result;
    await tester.pumpWidget(
      MaterialApp(
        locale: kineticLocale,
        supportedLocales: const [kineticLocale],
        localizationsDelegates: kineticLocalizationsDelegates(weekStart),
        home: Builder(
          builder: (context) {
            result = MaterialLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('standaard: week begint op maandag, teksten in het Nederlands', (
    tester,
  ) async {
    final l = await loc(tester, 1);
    expect(l.firstDayOfWeekIndex, 1);
    expect(l.cancelButtonLabel.toLowerCase(), 'annuleren');
    expect(l.formatMonthYear(DateTime(2026, 10)), 'oktober 2026');
  });

  testWidgets('instelbaar: zondag of zaterdag', (tester) async {
    expect((await loc(tester, 0)).firstDayOfWeekIndex, 0);
    expect((await loc(tester, 6)).firstDayOfWeekIndex, 6);
  });

  test('weekstart staat in het profiel, standaard maandag', () {
    expect(AppProfile.defaults('u').weekStart, 1);
    final p = AppProfile.defaults('u').copyWith(weekStart: 0);
    expect(AppProfile.fromJson(p.toJson()).weekStart, 0);
    expect(AppProfile.fromJson({'id': 'u'}).weekStart, 1);
  });
}
