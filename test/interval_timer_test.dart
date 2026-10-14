import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/interval_timer.dart';

void main() {
  test('start/remaining/isRunning/cancel op basis van echte kloktijd', () async {
    final timer = IntervalTimer();
    expect(timer.isRunning, isFalse);
    expect(timer.remaining, Duration.zero);

    timer.start(const Duration(milliseconds: 200));
    expect(timer.isRunning, isTrue);
    expect(timer.remaining.inMilliseconds, greaterThan(0));

    await Future.delayed(const Duration(milliseconds: 260));
    expect(timer.isRunning, isFalse);
    expect(timer.remaining, Duration.zero);
  });

  test('cancel() stopt de aftelling meteen', () {
    final timer = IntervalTimer();
    timer.start(const Duration(seconds: 10));
    expect(timer.isRunning, isTrue);

    timer.cancel();
    expect(timer.isRunning, isFalse);
    expect(timer.remaining, Duration.zero);
  });
}
