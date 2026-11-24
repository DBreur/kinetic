// telemetry_widgets.dart: live Dexcom G7- en Polar H10-kaarten voor de
// mat-schermen. Groot en hoog contrast, leesbaar op een paar meter afstand.

import 'package:material_ui/material_ui.dart';

import '../core/glucose_rules.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic_widgets.dart';

class DexcomLiveCard extends StatelessWidget {
  const DexcomLiveCard({super.key, this.showClearance = false});
  final bool showClearance;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final r = store.reading;
    final age = r == null ? null : store.now().difference(r.at).inMinutes;
    final clearance = store.clearanceForNextRound();
    final inRange = r != null && !r.isStale && zoneFor(r.mmol) == GlucoseZone.inTarget;
    return KCard(
      padding: const EdgeInsets.all(14),
      borderColor: (showClearance ? clearance.color : (r == null ? KColor.border : glucoseColor(r.mmol))).withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('Dexcom G7', color: KColor.tealLight, icon: Icons.sensors)),
              if (age != null) Text('${age}m', style: KText.caption.copyWith(color: r!.isStale ? KColor.warning : KColor.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: GlucoseReadout(reading: r, size: 38, showUnit: false),
          ),
          Text('mmol/L • IOB ${store.iob.toStringAsFixed(2)} E', style: KText.caption),
          const SizedBox(height: 8),
          if (showClearance)
            KBadge(clearance.title, color: clearance.color, filled: clearance.level == ClearanceLevel.danger)
          else
            KBadge(
              r == null
                  ? 'Geen data'
                  : inRange
                  ? 'Stabiel doelbereik ${targetLow.toStringAsFixed(1)} - ${targetHigh.toStringAsFixed(1)}'
                  : trendLabel(r.trend),
              color: r == null ? KColor.textMuted : glucoseColor(r.mmol),
            ),
        ],
      ),
    );
  }
}

class PolarLiveCard extends StatelessWidget {
  const PolarLiveCard({super.key, this.showRecovery = false});
  final bool showRecovery;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final bpm = store.heartRateBpm;
    final zone = store.currentHeartRateZone;
    final rec = store.heartRateRecovery;
    final zoneColor = switch (zone.zone) {
      1 || 2 => KColor.success,
      3 => KColor.blue,
      4 => KColor.warning,
      _ => KColor.danger,
    };
    return KCard(
      padding: const EdgeInsets.all(14),
      borderColor: KColor.blue.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('Polar H10', color: KColor.blue, icon: Icons.favorite)),
              if (store.heartRate.isSimulated)
                Text('SIMULATIE', style: KText.eyebrow.copyWith(fontSize: 9, color: KColor.warning)),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$bpm', style: KText.metric.copyWith(fontSize: 38)),
                const SizedBox(width: 6),
                Text('BPM', style: KText.caption),
              ],
            ),
          ),
          Text(
            showRecovery && rec != null
                ? 'Herstel ${rec.$1 > 0 ? '+' : ''}${rec.$1} BPM / ${rec.$2}s'
                : '${zone.percentOfMax}% max HR',
            style: KText.caption,
          ),
          const SizedBox(height: 8),
          KBadge(zone.label, color: zoneColor),
        ],
      ),
    );
  }
}
