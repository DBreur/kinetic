// sparring_timer.dart: de rondeklok van de live sessie als pure
// statemachine. Rekent met eindtijdstippen (wandklok) in plaats van een
// teller die per tick afloopt: zo klopt de tijd ook als het scherm even uit
// ging of de app op de achtergrond stond.

import 'dart:math' as math;

enum SparringPhase { work, rest, done }

enum SparringEvent { restStarted, roundStarted, finished, restHeld }

class SparringConfig {
  final int rounds;
  final int workSeconds;
  final int restSeconds;

  const SparringConfig({
    this.rounds = 5,
    this.workSeconds = 300,
    this.restSeconds = 60,
    this.roundWork,
    this.roundRest,
  });

  /// Per ronde een eigen werktijd (index 0 = ronde 1); null = [workSeconds].
  final List<int>? roundWork;

  /// Rust ná ronde n (index 0 = na ronde 1); null = [restSeconds].
  final List<int>? roundRest;

  int workFor(int round) {
    final w = roundWork;
    return w != null && round >= 1 && round <= w.length ? w[round - 1] : workSeconds;
  }

  int restAfter(int round) {
    final r = roundRest;
    return r != null && round >= 1 && round <= r.length ? r[round - 1] : restSeconds;
  }

  SparringConfig copyWithRounds(int rounds, int workSeconds, int restSeconds) =>
      SparringConfig(rounds: rounds, workSeconds: workSeconds, restSeconds: restSeconds);

  String get summary =>
      '$rounds × ${_m(workSeconds)} / ${_m(restSeconds)} rust';

  static String _m(int s) =>
      s % 60 == 0 ? '${s ~/ 60}:00' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'rounds': rounds,
    'work': workSeconds,
    'rest': restSeconds,
    'round_work': ?roundWork,
    'round_rest': ?roundRest,
  };

  factory SparringConfig.fromJson(Map<String, dynamic> j) => SparringConfig(
    rounds: (j['rounds'] as num?)?.toInt() ?? 5,
    workSeconds: (j['work'] as num?)?.toInt() ?? 300,
    restSeconds: (j['rest'] as num?)?.toInt() ?? 60,
    roundWork: (j['round_work'] as List?)?.map((e) => (e as num).toInt()).toList(),
    roundRest: (j['round_rest'] as List?)?.map((e) => (e as num).toInt()).toList(),
  );
}

class SparringTimer {
  SparringTimer({required this.config, required DateTime now})
    : startedAt = now,
      round = 1,
      phase = SparringPhase.work,
      phaseStartedAt = now,
      _endsAt = now.add(Duration(seconds: config.workFor(1)));

  SparringTimer._restore({
    required this.config,
    required this.startedAt,
    required this.round,
    required this.phase,
    required this.phaseStartedAt,
    required this._endsAt,
    required this._pausedRemaining,
    required this.restHeld,
  });

  /// Kan tijdens het sparren worden aangepast, zie [reconfigure].
  SparringConfig config;
  final DateTime startedAt;
  int round;
  SparringPhase phase;
  DateTime phaseStartedAt;
  DateTime? _endsAt;
  int? _pausedRemaining;

  /// De rust is op 0 gekomen maar de volgende ronde is tegengehouden
  /// (bijvoorbeeld door een hypo). Wacht op een expliciete start.
  bool restHeld = false;

  bool get isPaused => _pausedRemaining != null;
  bool get isLastRound => round >= config.rounds;
  bool get isDone => phase == SparringPhase.done;

  int remaining(DateTime now) {
    if (phase == SparringPhase.done) return 0;
    final paused = _pausedRemaining;
    if (paused != null) return paused;
    final ms = _endsAt!.difference(now).inMilliseconds;
    return math.max(0, (ms / 1000).ceil());
  }

  int phaseLength() => phase == SparringPhase.work
      ? config.workFor(round)
      : config.restAfter(round);

  /// Hoeveel van de huidige fase al voorbij is (0..1), voor de voortgangsring.
  double phaseProgress(DateTime now) {
    final len = phaseLength();
    if (len <= 0) return 1;
    return (1 - remaining(now) / len).clamp(0.0, 1.0);
  }

  void pause(DateTime now) {
    if (isPaused || isDone) return;
    _pausedRemaining = remaining(now);
  }

  void resume(DateTime now) {
    final paused = _pausedRemaining;
    if (paused == null) return;
    _endsAt = now.add(Duration(seconds: paused));
    _pausedRemaining = null;
  }

  void togglePause(DateTime now) => isPaused ? resume(now) : pause(now);

  /// Werk → rust, of klaar na de laatste ronde.
  void toRest(DateTime now) {
    _pausedRemaining = null;
    restHeld = false;
    if (isLastRound) {
      phase = SparringPhase.done;
      _endsAt = now;
      return;
    }
    phase = SparringPhase.rest;
    phaseStartedAt = now;
    _endsAt = now.add(Duration(seconds: config.restAfter(round)));
  }

  void addRest(int seconds, DateTime now) {
    if (phase != SparringPhase.rest) return;
    restHeld = false;
    final paused = _pausedRemaining;
    if (paused != null) {
      _pausedRemaining = paused + seconds;
      return;
    }
    final base = remaining(now) == 0 ? now : _endsAt!;
    _endsAt = base.add(Duration(seconds: seconds));
  }

  void startNextRound(DateTime now) {
    if (isDone) return;
    if (phase == SparringPhase.rest) round = math.min(round + 1, config.rounds);
    phase = SparringPhase.work;
    phaseStartedAt = now;
    restHeld = false;
    _pausedRemaining = null;
    _endsAt = now.add(Duration(seconds: config.workFor(round)));
  }

  /// Nieuwe rondes/duur tijdens het sparren. De lopende fase schuift mee
  /// met het verschil in duur (5:00 → 4:00 haalt een minuut van de klok af).
  void reconfigure(SparringConfig next, DateTime now) {
    final oldLength = phaseLength();
    config = next;
    if (isDone) return;
    if (round > next.rounds) round = next.rounds;
    final delta = phaseLength() - oldLength;
    if (delta == 0) return;
    final paused = _pausedRemaining;
    if (paused != null) {
      _pausedRemaining = math.max(0, paused + delta);
    } else if (_endsAt != null) {
      _endsAt = _endsAt!.add(Duration(seconds: delta));
    }
  }

  /// Rondt een sessie vroegtijdig af.
  void finish(DateTime now) {
    phase = SparringPhase.done;
    _pausedRemaining = null;
    _endsAt = now;
  }

  /// Aanroepen per seconde. Geeft een event terug zodra een fase afloopt.
  /// Met [holdRest] start de volgende ronde niet vanzelf na de rust.
  SparringEvent? tick(DateTime now, {bool holdRest = false}) {
    if (isPaused || isDone || restHeld) return null;
    if (remaining(now) > 0) return null;
    if (phase == SparringPhase.work) {
      toRest(now);
      return isDone ? SparringEvent.finished : SparringEvent.restStarted;
    }
    if (holdRest) {
      restHeld = true;
      return SparringEvent.restHeld;
    }
    startNextRound(now);
    return SparringEvent.roundStarted;
  }

  Map<String, dynamic> toJson() => {
    'config': config.toJson(),
    'started_at': startedAt.toIso8601String(),
    'round': round,
    'phase': phase.name,
    'phase_started_at': phaseStartedAt.toIso8601String(),
    'ends_at': _endsAt?.toIso8601String(),
    'paused_remaining': _pausedRemaining,
    'rest_held': restHeld,
  };

  factory SparringTimer.fromJson(Map<String, dynamic> j) => SparringTimer._restore(
    config: SparringConfig.fromJson(j['config'] as Map<String, dynamic>),
    startedAt: DateTime.parse(j['started_at'] as String),
    round: (j['round'] as num).toInt(),
    phase: SparringPhase.values.byName(j['phase'] as String),
    phaseStartedAt: DateTime.parse(j['phase_started_at'] as String),
    endsAt: j['ends_at'] == null ? null : DateTime.parse(j['ends_at'] as String),
    pausedRemaining: (j['paused_remaining'] as num?)?.toInt(),
    restHeld: (j['rest_held'] as bool?) ?? false,
  );
}
