// dashboard_editor.dart — in de instellingen: de blokken van het dashboard
// en de snelle acties aan/uit zetten en (als het slot open is) in een
// andere volgorde slepen. Het slot voorkomt dat je per ongeluk iets
// versleept terwijl je door de instellingen scrollt.

import 'package:flutter/material.dart';

import '../models/dashboard_config.dart';
import '../theme/kinetic_theme.dart';

class DashboardEditor extends StatelessWidget {
  const DashboardEditor({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final DashboardConfig config;
  final ValueChanged<DashboardConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final locked = config.locked;
    final quickOn = config.sections
        .firstWhere((s) => s.id == DashSection.quickActions)
        .enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                locked
                    ? 'Op slot — tik op het slotje om te kunnen slepen.'
                    : 'Sleep aan de grepen om de volgorde te veranderen.',
                style: AppText.caption,
              ),
            ),
            IconButton(
              tooltip: locked ? 'Slot openen' : 'Op slot zetten',
              onPressed: () => onChanged(config.copyWith(locked: !locked)),
              icon: Icon(
                locked ? Icons.lock_outline : Icons.lock_open,
                color: locked ? AppColor.inkMuted : AppColor.ice,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Blokken', style: AppText.bodyStrong),
        const SizedBox(height: 6),
        _ReorderList<DashSection>(
          items: config.sections,
          locked: locked,
          label: (s) => s.label,
          icon: (s) => s.icon,
          onChanged: (items) => onChanged(config.copyWith(sections: items)),
        ),
        const SizedBox(height: 16),
        Text('Snelle acties', style: AppText.bodyStrong),
        const SizedBox(height: 2),
        Text(
          quickOn
              ? 'Kies welke acties je ziet, en in welke volgorde.'
              : 'Het blok Snelle acties staat uit — deze acties zie je pas '
                    'als je het blok weer aanzet.',
          style: AppText.caption,
        ),
        const SizedBox(height: 6),
        Opacity(
          opacity: quickOn ? 1 : .5,
          child: _ReorderList<QuickAction>(
            items: config.actions,
            locked: locked,
            label: (a) => a.label,
            icon: (a) => a.icon,
            subtitle: (a) => a == QuickAction.finger
                ? 'Alleen bij meten met vingerprik'
                : null,
            onChanged: (items) => onChanged(config.copyWith(actions: items)),
          ),
        ),
      ],
    );
  }
}

class _ReorderList<T> extends StatelessWidget {
  const _ReorderList({
    required this.items,
    required this.locked,
    required this.label,
    required this.icon,
    required this.onChanged,
    this.subtitle,
  });

  final List<DashItem<T>> items;
  final bool locked;
  final String Function(T) label;
  final IconData Function(T) icon;
  final String? Function(T)? subtitle;
  final ValueChanged<List<DashItem<T>>> onChanged;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (from, to) {
        final next = List.of(items);
        next.insert(to, next.removeAt(from));
        onChanged(next);
      },
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            key: ValueKey(items[i].id),
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: AppColor.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: locked
                          ? null
                          : ReorderableDragStartListener(
                              index: i,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.drag_handle,
                                  size: 20,
                                  color: AppColor.inkMuted,
                                ),
                              ),
                            ),
                    ),
                    Icon(
                      icon(items[i].id),
                      size: 18,
                      color: items[i].enabled
                          ? AppColor.coral
                          : AppColor.inkGhost,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label(items[i].id),
                            style: AppText.body.copyWith(
                              color: items[i].enabled
                                  ? AppColor.ink
                                  : AppColor.inkFaint,
                            ),
                          ),
                          if (subtitle?.call(items[i].id) case final sub?)
                            Text(
                              sub,
                              style: AppText.caption.copyWith(fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    Switch(
                      value: items[i].enabled,
                      onChanged: (v) {
                        final next = List.of(items);
                        next[i] = items[i].withEnabled(v);
                        onChanged(next);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
