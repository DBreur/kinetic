// formatters.dart: Nederlandse notatie voor tijden, duur en getallen.

String two(int n) => n.toString().padLeft(2, '0');

/// 198 → "03:18".
String mmss(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  return '${two(s ~/ 60)}:${two(s % 60)}';
}

String hhmm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

/// 525 → "8u 45m", 65 → "1u 05m", 40 → "40 min".
String durationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60}u ${two(minutes % 60)}m';
}

/// 462 → "7h 42m" (slaap).
String sleepLabel(int minutes) => '${minutes ~/ 60}h ${two(minutes % 60)}m';

/// Eén decimaal met punt, zoals de spec (78.4 kg, 6.5 mmol/L).
String dec1(double v) => v.toStringAsFixed(1);

/// Gram zonder overbodige ".0".
String grams(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// 2450 → "2.450" (Nederlandse duizendtallen).
String thousands(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}$b';
}

const _days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
const _months = [
  'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
  'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
];
const _monthsLong = [
  'januari', 'februari', 'maart', 'april', 'mei', 'juni',
  'juli', 'augustus', 'september', 'oktober', 'november', 'december',
];

/// "ma 24 nov".
String shortDate(DateTime d) =>
    '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// "28 november".
String longDate(DateTime d) => '${d.day} ${_monthsLong[d.month - 1]}';

String monthShort(int month) => _months[month - 1];

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

/// Hele kalenderdagen tot [target] (vandaag = 0).
int daysUntil(DateTime target, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return dayStart(target).difference(dayStart(n)).inDays;
}
