// eten_screen.dart: Eet Logboek (kinetic_eet_logboek_dark/_light): het
// dagoverzicht brandstof met de koolhydraten per maaltijd en de piek na het
// eten, de macrobarometer, snelle carb-presets, de maaltijd-bottom-sheet en
// per maaltijd de glycemische respons uit de CGM-tijdlijn.

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/meal_impact.dart';
import '../models/food_log_entry.dart';
import '../models/glucose.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/charts.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/food_preset_widgets.dart';
import '../widgets/sheets.dart';

class EtenScreen extends StatelessWidget {
  const EtenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    if (store.tab == KTab.eten) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && store.consumeMealSheetRequest()) {
          showMealSheet(context);
        }
      });
    }
    final now = store.now();
    final hyper = store.profile?.hyperLimit ?? 10.0;
    // Nieuwste bovenaan in de lijst, chronologisch in de balk.
    final entries = [...store.todayEntries]..sort((a, b) => b.at.compareTo(a.at));
    final responses = {
      for (final e in entries) e.id: mealResponse(e, store.glucoseHistory, now),
    };
    final insight = _insight(store, entries, responses, now);
    return RefreshIndicator(
      color: k.primary,
      backgroundColor: k.surface,
      onRefresh: store.refreshAll,
      child: ListView(
        padding: pagePadding(context, top: 16),
        children: [
          _FuelOverview(entries: entries.reversed.toList(), responses: responses, hyper: hyper),
          const SizedBox(height: 12),
          BigButton(
            label: '+ Maaltijd of correctie toevoegen',
            icon: Icons.restaurant_menu,
            onPressed: () => showMealSheet(context),
          ),
          const SizedBox(height: 12),
          const PresetManagerCard(training: false),
          const SizedBox(height: 12),
          if (store.nutritionGoalsEnabled)
            const _MacroBarometer()
          else
            KCard(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  Icon(Icons.speed, size: 20, color: k.textMuted),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Dagdoel voeding staat uit', style: context.t.caption)),
                  TextButton(onPressed: () => store.setNutritionGoalsEnabled(true), child: const Text('Aanzetten')),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: Eyebrow('Maaltijden & glycemische respons')),
              const SizedBox(width: 8),
              Text(
                '${entries.length} ${entries.length == 1 ? 'maaltijd' : 'maaltijden'}',
                style: context.t.caption,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            KCard(
              child: Row(
                children: [
                  IconTile(icon: Icons.restaurant_outlined, size: 40, color: k.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Nog niets gelogd vandaag. Tik op een preset of voeg een maaltijd toe; de glucoserespons verschijnt hier.',
                      style: context.t.caption,
                    ),
                  ),
                ],
              ),
            ),
          for (final e in entries) ...[
            _EntryCard(entry: e, response: responses[e.id], hyper: hyper),
            const SizedBox(height: 12),
          ],
          if (insight != null) ...[
            const SizedBox(height: 4),
            _InsightCard(text: insight),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- respons

/// Hoe lang na een maaltijd we de glucosecurve bekijken.
const _responseWindow = Duration(hours: 2);

/// De glucoserespons na één maaltijd: beginwaarde, piek en dal binnen
/// [_responseWindow], afgeleid uit de CGM-tijdlijn.
class MealResponse {
  const MealResponse({
    required this.start,
    required this.peak,
    required this.low,
    required this.peakAfter,
    required this.complete,
    required this.points,
  });

  final double start;
  final double peak;
  final double low;
  final Duration peakAfter;

  /// Het volledige venster van 2 uur ligt achter ons.
  final bool complete;
  final List<GlucosePoint> points;

  double get rise => peak - start;
}

MealResponse? mealResponse(FoodLogEntry e, List<GlucosePoint> history, DateTime now) {
  final end = e.at.add(_responseWindow);
  final pts = [
    for (final g in history)
      if (!g.at.isBefore(e.at) && !g.at.isAfter(end)) g,
  ]..sort((a, b) => a.at.compareTo(b.at));
  if (pts.isEmpty) return null;
  // Beginwaarde: de glucose bij het loggen, anders de CGM-meting die er het
  // dichtst bij ligt (hooguit 15 minuten ervoor).
  GlucosePoint? before;
  for (final g in history) {
    if (g.at.isAfter(e.at) || e.at.difference(g.at) > const Duration(minutes: 15)) continue;
    if (before == null || g.at.isAfter(before.at)) before = g;
  }
  final start = e.mmol ?? before?.mmol ?? pts.first.mmol;
  var peak = pts.first;
  var low = pts.first.mmol;
  for (final p in pts) {
    if (p.mmol > peak.mmol) peak = p;
    low = math.min(low, p.mmol);
  }
  return MealResponse(
    start: start,
    peak: peak.mmol,
    low: low,
    peakAfter: peak.at.difference(e.at),
    complete: !now.isBefore(end),
    points: [?before, ...pts],
  );
}

/// Oordeel over een respons: tekst plus toon (nooit alleen kleur).
(KTone, String) responseVerdict(MealResponse r, double hyper) {
  if (r.low < hypoBelow) return (KTone.danger, 'Hypo na maaltijd');
  if (r.low < targetLow) return (KTone.warning, 'Laag na maaltijd');
  if (r.peak > hyper) return (KTone.warning, 'Boven ${dec1(hyper)} mmol/L');
  if (r.peak > targetHigh) return (KTone.warning, 'Boven doelbereik');
  if (r.rise > 3.0) return (KTone.warning, 'Snelle stijging');
  return (KTone.success, 'Binnen doelbereik');
}

// ------------------------------------------------------------- naamgeving

bool _isQuickCarbs(FoodLogEntry e) =>
    (e.protein ?? 0) + (e.fat ?? 0) == 0 && (e.carbs ?? 0) > 0 && (e.carbs ?? 0) <= 20;

bool _isSnack(FoodLogEntry e) => (e.carbs ?? 0) <= 35 && (e.protein ?? 0) + (e.fat ?? 0) < 10;

/// "Ontbijt", "Lunch", "Pre-workout brandstof"...: de titel van een kaart.
String mealTitle(FoodLogEntry e) {
  switch (e.context) {
    case MealContext.preTraining:
      return 'Pre-workout brandstof';
    case MealContext.postTraining:
      return 'Post-workout herstel';
    case MealContext.acute:
      return 'Mat-interventie';
    case MealContext.recovery:
    case null:
      if (_isQuickCarbs(e)) return 'Snelle carbs';
      final h = e.at.hour;
      final snack = _isSnack(e);
      if (h >= 5 && h < 11) return snack ? 'Ochtendsnack' : 'Ontbijt';
      if (h >= 11 && h < 16) return snack ? 'Middagsnack' : 'Lunch';
      if (h >= 16 && h < 22) return snack ? 'Avondsnack' : 'Diner';
      return 'Nachtsnack';
  }
}

/// Korte naam voor de legenda van de koolhydratenbalk.
String _legendName(FoodLogEntry e) => switch (e.context) {
  MealContext.preTraining => 'Pre-training',
  MealContext.postTraining => 'Na training',
  MealContext.acute => 'Interventie',
  _ => mealTitle(e),
};

String _contextLabel(MealContext? c) => switch (c) {
  MealContext.preTraining => 'Vóór training / sparring',
  MealContext.postTraining => 'Direct na training',
  MealContext.acute => 'Acute mat-interventie',
  MealContext.recovery => 'Regulier herstel',
  null => 'Zonder context',
};

IconData _mealIcon(FoodLogEntry e) {
  switch (e.context) {
    case MealContext.preTraining:
      return Icons.sports_martial_arts;
    case MealContext.postTraining:
      return Icons.autorenew;
    case MealContext.acute:
      return Icons.shield_outlined;
    case MealContext.recovery:
    case null:
      if (_isQuickCarbs(e)) return Icons.bolt;
      final h = e.at.hour;
      if (_isSnack(e)) return Icons.cookie_outlined;
      if (h >= 5 && h < 11) return Icons.wb_twilight;
      if (h >= 11 && h < 16) return Icons.lunch_dining;
      if (h >= 16 && h < 22) return Icons.restaurant;
      return Icons.nightlight_outlined;
  }
}

// ---------------------------------------------------------- dagoverzicht

class _FuelOverview extends StatelessWidget {
  const _FuelOverview({required this.entries, required this.responses, required this.hyper});

  /// Chronologisch (oudste eerst).
  final List<FoodLogEntry> entries;
  final Map<String, MealResponse?> responses;
  final double hyper;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final total = store.carbsToday;
    // Zonder dagdoel schaalt de balk op het totaal.
    final target = store.nutritionGoalsEnabled ? store.carbsTarget : (total > 0 ? total : 1.0);

    // Hoogste glucose binnen 2 uur na een maaltijd van vandaag.
    FoodLogEntry? peakEntry;
    MealResponse? peak;
    var anyHypo = false;
    for (final e in entries) {
      final r = responses[e.id];
      if (r == null) continue;
      if (r.low < hypoBelow) anyHypo = true;
      if (peak == null || r.peak > peak.peak) {
        peak = r;
        peakEntry = e;
      }
    }
    final (tone, status) = entries.isEmpty
        ? (KTone.neutral, 'Nog niets gelogd')
        : peak == null
        ? (KTone.neutral, 'Wacht op CGM')
        : anyHypo
        ? (KTone.danger, 'Hypo na maaltijd')
        : peak.peak > hyper
        ? (KTone.warning, 'Piek boven ${dec1(hyper)}')
        : peak.peak > targetHigh
        ? (KTone.warning, 'Boven doelbereik')
        : (KTone.success, 'Stabiel bereik');

    final withCarbs = entries.where((e) => (e.carbs ?? 0) > 0).toList();
    final colors = [k.primary, k.primary.withValues(alpha: 0.62), k.primary.withValues(alpha: 0.36)];
    Color segColor(int i) => colors[i % colors.length];
    final scale = math.max(target, total);
    final rest = scale - total;

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: k.primary, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Expanded(child: Eyebrow('Dagoverzicht brandstof')),
              const SizedBox(width: 8),
              KPill(status, tone: tone, dense: true, icon: tone == KTone.success ? Icons.check : (tone == KTone.neutral ? null : Icons.warning_amber_rounded)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(grams(total), style: context.t.metric.copyWith(fontSize: 40)),
                          const SizedBox(width: 4),
                          Text('g', style: context.t.subtitle.copyWith(color: k.accent)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('Koolhydraten totaal gelogd', style: context.t.caption),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        peak == null ? Icons.trending_flat : Icons.trending_up,
                        size: 18,
                        color: peak == null ? k.textMuted : _toneInk(k, tone),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        peak == null ? '--' : '${dec1(peak.peak)} mmol/L',
                        style: context.t.subtitle.copyWith(
                          color: peak == null ? k.textMuted : _toneInk(k, tone),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    peakEntry == null ? 'Piek na maaltijd' : 'Piek na ${mealTitle(peakEntry).toLowerCase()}',
                    style: context.t.caption,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Koolhydraten per maaltijd t.o.v. het dagdoel.
          SizedBox(
            height: 10,
            child: Row(
              children: [
                for (final (i, e) in withCarbs.indexed) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    flex: math.max(1, (e.carbs! * 10).round()),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: segColor(i), borderRadius: BorderRadius.circular(KRadius.full)),
                    ),
                  ),
                ],
                if (rest > 0) ...[
                  if (withCarbs.isNotEmpty) const SizedBox(width: 3),
                  Expanded(
                    flex: math.max(1, (rest * 10).round()),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: k.well, borderRadius: BorderRadius.circular(KRadius.full)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final (i, e) in withCarbs.indexed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: segColor(i), borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 6),
                    Text('${_legendName(e)} ${grams(e.carbs!)}g', style: context.t.caption),
                  ],
                ),
              if (store.nutritionGoalsEnabled)
                Text(
                  total > target ? '${grams(total - target)}g boven dagdoel' : 'Dagdoel ${grams(target)}g',
                  style: context.t.caption.copyWith(color: total > target ? k.dangerInk : k.textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _toneInk(KineticColors k, KTone tone) => toneColors(k, tone).$2;

// ------------------------------------------------------------ presets

// ---------------------------------------------------------- barometer

class _MacroBarometer extends StatelessWidget {
  const _MacroBarometer();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    return KCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Eyebrow('Actieve macro-barometer', icon: Icons.speed, color: k.accent)),
              IconButton(
                tooltip: 'Doelen aanpassen',
                icon: Icon(Icons.edit_outlined, size: 20, color: k.textSecondary),
                onPressed: () => _editTargets(context),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              children: [
                _MacroRow(label: 'Koolhydraten', value: store.carbsToday, target: store.carbsTarget, color: k.primary),
                _MacroRow(label: 'Eiwit', value: store.proteinToday, target: store.proteinTarget, color: k.blue),
                _MacroRow(label: 'Vetten', value: store.fatToday, target: store.fatTarget, color: k.purple),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTargets(BuildContext context) async {
    final store = KineticScope.read(context);
    final c = TextEditingController(text: grams(store.carbsTarget));
    final p = TextEditingController(text: grams(store.proteinTarget));
    final f = TextEditingController(text: grams(store.fatTarget));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dagdoelen (gram)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (ctrl, label) in [(c, 'Koolhydraten'), (p, 'Eiwit'), (f, 'Vetten')]) ...[
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: ctx.t.body,
                decoration: InputDecoration(labelText: label, suffixText: 'g'),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              store.setNutritionGoalsEnabled(false);
            },
            child: const Text('Dagdoel uitzetten'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Opslaan')),
        ],
      ),
    );
    if (ok == true) {
      double? v(TextEditingController x) {
        final n = parseNum(x.text);
        return n == null || n <= 0 || n > 2000 ? null : n;
      }

      await store.setMacroTargets(carbs: v(c), protein: v(p), fat: v(f));
    }
    c.dispose();
    p.dispose();
    f.dispose();
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.label, required this.value, required this.target, required this.color});
  final String label;
  final double value;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final rest = target - value;
    final over = rest < 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(label, style: context.t.bodyStrong),
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: grams(value),
                      style: context.t.subtitle.copyWith(
                        color: over ? k.dangerInk : k.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(text: ' / ${grams(target)}g', style: context.t.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          KProgressBar(value: target <= 0 ? 0 : value / target, color: over ? k.danger : color, height: 8),
          const SizedBox(height: 6),
          Row(
            children: [
              if (over) ...[Icon(Icons.warning_amber_rounded, size: 14, color: k.dangerInk), const SizedBox(width: 4)],
              Text(
                over ? '${grams(-rest)}g boven doel' : '${grams(rest)}g resterend',
                style: context.t.caption.copyWith(color: over ? k.dangerInk : k.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ maaltijden

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.response, required this.hyper});
  final FoodLogEntry entry;
  final MealResponse? response;
  final double hyper;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.read(context);
    final k = context.k;
    final e = entry;
    final macros = [
      if (e.protein != null) 'Eiwit ${grams(e.protein!)}g',
      if (e.fat != null) 'Vet ${grams(e.fat!)}g',
    ];
    final iconColor = switch (e.context) {
      MealContext.preTraining => k.accent,
      MealContext.postTraining => k.blue,
      MealContext.acute => k.warning,
      _ => k.accent,
    };
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: k.dangerTint, borderRadius: BorderRadius.circular(KRadius.lg)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Verwijderen', style: context.t.bodyStrong.copyWith(color: k.dangerInk)),
            const SizedBox(width: 8),
            Icon(Icons.delete_outline, color: k.dangerInk),
          ],
        ),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Verwijderen?'),
          content: Text('"${e.description.isEmpty ? 'Maaltijd' : e.description}" wordt uit je logboek en Supabase verwijderd.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: k.danger, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Verwijderen'),
            ),
          ],
        ),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final ok = await store.deleteFood(e);
        if (!ok) showToastOn(messenger, 'Verwijderen mislukt', error: true);
      },
      child: KCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(icon: _mealIcon(e), size: 40, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mealTitle(e), style: context.t.title),
                      const SizedBox(height: 2),
                      Text('${hhmm(e.at)} • ${_contextLabel(e.context)}', style: context.t.caption),
                    ],
                  ),
                ),
                if ((e.insulinUnits ?? 0) > 0) ...[
                  const SizedBox(width: 8),
                  KPill('${e.insulinUnits!.toStringAsFixed(1)} E bolus', tone: KTone.info, dense: true),
                ],
              ],
            ),
            const SizedBox(height: 12),
            KWell(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.description.isEmpty ? 'Maaltijd' : e.description,
                          style: context.t.bodyStrong,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (macros.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(macros.join(' • '), style: context.t.caption),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        e.carbs == null ? '--' : '${grams(e.carbs!)}g',
                        style: context.t.metricSm.copyWith(color: e.carbs == null ? k.textMuted : k.accent),
                      ),
                      Text('carbs', style: context.t.labelSm.copyWith(color: k.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _ResponseRow(entry: e, response: response, hyper: hyper),
          ],
        ),
      ),
    );
  }
}

class _ResponseRow extends StatelessWidget {
  const _ResponseRow({required this.entry, required this.response, required this.hyper});
  final FoodLogEntry entry;
  final MealResponse? response;
  final double hyper;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final r = response;
    final buffer = entry.context == MealContext.preTraining || entry.context == MealContext.acute;
    final (tone, verdict) = r == null ? (KTone.neutral, '') : responseVerdict(r, hyper);
    final ink = _toneInk(k, tone);
    String detail;
    if (r == null) {
      detail = 'Geen CGM-data in de 2 uur na deze maaltijd';
    } else {
      final rising = r.rise > 0.2 && r.peakAfter.inMinutes > 0;
      detail = [
        rising ? 'Piek na ${r.peakAfter.inMinutes} min' : 'Geen stijging',
        verdict,
        if (!r.complete) 'meting loopt',
      ].join(' • ');
    }
    return KWell(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: r == null ? k.textMuted : ink, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r == null)
                  Text('Nog geen respons', style: context.t.bodyStrong.copyWith(color: k.textSecondary))
                else
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: buffer ? 'Glucosebuffer: ' : 'Respons: ', style: context.t.caption.copyWith(color: k.text)),
                        TextSpan(
                          text: '${dec1(r.start)} → ${dec1(r.peak)} mmol/L',
                          style: context.t.bodyStrong.copyWith(
                            color: tone == KTone.success ? k.accent : ink,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 2),
                Text(detail, style: context.t.caption.copyWith(color: r == null ? k.textMuted : k.textSecondary)),
              ],
            ),
          ),
          if (r != null && r.points.length >= 3) ...[
            const SizedBox(width: 10),
            SizedBox(width: 64, child: GlucoseSparkline(points: r.points, height: 28)),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- inzicht

/// Eén korte, afgeleide observatie over brandstof en glucose vandaag.
String? _insight(KineticStore store, List<FoodLogEntry> entries, Map<String, MealResponse?> responses, DateTime now) {
  final next = store.nextPlannedTraining;
  if (next != null && next.startsAt.isAfter(now) && next.startsAt.difference(now) <= const Duration(hours: 3)) {
    final mins = next.startsAt.difference(now).inMinutes;
    final left = store.carbsRemaining;
    final hasPre = entries.any(
      (e) => e.context == MealContext.preTraining && now.difference(e.at) <= const Duration(minutes: 90),
    );
    return '${next.title} begint om ${hhmm(next.startsAt)} (over ${durationLabel(mins)}). '
        '${left > 0 ? 'Nog ${grams(left)}g koolhydraten tot je dagdoel. ' : ''}'
        '${hasPre ? 'Je pre-workout brandstof staat al gelogd.' : '15-30g snelle koolhydraten ~30 min vooraf houdt je glucose stabiel tijdens harde rondes.'}';
  }
  for (final e in entries) {
    final r = responses[e.id];
    if (e.context == MealContext.preTraining && r != null && r.low >= targetLow && r.peak <= targetHigh) {
      return 'Je pre-workout brandstof van ${hhmm(e.at)} hield je glucose tussen ${dec1(r.low)} en ${dec1(r.peak)} mmol/L. Die timing werkt voor harde rondes.';
    }
  }
  FoodLogEntry? biggest;
  for (final e in entries) {
    final r = responses[e.id];
    if (r == null || r.rise <= 2.5) continue;
    if (biggest == null || r.rise > responses[biggest.id]!.rise) biggest = e;
  }
  if (biggest != null) {
    final r = responses[biggest.id]!;
    return 'Grootste stijging vandaag: +${dec1(r.rise)} mmol/L na ${mealTitle(biggest).toLowerCase()} (piek na ${r.peakAfter.inMinutes} min).';
  }
  final measured = [for (final e in entries) ?responses[e.id]];
  if (measured.isNotEmpty && measured.every((r) => r.low >= targetLow && r.peak <= targetHigh)) {
    return 'Alle maaltijden van vandaag bleven binnen je doelbereik (${dec1(targetLow)} - ${dec1(targetHigh)} mmol/L).';
  }
  return null;
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return KCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: Icons.lightbulb_outline, size: 40, color: k.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Metabool inzicht', style: context.t.title),
                const SizedBox(height: 6),
                Text(text, style: context.t.body.copyWith(color: k.textSecondary)),
                const SizedBox(height: 8),
                Text('Vuistregel op basis van je eigen data, geen medisch advies.', style: context.t.caption.copyWith(color: k.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
