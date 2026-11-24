// systems_view.dart: sub-tab "Systemen": eigen flow-grafen van posities en
// technieken (bv. "Clinch naar worp"). Lijst met preview per systeem,
// nieuw systeem aanmaken en doorklikken naar de editor.

import 'package:material_ui/material_ui.dart';

import '../../models/technique_system.dart';
import '../../theme/kinetic_theme.dart';
import '../../widgets/kinetic_widgets.dart';
import 'system_editor_screen.dart';
import 'system_graph.dart';
import 'technique_ui.dart';

class SystemsView extends StatelessWidget {
  const SystemsView({super.key});

  static Future<void> open(BuildContext context, TechniqueSystem s) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SystemEditorScreen(systemId: s.id)));

  static Future<void> create(BuildContext context) async {
    final store = KineticScope.read(context);
    final result = await showSystemForm(context);
    if (result == null || !context.mounted) return;
    final saved = await store.saveSystem(TechniqueSystem(id: '', name: result.$1, notes: result.$2));
    if (!context.mounted) return;
    if (saved == null) {
      showToast(context, 'Systeem aanmaken mislukt. Controleer je verbinding.', error: true);
      return;
    }
    await open(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final systems = [...store.systems]..sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
    });
    final pad = pagePadding(context, top: 16);
    return RefreshIndicator(
      color: context.k.primary,
      backgroundColor: context.k.surface,
      onRefresh: store.refreshAll,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        itemCount: systems.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SubTabHeader(
                title: 'Systemen',
                caption: systems.isEmpty
                    ? 'Flows van posities en technieken'
                    : '${systems.length} ${systems.length == 1 ? 'systeem' : 'systemen'} • flows van positie tot finish',
                action: HeaderButton(label: 'Systeem', onPressed: () => create(context)),
              ),
            );
          }
          if (i == systems.length + 1) {
            return systems.isEmpty
                ? EmptyCard(
                    icon: Icons.account_tree_outlined,
                    title: 'Nog geen systemen',
                    message:
                        'Een systeem is een flow: vanuit een positie via technieken naar een finish, '
                        'bijvoorbeeld "Clinch naar worp". Zo zie je je game-plan in één oogopslag.',
                    action: BigButton(
                      label: 'Eerste systeem maken',
                      icon: Icons.add,
                      height: 48,
                      onPressed: () => create(context),
                    ),
                  )
                : const _LegendHint();
          }
          final s = systems[i - 1];
          return Padding(
            key: ValueKey(s.id),
            padding: const EdgeInsets.only(bottom: 12),
            child: _SystemCard(system: s, onTap: () => open(context, s)),
          );
        },
      ),
    );
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({required this.system, required this.onTap});
  final TechniqueSystem system;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final s = system;
    int count(SystemNodeKind kind) => s.nodes.where((n) => n.kind == kind).length;
    return KCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: Icons.account_tree_outlined, size: 40, color: k.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: context.t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      '${s.nodes.length} ${s.nodes.length == 1 ? 'stap' : 'stappen'} • '
                      '${s.edges.length} ${s.edges.length == 1 ? 'verbinding' : 'verbindingen'}',
                      style: context.t.caption,
                    ),
                  ],
                ),
              ),
              if (s.favorite) ...[Icon(Icons.star, size: 20, color: k.warning), const SizedBox(width: 4)],
              Icon(Icons.chevron_right, color: k.textSecondary),
            ],
          ),
          if (s.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              s.notes.trim(),
              style: context.t.body.copyWith(color: k.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          KWell(
            padding: const EdgeInsets.all(8),
            child: s.nodes.isEmpty
                ? SizedBox(
                    height: 64,
                    child: Center(child: Text('Nog geen stappen. Tik om te beginnen.', style: context.t.caption)),
                  )
                : SystemPreview(system: s),
          ),
          if (s.nodes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final kind in SystemNodeKind.values)
                  if (count(kind) > 0) _KindCount(kind: kind, count: count(kind)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _KindCount extends StatelessWidget {
  const _KindCount({required this.kind, required this.count});
  final SystemNodeKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = systemKindColor(k, kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: systemKindFill(k, kind),
        borderRadius: BorderRadius.circular(KRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(systemKindIcon(kind), size: 13, color: c),
          const SizedBox(width: 4),
          Text(systemKindCount(kind, count), style: context.t.caption.copyWith(color: k.text)),
        ],
      ),
    );
  }
}

class _LegendHint extends StatelessWidget {
  const _LegendHint();

  @override
  Widget build(BuildContext context) {
    return KWell(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SystemLegend(),
          const SizedBox(height: 8),
          Text('Tik op een systeem om stappen en pijlen te bewerken.', style: context.t.caption),
        ],
      ),
    );
  }
}

/// Naam + notities voor een (nieuw) systeem. Geeft (naam, notities) terug.
Future<(String, String)?> showSystemForm(BuildContext context, {TechniqueSystem? initial}) =>
    showKineticSheet<(String, String)>(context, builder: (_) => _SystemFormSheet(initial: initial));

class _SystemFormSheet extends StatefulWidget {
  const _SystemFormSheet({this.initial});
  final TechniqueSystem? initial;

  @override
  State<_SystemFormSheet> createState() => _SystemFormSheetState();
}

class _SystemFormSheetState extends State<_SystemFormSheet> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _done() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    Navigator.of(context).pop((n, _notes.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(editing ? 'Systeem bewerken' : 'Nieuw systeem', style: context.t.headline),
        const SizedBox(height: 4),
        Text('Een flow van posities en technieken, van start tot finish.', style: context.t.caption),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          autofocus: !editing,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Naam', hintText: 'Bijv. Clinch naar worp'),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Notities (optioneel)', hintText: 'Wanneer gebruik je deze flow?'),
        ),
        const SizedBox(height: 20),
        BigButton(
          label: editing ? 'Opslaan' : 'Systeem aanmaken',
          icon: editing ? Icons.check : Icons.add,
          onPressed: _name.text.trim().isEmpty ? null : _done,
        ),
      ],
    );
  }
}
