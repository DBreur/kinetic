// kinetic_localizations.dart — Nederlandse Material-teksten (datumkiezer,
// knoppen, maandnamen) met een instelbare eerste dag van de week. Zonder
// dit gebruikt Flutter de Engelse standaard: week begint op zondag.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' as intl;

class KineticMaterialLocalizations extends MaterialLocalizationNl {
  KineticMaterialLocalizations({
    required this.weekStart,
    required super.fullYearFormat,
    required super.compactDateFormat,
    required super.shortDateFormat,
    required super.mediumDateFormat,
    required super.longDateFormat,
    required super.yearMonthFormat,
    required super.shortMonthDayFormat,
    required super.decimalFormat,
    required super.twoDigitZeroPaddedFormat,
  });

  /// 0 = zondag, 1 = maandag, 6 = zaterdag.
  final int weekStart;

  @override
  int get firstDayOfWeekIndex => weekStart;
}

class KineticMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const KineticMaterialLocalizationsDelegate({this.weekStart = 1});

  final int weekStart;

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'nl';

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    const name = 'nl';
    // Zelf de Nederlandse datumgegevens laden (net als Flutters eigen
    // delegate), in plaats van te vertrouwen op een aanroep in main(). Met
    // de lokale data gebeurt dit synchroon; de Future hoeft niet gewacht.
    initializeDateFormatting('nl_NL');
    return SynchronousFuture(
      KineticMaterialLocalizations(
        weekStart: weekStart,
        fullYearFormat: intl.DateFormat.y(name),
        compactDateFormat: intl.DateFormat.yMd(name),
        shortDateFormat: intl.DateFormat.yMMMd(name),
        mediumDateFormat: intl.DateFormat.MMMEd(name),
        longDateFormat: intl.DateFormat.yMMMMEEEEd(name),
        yearMonthFormat: intl.DateFormat.yMMMM(name),
        shortMonthDayFormat: intl.DateFormat.MMMd(name),
        decimalFormat: intl.NumberFormat.decimalPattern(name),
        twoDigitZeroPaddedFormat: intl.NumberFormat('00', name),
      ),
    );
  }

  @override
  bool shouldReload(KineticMaterialLocalizationsDelegate old) =>
      old.weekStart != weekStart;
}

/// Alle delegates voor MaterialApp, met de gekozen eerste weekdag.
List<LocalizationsDelegate<dynamic>> kineticLocalizationsDelegates(
  int weekStart,
) => [
  KineticMaterialLocalizationsDelegate(weekStart: weekStart),
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

const kineticLocale = Locale('nl', 'NL');
