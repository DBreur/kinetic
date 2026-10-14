// interval_timer.dart — herbruikbare afteller op basis van kloktijd
// (DateTime.now()), niet een Stopwatch of losse Timer-teller. Android
// pauzeert de monotone klok achter een Stopwatch zodra het scherm uit is en
// er geen wakelock is (zie de trainingsduur-fix in de sessie-controllers) —
// deze klasse is daar immuun voor en wordt gebruikt voor de set-rusttimer,
// tijd-gebaseerde sets en de circuit-fasetimer.

class IntervalTimer {
  DateTime? _endAt;

  void start(Duration duration) {
    _endAt = DateTime.now().add(duration);
  }

  void cancel() {
    _endAt = null;
  }

  bool get isRunning => remaining > Duration.zero;

  Duration get remaining {
    final endAt = _endAt;
    if (endAt == null) return Duration.zero;
    final left = endAt.difference(DateTime.now());
    return left > Duration.zero ? left : Duration.zero;
  }
}
