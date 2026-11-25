// system_editor_screen.dart: één systeem bekijken en bewerken: de gelaagde
// flow-graaf met legenda, stappen toevoegen/hernoemen/verwijderen met soort
// en optionele gekoppelde techniek, pijlen leggen en wissen, en het systeem
// verwijderen (met bevestiging). Elke wijziging gaat direct naar de store.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/library.dart';
import '../../models/technique.dart';
import '../../models/technique_system.dart';
import '../../theme/kinetic_theme.dart';
import '../../widgets/kinetic_widgets.dart';
import '../../widgets/technique_detail_widgets.dart';
import 'system_graph.dart';
import 'systems_view.dart';
import 'technique_ui.dart';

class SystemEditorScreen extends StatefulWidget {
  const SystemEditorScreen({super.key, required this.systemId});
  final String systemId;

  @override
  State<SystemEditorScreen> createState() => _SystemEditorScreenState();
}

enum _NodeAction { edit, addAfter, connect, openTechnique, unlink, delete }

class _SystemEditorScreenState extends State<SystemEditorScreen> {
  TechniqueSystem? _s;
  String? _connectFrom;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final x in KineticScope.read(context).systems) {
      if (x.id == widget.systemId) _s = x;
    }
  }

  TechniqueSystem get s => _s!;

  String _newId() => 'n${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  SystemNode? _node(String id) {
    for (final n in s.nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Future<bool> _save(TechniqueSystem next, {String? undoMessage}) async {
    final store = KineticScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final previous = s;
    setState(() {
      _s = next;
      _saving = true;
    });
    final saved = await store.saveSystem(next);
    if (!mounted) return saved != null;
    setState(() {
      _saving = false;
      _s = saved ?? previous;
    });
    if (saved == null) {
      showToastOn(messenger, 'Opslaan mislukt. Wijziging teruggezet.', error: true);
      return false;
    }
    if (undoMessage != null) {
      showToastOn(
        messenger,
        undoMessage,
        actionLabel: 'Herstel',
        onAction: () {
          if (mounted) _save(previous);
        },
      );
    }
    return true;
  }

  // ------------------------------------------------------------ acties

  Future<void> _editSystem() async {
    final result = await showSystemForm(context, initial: s);
    if (result == null || !mounted) return;
    await _save(s.copyWith(name: result.$1, notes: result.$2));
  }

  Future<void> _addNode({String? after}) async {
    final node = await showKineticSheet<SystemNode>(
      context,
      builder: (_) => _NodeSheet(newId: _newId(), afterLabel: after == null ? null : _node(after)?.label),
    );
    if (node == null || !mounted) return;
    var next = s.copyWith(nodes: [...s.nodes, node]);
    if (after != null) next = next.withEdge(after, node.id);
    await _save(next);
  }

  Future<void> _editNode(SystemNode node) async {
    final edited = await showKineticSheet<SystemNode>(
      context,
      builder: (_) => _NodeSheet(initial: node, newId: node.id),
    );
    if (edited == null || !mounted) return;
    await _save(s.copyWith(nodes: [for (final n in s.nodes) n.id == node.id ? edited : n]));
  }

  Future<void> _deleteNode(SystemNode node) async {
    await _save(s.withoutNode(node.id), undoMessage: '"${node.label}" verwijderd');
  }

  Future<void> _addEdge() async {
    final edge = await showKineticSheet<SystemEdge>(context, builder: (_) => _EdgeSheet(system: s));
    if (edge == null || !mounted) return;
    await _save(s.withEdge(edge.from, edge.to, label: edge.label));
  }

  /// Transitie aantikken: bekijken, tekst aanpassen of de pijl verwijderen,
  /// plus de techniek waar hij naartoe leidt (video's, notities).
  Future<void> _onEdgeTap(SystemEdge e) async {
    final result = await showKineticSheet<(String, bool)>(
      context,
      builder: (_) => _TransitionSheet(edge: e, from: _node(e.from), to: _node(e.to)),
    );
    if (result == null || !mounted) return;
    final (label, remove) = result;
    if (remove) {
      await _removeEdge(e);
    } else if (label != e.label) {
      await _save(s.withEdgeLabel(e, label));
    }
  }

  /// Technieken aanvinken: elke aangevinkte techniek staat als stap in het
  /// systeem; uitvinken haalt de stap (en zijn pijlen) weer weg.
  Future<void> _pickTechniques() async {
    await showKineticSheet<void>(
      context,
      scrollable: false,
      builder: (_) => _TechniqueChecklist(
        isIn: (e) => e.own != null && s.nodeForTechnique(e.own!.id) != null,
        onToggle: _toggleTechnique,
      ),
    );
  }

  Future<bool> _toggleTechnique(VaultEntry e) async {
    final store = KineticScope.read(context);
    final existing = e.own == null ? null : s.nodeForTechnique(e.own!.id);
    if (existing != null) {
      return _save(s.withoutNode(existing.id));
    }
    final own = await store.ensureOwnTechnique(e);
    if (own == null || !mounted) return false;
    final node = SystemNode(
      id: _newId(),
      label: own.name,
      kind: own.group == TechniqueGroup.submissions ? SystemNodeKind.finish : SystemNodeKind.technique,
      techniqueId: own.id,
    );
    return _save(s.copyWith(nodes: [...s.nodes, node]));
  }

  Future<void> _removeEdge(SystemEdge e) async {
    final from = _node(e.from)?.label ?? '?';
    final to = _node(e.to)?.label ?? '?';
    await _save(s.copyWith(edges: s.edges.where((x) => x != e).toList()), undoMessage: 'Pijl $from → $to verwijderd');
  }

  void _startConnect(SystemNode from) {
    setState(() => _connectFrom = from.id);
    showToast(context, 'Tik op de stap waar de pijl naartoe gaat');
  }

  Future<void> _onNodeTap(SystemNode node) async {
    final from = _connectFrom;
    if (from != null) {
      HapticFeedback.selectionClick();
      setState(() => _connectFrom = null);
      if (from == node.id) return;
      final before = s.edges.length;
      final next = s.withEdge(from, node.id);
      if (next.edges.length == before) {
        showToast(context, 'Deze pijl bestaat al');
        return;
      }
      await _save(next);
      return;
    }
    await _nodeActions(node);
  }

  Future<void> _nodeActions(SystemNode node) async {
    final store = KineticScope.read(context);
    final hasOutgoing = s.edges.any((e) => e.from == node.id);
    final action = await showKineticSheet<_NodeAction>(
      context,
      builder: (ctx) => _NodeActionsSheet(
        node: node,
        canConnect: s.nodes.length > 1,
        hasOutgoing: hasOutgoing,
        hasTechnique: node.techniqueId != null,
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _NodeAction.edit:
        await _editNode(node);
      case _NodeAction.addAfter:
        await _addNode(after: node.id);
      case _NodeAction.connect:
        _startConnect(node);
      case _NodeAction.openTechnique:
        final e = locateEntry(store.vault, ownId: node.techniqueId);
        if (e == null) {
          showToast(context, 'Gekoppelde techniek niet gevonden', error: true);
        } else {
          await showTechniqueSheet(context, e);
        }
      case _NodeAction.unlink:
        await _save(
          s.copyWith(edges: s.edges.where((e) => e.from != node.id).toList()),
          undoMessage: 'Pijlen vanaf "${node.label}" gewist',
        );
      case _NodeAction.delete:
        await _deleteNode(node);
    }
  }

  Future<void> _deleteSystem() async {
    final store = KineticScope.read(context);
    final ok = await confirmDelete(
      context,
      title: 'Systeem verwijderen?',
      message: '"${s.name}" en alle ${s.nodes.length} stappen worden definitief verwijderd.',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = s.name;
    final done = await store.deleteSystem(s.id);
    if (!done) {
      showToastOn(messenger, 'Verwijderen mislukt. Controleer je verbinding.', error: true);
      return;
    }
    navigator.pop();
    showToastOn(messenger, '"$name" verwijderd');
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    if (_s == null) {
      return KineticPage(
        subtitle: 'Systeem',
        body: Padding(
          padding: pagePadding(context, top: 16),
          child: const EmptyCard(
            icon: Icons.account_tree_outlined,
            title: 'Systeem niet gevonden',
            message: 'Dit systeem bestaat niet meer.',
          ),
        ),
      );
    }
    final store = KineticScope.of(context);
    final connecting = _connectFrom == null ? null : _node(_connectFrom!);
    return KineticPage(
      subtitle: 'Systeem',
      body: ListView(
        padding: pagePadding(context, top: 16),
        children: [
          // ---------------------------------------------- kop
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Systeem', icon: Icons.account_tree_outlined),
                    const SizedBox(height: 6),
                    Text(s.name, style: context.t.headline),
                  ],
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              IconButton(
                tooltip: s.favorite ? 'Geen favoriet meer' : 'Favoriet',
                onPressed: () => _save(s.copyWith(favorite: !s.favorite)),
                icon: Icon(
                  s.favorite ? Icons.star : Icons.star_border,
                  color: s.favorite ? k.warning : k.textSecondary,
                ),
              ),
              IconButton(
                tooltip: 'Naam en notities bewerken',
                onPressed: _editSystem,
                icon: Icon(Icons.edit_outlined, color: k.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.notes.isEmpty ? 'Nog geen notities.' : s.notes,
            style: context.t.body.copyWith(
              color: s.notes.isEmpty ? k.textMuted : k.textSecondary,
              fontStyle: s.notes.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              KPill(
                '${s.nodes.length} ${s.nodes.length == 1 ? 'stap' : 'stappen'}',
                icon: Icons.circle_outlined,
                dense: true,
              ),
              KPill(
                '${s.edges.length} ${s.edges.length == 1 ? 'verbinding' : 'verbindingen'}',
                icon: Icons.trending_flat,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ---------------------------------------------- graaf
          KCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Flow', style: context.t.title),
                      const SizedBox(height: 6),
                      const SystemLegend(),
                    ],
                  ),
                ),
                if (connecting != null) ...[
                  _ConnectBanner(from: connecting.label, onCancel: () => setState(() => _connectFrom = null)),
                  const SizedBox(height: 8),
                ],
                KWell(
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    height: s.nodes.isEmpty ? 180 : 340,
                    child: s.nodes.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.account_tree_outlined, size: 32, color: k.textMuted),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Begin met een positie, bijvoorbeeld "Clinch" of "Closed guard".',
                                    style: context.t.caption,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SystemGraph(
                            system: s,
                            highlightNodeId: _connectFrom,
                            onNodeTap: _onNodeTap,
                            onEdgeTap: _onEdgeTap,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Tik op een stap of transitie voor details. Knijp om te zoomen, sleep om te schuiven.',
                    style: context.t.caption,
                  ),
                ),
                if (s.nodes.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) =>
                              _FullScreenGraph(systemId: s.id, onNodeTap: _onNodeTap, onEdgeTap: _onEdgeTap),
                        ),
                      ),
                      icon: const Icon(Icons.open_in_full, size: 18),
                      label: const Text('Volledig scherm'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          BigButton(label: 'Technieken kiezen', icon: Icons.checklist, height: 52, onPressed: _pickTechniques),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: BigButton(
                  label: 'Stap',
                  icon: Icons.add,
                  style: KButtonStyle.secondary,
                  height: 52,
                  onPressed: () => _addNode(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BigButton(
                  label: 'Verbinding',
                  icon: Icons.add_link,
                  style: KButtonStyle.secondary,
                  height: 52,
                  onPressed: s.nodes.length < 2 ? null : _addEdge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ---------------------------------------------- stappen
          SectionTitle('Stappen (${s.nodes.length})'),
          if (s.nodes.isEmpty)
            Text('Nog geen stappen.', style: context.t.caption)
          else
            KCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < s.nodes.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: k.border, indent: 60),
                    _NodeRow(
                      node: s.nodes[i],
                      next: [
                        for (final e in s.edges)
                          if (e.from == s.nodes[i].id) _node(e.to)?.label ?? '?',
                      ],
                      techniqueName: _techniqueName(store.techniques, s.nodes[i].techniqueId),
                      onTap: () => _nodeActions(s.nodes[i]),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 20),

          // ---------------------------------------------- verbindingen
          SectionTitle('Verbindingen (${s.edges.length})'),
          if (s.edges.isEmpty)
            Text(
              s.nodes.length < 2 ? 'Voeg minstens twee stappen toe om ze te verbinden.' : 'Nog geen verbindingen.',
              style: context.t.caption,
            )
          else
            KCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < s.edges.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: k.border, indent: 16),
                    _EdgeRow(
                      from: _node(s.edges[i].from),
                      to: _node(s.edges[i].to),
                      label: s.edges[i].label,
                      onTap: () => _onEdgeTap(s.edges[i]),
                      onRemove: () => _removeEdge(s.edges[i]),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 28),
          BigButton(
            label: 'Systeem verwijderen',
            icon: Icons.delete_outline,
            color: k.danger,
            outlined: true,
            onPressed: _deleteSystem,
          ),
        ],
      ),
    );
  }

  static String? _techniqueName(List<Technique> techniques, String? id) {
    if (id == null) return null;
    for (final t in techniques) {
      if (t.id == id) return t.name;
    }
    return null;
  }
}

class _ConnectBanner extends StatelessWidget {
  const _ConnectBanner({required this.from, required this.onCancel});
  final String from;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: k.primaryTint,
        borderRadius: BorderRadius.circular(KRadius.md),
        border: Border.all(color: k.primary),
      ),
      child: Row(
        children: [
          Icon(Icons.trending_flat, color: k.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Pijl vanaf "$from": tik op de doelstap',
              style: context.t.bodyStrong.copyWith(color: k.text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onCancel, child: const Text('Annuleren')),
        ],
      ),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind, this.size = 36});
  final SystemNodeKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: systemKindFill(k, kind),
        borderRadius: BorderRadius.circular(KRadius.sm),
        border: Border.all(color: systemKindColor(k, kind), width: 1.2),
      ),
      child: Icon(systemKindIcon(kind), size: size * 0.5, color: systemKindColor(k, kind)),
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({required this.node, required this.next, required this.techniqueName, required this.onTap});
  final SystemNode node;
  final List<String> next;
  final String? techniqueName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final meta = [systemKindShort(node.kind), if (techniqueName != null) 'Techniek: $techniqueName'].join(' • ');
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              _KindTile(kind: node.kind),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(node.label, style: context.t.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(meta, style: context.t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (next.isNotEmpty)
                      Text(
                        '→ ${next.join(', ')}',
                        style: context.t.caption.copyWith(color: k.accent),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              SizedBox(width: 48, height: 48, child: Icon(Icons.more_vert, color: k.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EdgeRow extends StatelessWidget {
  const _EdgeRow({required this.from, required this.to, required this.onRemove, this.label = '', this.onTap});
  final SystemNode? from;
  final SystemNode? to;
  final VoidCallback onRemove;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    Widget label(SystemNode? n) => Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (n != null) ...[
            Icon(systemKindIcon(n.kind), size: 14, color: systemKindColor(k, n.kind)),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(n?.label ?? '?', style: context.t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      label(from),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward, size: 16, color: k.textMuted),
                      ),
                      label(to),
                    ],
                  ),
                  if (this.label.trim().isNotEmpty)
                    Text(this.label.trim(), style: context.t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Verbinding verwijderen',
              onPressed: onRemove,
              icon: Icon(Icons.close, color: k.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ sheets

class _NodeActionsSheet extends StatelessWidget {
  const _NodeActionsSheet({
    required this.node,
    required this.canConnect,
    required this.hasOutgoing,
    required this.hasTechnique,
  });
  final SystemNode node;
  final bool canConnect;
  final bool hasOutgoing;
  final bool hasTechnique;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    Widget action(_NodeAction a, IconData icon, String label, {bool danger = false}) => InkWell(
      onTap: () => Navigator.of(context).pop(a),
      borderRadius: BorderRadius.circular(KRadius.md),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: 4),
            Icon(icon, color: danger ? k.danger : k.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: context.t.body.copyWith(color: danger ? k.dangerInk : k.text, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _KindTile(kind: node.kind, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(node.label, style: context.t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(node.kind.label, style: context.t.caption),
                ],
              ),
            ),
          ],
        ),
        if (node.techniqueId != null) ...[
          const SizedBox(height: 12),
          TechniqueDetails(techniqueId: node.techniqueId!, compact: true),
        ],
        const SizedBox(height: 12),
        Divider(height: 1, color: k.border),
        const SizedBox(height: 4),
        action(_NodeAction.edit, Icons.edit_outlined, 'Naam, soort of techniek wijzigen'),
        action(_NodeAction.addAfter, Icons.add_circle_outline, 'Nieuwe stap hierna'),
        if (canConnect) action(_NodeAction.connect, Icons.trending_flat, 'Pijl naar bestaande stap'),
        if (hasTechnique) action(_NodeAction.openTechnique, Icons.menu_book_outlined, 'Gekoppelde techniek openen'),
        if (hasOutgoing) action(_NodeAction.unlink, Icons.link_off, 'Pijlen vanaf deze stap wissen'),
        action(_NodeAction.delete, Icons.delete_outline, 'Stap verwijderen', danger: true),
      ],
    );
  }
}

/// Stap toevoegen of bewerken: naam, soort en optioneel een techniek uit
/// de vault.
class _NodeSheet extends StatefulWidget {
  const _NodeSheet({required this.newId, this.initial, this.afterLabel});
  final String newId;
  final SystemNode? initial;
  final String? afterLabel;

  @override
  State<_NodeSheet> createState() => _NodeSheetState();
}

class _NodeSheetState extends State<_NodeSheet> {
  late final _name = TextEditingController(text: widget.initial?.label ?? '');
  final _search = TextEditingController();
  late SystemNodeKind _kind = widget.initial?.kind ?? SystemNodeKind.position;
  VaultEntry? _linked;
  bool _linkCleared = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    final id = widget.initial?.techniqueId;
    if (id != null) _linked = locateEntry(KineticScope.read(context).vault, ownId: id);
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _pick(VaultEntry e) {
    setState(() {
      _linked = e;
      _linkCleared = false;
      if (_name.text.trim().isEmpty || widget.initial == null) _name.text = e.name;
      if (widget.initial == null) {
        _kind = e.group == TechniqueGroup.submissions ? SystemNodeKind.finish : SystemNodeKind.technique;
      }
      _search.clear();
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _done() async {
    final label = _name.text.trim();
    if (label.isEmpty || _busy) return;
    final store = KineticScope.read(context);
    String? techniqueId = _linkCleared ? null : widget.initial?.techniqueId;
    final linked = _linked;
    if (linked != null) {
      setState(() => _busy = true);
      final own = await store.ensureOwnTechnique(linked);
      if (!mounted) return;
      setState(() => _busy = false);
      if (own == null) {
        showToast(context, 'Techniek koppelen mislukt', error: true);
        return;
      }
      techniqueId = own.id;
    }
    if (!mounted) return;
    Navigator.of(context).pop(SystemNode(id: widget.newId, label: label, kind: _kind, techniqueId: techniqueId));
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final editing = widget.initial != null;
    final q = _search.text.trim();
    // Leeg = bladeren (voor als je de naam even kwijt bent), anders filteren.
    final matches = (q.isEmpty ? store.vault.toList() : store.vault.where((e) => e.matches(q)).toList())
      ..sort((a, b) {
        final g = a.group.index.compareTo(b.group.index);
        if (g != 0) return g;
        if (a.isOwn != b.isOwn) return a.isOwn ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(editing ? 'Stap bewerken' : 'Stap toevoegen', style: context.t.headline),
        if (widget.afterLabel != null) ...[
          const SizedBox(height: 4),
          Text('Komt na "${widget.afterLabel}"', style: context.t.caption),
        ],
        const SizedBox(height: 16),
        KSegmented<SystemNodeKind>(
          options: [for (final kind in SystemNodeKind.values) (kind, systemKindShort(kind))],
          value: _kind,
          onChanged: (v) => setState(() => _kind = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          autofocus: !editing,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: InputDecoration(
            labelText: 'Naam',
            hintText: switch (_kind) {
              SystemNodeKind.position => 'Bijv. Clinch (over-under)',
              SystemNodeKind.technique => 'Bijv. Harai Goshi',
              SystemNodeKind.finish => 'Bijv. Kesa gatame',
            },
          ),
          onSubmitted: (_) => _done(),
        ),
        const Eyebrow('Koppel aan techniek (optioneel)'),
        const SizedBox(height: 8),
        if (_linked != null)
          KWell(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Icon(Icons.link, color: k.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_linked!.name, style: context.t.bodyStrong),
                      Text(_linked!.group.label, style: context.t.caption),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Koppeling verwijderen',
                  onPressed: () => setState(() {
                    _linked = null;
                    _linkCleared = true;
                  }),
                  icon: Icon(Icons.close, color: k.textSecondary),
                ),
              ],
            ),
          )
        else ...[
          KSearchField(controller: _search, hint: 'Zoek in je vault', onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          Text(
            q.isEmpty ? 'Of kies uit de lijst (${matches.length})' : '${matches.length} gevonden',
            style: context.t.caption,
          ),
          const SizedBox(height: 4),
          Container(
            height: 280,
            decoration: BoxDecoration(color: k.well, borderRadius: BorderRadius.circular(KRadius.md)),
            child: matches.isEmpty
                ? Center(child: Text('Niets gevonden', style: context.t.caption))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: matches.length,
                    itemBuilder: (context, i) {
                      final e = matches[i];
                      final header = i == 0 || matches[i - 1].group != e.group;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (header)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                              child: Eyebrow(e.group.label, color: groupColor(context, e.group)),
                            ),
                          InkWell(
                            onTap: () => _pick(e),
                            child: SizedBox(
                              height: 48,
                              child: Row(
                                children: [
                                  const SizedBox(width: 12),
                                  Icon(groupIcon(e.group), size: 20, color: groupColor(context, e.group)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      e.name,
                                      style: context.t.body,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (!e.isOwn) const KPill('Bibliotheek', dense: true),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
        const SizedBox(height: 20),
        BigButton(
          label: _busy ? 'Bezig...' : (editing ? 'Opslaan' : 'Stap toevoegen'),
          icon: editing ? Icons.check : Icons.add,
          onPressed: _name.text.trim().isEmpty || _busy ? null : _done,
        ),
      ],
    );
  }
}

/// Nieuwe pijl: van → naar.
class _EdgeSheet extends StatefulWidget {
  const _EdgeSheet({required this.system});
  final TechniqueSystem system;

  @override
  State<_EdgeSheet> createState() => _EdgeSheetState();
}

class _EdgeSheetState extends State<_EdgeSheet> {
  String? _from;
  String? _to;
  final _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.system;
    final exists = _from != null && _to != null && s.edges.contains(SystemEdge(from: _from!, to: _to!));
    final valid = _from != null && _to != null && _from != _to && !exists;
    DropdownButtonFormField<String> picker(String label, String? value, ValueChanged<String?> onChanged) =>
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          style: context.t.body,
          dropdownColor: context.k.surface,
          items: [
            for (final n in s.nodes)
              DropdownMenuItem(
                value: n.id,
                child: Row(
                  children: [
                    Icon(systemKindIcon(n.kind), size: 16, color: systemKindColor(context.k, n.kind)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(n.label, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
          ],
          onChanged: onChanged,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Verbinding toevoegen', style: context.t.headline),
        const SizedBox(height: 4),
        Text('Een pijl van de ene stap naar de volgende.', style: context.t.caption),
        const SizedBox(height: 16),
        picker('Van', _from, (v) => setState(() => _from = v)),
        const SizedBox(height: 12),
        picker('Naar', _to, (v) => setState(() => _to = v)),
        if (_from != null && _from == _to) ...[
          const SizedBox(height: 8),
          Text('Kies twee verschillende stappen.', style: context.t.caption.copyWith(color: context.k.warningInk)),
        ],
        if (exists) ...[
          const SizedBox(height: 8),
          Text('Deze verbinding bestaat al.', style: context.t.caption.copyWith(color: context.k.warningInk)),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _label,
          minLines: 1,
          maxLines: 3,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(
            labelText: 'Transitie (optioneel)',
            hintText: 'Bijv. Tegenstander sluit zijn knieën',
          ),
        ),
        const SizedBox(height: 12),
        BigButton(
          label: 'Verbinding toevoegen',
          icon: Icons.add_link,
          onPressed: valid
              ? () => Navigator.of(context).pop(SystemEdge(from: _from!, to: _to!, label: _label.text.trim()))
              : null,
        ),
      ],
    );
  }
}

/// Transitie bekijken/aanpassen: van → naar, tekst, en de techniek waar hij
/// naartoe leidt. Geeft (label, verwijderen) terug.
class _TransitionSheet extends StatefulWidget {
  const _TransitionSheet({required this.edge, required this.from, required this.to});
  final SystemEdge edge;
  final SystemNode? from;
  final SystemNode? to;

  @override
  State<_TransitionSheet> createState() => _TransitionSheetState();
}

class _TransitionSheetState extends State<_TransitionSheet> {
  late final _label = TextEditingController(text: widget.edge.label);

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final from = widget.from;
    final to = widget.to;
    Widget chip(SystemNode? n) => Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: n == null ? k.well : systemKindFill(k, n.kind),
          borderRadius: BorderRadius.circular(KRadius.sm + 2),
          border: Border.all(color: n == null ? k.border : systemKindColor(k, n.kind)),
        ),
        child: Text(n?.label ?? '?', style: context.t.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Transitie', style: context.t.headline),
        const SizedBox(height: 12),
        Row(
          children: [
            chip(from),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, color: k.textMuted),
            ),
            chip(to),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _label,
          minLines: 1,
          maxLines: 3,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(
            labelText: 'Wat gebeurt er?',
            hintText: 'Bijv. Tegenstander sluit zijn knieën',
          ),
        ),
        const SizedBox(height: 8),
        BigButton(
          label: 'Opslaan',
          icon: Icons.check,
          height: 52,
          onPressed: () => Navigator.of(context).pop((_label.text.trim(), false)),
        ),
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop((widget.edge.label, true)),
          icon: Icon(Icons.link_off, color: k.dangerInk),
          label: Text('Verbinding verwijderen', style: TextStyle(color: k.dangerInk)),
        ),
        if (to?.techniqueId != null) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: k.border),
          const SizedBox(height: 12),
          Text('Leidt naar: ${to!.label}', style: context.t.title),
          const SizedBox(height: 8),
          TechniqueDetails(techniqueId: to.techniqueId!, compact: true),
        ],
      ],
    );
  }
}

/// Technieken aanvinken voor het systeem: zoeken of bladeren (gegroepeerd).
/// Rondje = niet in het systeem, vinkje = staat erin.
class _TechniqueChecklist extends StatefulWidget {
  const _TechniqueChecklist({required this.isIn, required this.onToggle});
  final bool Function(VaultEntry e) isIn;
  final Future<bool> Function(VaultEntry e) onToggle;

  @override
  State<_TechniqueChecklist> createState() => _TechniqueChecklistState();
}

class _TechniqueChecklistState extends State<_TechniqueChecklist> {
  final _search = TextEditingController();
  final Set<String> _busy = {};
  bool _onlyOwn = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _toggle(VaultEntry e) async {
    HapticFeedback.selectionClick();
    setState(() => _busy.add(e.key));
    final ok = await widget.onToggle(e);
    if (!mounted) return;
    setState(() => _busy.remove(e.key));
    if (!ok) showToast(context, 'Bijwerken mislukt', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final q = _search.text.trim();
    final list = store.vault.where((e) => (!_onlyOwn || e.isOwn) && (q.isEmpty || e.matches(q))).toList()
      ..sort((a, b) {
        final g = a.group.index.compareTo(b.group.index);
        if (g != 0) return g;
        if (a.isOwn != b.isOwn) return a.isOwn ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final chosen = store.vault.where(widget.isIn).length;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Technieken kiezen', style: context.t.headline)),
              KPill('$chosen in systeem', tone: KTone.primary, dense: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tik een techniek aan om hem toe te voegen of weg te halen. Verbind de stappen daarna in de flow.',
            style: context.t.caption,
          ),
          const SizedBox(height: 12),
          KSearchField(controller: _search, hint: 'Zoek in je vault', onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          Row(
            children: [
              KChip(label: 'Alles', selected: !_onlyOwn, onTap: () => setState(() => _onlyOwn = false)),
              const SizedBox(width: 8),
              KChip(label: 'Mijn technieken', selected: _onlyOwn, onTap: () => setState(() => _onlyOwn = true)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('Niets gevonden', style: context.t.caption))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final e = list[i];
                      final header = i == 0 || list[i - 1].group != e.group;
                      final selected = widget.isIn(e);
                      final busy = _busy.contains(e.key);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (header)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                              child: Eyebrow(e.group.label, color: groupColor(context, e.group)),
                            ),
                          Semantics(
                            checked: selected,
                            button: true,
                            label: e.name,
                            excludeSemantics: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(KRadius.md),
                              onTap: busy ? null : () => _toggle(e),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected ? k.primaryTint : k.well,
                                  borderRadius: BorderRadius.circular(KRadius.md),
                                  border: Border.all(color: selected ? k.primary : k.border),
                                ),
                                child: Row(
                                  children: [
                                    if (busy)
                                      const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    else
                                      Icon(
                                        selected ? Icons.check_circle : Icons.radio_button_unchecked,
                                        color: selected ? k.primary : k.textMuted,
                                        size: 24,
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        e.name,
                                        style: context.t.bodyStrong,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!e.isOwn) const KPill('Bibliotheek', dense: true),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          BigButton(label: 'Klaar', icon: Icons.check, height: 52, onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

/// De flow op volledig scherm (zoals in FlowRoll), live met het systeem mee.
class _FullScreenGraph extends StatelessWidget {
  const _FullScreenGraph({required this.systemId, required this.onNodeTap, required this.onEdgeTap});
  final String systemId;
  final ValueChanged<SystemNode> onNodeTap;
  final ValueChanged<SystemEdge> onEdgeTap;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final s = store.systems.where((x) => x.id == systemId).firstOrNull;
    return Scaffold(
      backgroundColor: k.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(child: Text(s?.name ?? 'Systeem', style: context.t.headline, maxLines: 2)),
                  IconButton.filledTonal(
                    tooltip: 'Sluiten',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SystemLegend()),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: KWell(
                  padding: EdgeInsets.zero,
                  child: s == null
                      ? const SizedBox.shrink()
                      : SystemGraph(system: s, onNodeTap: onNodeTap, onEdgeTap: onEdgeTap),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
