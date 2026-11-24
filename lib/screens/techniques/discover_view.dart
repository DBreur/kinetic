// discover_view.dart: sub-tab "Ontdekken": de gedeelde bibliotheek
// (`technique_library`) doorzoeken op naam, discipline en niveau, en
// technieken overnemen in je vault of meteen in focus zetten.

import 'package:material_ui/material_ui.dart';

import '../../models/library.dart';
import '../../theme/kinetic_theme.dart';
import '../../widgets/kinetic_widgets.dart';
import 'technique_ui.dart';

/// Disciplinefilters: label → codes uit de database.
const _disciplineFilters = <(String, List<String>)>[
  ('Alle', []),
  ('Sambo', ['sambo']),
  ('BJJ', ['bjj']),
  ('Judo', ['judo']),
  ('MMA', ['mma']),
  ('Worstelen', ['wrestling']),
  ('Striking', ['boxing', 'kickboxing', 'muay_thai']),
];

class DiscoverView extends StatefulWidget {
  const DiscoverView({super.key});

  @override
  State<DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<DiscoverView> {
  final _search = TextEditingController();
  String _query = '';
  int _discipline = 0;

  /// 0 = alle niveaus, anders 1..3.
  int _difficulty = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _passes(LibraryTechnique t) {
    final codes = _disciplineFilters[_discipline].$2;
    if (codes.isNotEmpty && !t.disciplines.any(codes.contains)) return false;
    if (_difficulty != 0 && t.difficulty.clamp(1, 3) != _difficulty) return false;
    return t.matches(_query);
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final library = store.library;
    // Bibliotheek-id → vault-regel (eigen kopie, als die er is).
    final byLib = <String, VaultEntry>{
      for (final e in store.vault)
        if (e.library != null) e.library!.id: e,
    };
    final inVault = byLib.values.where((e) => e.isOwn).length;
    final results = library.where(_passes).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final pad = pagePadding(context);
    final filtering = _query.trim().isNotEmpty || _discipline != 0 || _difficulty != 0;

    return RefreshIndicator(
      color: k.primary,
      backgroundColor: k.surface,
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
                    title: 'Ontdekken',
                    caption: '${library.length} technieken in de bibliotheek • $inVault in je vault',
                  ),
                  const SizedBox(height: 16),
                  KSearchField(
                    controller: _search,
                    hint: 'Zoek op naam, type, tag of discipline...',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ChipRow(
              children: [
                for (var i = 0; i < _disciplineFilters.length; i++)
                  KChip(
                    label: _disciplineFilters[i].$1,
                    selected: _discipline == i,
                    onTap: () => setState(() => _discipline = i),
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KSegmented<int>(
                    options: const [(0, 'Elk niveau'), (1, 'Beginner'), (2, 'Gevorderd'), (3, 'Expert')],
                    value: _difficulty,
                    onChanged: (v) => setState(() => _difficulty = v),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${results.length} ${results.length == 1 ? 'resultaat' : 'resultaten'}',
                          style: context.t.label,
                        ),
                      ),
                      if (filtering)
                        TextButton(
                          onPressed: () {
                            _search.clear();
                            setState(() {
                              _query = '';
                              _discipline = 0;
                              _difficulty = 0;
                            });
                          },
                          child: const Text('Filters wissen'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          if (library.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: EmptyCard(
                  icon: Icons.cloud_off,
                  title: 'Bibliotheek niet geladen',
                  message: 'Controleer je verbinding en trek omlaag om opnieuw te laden.',
                ),
              ),
            )
          else if (results.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: EmptyCard(
                  icon: Icons.search_off,
                  title: 'Geen technieken gevonden',
                  message: 'Probeer een andere zoekterm, discipline of niveau.',
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, pad.bottom),
            sliver: SliverList.builder(
              itemCount: results.length,
              itemBuilder: (context, i) {
                final lib = results[i];
                final entry = byLib[lib.id] ?? VaultEntry(library: lib);
                return Padding(
                  key: ValueKey(lib.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LibraryCard(entry: entry),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({required this.entry});
  final VaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final e = entry;
    final lib = e.library!;
    final owned = e.isOwn;
    final subtitle = [
      if (lib.subcategory.isNotEmpty) lib.subcategory,
      lib.disciplines.take(3).map(disciplineLabel).join(', '),
    ].where((s) => s.isNotEmpty).join(' • ');
    return KCard(
      onTap: () => showTechniqueSheet(context, e),
      borderColor: e.inFocus ? k.primary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [GroupTag(lib.group), DifficultyPill(lib.difficulty)],
                ),
              ),
              if (owned) const KPill('In je vault', tone: KTone.success, icon: Icons.check, dense: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(lib.name, style: context.t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: context.t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          if (lib.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              lib.description,
              style: context.t.body.copyWith(color: k.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: owned
                    ? const BigButton(
                        label: 'In je vault',
                        icon: Icons.check,
                        style: KButtonStyle.secondary,
                        height: 48,
                        onPressed: null,
                      )
                    : BigButton(
                        label: 'Toevoegen',
                        icon: Icons.add,
                        style: KButtonStyle.ghost,
                        height: 48,
                        onPressed: () => addToVault(context, e),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: e.inFocus
                    ? BigButton(
                        label: 'In focus',
                        icon: Icons.center_focus_strong,
                        color: k.primary,
                        foreground: k.accent,
                        outlined: true,
                        height: 48,
                        onPressed: () => toggleFocus(context, e),
                      )
                    : BigButton(
                        label: 'Focus',
                        icon: Icons.center_focus_weak,
                        style: KButtonStyle.secondary,
                        height: 48,
                        onPressed: () => toggleFocus(context, e),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

