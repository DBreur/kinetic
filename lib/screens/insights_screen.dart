// insights_screen.dart — "Inzicht"-tab: hoe sport en glucose samenhangen.
//
// Puur beschrijvend, geen advies: alleen cijfers over wat je al vastlegt
// (trainingssessies met hun glucose-curve, en het eetlogboek). Zie
// core/training_insights.dart voor de berekeningen.

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/training_insights.dart';
import '../models/food_log_entry.dart';
import '../models/training_session.dart';
import '../repositories/food_log_repository.dart';
import '../repositories/session_repository.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/kinetic.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool _loading = true;
  List<TrainingSession> _sessions = const [];
  List<FoodLogEntry> _foodLogEntries = const [];
  InsightPeriod _period = InsightPeriod.week;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = widget.controller.user?.id;
    final client = widget.controller.client;
    if (userId == null || client == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        SessionRepository(client).listForUser(userId),
        FoodLogRepository(client).listForUser(userId),
      ]);
      if (mounted) {
        setState(() {
          _sessions = results[0] as List<TrainingSession>;
          _foodLogEntries = results[1] as List<FoodLogEntry>;
        });
      }
    } catch (_) {
      // Cijfers blijven leeg/oud; pull-to-refresh probeert het opnieuw.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insights = TrainingInsights.compute(
      sessions: _sessions,
      foodLogEntries: _foodLogEntries,
      period: _period,
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          4,
          AppSpace.gutter,
          AppSpace.xl,
        ),
        children: [
          KSegmented<InsightPeriod>(
            activeColor: AppColor.iceDeep,
            activeInk: AppColor.iceInk,
            options: [for (final p in InsightPeriod.values) (p, p.label, null)],
            selected: _period,
            onChanged: (p) => setState(() => _period = p),
          ),
          const SizedBox(height: AppSpace.lg),
          if (!_loading && insights.totalSessions == 0)
            const EmptyState(
              icon: Icons.monitor_heart_outlined,
              message:
                  'Nog geen trainingen in deze periode. Zodra je '
                  'sessies opslaat, vult dit scherm zich met echte '
                  'cijfers.',
            )
          else ...[
            _StabilityCard(insights: insights),
            const SizedBox(height: AppSpace.md),
            _DipSummary(insights: insights, text: _summaryText(insights)),
            const SizedBox(height: AppSpace.lg),
            const KSectionTitle('Responsprofielen', trailing: 'per type'),
            _EffectCard(
              kind: SessionKind.sambo,
              stats: insights.byKind[SessionKind.sambo]!,
            ),
            const SizedBox(height: AppSpace.md),
            _EffectCard(
              kind: SessionKind.kracht,
              stats: insights.byKind[SessionKind.kracht]!,
            ),
            if (insights.carbsBeforeTraining.hasEnoughData) ...[
              const SizedBox(height: AppSpace.lg),
              const KSectionTitle('Koolhydraten vooraf'),
              _CarbsBeforeTrainingCard(insights: insights),
            ],
          ],
        ],
      ),
    );
  }

  String _summaryText(TrainingInsights insights) {
    final hypoCount = insights.byKind.values.fold<int>(
      0,
      (n, s) => n + s.dipCount,
    );
    if (hypoCount == 0) {
      return 'Geen van je ${insights.totalSessions} sessies deze periode '
          'zakte onder 5,0 mmol/L.';
    }
    return '$hypoCount van je ${insights.totalSessions} sessies deze '
        'periode zakte onder 5,0 mmol/L.';
  }
}

String _pct(double? v) => v == null ? '—' : '${v.round()}%';

String _signedMmol(double v) => '${v >= 0 ? '+' : '−'}${mmolText(v.abs())}';

/// Hero: aandeel metingen in bereik tijdens training, met ring en een
/// verdelingsbalk onder / in / boven bereik.
class _StabilityCard extends StatelessWidget {
  const _StabilityCard({required this.insights});

  final TrainingInsights insights;

  @override
  Widget build(BuildContext context) {
    final inRange = insights.overallInRangePercent;
    final low = insights.overallLowPercent ?? 0;
    final high = insights.overallHighPercent ?? 0;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KDot(color: AppColor.ice, size: 8),
              const SizedBox(width: 8),
              const Expanded(
                child: KLabel(
                  'Stabiliteit tijdens training',
                  color: AppColor.ice,
                ),
              ),
              Text(
                'Doel ${mmolText(TrainingInsights.lowMmol)}–${mmolText(TrainingInsights.highMmol)}',
                style: AppText.caption,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pct(inRange),
                      style: AppText.reading.copyWith(fontSize: 48),
                    ),
                    Text('In bereik', style: AppText.title),
                    const SizedBox(height: 4),
                    Text(
                      'Over ${insights.totalSessions} sessies · ${insights.totalMinutes} min',
                      style: AppText.body.copyWith(color: AppColor.inkFaint),
                    ),
                  ],
                ),
              ),
              KRing(
                size: 104,
                stroke: 7,
                value: (inRange ?? 0) / 100,
                color: AppColor.ice,
                child: const Icon(
                  Icons.verified_outlined,
                  color: AppColor.ice,
                  size: 28,
                ),
              ),
            ],
          ),
          if (inRange != null) ...[
            const SizedBox(height: AppSpace.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final (share, color) in [
                      (low, AppColor.red),
                      (inRange, AppColor.ice),
                      (high, AppColor.amber),
                    ])
                      if (share > 0)
                        Expanded(
                          flex: (share * 10).round().clamp(1, 1000),
                          child: Container(color: color),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _Legend(color: AppColor.red, label: 'Laag', value: _pct(low)),
                _Legend(
                  color: AppColor.ice,
                  label: 'In bereik',
                  value: _pct(inRange),
                ),
                _Legend(
                  color: AppColor.amber,
                  label: 'Hoog',
                  value: _pct(high),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      KDot(color: color, size: 8),
      const SizedBox(width: 6),
      Text(
        '$label $value',
        style: AppText.caption.copyWith(color: AppColor.inkMuted),
      ),
    ],
  );
}

class _DipSummary extends StatelessWidget {
  const _DipSummary({required this.insights, required this.text});

  final TrainingInsights insights;
  final String text;

  @override
  Widget build(BuildContext context) {
    final dips = insights.byKind.values.fold<int>(0, (n, s) => n + s.dipCount);
    final color = dips == 0 ? AppColor.ice : AppColor.amber;
    return KCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColor.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              dips == 0 ? Icons.shield_outlined : Icons.trending_down,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(child: Text(text, style: AppText.body)),
        ],
      ),
    );
  }
}

/// Responsprofiel per type training — puur beschrijvend: wat je glucose
/// gemiddeld deed tussen start en einde, zonder advies.
class _EffectCard extends StatelessWidget {
  const _EffectCard({required this.kind, required this.stats});

  final SessionKind kind;
  final SessionKindStats stats;

  @override
  Widget build(BuildContext context) {
    final isSambo = kind == SessionKind.sambo;
    final delta = stats.avgDeltaMmol;
    String fmt(double? v) => v == null ? '—' : mmolText(v);
    final body = stats.count == 0
        ? 'Nog geen ${isSambo ? 'sambo' : 'kracht'}sessies in deze periode.'
        : delta == null
        ? 'Te weinig metingen per sessie om de verandering te berekenen.'
        : 'Je glucose ${delta >= 0 ? 'steeg' : 'daalde'} gemiddeld '
              '${mmolText(delta.abs())} mmol/L tussen start en einde, over '
              '${stats.count} sessie${stats.count == 1 ? '' : 's'}.';
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColor.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  isSambo ? Icons.sports_mma_outlined : Icons.fitness_center,
                  size: 20,
                  color: isSambo ? AppColor.coral : AppColor.slate,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSambo ? 'Sambo-effect' : 'Kracht-effect',
                      style: AppText.title.copyWith(fontSize: 22),
                    ),
                    Text(
                      isSambo ? 'Combat & sparring' : 'Kracht & circuits',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              if (delta != null)
                KTag(
                  '${_signedMmol(delta)} mmol/L',
                  color: delta >= 0 ? AppColor.coralSoft : AppColor.ice,
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            body,
            style: AppText.bodyLarge.copyWith(color: AppColor.inkMuted),
          ),
          if (stats.count > 0) ...[
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: KMetricTile(label: 'Gem.', value: fmt(stats.avgMmol)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KMetricTile(
                    label: 'Laagste',
                    value: fmt(stats.lowestMmol),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KMetricTile(
                    label: 'Met dip',
                    value: _pct(stats.dipPercent),
                    valueColor: stats.dipCount == 0
                        ? AppColor.ice
                        : AppColor.amber,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CarbsBeforeTrainingCard extends StatelessWidget {
  const _CarbsBeforeTrainingCard({required this.insights});

  final TrainingInsights insights;

  @override
  Widget build(BuildContext context) {
    final c = insights.carbsBeforeTraining;
    final grams = TrainingInsights.carbThresholdGrams.round();
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vergeleken over de anderhalf uur vóór de start van een sessie:',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _bucket(
                  'Minder dan ${grams}g',
                  c.lowCarbSessions,
                  c.lowCarbDipPercent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _bucket(
                  '$grams g of meer',
                  c.higherCarbSessions,
                  c.higherCarbDipPercent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bucket(String label, int count, double? dipPercent) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColor.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          const SizedBox(height: 6),
          Text(
            dipPercent != null ? '${dipPercent.round()}%' : '—',
            style: AppText.metric,
          ),
          Text(
            'van $count sessies met dip',
            style: AppText.caption.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}
