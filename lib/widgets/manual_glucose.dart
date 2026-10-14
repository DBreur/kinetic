// manual_glucose.dart — vingerprik invoeren en de laatste waardes tonen.
//
// Gebruikt op de "Nu"-pagina en tijdens een live sessie (mat-modus en
// krachttraining), zodat vingerprikgebruikers overal op dezelfde manier een
// meting kunnen invoeren en de richting (stijgend/dalend/stabiel) kunnen
// aflezen uit de laatste metingen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../core/formatters.dart';
import '../models/glucose.dart';
import '../models/glucose_entry.dart';
import '../theme/kinetic_theme.dart';

/// Toont een dialoog om een vingerprikwaarde in te voeren. Geeft de waarde
/// terug, of null als geannuleerd.
Future<double?> showManualGlucoseDialog(
  BuildContext context, {
  double? initial,
}) {
  final controller = TextEditingController(
    text: initial != null ? mmolText(initial) : '',
  );
  return showDialog<double>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: AppColor.surface,
      title: Text('Vingerprik invoeren', style: AppText.cardTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: AppText.display.copyWith(fontSize: 32),
        decoration: InputDecoration(
          suffixText: 'mmol/L',
          suffixStyle: AppText.caption,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Annuleer'),
        ),
        FilledButton(
          onPressed: () {
            final value = double.tryParse(
              controller.text.trim().replaceAll(',', '.'),
            );
            if (value == null || value <= 0 || value > 40) return;
            Navigator.pop(c, value);
          },
          child: const Text('Opslaan'),
        ),
      ],
    ),
  );
}

/// Resultaat van [showManualGlucoseEditDialog]: een nieuwe waarde, of een
/// signaal dat de meting verwijderd moet worden.
class ManualGlucoseEditResult {
  final double? mmol;
  final bool deleted;
  const ManualGlucoseEditResult.updated(this.mmol) : deleted = false;
  const ManualGlucoseEditResult.deleted() : mmol = null, deleted = true;
}

/// Dialoog om een eerder ingevoerde meting te wijzigen of te verwijderen —
/// getoond na een tik op een meting in [FingerHistoryStrip].
Future<ManualGlucoseEditResult?> showManualGlucoseEditDialog(
  BuildContext context,
  ManualGlucoseEntry entry,
) {
  final controller = TextEditingController(text: mmolText(entry.mmol));
  return showDialog<ManualGlucoseEditResult>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: AppColor.surface,
      title: Text(
        'Vingerprik om ${DateFormat('HH:mm', 'nl_NL').format(entry.at)}',
        style: AppText.cardTitle,
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: AppText.display.copyWith(fontSize: 32),
        decoration: InputDecoration(
          suffixText: 'mmol/L',
          suffixStyle: AppText.caption,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(c, const ManualGlucoseEditResult.deleted()),
          style: TextButton.styleFrom(foregroundColor: AppColor.redBright),
          child: const Text('Verwijderen'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Annuleer'),
        ),
        FilledButton(
          onPressed: () {
            final value = double.tryParse(
              controller.text.trim().replaceAll(',', '.'),
            );
            if (value == null || value <= 0 || value > 40) return;
            Navigator.pop(c, ManualGlucoseEditResult.updated(value));
          },
          child: const Text('Opslaan'),
        ),
      ],
    ),
  );
}

/// Kaart voor de "Nu"-pagina bij vingerprik: grote laatste waarde + richting,
/// de laatste metingen op een rij, en een knop om een nieuwe in te voeren.
class FingerGlucoseCard extends StatelessWidget {
  final List<ManualGlucoseEntry> entries; // nieuwste eerst
  final VoidCallback onAdd;
  final ValueChanged<ManualGlucoseEntry>? onTapEntry;
  const FingerGlucoseCard({
    super.key,
    required this.entries,
    required this.onAdd,
    this.onTapEntry,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: AppColor.line),
          color: AppColor.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nog geen vingerprik ingevoerd.',
              style: AppText.body.copyWith(color: AppColor.inkMuted),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onAdd,
              child: const Text('Vingerprik invoeren'),
            ),
          ],
        ),
      );
    }

    final latest = entries.first;
    final state = glucoseStateFor(latest.mmol);
    final c = glucoseColor(state);
    final bright = state == GlucoseState.inRange
        ? AppColor.greenBright
        : (state == GlucoseState.low
              ? AppColor.redBright
              : AppColor.amberBright);
    const trendIcons = {
      Trend.up: '↑',
      Trend.slightUp: '↗',
      Trend.flat: '→',
      Trend.slightDown: '↘',
      Trend.down: '↓',
      Trend.fastDown: '↓↓',
    };
    const trendLabels = {
      Trend.up: 'stijgend',
      Trend.slightUp: 'licht stijgend',
      Trend.flat: 'stabiel',
      Trend.slightDown: 'licht dalend',
      Trend.down: 'dalend',
      Trend.fastDown: 'snel dalend',
    };
    final trend = entries.length > 1
        ? trendFromDelta(latest.mmol - entries[1].mmol)
        : null;
    final trendIcon = trend == null ? '→' : trendIcons[trend]!;
    final trendLabel = trend == null ? 'eerste meting' : trendLabels[trend]!;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: c.withValues(alpha: .35)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.withValues(alpha: .22), c.withValues(alpha: .06)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(mmolText(latest.mmol), style: AppText.reading),
              const SizedBox(width: 8),
              Text(
                'mmol/L',
                style: AppText.caption.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: .25),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Row(
                  children: [
                    Text(
                      trendIcon,
                      style: AppText.bodyStrong.copyWith(
                        fontWeight: FontWeight.w700,
                        color: bright,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      trendLabel,
                      style: AppText.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: bright,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Vingerprik · ${relativeDutch(latest.at)}',
            style: AppText.caption.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 12),
          FingerHistoryStrip(entries: entries, onTapEntry: onTapEntry),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onAdd,
              child: const Text('Nieuwe vingerprik invoeren'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compacte rij met de laatste metingen — herbruikt tijdens een live sessie
/// zodat je ook daar in één oogopslag de richting ziet.
class FingerHistoryStrip extends StatelessWidget {
  final List<ManualGlucoseEntry> entries; // nieuwste eerst
  final ValueChanged<ManualGlucoseEntry>? onTapEntry;
  const FingerHistoryStrip({super.key, required this.entries, this.onTapEntry});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final ordered = entries.reversed
        .toList(); // oudste eerst, links naar rechts
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ordered.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = ordered[i];
          final isLatest = i == ordered.length - 1;
          final content = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isLatest
                  ? Colors.white.withValues(alpha: .12)
                  : Colors.white.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(AppRadius.sm + 3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(mmolText(e.mmol), style: AppText.cardTitle),
                Text(
                  DateFormat('HH:mm', 'nl_NL').format(e.at),
                  style: AppText.caption.copyWith(fontSize: 9),
                ),
              ],
            ),
          );
          if (onTapEntry == null) return content;
          return InkWell(
            onTap: () => onTapEntry!(e),
            borderRadius: BorderRadius.circular(AppRadius.sm + 3),
            child: content,
          );
        },
      ),
    );
  }
}
