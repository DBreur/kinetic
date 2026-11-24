// eten_screen.dart: Eet Logboek: macrobarometer, snelle carb-presets,
// de maaltijd-bottom-sheet en het dagoverzicht uit `food_log_entries`.

import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../models/food_log_entry.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/sheets.dart';

class EtenScreen extends StatelessWidget {
  const EtenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    if (store.tab == KTab.eten) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && store.consumeMealSheetRequest()) showMealSheet(context);
      });
    }
    final entries = store.todayEntries;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: KColor.teal,
        onRefresh: store.refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Eyebrow(shortDate(store.now())),
            const SizedBox(height: 4),
            Text('Eet Logboek', style: KText.display),
            const SizedBox(height: 16),
            const _MacroBarometer(),
            const SizedBox(height: 12),
            const _CarbPresets(),
            const SizedBox(height: 12),
            BigButton(
              label: '+ Maaltijd of Snelle Carbs Toevoegen',
              icon: Icons.restaurant_menu,
              onPressed: () => showMealSheet(context),
            ),
            const SizedBox(height: 20),
            SectionTitle(
              'Dagoverzicht',
              trailing: Text('${entries.length} ${entries.length == 1 ? 'regel' : 'regels'}', style: KText.caption),
            ),
            if (entries.isEmpty)
              KCard(
                child: Text('Nog niets gelogd vandaag. Tik op een preset of voeg een maaltijd toe.', style: KText.caption),
              ),
            for (final e in entries) ...[
              _EntryTile(entry: e),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _MacroBarometer extends StatelessWidget {
  const _MacroBarometer();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    Widget row(String label, double value, double target, Color color) {
      final rest = target - value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(label, style: KText.subtitle),
                const Spacer(),
                Text.rich(TextSpan(children: [
                  TextSpan(text: grams(value), style: KText.subtitle.copyWith(color: color)),
                  TextSpan(text: ' / ${grams(target)}g', style: KText.caption),
                ])),
              ],
            ),
            const SizedBox(height: 8),
            KProgressBar(value: target <= 0 ? 0 : value / target, color: rest < 0 ? KColor.danger : color, height: 10),
            const SizedBox(height: 6),
            Text(
              rest >= 0 ? '${grams(rest)}g resterend' : '${grams(-rest)}g boven doel',
              style: KText.caption.copyWith(color: rest < 0 ? KColor.danger : KColor.textSecondary),
            ),
          ],
        ),
      );
    }

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('Actieve macro-barometer', color: KColor.tealLight, icon: Icons.speed)),
              IconButton(
                tooltip: 'Doelen aanpassen',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18, color: KColor.textSecondary),
                onPressed: () => _editTargets(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          row('Koolhydraten', store.carbsToday, store.carbsTarget, KColor.warning),
          row('Eiwit', store.proteinToday, store.proteinTarget, KColor.blue),
          row('Vetten', store.fatToday, store.fatTarget, KColor.purple),
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
                decoration: InputDecoration(labelText: label),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
        actions: [
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

class _CarbPresets extends StatelessWidget {
  const _CarbPresets();

  static const _presets = [
    (15.0, '+15g Dextrose', 'Dextrose', Icons.bolt),
    (30.0, '+30g Snack/Fruit', 'Snack/fruit', Icons.apple),
    (50.0, '+50g Maaltijd', 'Maaltijd', Icons.lunch_dining),
  ];

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    return Row(
      children: [
        for (final (i, p) in _presets.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: KCard(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              borderColor: KColor.warning.withValues(alpha: 0.35),
              onTap: () async {
                final before = store.carbsToday;
                final e = await store.logFood(description: p.$3, carbs: p.$1);
                if (!context.mounted) return;
                if (e == null) {
                  showToast(context, 'Opslaan mislukt', error: true);
                  return;
                }
                showToast(
                  context,
                  'Koolhydraten ${grams(before)} ➔ ${grams(store.carbsToday)}g',
                  actionLabel: 'Ongedaan',
                  onAction: () => store.deleteFood(e),
                );
              },
              child: Column(
                children: [
                  Icon(p.$4, color: KColor.warning, size: 22),
                  const SizedBox(height: 6),
                  Text(p.$2, textAlign: TextAlign.center, style: KText.caption.copyWith(color: KColor.text, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final FoodLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.read(context);
    final e = entry;
    final macros = [
      if (e.carbs != null) ('${grams(e.carbs!)}g K', KColor.warning),
      if (e.protein != null) ('${grams(e.protein!)}g E', KColor.blue),
      if (e.fat != null) ('${grams(e.fat!)}g V', KColor.purple),
      if ((e.insulinUnits ?? 0) > 0) ('${e.insulinUnits!.toStringAsFixed(1)} E ins.', KColor.teal),
    ];
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: KColor.danger.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(KRadius.lg)),
        child: const Icon(Icons.delete_outline, color: KColor.danger),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Verwijderen?'),
          content: Text('"${e.description}" wordt uit je logboek en Supabase verwijderd.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: KColor.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Verwijderen'),
            ),
          ],
        ),
      ),
      onDismissed: (_) => store.deleteFood(e),
      child: KCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 46, child: Text(hhmm(e.at), style: KText.subtitle.copyWith(color: KColor.textSecondary))),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.description.isEmpty ? 'Maaltijd' : e.description, style: KText.body.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (t, c) in macros) KBadge(t, color: c, dot: false),
                      if (e.context != null) KBadge(e.context!.shortLabel, color: KColor.textSecondary, dot: false),
                    ],
                  ),
                ],
              ),
            ),
            if (e.mmol != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(e.mmol!.toStringAsFixed(1), style: KText.subtitle.copyWith(color: glucoseColor(e.mmol!))),
              ),
          ],
        ),
      ),
    );
  }
}
