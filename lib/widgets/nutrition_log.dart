// nutrition_log.dart — voeding loggen tijdens een training.
//
// Elke preset (samengesteld in de instellingen) heeft een plus en een min om
// aan te geven hoeveel je ervan neemt. Pas als je op "Toevoegen" drukt wordt
// alles wat je hebt opgeteld in één keer gelogd als één blokje (bv. "4x AA,
// Melk"), zodat de log overzichtelijk blijft. Daarna resetten de tellers.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../core/formatters.dart';
import '../models/training_session.dart';
import '../theme/kinetic_theme.dart';

/// Rij met voedingspresets — elk met een eigen +/− om op te tellen voor de
/// volgende keer loggen. Nog niet gelogd; dat gebeurt pas bij "Toevoegen".
class NutritionPresetRow extends StatelessWidget {
  final List<String> presets;
  final Map<String, int> pending;
  final ValueChanged<String> onIncrement;
  final ValueChanged<String> onDecrement;
  const NutritionPresetRow({
    super.key,
    required this.presets,
    required this.pending,
    required this.onIncrement,
    required this.onDecrement,
  });

  int _countFor(String preset) => pending[preset] ?? 0;

  @override
  Widget build(BuildContext context) {
    if (presets.isEmpty) {
      return Text(
        'Nog geen presets — voeg ze toe in Instellingen.',
        style: AppText.caption,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in presets)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColor.tealWash,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColor.teal.withValues(alpha: .3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p,
                      style: AppText.bodyStrong.copyWith(
                        fontSize: 13,
                        color: AppColor.tealBright,
                      ),
                    ),
                  ),
                  _stepBtn(
                    Icons.remove,
                    _countFor(p) > 0 ? () => onDecrement(p) : null,
                  ),
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${_countFor(p)}',
                      textAlign: TextAlign.center,
                      style: AppText.bodyStrong.copyWith(
                        color: AppColor.tealBright,
                      ),
                    ),
                  ),
                  _stepBtn(Icons.add, () => onIncrement(p)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 16,
        color: onTap == null ? AppColor.inkGhost : AppColor.tealBright,
      ),
    ),
  );
}

/// Compacte knop die de presets + de voedingslog in een bottom sheet opent —
/// houdt de hoofdlijst tijdens een training overzichtelijk in plaats van
/// alles permanent open te laten staan tussen de technieken/oefeningen.
class NutritionQuickButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const NutritionQuickButton({
    super.key,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColor.tealWash,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColor.teal.withValues(alpha: .35)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.restaurant_outlined,
              size: 17,
              color: AppColor.tealBright,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                count == 0 ? 'Voeding loggen' : 'Voeding · $count gelogd',
                style: AppText.bodyStrong.copyWith(
                  fontSize: 13,
                  color: AppColor.tealBright,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColor.tealBright,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opent de presets + voedingslog als bottom sheet, in plaats van ze
/// permanent tussen de technieken/oefeningen te tonen.
Future<void> showNutritionSheet(
  BuildContext context, {
  required List<String> presets,
  required List<NutritionEntry> entries,
  required NutritionEntry Function(String preset) onPick,
  required ValueChanged<int> onRemove,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColor.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.of(ctx).viewInsets.bottom +
            MediaQuery.of(ctx).padding.bottom +
            20,
      ),
      child: _NutritionSheet(
        presets: presets,
        initialEntries: entries,
        onPick: onPick,
        onRemove: onRemove,
      ),
    ),
  );
}

class _NutritionSheet extends StatefulWidget {
  final List<String> presets;
  final List<NutritionEntry> initialEntries;
  final NutritionEntry Function(String preset) onPick;
  final ValueChanged<int> onRemove;
  const _NutritionSheet({
    required this.presets,
    required this.initialEntries,
    required this.onPick,
    required this.onRemove,
  });

  @override
  State<_NutritionSheet> createState() => _NutritionSheetState();
}

class _NutritionSheetState extends State<_NutritionSheet> {
  late List<NutritionEntry> _entries;

  final Map<String, int> _pending = {};

  @override
  void initState() {
    super.initState();
    _entries = List.of(widget.initialEntries);
  }

  void _increment(String preset) {
    setState(() => _pending[preset] = (_pending[preset] ?? 0) + 1);
  }

  void _decrement(String preset) {
    setState(() {
      final next = (_pending[preset] ?? 0) - 1;
      if (next <= 0) {
        _pending.remove(preset);
      } else {
        _pending[preset] = next;
      }
    });
  }

  /// Alles wat je hebt opgeteld gaat in één keer als één blokje de log in,
  /// bv. "4x AA, Melk" — in plaats van vijf losse regels.
  void _confirm() {
    if (_pending.isEmpty) return;
    final label = _pending.entries
        .map((e) => e.value > 1 ? '${e.value}x ${e.key}' : e.key)
        .join(', ');
    final entry = widget.onPick(label);
    setState(() {
      _entries = [..._entries, entry];
      _pending.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColor.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            'Voeding tijdens training',
            style: AppText.cardTitle.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 16),
          Text('PRESETS', style: AppText.overline),
          const SizedBox(height: 10),
          NutritionPresetRow(
            presets: widget.presets,
            pending: _pending,
            onIncrement: _increment,
            onDecrement: _decrement,
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _pending.isEmpty ? null : _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.teal,
                foregroundColor: AppColor.greenInk,
              ),
              child: const Text('Toevoegen'),
            ),
          ),
          if (_entries.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('GELOGD', style: AppText.overline),
            const SizedBox(height: 10),
            NutritionLogList(
              entries: _entries,
              onRemove: (i) {
                widget.onRemove(i);
                setState(() => _entries = List.of(_entries)..removeAt(i));
              },
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Gereed'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wat er tijdens deze sessie al gelogd is, met tijd en glucose op dat
/// moment.
class NutritionLogList extends StatelessWidget {
  final List<NutritionEntry> entries;
  final ValueChanged<int>? onRemove;
  const NutritionLogList({super.key, required this.entries, this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(entries[i].label, style: AppText.bodyStrong),
                ),
                Text(
                  '${mmolText(entries[i].mmol)} mmol/L',
                  style: AppText.caption.copyWith(fontSize: 11),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('HH:mm', 'nl_NL').format(entries[i].at),
                  style: AppText.caption.copyWith(fontSize: 11),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => onRemove!(i),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: AppColor.inkFaint,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
