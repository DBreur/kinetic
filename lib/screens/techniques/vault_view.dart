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

  /// Normale weergave: maximaal één groep tegelijk open (accordeon).
  /// Tot je zelf iets aantikt is dat de eerste groep met focus-technieken.
  TechniqueGroup? _open;
  bool _openChosen = false;
  TechniqueGroup? _defaultOpen;

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
    return (_openChosen ? _open : _defaultOpen) == g;
  }

  void _toggle(TechniqueGroup g, bool hasFocus) {
    setState(() {
      if (_filtering) {
        if (!_collapsedWhileFiltering.remove(g)) _collapsedWhileFiltering.add(g);
      } else {
        // Een andere groep openen klapt de vorige dicht.
        _open = _isExpanded(g, hasFocus) ? null : g;
        _openChosen = true;
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
    if (t != null) {
      setState(() {
        _open = group;
        _openChosen = true;
      });
    }
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
    _defaultOpen = null;
    for (final g in TechniqueGroup.values) {
      if ((byGroup[g] ?? const []).any((e) => e.inFocus)) {
        _defaultOpen = g;
        break;
      }
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
                  child: GroupHeader(
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
    final footerText = goal.isNotEmpty
        ? 'Doel: $goal'
        : e.difficulty != null
        ? difficultyLabel(e.difficulty!)
        : 'Eigen techniek';
    final eyebrow = [e.group.label, if (e.subtitle.isNotEmpty) e.subtitle].join(' • ');
    return KCard(
      borderColor: e.inFocus ? k.accent : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
                    Text(
                      eyebrow.toUpperCase(),
                      style: context.t.labelSm.copyWith(color: groupColor(context, e.group), letterSpacing: 0.6),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(e.name, style: context.t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (e.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        e.description,
                        style: context.t.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (!e.isOwn) ...[
                const SizedBox(width: 8),
                const KPill('Bibliotheek', icon: Icons.local_library_outlined, dense: true),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Mastery + volume in een donker vlak, zoals in de mock.
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: k.isDark ? KineticColors.sunken : k.well,
              borderRadius: BorderRadius.circular(KRadius.sm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mastery Index', style: context.t.caption.copyWith(color: k.text, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            mastery == null ? '—' : '$mastery%',
                            style: context.t.caption.copyWith(color: k.successInk, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: KProgressBar(value: (mastery ?? 0) / 100, color: k.successInk, height: 5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Volume', style: context.t.caption.copyWith(color: k.text, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      repsLabel(e.loggedReps).replaceAll(' gelogd', ''),
                      style: context.t.caption.copyWith(color: k.text, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  footerText,
                  style: context.t.caption.copyWith(color: k.text, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              _RepButton(onTap: () => addRep(context, e)),
              const SizedBox(width: 6),
              _FocusButton(entry: e),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Focus in Sessie" als knop: omlijnd met +, of teal "In Focus" met vinkje.
class _FocusButton extends StatelessWidget {
  const _FocusButton({required this.entry});
  final VaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final on = entry.inFocus;
    final fg = on ? k.onPrimary : k.text;
    return Semantics(
      toggled: on,
      button: true,
      label: 'Focus in Sessie',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: on ? k.primary : k.well,
          borderRadius: BorderRadius.circular(KRadius.sm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => toggleFocus(context, entry),
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(on ? Icons.check : Icons.add_circle_outline, size: 16, color: fg),
                    const SizedBox(width: 5),
                    Text(on ? 'In Focus' : 'Focus', style: context.t.bodyStrong.copyWith(fontSize: 13, color: fg)),
                  ],
                ),
              ),
            ),
          ),
        ),
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
