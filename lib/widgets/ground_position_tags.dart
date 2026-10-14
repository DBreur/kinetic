// ground_position_tags.dart — toont de transitie van een techniek ("Striking
// → Takedown") en de gekozen grondposities van een Submission-techniek (zie
// lib/core/positions.dart's kGroundPositions) als kleine outline-tags met
// een icoontje, zodat meteen duidelijk is waar het om gaat — platte grijze
// tekst onder de naam viel te veel weg tussen de andere onderschriften.

import 'package:flutter/material.dart';

import '../core/positions.dart';
import '../theme/kinetic_theme.dart';

class GroundPositionTags extends StatelessWidget {
  const GroundPositionTags({
    super.key,
    this.positions = const [],
    this.transition = '',
  });

  final List<String> positions;

  /// Ruwe transitie ("Staand -> Takedown"); leeg = geen transitie-tag.
  final String transition;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty && transition.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (transition.trim().isNotEmpty) TransitionTag(transition: transition),
        for (final p in positions)
          _Tag(
            children: [
              const Icon(
                Icons.place_outlined,
                size: 10,
                color: AppColor.inkFaint,
              ),
              const SizedBox(width: 3),
              Text(p, style: _style),
            ],
          ),
      ],
    );
  }
}

final _style = AppText.caption.copyWith(
  fontSize: 10,
  color: AppColor.inkMuted,
);

/// "Striking → Takedown" als tag: van, een pijl, naar.
class TransitionTag extends StatelessWidget {
  const TransitionTag({super.key, required this.transition});

  final String transition;

  @override
  Widget build(BuildContext context) {
    final parsed = parseTransition(transition);
    return _Tag(
      children: [
        const Icon(Icons.alt_route, size: 10, color: AppColor.inkFaint),
        const SizedBox(width: 3),
        if (parsed == null)
          Text(transition.replaceAll('->', '→'), style: _style)
        else ...[
          Text(parsed.from, style: _style),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 3),
            child: Icon(Icons.arrow_forward, size: 10, color: AppColor.inkFaint),
          ),
          Text(parsed.to, style: _style),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: AppColor.line),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
