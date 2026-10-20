// glucose_alarm.dart — alarm bij hypo én hyper tijdens een live sessie of
// daarbuiten.
//
// GlucoseAlarmGuard is de enige plek die daadwerkelijk een alarmsheet toont.
// De beslissing of, en hoe (geluid), er mag worden gealarmeerd komt altijd
// van AppController.alarmDecision() — deze guard voert die beslissing alleen
// uit. Gebruikt door mat_mode_screen.dart, strength_mode_screen.dart en (via
// AppController) elke andere plek die een meting binnenkrijgt.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/glucose.dart';
import '../services/alarm_notification_service.dart';
import '../theme/kinetic_theme.dart';
import 'manual_glucose.dart';

/// Bewaakt elke nieuwe meting tegen de onder- en bovengrens en toont
/// [GlucoseAlertSheet] zodra er eentje wordt overschreden — zonder aan een
/// State gebonden te zijn, nodig voor een sessie die op de achtergrond
/// doorloopt terwijl de gebruiker op een ander scherm zit. De aanroeper
/// geeft een context-getter mee die altijd naar een gemount widget wijst
/// (bv. het tabblad-scherm, dat zolang je bent ingelogd nooit weg is).
///
/// Eén instantie (via `AppController.alarmGuard`) wordt gedeeld door de hele
/// app, zodat er nooit twee alarmsheets tegelijk kunnen verschijnen.
class GlucoseAlarmGuard {
  GlucoseAlarmGuard({GlucoseAlarmNotifier? notifier})
    : _notifier = notifier ?? AlarmNotificationService.instance;

  /// Injecteerbaar zodat een test geen echt platformkanaal hoeft aan te
  /// roken (dat kan hangen of een `MissingPluginException` geven).
  final GlucoseAlarmNotifier _notifier;

  bool _alarmShowing = false;

  /// Context van de open alarmsheet — om hem te kunnen sluiten als je via
  /// de knop in de melding sluimert.
  BuildContext? _sheetContext;

  // Sluimeren: tot [_snoozedUntil] geen nieuw alarm voor dezelfde kant
  // (laag/hoog). Bij laag gaat het alarm tóch af als de waarde nog 0,5
  // mmol/L of meer verder zakt. Komt de waarde weer binnen de grenzen, dan
  // vervalt het sluimeren en volgt er geen alarm meer.
  DateTime? _snoozedUntil;
  bool _snoozeHigh = false;
  double? _snoozeValue;

  /// Waar als het sluimeren kwam van de knop in het paneel (behandeld) — dan
  /// volgt na afloop een hermeet-herinnering (als er intussen geen herstel
  /// was).
  bool _snoozeTreated = false;
  Timer? _snoozeTimer;

  // Laatst geziene meting/parameters — nodig om na het sluimeren opnieuw te
  // kunnen beoordelen zonder dat er intussen per se een nieuwe meting is
  // binnengekomen.
  GlucoseReading? _lastReading;
  BuildContext Function()? _lastContextOf;
  double? _lastLowBelow;
  bool _lastLowEnabled = true;
  double? _lastHighAbove;
  bool _lastHighEnabled = true;
  bool _lastWithSound = true;
  bool _lastBreakSilentMode = true;
  bool _lastIsTrainingLimit = false;
  int _lastSnoozeMinutes = 15;
  Future<void> Function(BuildContext)? _lastOnManualEntry;

  /// Lopend sluimeren (of hermeet-timer na sluimeren via het paneel) — null als er niets
  /// loopt. UI (bv. het Nu-scherm) toont dit als aftellertje.
  final ValueNotifier<AlarmSnooze?> snooze = ValueNotifier(null);

  /// Wordt aangeroepen als het sluimeren begint of stopt — de app geeft het
  /// door aan de achtergrondbewaking, zodat die ook stil blijft.
  void Function(AlarmSnooze? snooze)? onSnoozeChanged;

  /// Annuleert een eventuele lopende sluimer-timer — nodig zodra de guard
  /// niet langer gebruikt wordt (bv. bij het opruimen van een test of een
  /// sessie), anders blijft er een losse Timer hangen.
  void dispose() {
    _snoozeTimer?.cancel();
    snooze.dispose();
  }

  Future<void> check(
    BuildContext Function() contextOf,
    GlucoseReading reading, {
    required double lowBelow,
    bool lowEnabled = true,
    bool withSound = true,
    bool breakSilentMode = true,
    bool isTrainingLimit = false,
    double? highAbove,
    bool highEnabled = true,
    int snoozeMinutes = 15,
    Future<void> Function(BuildContext)? onManualEntry,
  }) async {
    _lastReading = reading;
    _lastContextOf = contextOf;
    _lastLowBelow = lowBelow;
    _lastLowEnabled = lowEnabled;
    _lastHighAbove = highAbove;
    _lastHighEnabled = highEnabled;
    _lastWithSound = withSound;
    _lastBreakSilentMode = breakSilentMode;
    _lastIsTrainingLimit = isTrainingLimit;
    _lastSnoozeMinutes = snoozeMinutes;
    _lastOnManualEntry = onManualEntry;

    if (_alarmShowing) return;

    final isLow = lowEnabled && reading.mmol <= lowBelow;
    final isHigh =
        !isLow && highEnabled && highAbove != null && reading.mmol >= highAbove;
    if (isLow || isHigh) {
      if (_isSnoozed(reading.mmol, high: isHigh)) return;
      await _raiseAlarm(contextOf(), reading, isHigh: isHigh);
    } else {
      // Weer binnen de grenzen: sluimeren vervalt, geen alarm meer — en een
      // latere, nieuwe overschrijding alarmeert gewoon weer.
      _clearSnooze();
    }
  }

  bool _isSnoozed(double mmol, {required bool high}) {
    final until = _snoozedUntil;
    final value = _snoozeValue;
    if (until == null || value == null) return false;
    if (!DateTime.now().isBefore(until)) return false;
    if (_snoozeHigh != high) return false;
    // Laag: alleen opnieuw alarmeren als de waarde nog 0,5 mmol/L of meer
    // verder gezakt is dan toen je sluimerde via het paneel.
    return high || mmol > value - 0.5;
  }

  void _clearSnooze() {
    final had = _snoozedUntil != null;
    _snoozedUntil = null;
    _snoozeValue = null;
    _snoozeTreated = false;
    _snoozeTimer?.cancel();
    _snoozeTimer = null;
    snooze.value = null;
    if (had) onSnoozeChanged?.call(null);
  }

  /// Start het sluimeren voor [minutes] minuten. [treated] = via de knop in
  /// het paneel (dan volgt bij een hypo een hermeet-herinnering).
  void startSnooze({
    required bool isHigh,
    required double value,
    required int minutes,
    bool treated = false,
  }) {
    final until = DateTime.now().add(Duration(minutes: minutes));
    _snoozedUntil = until;
    _snoozeHigh = isHigh;
    _snoozeValue = value;
    _snoozeTreated = treated;
    _snoozeTimer?.cancel();
    _snoozeTimer = Timer(Duration(minutes: minutes), _onSnoozeEnd);
    final next = AlarmSnooze(
      until: until,
      isHigh: isHigh,
      value: value,
      treated: treated,
    );
    snooze.value = next;
    onSnoozeChanged?.call(next);
  }

  /// Sluimeren handmatig opheffen: het alarm let meteen weer op.
  void cancelSnooze() => _clearSnooze();

  /// "Sluimeren" uit de knop in de systeemmelding: sluit een open sheet en
  /// sluimert met de laatst ingestelde duur.
  void snoozeFromNotification({required bool isHigh, required double mmol}) {
    startSnooze(isHigh: isHigh, value: mmol, minutes: _lastSnoozeMinutes);
    _notifier.cancelAlarm();
    final sheet = _sheetContext;
    if (sheet != null && sheet.mounted) Navigator.pop(sheet);
  }

  void _onSnoozeEnd() {
    final treated = _snoozeTreated;
    final high = _snoozeHigh;
    final reading = _lastReading;
    final lowBelow = _lastLowBelow;
    final contextOf = _lastContextOf;
    _clearSnooze();
    if (reading == null || lowBelow == null || contextOf == null) return;
    final highAbove = _lastHighAbove;
    final stillOut = high
        ? (_lastHighEnabled && highAbove != null && reading.mmol >= highAbove)
        : (_lastLowEnabled && reading.mmol <= lowBelow);
    if (stillOut) {
      // Nog steeds buiten de grens: alarm gaat opnieuw af.
      _raiseAlarm(contextOf(), reading, isHigh: high);
    } else if (treated && !high) {
      _notifier.showRemeasureReminder(
        withSound: _lastWithSound,
        currentValue: reading.mmol,
      );
    }
  }

  Future<void> _raiseAlarm(
    BuildContext context,
    GlucoseReading reading, {
    required bool isHigh,
  }) async {
    _alarmShowing = true;
    final minutes = _lastSnoozeMinutes;
    final onManualEntry = _lastOnManualEntry;
    HapticFeedback.heavyImpact();
    await _notifier.showAlarm(
      withSound: _lastWithSound,
      breakSilentMode: _lastBreakSilentMode,
      isHigh: isHigh,
      mmol: reading.mmol,
    );
    if (!context.mounted) {
      _alarmShowing = false;
      return;
    }
    var handled = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColor.bg.withValues(alpha: .55),
      builder: (sheetContext) {
        _sheetContext = sheetContext;
        return GlucoseAlertSheet(
          reading: reading,
          isHigh: isHigh,
          lowBelow: _lastLowBelow ?? 3.9,
          highAbove: _lastHighAbove,
          isTrainingLimit: _lastIsTrainingLimit,
          snoozeMinutes: minutes,
          onSnooze: () {
            handled = true;
            startSnooze(
              isHigh: isHigh,
              value: reading.mmol,
              minutes: minutes,
              treated: true,
            );
            Navigator.pop(sheetContext);
          },
          onManualEntry: onManualEntry == null
              ? null
              : () async {
                  await onManualEntry(sheetContext);
                },
        );
      },
    );
    _sheetContext = null;
    // Weggeveegd of weggetikt zonder knop: telt als sluimeren (tenzij er
    // intussen via de melding al gesluimerd is).
    if (!handled && _snoozedUntil == null) {
      startSnooze(isHigh: isHigh, value: reading.mmol, minutes: minutes);
    }
    _notifier.cancelAlarm();
    _alarmShowing = false;
  }
}

/// Een lopende sluimering — voor het aftellertje in de UI.
class AlarmSnooze {
  final DateTime until;
  final bool isHigh;

  /// De waarde op het moment van sluimeren.
  final double value;

  /// Waar na "Ingenomen"/"Correctie genomen": dan is het een hermeet-timer.
  final bool treated;
  const AlarmSnooze({
    required this.until,
    required this.isHigh,
    required this.value,
    required this.treated,
  });
}

/// Komt over álles heen — ook over mat-modus, krachttraining en
/// instellingen. Een compact paneel van onderen; wegvegen telt als
/// sluimeren.
class GlucoseAlertSheet extends StatelessWidget {
  final GlucoseReading reading;
  final bool isHigh;
  final double lowBelow;
  final double? highAbove;
  final bool isTrainingLimit;
  final int snoozeMinutes;

  /// De enige actieknop: behandeld (of later) — het alarm blijft
  /// [snoozeMinutes] minuten stil, daarna volgt een hermeting.
  final VoidCallback onSnooze;
  final VoidCallback? onManualEntry;
  const GlucoseAlertSheet({
    super.key,
    required this.reading,
    required this.onSnooze,
    this.isHigh = false,
    this.lowBelow = 3.9,
    this.highAbove,
    this.isTrainingLimit = false,
    this.snoozeMinutes = 15,
    this.onManualEntry,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isHigh ? AppColor.amber : AppColor.red;
    final bright = isHigh ? AppColor.amberBright : AppColor.redBright;
    final ground = isHigh ? AppColor.amberInk : AppColor.redGround;
    final title = isHigh ? 'GLUCOSE TE HOOG' : 'HYPO DREIGT';
    final trendLabel = isHigh ? '↑ stijgend' : '↓↓ snel dalend';
    final limitLabel = isHigh
        ? 'Boven je bovengrens van ${_fmt(highAbove ?? 0)}'
        : (isTrainingLimit
              ? 'Onder je trainingsgrens van ${_fmt(lowBelow)}'
              : 'Onder je dagelijkse grens van ${_fmt(lowBelow)}');
    final adviceTitle = isHigh
        ? 'Neem je correctiedosis en drink water.'
        : 'Stop de sessie en neem 15 g snelle koolhydraten.';
    final adviceBody = isHigh
        ? 'Meet opnieuw over 30 minuten voor je verder traint.'
        : 'Meet opnieuw over $snoozeMinutes minuten.';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ground,
        border: Border(top: BorderSide(color: accent, width: 2)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '!',
                  style: AppText.cardTitle.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ground,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppText.cardTitle.copyWith(
                    letterSpacing: .3,
                    color: bright,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              limitLabel,
              style: AppText.caption.copyWith(
                color: Colors.white.withValues(alpha: .65),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                reading.mmol.toStringAsFixed(1).replaceAll('.', ','),
                style: AppText.readingAlarm,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trendLabel,
                        style: AppText.bodyStrong.copyWith(
                          fontSize: 14,
                          color: bright,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adviceTitle,
                  style: AppText.bodyStrong.copyWith(
                    height: 1.4,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  adviceBody,
                  style: AppText.body.copyWith(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: .55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSnooze,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: ground,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.snooze),
              label: Text('Sluimeren $snoozeMinutes min'),
            ),
          ),
          if (!isHigh) ...[
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onManualEntry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: .75),
                  side: BorderSide(color: Colors.white.withValues(alpha: .2)),
                ),
                child: const Text('Vingerprik invoeren'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
}

/// Opent de bestaande vingerprikdialoog en geeft de waarde door aan
/// [onReading] — een handmatige waarde start hier zelf nooit een nieuw
/// alarm, want de sheet die deze aanroept staat al open (de guard toont nooit
/// twee sheets tegelijk).
Future<void> handleManualEntryFromAlarm(
  BuildContext context,
  void Function(GlucoseReading reading) onReading,
) async {
  final value = await showManualGlucoseDialog(context);
  if (value == null) return;
  onReading(GlucoseReading(value, Trend.flat, DateTime.now()));
}

/// Balk "Alarm gesluimerd — nog 12 min" met een knop om het sluimeren op te
/// heffen. Alleen zichtbaar zolang er gesluimerd wordt; telt elke 15 s af.
class SnoozeBanner extends StatelessWidget {
  const SnoozeBanner({super.key, required this.guard, this.padding});

  final GlucoseAlarmGuard guard;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AlarmSnooze?>(
      valueListenable: guard.snooze,
      builder: (context, snooze, _) {
        if (snooze == null) return const SizedBox.shrink();
        return StreamBuilder<void>(
          stream: Stream<void>.periodic(const Duration(seconds: 15)),
          builder: (context, _) {
            final left = snooze.until.difference(DateTime.now());
            final minutes = left.isNegative ? 0 : (left.inSeconds / 60).ceil();
            final accent = snooze.isHigh ? AppColor.amber : AppColor.redBright;
            return Padding(
              padding: padding ?? EdgeInsets.zero,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: accent.withValues(alpha: .35)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.snooze, size: 18, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${snooze.isHigh ? 'Hyper' : 'Hypo'}-alarm '
                        'gesluimerd — nog $minutes min',
                        style: AppText.bodyStrong.copyWith(
                          fontSize: 13,
                          color: accent,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: guard.cancelSnooze,
                      child: const Text('Opheffen'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
