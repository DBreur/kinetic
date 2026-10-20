// interval_timer.dart — herbruikbare afteller op basis van kloktijd
// (DateTime.now()), niet een Stopwatch of losse Timer-teller. Android
// pauzeert de monotone klok achter een Stopwatch zodra het scherm uit is en
// er geen wakelock is (zie de trainingsduur-fix in de sessie-controllers) —
// deze klasse is daar immuun voor en wordt gebruikt voor de set-rusttimer,
// tijd-gebaseerde sets en de circuit-fasetimer.
//
// Pauzeren bevriest de resterende tijd: tijdens de pauze blijft [remaining]
// staan (en telt [isRunning] als lopend, zodat niets denkt dat de tijd om
// is), na [resume] telt hij verder vanaf daar.

class IntervalTimer {
  DateTime? _endAt;
  Duration? _pausedLeft;

  void start(Duration duration) {
    _pausedLeft = null;
    _endAt = DateTime.now().add(duration);
  }

  void cancel() {
    _endAt = null;
    _pausedLeft = null;
  }

  bool get isPaused => _pausedLeft != null;

  /// Bevriest de resterende tijd. Doet niets als hij niet loopt.
  void pause() {
    if (isPaused || _endAt == null) return;
    _pausedLeft = remaining;
    _endAt = null;
  }

  void resume() {
    final left = _pausedLeft;
    if (left == null) return;
    _pausedLeft = null;
    _endAt = DateTime.now().add(left);
  }

  bool get isRunning => remaining > Duration.zero;

  Duration get remaining {
    final paused = _pausedLeft;
    if (paused != null) return paused;
    final endAt = _endAt;
    if (endAt == null) return Duration.zero;
    final left = endAt.difference(DateTime.now());
    return left > Duration.zero ? left : Duration.zero;
  }
}
