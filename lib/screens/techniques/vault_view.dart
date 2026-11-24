// vault_view.dart: sub-tab "Technieken" = de Technique Vault
// (kinetic-design/kinetic_techniques). Toont ALLE technieken (eigen +
// bibliotheek) in inklapbare accordeons per groep, met zoeken, filterchips,
// +1 Rep en de "Focus in Sessie"-schakelaar die de live mat-tellers voedt.
// De lijst wordt lui opgebouwd (140+ kaarten).

import 'package:material_ui/material_ui.dart';

import '../../models/library.dart';
import '../../models/technique.dart';
import '../../theme/kinetic_theme.dart';
import '../../widgets/kinetic_widgets.dart';
import 'technique_ui.dart';

class VaultView extends StatefulWidget {
  const VaultView({super.key});

  @override
  State<VaultView> createState() => _VaultViewState();
}

/// Filter: 'all', 'focus', 'mine' of de naam van een [TechniqueGroup].
const _all = 'all';
const _focus = 'focus';
const _mine = 'mine';

sealed class _Item {
  const _Item();
}

class _HeaderItem extends _Item {
  const _HeaderItem(this.group, this.count, this.focusCount, this.expanded);
  final TechniqueGroup group;
  final int count;
  final int focusCount;
  final bool expanded;
}

class _CardItem extends _Item {
  const _CardItem(this.entry, {required this.last});
  final VaultEntry entry;
  final bool last;
}

class _VaultViewState extends State<VaultView> {
  final _search = TextEditingController();
  String _query = '';
  String _filter = _all;

  /// Handmatig open/dicht geklapte groepen (normale weergave).
  final Map<TechniqueGroup, bool> _expanded = {};

  /// Tijdens zoeken/filteren staat alles open, behalve wat je hier dichtklapt.
  final Set<TechniqueGroup> _collapsedWhileFiltering = {};

  // Vault-cache: de store vervangt de lijsten bij elke wijziging.
  List<Technique>? _lastOwn;
  List<LibraryTechnique>? _lastLib;
  List<VaultEntry> _vault = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _filtering => _query.trim().isNotEmpty || _filter != _all;

  TechniqueGroup? get _groupFilter {
    for (final g in TechniqueGroup.values) {
      if (g.name == _filter) return g;
    }
    return null;
  }

  bool _passes(VaultEntry e) {
    final g = _groupFilter;
    final okFilter = switch (_filter) {
      _all => true,
      _focus => e.inFocus,
      _mine => e.isOwn,
      _ => e.group == g,
    };
    return okFilter && e.matches(_query);
  }

  bool _isExpanded(TechniqueGroup g, bool hasFocus) {
    if (_filtering) return !_collapsedWhileFiltering.contains(g);
    return _expanded[g] ?? hasFocus;
  }

  void _toggle(TechniqueGroup g, bool hasFocus) {
    setState(() {
      if (_filtering) {
        if (!_collapsedWhileFiltering.remove(g)) _collapsedWhileFiltering.add(g);
      } else {
        _expanded[g] = !_isExpanded(g, hasFocus);
      }
    });
  }

  void _setFilter(String f) => setState(() {
    _filter = f;
    _collapsedWhileFiltering.clear();
  });

  void _setQuery(String q) => setState(() {
    _query = q;
    _collapsedWhileFiltering.clear();
  });

  Future<void> _create() async {
    final store = KineticScope.read(context);
    final result = await showKineticSheet<(String, TechniqueGroup)>(
      context,
      builder: (_) => _NewTechniqueSheet(initialGroup: _groupFilter ?? TechniqueGroup.throws),
    );
    if (result == null || !mounted) return;
    final (name, group) = result;
    final t = await store.createTechnique(name, group);
    if (!mounted) return;
    if (t != null) setState(() => _expanded[group] = true);
    showToast(context, t == null ? 'Toevoegen mislukt. Controleer je verbinding.' : '$name toegevoegd aan ${group.label}', error: t == null);
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    if (!identical(store.techniques, _lastOwn) || !identical(store.library, _lastLib)) {
      _lastOwn = store.techniques;
      _lastLib = store.library;
      _vault = store.vault;
    }
    final vault = _vault;
    final focusCount = vault.where((e) => e.inFocus).length;
    final ownCount = vault.where((e) => e.isOwn).length;

    final shown = vault.where(_passes).toList();
    final byGroup = <TechniqueGroup, List<VaultEntry>>{};
    for (final e in shown) {
      byGroup.putIfAbsent(e.group, () => []).add(e);
    }
    final items = <_Item>[];
    for (final g in TechniqueGroup.values) {
      final list = byGroup[g];
      if (list == null || list.isEmpty) continue;
      final focus = list.where((e) => e.inFocus).length;
      final open = _isExpanded(g, focus > 0);
      items.add(_HeaderItem(g, list.length, focus, open));
      if (open) {
        for (var i = 0; i < list.length; i++) {
          items.add(_CardItem(list[i], last: i == list.length - 1));
        }
      }
    }

    final pad = pagePadding(context);
    return RefreshIndicator(
      color: context.k.primary,
      backgroundColor: context.k.surface,
      onRefresh: store.refreshAll,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SubTabHeader(
                    title: 'Technique Vault',
                    caption: '${vault.length} technieken • $focusCount in focus',
                    action: HeaderButton(label: 'Techniek', onPressed: _create),
                  ),
                  const SizedBox(height: 16),
                  KSearchField(
                    controller: _search,
                    hint: 'Zoek technieken, counters, submissions...',
                    onChanged: _setQuery,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ChipRow(
              children: [
                KChip(label: 'Alle (${vault.length})', selected: _filter == _all, onTap: () => _setFilter(_all)),
                KChip(
                  label: 'In focus ($focusCount)',
                  icon: Icons.center_focus_strong,
                  selected: _filter == _focus,
                  onTap: () => _setFilter(_focus),
                ),
                KChip(label: 'Mijn technieken ($ownCount)', selected: _filter == _mine, onTap: () => _setFilter(_mine)),
                for (final g in TechniqueGroup.values)
                  KChip(label: g.label, selected: _filter == g.name, onTap: () => _setFilter(g.name)),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          if (items.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: EmptyCard(
                  icon: Icons.search_off,
                  title: 'Geen technieken gevonden',
                  message: _filter == _focus && _query.isEmpty
                      ? 'Zet "Focus in Sessie" aan op een techniek om hem op de live mat te tellen.'
                      : 'Probeer een andere zoekterm of filter.',
                  action: _filtering
                      ? BigButton(
                          label: 'Filters wissen',
                          style: KButtonStyle.secondary,
                          height: 48,
                          onPressed: () {
                            _search.clear();
                            setState(() {
                              _query = '';
                              _filter = _all;
                            });
                          },
                        )
                      : null,
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, pad.bottom),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, i) => switch (items[i]) {
                _HeaderItem(:final group, :final count, :final focusCount, :final expanded) => Padding(
                  key: ValueKey('h-${group.name}'),
                  padding: EdgeInsets.only(bottom: expanded ? 10 : 12),
                  child: _GroupHeader(
                    group: group,
                    count: count,
                    focusCount: focusCount,
                    expanded: expanded,
                    onTap: () => _toggle(group, focusCount > 0),
                  ),
                ),
                _CardItem(:final entry, :final last) => Padding(
                  key: ValueKey(entry.key),
                  padding: EdgeInsets.only(bottom: last ? 24 : 10),
                  child: VaultCard(entry: entry),
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Accordeonkop per groep: icoon, naam, omschrijving, aantal en chevron.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.count,
    required this.focusCount,
    required this.expanded,
    required this.onTap,
  });
  final TechniqueGroup group;
  final int count;
  final int focusCount;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      button: true,
      expanded: expanded,
      child: KCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        onTap: onTap,
        child: Row(
          children: [
            IconTile(icon: groupIcon(group), size: 40, color: groupColor(context, group)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.label, style: context.t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    focusCount > 0 ? '${group.description} • $focusCount in focus' : group.description,
                    style: context.t.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _CountBadge(count: count, highlight: focusCount > 0),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(Icons.expand_more, color: k.textSecondary, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.highlight});
  final int count;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      constraints: const BoxConstraints(minWidth: 32),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlight ? k.primaryTint : k.well,
        borderRadius: BorderRadius.circular(KRadius.full),
      ),
      child: Text(
        '$count',
        style: context.t.caption.copyWith(
          color: highlight ? k.accent : k.textSecondary,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Techniekkaart volgens de mockup: tag + reps, naam + ondertitel, uitleg in
/// een well, voettekst met niveau en "+1 Rep", en de focus-schakelaar.
class VaultCard extends StatelessWidget {
  const VaultCard({super.key, required this.entry});
  final VaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final e = entry;
    final mastery = e.masteryPercent;
    final goal = e.own?.learningGoal.trim() ?? '';
    final (footerIcon, footerText) = goal.isNotEmpty
        ? (Icons.flag_outlined, 'Doel: $goal')
        : e.difficulty != null
        ? (Icons.signal_cellular_alt, difficultyLabel(e.difficulty!))
        : (Icons.person_outline, 'Eigen techniek');
    return KCard(
      borderColor: e.inFocus ? k.primary : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      onTap: () => showTechniqueSheet(context, e),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        GroupTag(e.group),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.repeat, size: 14, color: k.accent),
                            const SizedBox(width: 4),
                            Text(repsLabel(e.loggedReps), style: context.t.caption),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(e.name, style: context.t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (e.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(e.subtitle, style: context.t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (!e.isOwn) ...[
                const SizedBox(width: 8),
                const KPill('Bibliotheek', icon: Icons.local_library_outlined, dense: true),
              ] else if (mastery != null) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$mastery%', style: context.t.metricSm.copyWith(color: k.accent)),
                    const SizedBox(height: 2),
                    Text('MASTERY', style: context.t.labelSm),
                  ],
                ),
              ],
            ],
          ),
          if (e.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            KWell(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.insights, size: 18, color: k.accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.description,
                      style: context.t.body.copyWith(color: k.textSecondary),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(footerIcon, size: 16, color: k.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(footerText, style: context.t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              _RepButton(onTap: () => addRep(context, e)),
            ],
          ),
          const SizedBox(height: 6),
          Divider(color: k.border, height: 1),
          FocusToggleRow(entry: e),
        ],
      ),
    );
  }
}

/// "+1 Rep": compact, maar met een raakvlak van 48px.
class _RepButton extends StatelessWidget {
  const _RepButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    // Het zichtbare vlak is 40px; de rand eromheen vangt ook tikken op,
    // zodat het raakvlak 48px is.
    return Semantics(
      button: true,
      label: '+1 Rep',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _visual(context, k),
        ),
      ),
    );
  }

  Widget _visual(BuildContext context, KineticColors k) {
    return Material(
        color: k.well,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.sm),
          side: BorderSide(color: k.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text('+1 Rep', style: context.t.bodyStrong.copyWith(fontSize: 13)),
              ),
            ),
          ),
        ),
    );
  }
}

/// Nieuwe eigen techniek: naam + groep.
class _NewTechniqueSheet extends StatefulWidget {
  const _NewTechniqueSheet({required this.initialGroup});
  final TechniqueGroup initialGroup;

  @override
  State<_NewTechniqueSheet> createState() => _NewTechniqueSheetState();
}

class _NewTechniqueSheetState extends State<_NewTechniqueSheet> {
  final _name = TextEditingController();
  late TechniqueGroup _group = widget.initialGroup;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    Navigator.of(context).pop((n, _group));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Nieuwe techniek', style: context.t.headline),
        const SizedBox(height: 4),
        Text('Komt in je vault en kan meteen in focus voor de live mat.', style: context.t.caption),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Naam', hintText: 'Bijv. Harai Goshi'),
          onSubmitted: (_) => _done(),
        ),
        const SizedBox(height: 4),
        const Eyebrow('Groep'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in TechniqueGroup.values)
              KChip(
                label: g.label,
                icon: groupIcon(g),
                selected: _group == g,
                onTap: () => setState(() => _group = g),
              ),
          ],
        ),
        const SizedBox(height: 20),
        BigButton(label: 'Techniek toevoegen', icon: Icons.add, onPressed: _name.text.trim().isEmpty ? null : _done),
      ],
    );
  }
}
