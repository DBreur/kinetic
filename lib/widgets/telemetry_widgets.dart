// telemetry_widgets.dart: live Dexcom G7- en Polar H10-kaarten voor de
// mat-schermen (live sessie en ronde rust). Platte kaart met haarlijn,
// grote tabulaire cijfers, en status altijd als tekst/icoon plus kleur.
// Leeftijd van de meting rekent met de klok van de store (testbaar).

import 'package:material_ui/material_ui.dart';

import '../core/glucose_rules.dart';
import '../models/glucose.dart';
import '../models/training_session.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic_widgets.dart';

// ------------------------------------------------------------- helpers

/// Toon bij een glucosewaarde: doelbereik = success, laag/hoog = warning,
/// hypo = danger.
KTone glucoseZoneTone(double mmol) => switch (zoneFor(mmol)) {
  GlucoseZone.hypo => KTone.danger,
  GlucoseZone.low => KTone.warning,
  GlucoseZone.inTarget => KTone.success,
  GlucoseZone.high => KTone.warning,
};

/// Toon bij de "mag de volgende ronde starten?"-check.
KTone clearanceTone(ClearanceLevel level) => switch (level) {
  ClearanceLevel.safe => KTone.success,
  ClearanceLevel.caution => KTone.warning,
  ClearanceLevel.danger => KTone.danger,
  ClearanceLevel.unknown => KTone.neutral,
};

IconData clearanceIcon(ClearanceLevel level) => switch (level) {
  ClearanceLevel.safe => Icons.verified,
  ClearanceLevel.caution => Icons.warning_amber_rounded,
  ClearanceLevel.danger => Icons.dangerous,
  ClearanceLevel.unknown => Icons.help_outline,
};

/// Volle kleur van een toon (voor stippen, randen en ringen).
Color toneSolid(KineticColors k, KTone tone) => switch (tone) {
  KTone.neutral => k.textSecondary,
  KTone.primary => k.primary,
  KTone.success => k.success,
  KTone.warning => k.warning,
  KTone.danger => k.danger,
  KTone.info => k.blue,
  KTone.purple => k.purple,
};

/// Trendpijl als icoon (recht, diagonaal, verticaal).
IconData trendIcon(Trend t) => switch (t) {
  Trend.up => Icons.arrow_upward,
  Trend.slightUp => Icons.north_east,
  Trend.flat => Icons.arrow_forward,
  Trend.slightDown => Icons.south_east,
  Trend.down => Icons.arrow_downward,
  Trend.fastDown => Icons.keyboard_double_arrow_down,
};

/// Minuten sinds de laatste meting volgens de klok van de store.
int? readingAgeMinutes(KineticStore store) {
  final r = store.reading;
  return r == null ? null : store.now().difference(r.at).inMinutes;
}

/// Meting van 15 minuten of ouder telt niet meer als actueel.
bool readingIsStale(KineticStore store) => (readingAgeMinutes(store) ?? 0) >= 15;

/// Actuele hypo: verse meting onder 4.0 mmol/L.
bool liveHypo(KineticStore store) {
  final r = store.reading;
  return r != null && !readingIsStale(store) && r.mmol < hypoBelow;
}

/// Verbrande kcal sinds de start van de lopende sessie.
int sessionKcal(KineticStore store) {
  final t = store.sparring;
  final minutes = t == null ? 0 : store.now().difference(t.startedAt).inMinutes;
  return estimateKcal(minutes: minutes, weightKg: store.currentWeightKg ?? 75);
}

/// Korte status bij de glucosewaarde ("Stabiel corridor", "Dalend"...).
(String, KTone) glucoseStatus(KineticStore store) {
  final r = store.reading;
  if (r == null) return ('Geen data', KTone.neutral);
  final age = readingAgeMinutes(store) ?? 0;
  if (age >= 15) return ('Meting $age min oud', KTone.warning);
  return switch (zoneFor(r.mmol)) {
    GlucoseZone.hypo => ('Hypo', KTone.danger),
    GlucoseZone.low => ('Onder corridor', KTone.warning),
    GlucoseZone.high => (r.mmol > ketoneCheckAbove ? 'Hoog • ketonen' : 'Boven corridor', KTone.warning),
    GlucoseZone.inTarget => isFalling(r.trend) ? (trendLabel(r.trend), KTone.warning) : ('Stabiel corridor', KTone.success),
  };
}

// ------------------------------------------------------------- kaarten

class DexcomLiveCard extends StatelessWidget {
  const DexcomLiveCard({super.key, this.showClearance = false});

  /// Toon de veiligheidscheck voor de volgende ronde in plaats van de
  /// corridorstatus.
  final bool showClearance;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final r = store.reading;
    final age = readingAgeMinutes(store);
    final stale = readingIsStale(store);
    final zone = r == null || stale ? KTone.neutral : glucoseZoneTone(r.mmol);
    final (status, statusTone) = glucoseStatus(store);
    final clearance = store.clearanceForNextRound();
    final valueColor = r == null || stale
        ? k.textMuted
        : zone == KTone.success
        ? k.text
        : toneColors(k, zone).$2;
    return KCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bloodtype, size: 18, color: k.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text('DEXCOM G7', style: t.labelSm, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (age != null) ...[
                Text(
                  age <= 0 ? 'nu' : '${age}m',
                  style: t.caption.copyWith(color: stale ? k.warningInk : k.textMuted),
                ),
                const SizedBox(width: 6),
              ],
              _Dot(color: r == null || stale ? k.textMuted : toneSolid(k, zone)),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: r == null ? 'Geen glucosewaarde' : 'Glucose ${r.mmol.toStringAsFixed(1)} mmol per liter, ${trendLabel(r.trend)}',
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(r == null ? '--' : r.mmol.toStringAsFixed(1), style: t.metric.copyWith(fontSize: 38, color: valueColor)),
                  const SizedBox(width: 5),
                  Text('mmol/L', style: t.unit),
                  if (r != null) ...[
                    const SizedBox(width: 4),
                    Icon(trendIcon(r.trend), size: 24, color: stale ? k.textMuted : toneSolid(k, zone)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (showClearance)
            KPill(clearance.title, tone: clearanceTone(clearance.level), icon: clearanceIcon(clearance.level))
          else
            KPill(status, tone: statusTone, dot: true),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${targetLow.toStringAsFixed(1)} – ${targetHigh.toStringAsFixed(1)} • IOB ${store.iob.toStringAsFixed(2)} E',
              style: t.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class PolarLiveCard extends StatelessWidget {
  const PolarLiveCard({super.key, this.showRecovery = false});

  /// In de rust: herstelsnelheid ("−30 BPM / 45s") in plaats van de zone.
  final bool showRecovery;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final bpm = store.heartRateBpm;
    final zone = store.currentHeartRateZone;
    final rec = store.heartRateRecovery;
    final zoneTone = switch (zone.zone) {
      1 || 2 => KTone.success,
      3 => KTone.info,
      4 => KTone.warning,
      _ => KTone.danger,
    };
    final simulated = store.heartRate.isSimulated;
    return KCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite, size: 18, color: k.danger),
              const SizedBox(width: 6),
              Expanded(
                child: Text('POLAR H10', style: t.labelSm, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              LiveDot(color: k.danger),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: 'Hartslag $bpm slagen per minuut',
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$bpm', style: t.metric.copyWith(fontSize: 38)),
                  const SizedBox(width: 5),
                  Text('BPM', style: t.unit),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (showRecovery && rec != null)
            KPill(
              '${_signed(rec.$1)} BPM / ${rec.$2}s',
              tone: rec.$1 < 0 ? KTone.success : KTone.neutral,
              icon: rec.$1 < 0 ? Icons.south_east : Icons.arrow_forward,
            )
          else
            KPill(zone.label, tone: zoneTone, dot: true),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              showRecovery
                  ? (rec != null ? 'Herstel • zone ${zone.zone} • ${zone.percentOfMax}% max' : '${zone.label} • ${zone.percentOfMax}% max')
                  : '${zone.percentOfMax}% max HR • ${sessionKcal(store)} kcal',
              style: t.caption,
            ),
          ),
          if (simulated) ...[
            const SizedBox(height: 8),
            const KPill('SIMULATIE', tone: KTone.warning, icon: Icons.science, dense: true),
          ],
        ],
      ),
    );
  }

  static String _signed(int v) => v > 0 ? '+$v' : (v < 0 ? '−${-v}' : '0');
}

/// Dexcom en Polar naast elkaar, even hoog.
class TelemetryRow extends StatelessWidget {
  const TelemetryRow({super.key, this.rest = false});
  final bool rest;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: DexcomLiveCard()),
          const SizedBox(width: 10),
          Expanded(child: PolarLiveCard(showRecovery: rest)),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
