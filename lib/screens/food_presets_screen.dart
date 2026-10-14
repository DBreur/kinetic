// food_presets_screen.dart — voedingspresets beheren als volwaardige
// pagina (was een lange modal in de instellingen): zoeken, per letter
// gegroepeerd, met hoe vaak je elke preset gebruikt. Elke wijziging wordt
// meteen in het profiel bewaard.

import 'package:flutter/material.dart';

import '../core/food_preset_usage.dart';
import '../core/formatters.dart';
import '../models/food_preset.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic.dart';
import 'settings_screen.dart' show showFoodPresetDialog;

class FoodPresetsScreen extends StatefulWidget {
  const FoodPresetsScreen({
    super.key,
    required this.controller,
    this.usage,
  });

  final AppController controller;

  /// Hoe vaak elke preset gebruikt is; null = onbekend (dan niet tonen).
  final Map<String, int>? usage;

  @override
  State<FoodPresetsScreen> createState() => _FoodPresetsScreenState();
}

class _FoodPresetsScreenState extends State<FoodPresetsScreen> {
  final _search = TextEditingController();
  bool _busy = false;

  List<FoodPreset> get _presets =>
      widget.controller.profile?.foodPresets ?? const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _save(List<FoodPreset> next) async {
    final profile = widget.controller.profile;
    if (profile == null) return;
    setState(() => _busy = true);
    await widget.controller.saveProfile(
      profile.copyWith(foodPresets: sortedPresets(next)),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final error = widget.controller.authError;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _add() async {
    final result = await showFoodPresetDialog(context);
    if (result == null) return;
    if (_presets.any(
      (p) => p.singular.toLowerCase() == result.singular.toLowerCase(),
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${result.singular}" bestaat al.')),
        );
      }
      return;
    }
    await _save([..._presets, result]);
  }

  Future<void> _edit(FoodPreset preset) async {
    final result = await showFoodPresetDialog(context, existing: preset);
    if (result == null) return;
    await _save([
      for (final p in _presets) p.singular == preset.singular ? result : p,
    ]);
  }

  Future<void> _delete(FoodPreset preset) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('"${preset.singular}" verwijderen?', style: AppText.cardTitle),
        content: Text(
          'Eerder gelogde eetmomenten blijven gewoon staan.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuleer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _save([
      for (final p in _presets)
        if (p.singular != preset.singular) p,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final query = _search.text.trim();
        final filtered = query.isEmpty
            ? _presets
            : searchPresets(_presets, query, usage: widget.usage ?? const {});
        final groups = groupByLetter(filtered);
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KINETIC',
                  style: AppText.cardTitle.copyWith(
                    height: 1,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 3),
                KLabel('Voedingspresets · ${_presets.length}'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add),
            label: const Text('Preset'),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  style: AppText.body,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Zoek een preset…',
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                ),
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  children: [
                    if (_presets.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          'Nog geen presets. Een preset is iets wat je vaak eet, '
                          'met de koolhydraten per stuk — bij het loggen tel je '
                          'het dan met één tik op.',
                          style: AppText.caption,
                        ),
                      )
                    else if (groups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          'Niets gevonden voor "$query".',
                          style: AppText.caption,
                        ),
                      ),
                    for (final (letter, items) in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 12, 0, 6),
                        child: KLabel(letter, color: AppColor.ice),
                      ),
                      for (final p in items)
                        _PresetTile(
                          preset: p,
                          uses: widget.usage == null ? null : (widget.usage![p.singular] ?? 0),
                          onTap: () => _edit(p),
                          onDelete: () => _delete(p),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.uses,
    required this.onTap,
    required this.onDelete,
  });

  final FoodPreset preset;
  final int? uses;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = preset;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Column(
                    children: [
                      Text(
                        carbsText(p.carbs),
                        style: AppText.cardTitle.copyWith(
                          color: AppColor.ice,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const KLabel('g KH'),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.singular, style: AppText.bodyStrong),
                      Text(
                        [
                          if (p.plural != p.singular) 'mv. ${p.plural}',
                          if (p.hasUnit) '${p.amountLabel(1)} per stuk',
                          if (uses != null)
                            uses == 0 ? 'nog niet gebruikt' : '$uses× gebruikt',
                        ].join(' · '),
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Verwijderen',
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppColor.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
