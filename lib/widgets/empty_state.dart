// empty_state.dart — consistente lege staat: klein icoon + korte uitleg,
// i.p.v. een kale tekstregel. Gebruikt op plekken waar een lijst nog leeg is
// (nog geen trainingen, technieken, oefeningen, enz.).

import 'package:flutter/material.dart';

import '../theme/kinetic_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColor.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColor.inkFaint),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: AppText.caption),
        ],
      ),
    );
  }
}
