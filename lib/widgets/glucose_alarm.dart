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

  // Snooze na "Ingenomen": 15 minuten geen nieuw alarm voor dezelfde
  // overschrijding, tenzij de waarde nog 0,5 mmol/L of meer verder zakt.
  DateTime? _treatedAt;
  double? _treatedValue;
  Timer? _remeasureTimer;

  // Laatst geziene meting/parameters — nodig om na 15 minuten opnieuw te
  // kunnen beoordelen zonder dat er intussen per se een nieuwe meting is
  // binnengekomen.
  GlucoseReading? _lastReading;
  BuildContext Function()? _lastContextOf;
  double? _lastLowBelow;
  bool _lastWithSound = true;
  bool _lastBreakSilentMode = true;
  bool _lastIsTrainingLimit = false;
  Future<void> Function(BuildContext)? _lastOnManualEntry;

  /// Wanneer de volgende hermeting-herinnering afgaat — null als er geen
  /// behandeling loopt. UI (bv. het Nu-scherm) kan dit tonen als aftellertje.
  final ValueNotifier<DateTime?> nextRemeasureAt = ValueNotifier(null);

  /// Annuleert een eventuele lopende hermeting-timer — nodig zodra de guard
  /// niet langer gebruikt wordt (bv. bij het opruimen van een test of een
  /// sessie), anders blijft er een losse Timer van tot 15 minuten hangen.
  void dispose() {
    _remeasureTimer?.cancel();
    nextRemeasureAt.dispose();
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
    Future<void> Function(BuildContext)? onManualEntry,
  }) async {
    _lastReading = reading;
    _lastContextOf = contextOf;
    _lastLowBelow = lowBelow;
    _lastWithSound = withSound;
    _lastBreakSilentMode = breakSilentMode;
    _lastIsTrainingLimit = isTrainingLimit;
    _lastOnManualEntry = onManualEntry;

    if (_alarmShowing) return;

    final isLow = lowEnabled && reading.mmol <= lowBelow;
    if (isLow) {
      if (_isSnoozed(reading.mmol)) return;
      await _raiseAlarm(
        contextOf(),
        reading,
        isHigh: false,
        lowBelow: lowBelow,
        withSound: withSound,
        breakSilentMode: breakSilentMode,
        isTrainingLimit: isTrainingLimit,
        onManualEntry: onManualEntry,
      );
    } else if (highEnabled && highAbove != null && reading.mmol >= highAbove) {
      await _raiseAlarm(
        contextOf(),
        reading,
        isHigh: true,
        lowBelow: lowBelow,
        highAbove: highAbove,
        withSound: withSound,
        breakSilentMode: breakSilentMode,
        isTrainingLimit: isTrainingLimit,
        onManualEntry: onManualEntry,
      );
    } else if (reading.mmol > lowBelow) {
      // Waarde is weer boven de grens: de behandeling is geslaagd, snooze
      // vervalt.
      _clearSnooze();
    }
  }

  bool _isSnoozed(double mmol) {
    final treatedAt = _treatedAt;
    final treatedValue = _treatedValue;
    if (treatedAt == null || treatedValue == null) return false;
    if (DateTime.now().difference(treatedAt) >= const Duration(minutes: 15)) {
      return false;
    }
    // Binnen het venster: alleen opnieuw alarmeren als de waarde nog 0,5
    // mmol/L of meer verder gezakt is dan toen je "Ingenomen" indrukte.
    return mmol > treatedValue - 0.5;
  }

  void _clearSnooze() {
    _treatedAt = null;
    _treatedValue = null;
    _remeasureTimer?.cancel();
    _remeasureTimer = null;
    nextRemeasureAt.value = null;
  }

  void _startSnooze(double valueAtTreatment) {
    _treatedAt = DateTime.now();
    _treatedValue = valueAtTreatment;
    _remeasureTimer?.cancel();
    final at = DateTime.now().add(const Duration(minutes: 15));
    nextRemeasureAt.value = at;
    _remeasureTimer = Timer(const Duration(minutes: 15), _onRemeasureDue);
  }

  void _onRemeasureDue() {
    nextRemeasureAt.value = null;
    final reading = _lastReading;
    final lowBelow = _lastLowBelow;
    final contextOf = _lastContextOf;
    if (reading == null || lowBelow == null || contextOf == null) return;
    if (reading.mmol <= lowBelow) {
      // Nog steeds onder de grens: alarm gaat opnieuw af.
      _treatedAt = null;
      _treatedValue = null;
      _raiseAlarm(
        contextOf(),
        reading,
        isHigh: false,
        lowBelow: lowBelow,
        withSound: _lastWithSound,
        breakSilentMode: _lastBreakSilentMode,
        isTrainingLimit: _lastIsTrainingLimit,
        onManualEntry: _lastOnManualEntry,
      );
    } else {
      _notifier.showRemeasureReminder(
        withSound: _lastWithSound,
        currentValue: reading.mmol,
      );
      _clearSnooze();
    }
  }

  Future<void> _raiseAlarm(
    BuildContext context,
    GlucoseReading reading, {
    required bool isHigh,
    required double lowBelow,
    double? highAbove,
    required bool withSound,
    required bool breakSilentMode,
    required bool isTrainingLimit,
    Future<void> Function(BuildContext)? onManualEntry,
  }) async {
    _alarmShowing = true;
    HapticFeedback.heavyImpact();
    await _notifier.showAlarm(
      withSound: withSound,
      breakSilentMode: breakSilentMode,
      isHigh: isHigh,
      mmol: reading.mmol,
    );
    if (!context.mounted) {
      _alarmShowing = false;
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColor.bg.withValues(alpha: .82),
      builder: (sheetContext) => GlucoseAlertSheet(
        reading: reading,
        isHigh: isHigh,
        lowBelow: lowBelow,
        highAbove: highAbove,
        isTrainingLimit: isTrainingLimit,
        onTreated: () {
          if (!isHigh) _startSnooze(reading.mmol);
          _notifier.cancelAlarm();
          Navigator.pop(sheetContext);
        },
        onManualEntry: onManualEntry == null
            ? null
            : () async {
                await onManualEntry(sheetContext);
              },
      ),
    );
    _notifier.cancelAlarm();
    _alarmShowing = false;
  }
}

/// Komt over álles heen — ook over mat-modus, krachttraining en
/// instellingen. Daarom een sheet met isDismissible: false, geen pagina in
/// de navigatiestapel.
class GlucoseAlertSheet extends StatelessWidget {
  final GlucoseReading reading;
  final bool isHigh;
  final double lowBelow;
  final double? highAbove;
  final bool isTrainingLimit;
  final VoidCallback onTreated;
  final VoidCallback? onManualEntry;
  const GlucoseAlertSheet({
    super.key,
    required this.reading,
    required this.onTreated,
    this.isHigh = false,
    this.lowBelow = 3.9,
    this.highAbove,
    this.isTrainingLimit = false,
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
        : 'Meet opnieuw over 15 minuten.';
    final primaryLabel = isHigh
        ? 'Correctie genomen'
        : 'Ingenomen — timer 15 min';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        26 + MediaQuery.of(context).padding.bottom,
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
          const SizedBox(height: 18),
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
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
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
            child: FilledButton(
              onPressed: onTreated,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: ground,
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(primaryLabel),
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
