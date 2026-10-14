import 'package:intl/intl.dart';

String mmolText(double value) => value.toStringAsFixed(1).replaceAll('.', ',');

/// Koolhydraten zijn meestal hele grammen — geen ",0" erbij als het niet
/// nodig is.
String carbsText(double value) => value % 1 == 0
    ? value.toInt().toString()
    : value.toStringAsFixed(1).replaceAll('.', ',');

String dutchDateTime(DateTime dateTime) {
  return DateFormat('EEEE d MMM · HH:mm', 'nl_NL').format(dateTime);
}

String dutchShortDate(DateTime dateTime) {
  return DateFormat('EEE d MMM', 'nl_NL').format(dateTime);
}

/// Label voor een geplande datum in de planning-sectie van het tabblad
/// Technieken: "Vandaag"/"Morgen", anders een korte datum, en bij een
/// verstreken datum "Te laat · N dagen" — bewust nooit rood/amber, dat is
/// voorbehouden aan glucose.
String planningLabel(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;
  if (diff == 0) return 'Vandaag';
  if (diff == 1) return 'Morgen';
  if (diff < 0) {
    final days = -diff;
    return 'Te laat · $days ${days == 1 ? 'dag' : 'dagen'}';
  }
  return dutchShortDate(date);
}

String relativeDutch(DateTime dateTime, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(dateTime);
  if (diff.inSeconds < 45) return 'Zojuist';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min geleden';
  if (diff.inHours < 24) return '${diff.inHours} uur geleden';
  return dutchShortDate(dateTime);
}
