// exercise_blocks.dart — weergave van blokken (supersets) en rust bij
// krachttraining, gedeeld door de live training en de schema-editor:
//   • een gekleurde balk links van alle oefeningen in hetzelfde blok;
//   • een kopje boven het blok ("Blok A · 3 rondes · 2 min rust");
//   • een menu per oefening (koppelen, losmaken, rust);
//   • een rustkiezer.
// De logica (welke oefeningen bij elkaar horen) zit in core/rest_blocks.dart.

import 'package:flutter/material.dart';

import '../core/rest_blocks.dart';
import '../theme/kinetic_theme.dart';

/// Kleuren voor opeenvolgende blokken — wisselen, zodat twee blokken onder
/// elkaar altijd van elkaar te onderscheiden zijn.
const kBlockColors = [
  AppColor.ice,
  AppColor.amber,
  AppColor.coralSoft,
  AppColor.slate,
];

/// Per oefening: de kleur en letter van zijn blok (null = losse oefening),
/// en of hij de eerste van zijn blok is.
class BlockInfo {
  final Color? color;
  final String? letter;
  final bool isFirst;
  final int size;
  const BlockInfo({
    this.color,
    this.letter,
    this.isFirst = true,
    this.size = 1,
  });

  bool get inBlock => color != null;
}

List<BlockInfo> blockInfos(List<int?> blocks) {
  final result = List<BlockInfo>.filled(blocks.length, const BlockInfo());
  var n = 0;
  for (final r in blockRanges(blocks)) {
    final size = r.end - r.start;
    if (size < 2) continue;
    final color = kBlockColors[n % kBlockColors.length];
    final letter = blockLetter(n);
    n++;
    for (var i = r.start; i < r.end; i++) {
      result[i] = BlockInfo(
        color: color,
        letter: letter,
        isFirst: i == r.start,
        size: size,
      );
    }
  }
  return result;
}

/// Zet een gekleurde balk links van [child] als de oefening in een blok zit.
class BlockFrame extends StatelessWidget {
  const BlockFrame({super.key, required this.info, required this.child});

  final BlockInfo info;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = info.color;
    if (color == null) return child;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Kopje boven een blok — tikken past de rust van het blok aan.
class BlockHeader extends StatelessWidget {
  const BlockHeader({
    super.key,
    required this.info,
    required this.rounds,
    required this.restSeconds,
    required this.onEditRest,
    this.label,
    this.collapsed,
    this.onToggle,
  });

  /// Als gezet: een pijltje om het hele blok in/uit te klappen.
  final bool? collapsed;
  final VoidCallback? onToggle;

  final BlockInfo info;
  final int rounds;
  final int restSeconds;
  final VoidCallback onEditRest;

  /// Eigen tekst in plaats van "Blok A · 3 rondes · 2 min rust …".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = info.color ?? AppColor.inkFaint;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: InkWell(
        onTap: onEditRest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(Icons.link, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label ??
                      'Blok ${info.letter} · $rounds '
                          '${rounds == 1 ? 'ronde' : 'rondes'} · '
                          '${formatRest(restSeconds)} rust na elke ronde',
                  style: AppText.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.edit_outlined, size: 12, color: color),
              const Spacer(),
              if (onToggle != null)
                InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(99),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      collapsed == true ? Icons.unfold_more : Icons.unfold_less,
                      size: 18,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum ExerciseBlockAction { info, link, unlink, rest, remove }

/// De enige actieknop (⋮) bij een oefening: opent een paneel met info en
/// video's, koppelen/losmaken (blok), rust en verwijderen — in plaats van
/// een rij losse icoontjes op de kaart.
class ExerciseBlockMenu extends StatelessWidget {
  const ExerciseBlockMenu({
    super.key,
    required this.title,
    required this.canLink,
    required this.inBlock,
    required this.onSelected,
    this.hasVideos = false,
  });

  final String title;
  final bool canLink;
  final bool inBlock;
  final bool hasVideos;
  final ValueChanged<ExerciseBlockAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Acties',
      visualDensity: VisualDensity.compact,
      icon: Icon(
        Icons.more_vert,
        color: hasVideos ? AppColor.ice : AppColor.inkFaint,
      ),
      onPressed: () async {
        final action = await showExerciseActions(
          context,
          title: title,
          canLink: canLink,
          inBlock: inBlock,
          hasVideos: hasVideos,
        );
        if (action == null || !context.mounted) return;
        if (action == ExerciseBlockAction.remove) {
          final sure = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text('$title verwijderen?', style: AppText.cardTitle),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Annuleer'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColor.redBright,
                  ),
                  child: const Text('Verwijder'),
                ),
              ],
            ),
          );
          if (sure != true) return;
        }
        onSelected(action);
      },
    );
  }
}

/// Paneel met de acties voor één oefening.
Future<ExerciseBlockAction?> showExerciseActions(
  BuildContext context, {
  required String title,
  required bool canLink,
  required bool inBlock,
  bool hasVideos = false,
}) {
  Widget item(
    BuildContext c,
    ExerciseBlockAction action,
    IconData icon,
    String label, {
    String? subtitle,
    Color? color,
  }) => ListTile(
    leading: Icon(icon, color: color),
    title: Text(label, style: color == null ? null : TextStyle(color: color)),
    subtitle: subtitle == null ? null : Text(subtitle),
    onTap: () => Navigator.pop(c, action),
  );

  return showModalBottomSheet<ExerciseBlockAction>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text(title, style: AppText.cardTitle),
          ),
          item(
            c,
            ExerciseBlockAction.info,
            hasVideos ? Icons.play_circle_outline : Icons.info_outline,
            hasVideos ? "Uitleg en video's" : 'Uitleg en video toevoegen',
          ),
          if (canLink)
            item(
              c,
              ExerciseBlockAction.link,
              Icons.link,
              'Koppel aan oefening erboven',
              subtitle: 'Samen één blok, rust pas na de ronde',
            ),
          if (inBlock)
            item(
              c,
              ExerciseBlockAction.unlink,
              Icons.link_off,
              'Losmaken uit blok',
            ),
          item(
            c,
            ExerciseBlockAction.rest,
            Icons.timer_outlined,
            inBlock ? 'Rust van het blok' : 'Rust na elke set',
          ),
          item(
            c,
            ExerciseBlockAction.remove,
            Icons.delete_outline,
            'Verwijderen',
            color: AppColor.redBright,
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Uitkomst van [showRestPicker]: een aantal seconden, of [useDefault].
class RestChoice {
  final int? seconds;
  const RestChoice(this.seconds);
  bool get useDefault => seconds == null;
}

/// Kiest een rusttijd (15 s – 5 min, per 15 s). Null = geannuleerd.
Future<RestChoice?> showRestPicker(
  BuildContext context, {
  required int? current,
  required int defaultRest,
  required String title,
}) {
  var value = (current ?? defaultRest).clamp(15, 300).toDouble();
  return showModalBottomSheet<RestChoice>(
    context: context,
    backgroundColor: AppColor.surfaceRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.cardTitle),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  formatRest(value.round()),
                  style: AppText.cardTitle.copyWith(
                    fontSize: 28,
                    color: AppColor.tealBright,
                  ),
                ),
              ),
              Slider(
                value: value,
                min: 15,
                max: 300,
                divisions: 19,
                activeColor: AppColor.teal,
                inactiveColor: AppColor.line,
                onChanged: (v) => setState(() => value = v),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in const [60, 90, 120, 180])
                    ActionChip(
                      label: Text(formatRest(s)),
                      onPressed: () => setState(() => value = s.toDouble()),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, const RestChoice(null)),
                    child: Text('Standaard (${formatRest(defaultRest)})'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, RestChoice(value.round())),
                    style: FilledButton.styleFrom(
                      // Thema-knoppen zijn standaard volle breedte; in een rij
                      // moet hij zijn eigen breedte houden.
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('Opslaan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
