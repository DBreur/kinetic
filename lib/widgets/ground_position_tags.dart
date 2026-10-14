// ground_position_tags.dart — toont de gekozen grondposities van een
// Submission-techniek (zie lib/core/positions.dart's kGroundPositions) als
// kleine outline-tags met een icoontje, zodat meteen duidelijk is dat het om
// een positie gaat — platte grijze tekst onder de naam viel te veel weg
// tussen de andere onderschriften.

import 'package:flutter/material.dart';

import '../theme/kinetic_theme.dart';

class GroundPositionTags extends StatelessWidget {
  const GroundPositionTags({super.key, required this.positions});

  final List<String> positions;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final p in positions)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: AppColor.line),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 10,
                  color: AppColor.inkFaint,
                ),
                const SizedBox(width: 3),
                Text(
                  p,
                  style: AppText.caption.copyWith(
                    fontSize: 10,
                    color: AppColor.inkMuted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
