// heart_rate_source.dart: hartslag voor de Polar H10-widgets.
//
// Er is nog geen echte BLE-koppeling: [SimulatedPolarH10] volgt een
// realistisch patroon (oplopen tijdens werk, ~30 BPM zakken per 45s rust),
// zodat de schermen werken. De UI toont overal "SIMULATIE" zolang
// [isSimulated] waar is, en gesimuleerde waarden worden nooit opgeslagen.
// Een echte H10-bron (Heart Rate Service 0x180D, characteristic 0x2A37)
// implementeert straks dezelfde interface.

import 'dart:math' as math;

import '../core/sparring_timer.dart';

abstract class HeartRateSource {
  int get bpm;
  bool get isSimulated;

  /// Aanroepen per seconde met de huidige fase (null = geen sessie).
  void update(SparringPhase? phase, DateTime now);
}

class SimulatedPolarH10 implements HeartRateSource {
  SimulatedPolarH10({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  double _bpm = 72;
  DateTime? _last;

  @override
  bool get isSimulated => true;

  @override
  int get bpm => _bpm.round();

  @override
  void update(SparringPhase? phase, DateTime now) {
    final dt = _last == null
        ? 1.0
        : (now.difference(_last!).inMilliseconds / 1000).clamp(0.0, 30.0);
    _last = now;
    final wave = math.sin(now.millisecondsSinceEpoch / 9000) * 6;
    final target = switch (phase) {
      SparringPhase.work => 166 + wave,
      SparringPhase.rest => 112 + wave / 2,
      _ => 74 + wave / 3,
    };
    // Omhoog ~2 BPM/s, omlaag ~0.67 BPM/s (≈ -30 BPM per 45s).
    final rate = target > _bpm ? 2.0 : 0.67;
    final step = math.min((target - _bpm).abs(), rate * dt);
    _bpm += (target > _bpm ? step : -step) + (_random.nextDouble() - 0.5);
  }
}

const int defaultMaxHeartRate = 190;

class HeartRateZone {
  final int zone;
  final String name;
  final int percentOfMax;
  const HeartRateZone(this.zone, this.name, this.percentOfMax);

  String get label => 'Zone $zone • $name';
}

HeartRateZone heartRateZone(int bpm, {int maxHr = defaultMaxHeartRate}) {
  final pct = (bpm / maxHr * 100).round();
  final (zone, name) = switch (pct) {
    < 60 => (1, 'Herstel'),
    < 70 => (2, 'Basis'),
    < 80 => (3, 'Aeroob'),
    < 90 => (4, 'Drempel'),
    _ => (5, 'Maximaal'),
  };
  return HeartRateZone(zone, name, pct);
}
