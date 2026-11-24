// technieken_screen.dart: Technieken Vault: accordeons per categorie,
// filterchips, mastery/bag-volume per techniek en de "Focus in Sessie"-
// toggle die bepaalt welke tellers op de live mat verschijnen.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../models/technique.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic_widgets.dart';

enum _Filter { all, focus, favorites, grappling, striking }

class TechniekenScreen extends StatefulWidget {
  const TechniekenScreen({super.key});

  @override
  State<TechniekenScreen> createState() => _TechniekenScreenState();
}

class _TechniekenScreenState extends State<TechniekenScreen> {
  _Filter _filter = _Filter.all;

  bool _matches(Technique t) => switch (_filter) {
    _Filter.all => true,
    _Filter.focus => t.isInFocus,
    _Filter.favorites => t.favorite,
    _Filter.grappling => !t.group.isStriking,
    _Filter.striking => t.group.isStriking,
  };

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final all = store.techniques;
    final shown = all.where(_matches).toList();
    final focusCount = store.focusTechniques.length;
    final groups = TechniqueGroup.values
        .where((g) => g != TechniqueGroup.other || shown.any((t) => t.group == g))
        .toList();
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: KColor.teal,
        onRefresh: store.refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const Eyebrow('Biomechanische vault'),
            const SizedBox(height: 4),
            Text('Technieken', style: KText.display),
            const SizedBox(height: 6),
            Text(
              '${all.length} technieken • $focusCount in focus voor de volgende sessie',
              style: KText.caption,
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (f, label) in const [
                    (_Filter.all, 'Alle'),
                    (_Filter.focus, '🎯 In focus'),
                    (_Filter.favorites, '★ Favorieten'),
                    (_Filter.grappling, 'Grappling'),
                    (_Filter.striking, 'Striking'),
                  ]) ...[
                    KChip(label: label, selected: _filter == f, onTap: () => setState(() => _filter = f)),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final g in groups) ...[
              _GroupAccordion(
                group: g,
                techniques: shown.where((t) => t.group == g).toList(),
                showAdd: _filter == _Filter.all,
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupAccordion extends StatelessWidget {
  const _GroupAccordion({required this.group, required this.techniques, required this.showAdd});
  final TechniqueGroup group;
  final List<Technique> techniques;
  final bool showAdd;

  Color get _accent => switch (group) {
    TechniqueGroup.strikes => KColor.danger,
    TechniqueGroup.throws => KColor.purple,
    TechniqueGroup.submissions => KColor.blue,
    TechniqueGroup.defense => KColor.warning,
    TechniqueGroup.other => KColor.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final focus = techniques.where((t) => t.isInFocus).length;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KRadius.lg),
      side: const BorderSide(color: KColor.border),
    );
    return ExpansionTile(
      key: PageStorageKey('group-${group.name}'),
      initiallyExpanded: techniques.isNotEmpty,
      shape: shape,
      collapsedShape: shape,
      backgroundColor: KColor.surfaceContainer,
      collapsedBackgroundColor: KColor.surfaceContainer,
      iconColor: KColor.textSecondary,
      collapsedIconColor: KColor.textSecondary,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      leading: Container(
        width: 10,
        height: 34,
        decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(4)),
      ),
      title: Text(group.label, style: KText.subtitle),
      subtitle: Text(
        '${techniques.length} ${techniques.length == 1 ? 'techniek' : 'technieken'}${focus > 0 ? ' • $focus in focus' : ''}',
        style: KText.caption,
      ),
      children: [
        if (techniques.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Nog geen technieken in deze categorie.', style: KText.caption),
          ),
        for (final t in techniques) ...[
          _TechniqueCard(technique: t, accent: _accent),
          const SizedBox(height: 8),
        ],
        if (showAdd)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add, color: KColor.teal),
              label: Text('Techniek toevoegen', style: KText.body.copyWith(color: KColor.teal)),
            ),
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final store = KineticScope.read(context);
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nieuwe techniek: ${group.label}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Naam', hintText: 'Harai Goshi'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Toevoegen')),
        ],
      ),
    );
    ctrl.dispose();
    final n = name?.trim() ?? '';
    if (n.isEmpty) return;
    final t = await store.createTechnique(n, group);
    if (!context.mounted) return;
    showToast(context, t == null ? 'Toevoegen mislukt' : '$n toegevoegd', error: t == null);
  }
}

class _TechniqueCard extends StatelessWidget {
  const _TechniqueCard({required this.technique, required this.accent});
  final Technique technique;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.read(context);
    final t = technique;
    final mastery = t.masteryPercent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(KRadius.md),
        border: Border.all(color: t.isInFocus ? KColor.teal.withValues(alpha: 0.6) : KColor.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (t.favorite) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.star, size: 16, color: KColor.warning)),
              Expanded(child: Text(t.name, style: KText.subtitle)),
              KBadge(t.group.isStriking ? 'Striking' : 'Grappling', color: accent, dot: false),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MASTERY INDEX', style: KText.eyebrow.copyWith(fontSize: 10)),
                    const SizedBox(height: 4),
                    Text(mastery == null ? '—' : '$mastery%', style: KText.metricSmall.copyWith(color: mastery == null ? KColor.textMuted : KColor.tealLight)),
                    const SizedBox(height: 6),
                    KProgressBar(value: (mastery ?? 0) / 100, height: 6),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 3,
                child: _Stat(label: 'BAG VOLUME', value: t.loggedReps == 0 ? '—' : '${thousands(t.loggedReps)} reps'),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: _Stat(label: 'DOELWIT', value: t.targetLabel)),
            ],
          ),
          const SizedBox(height: 10),
          Material(
            color: t.isInFocus ? KColor.teal.withValues(alpha: 0.12) : KColor.surfaceContainer,
            borderRadius: BorderRadius.circular(KRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(KRadius.md),
              onTap: () => _toggle(context, store),
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.center_focus_strong, size: 20, color: t.isInFocus ? KColor.teal : KColor.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Focus in Sessie',
                          style: KText.body.copyWith(fontWeight: FontWeight.w700, color: t.isInFocus ? KColor.tealLight : KColor.textSecondary),
                        ),
                      ),
                      Switch(value: t.isInFocus, onChanged: (_) => _toggle(context, store)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, KineticStore store) async {
    HapticFeedback.selectionClick();
    final ok = await store.toggleFocus(technique);
    if (!context.mounted) return;
    if (!ok) showToast(context, 'Focus aanpassen mislukt', error: true);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: KText.eyebrow.copyWith(fontSize: 10)),
        const SizedBox(height: 4),
        Text(value, style: KText.body.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
