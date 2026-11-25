// combinations_view.dart: sub-tab "Combo's": combinaties van technieken in
// volgorde (bv. Harai Goshi → O-soto-gari) maken, aanpassen en verwijderen,
// met notitie en video's. Tijdens een training log je ze met één tik.

import 'package:material_ui/material_ui.dart';

import '../../models/combination.dart';
import '../../theme/kinetic_theme.dart';
import '../../widgets/kinetic_widgets.dart';
import '../../widgets/start_training_sheet.dart';
import '../../widgets/technique_detail_widgets.dart';
import '../../widgets/video_widgets.dart';
import 'technique_ui.dart';

class CombinationsView extends StatelessWidget {
  const CombinationsView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final list = store.combinations;
    final pad = pagePadding(context);
    return RefreshIndicator(
      color: k.primary,
      backgroundColor: k.surface,
      onRefresh: store.refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, pad.bottom),
        children: [
          SubTabHeader(
            title: "Combo's",
            caption: '${list.length} ${list.length == 1 ? 'combinatie' : 'combinaties'}',
            action: HeaderButton(label: 'Combo', onPressed: () => showCombinationEditor(context)),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const EmptyCard(
              icon: Icons.alt_route,
              title: 'Nog geen combinaties',
              message: 'Maak een combinatie zoals "Harai Goshi → O-soto-gari" en log hem tijdens trainingen met één tik.',
            ),
          for (final c in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: KCard(
                onTap: () => showCombinationDetails(context, c),
                child: Row(
                  children: [
                    IconTile(icon: Icons.alt_route, color: k.purple, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: context.t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(c.sequence, style: context.t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: [
                              KPill(c.type.label, dense: true),
                              if (c.videoUrls.isNotEmpty)
                                KPill("${c.videoUrls.length} video${c.videoUrls.length == 1 ? '' : "'s"}", icon: Icons.ondemand_video, dense: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: k.textMuted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showCombinationEditor(BuildContext context, {Combination? existing}) =>
    showKineticSheet<void>(context, builder: (_) => _CombinationEditor(existing: existing));

class _CombinationEditor extends StatefulWidget {
  const _CombinationEditor({this.existing});
  final Combination? existing;

  @override
  State<_CombinationEditor> createState() => _CombinationEditorState();
}

class _CombinationEditorState extends State<_CombinationEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late ComboType _type = widget.existing?.type ?? ComboType.mixed;
  late List<String> _steps = [...?widget.existing?.techniques];
  late List<String> _videos = [...?widget.existing?.videoUrls];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addStep() async {
    final pick = await showTechniquePicker(context, title: 'Stap toevoegen', initiallySelected: (_) => false, allowCustom: true);
    if (pick == null) return;
    setState(() => _steps = [..._steps, ...pick.entries.map((e) => e.name), ...pick.customNames]);
  }

  Future<void> _save() async {
    final store = KineticScope.read(context);
    final name = _name.text.trim().isEmpty ? _steps.join(' → ') : _name.text.trim();
    if (name.isEmpty) return showToast(context, 'Geef de combinatie een naam of voeg stappen toe', error: true);
    setState(() => _saving = true);
    final saved = await store.saveCombination(
      (widget.existing ?? const Combination(id: '', name: '')).copyWith(
        name: name,
        type: _type,
        techniques: _steps,
        note: _note.text.trim(),
        videoUrls: _videos,
      ),
    );
    if (!mounted) return;
    if (saved == null) {
      setState(() => _saving = false);
      showToast(context, 'Opslaan mislukt', error: true);
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(context, title: 'Combinatie verwijderen?', message: '"${widget.existing!.name}" wordt verwijderd.');
    if (!ok || !mounted) return;
    final store = KineticScope.read(context);
    final nav = Navigator.of(context);
    await store.deleteCombination(widget.existing!);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final editing = widget.existing != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(editing ? 'Combinatie aanpassen' : 'Nieuwe combinatie', style: context.t.headline),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Naam (optioneel)', hintText: 'Bijv. Heupworp-ketting'),
        ),
        const SizedBox(height: 12),
        KSegmented<ComboType>(
          options: [for (final t in ComboType.values) (t, t.label)],
          value: _type,
          onChanged: (t) => setState(() => _type = t),
        ),
        const SizedBox(height: 16),
        FormLabel('Stappen in volgorde', trailing: '${_steps.length}'),
        if (_steps.isEmpty) Text('Nog geen stappen.', style: context.t.caption),
        if (_steps.isNotEmpty)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => setState(() {
              final s = [..._steps];
              s.insert(to, s.removeAt(from));
              _steps = s;
            }),
            children: [
              for (var i = 0; i < _steps.length; i++)
                Padding(
                  key: ValueKey('step-$i-${_steps[i]}'),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: KWell(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    child: Row(
                      children: [
                        Text('${i + 1}.', style: context.t.bodyStrong.copyWith(color: k.accent)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_steps[i], style: context.t.bodyStrong)),
                        IconButton(
                          tooltip: '${_steps[i]} weghalen',
                          onPressed: () => setState(() => _steps = [..._steps]..removeAt(i)),
                          icon: Icon(Icons.close, color: k.textMuted, size: 20),
                        ),
                        ReorderableDragStartListener(index: i, child: Icon(Icons.drag_handle, color: k.textMuted)),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 6),
        OutlinedButton.icon(onPressed: _addStep, icon: const Icon(Icons.add), label: const Text('Stap toevoegen')),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Notitie (optioneel)'),
        ),
        const SizedBox(height: 16),
        DetailHeader(
          icon: Icons.ondemand_video,
          title: "Video's",
          action: 'Video',
          onAction: () => showAddVideoSheet(
            context,
            onAdd: (url, label) async {
              if (label.isNotEmpty) await KineticScope.read(context).setVideoLabel(url, label);
              setState(() => _videos = [..._videos, url]);
              return true;
            },
          ),
        ),
        if (_videos.isNotEmpty)
          VideoList(
            urls: _videos,
            onRemove: (url) async {
              setState(() => _videos = _videos.where((v) => v != url).toList());
              return true;
            },
          ),
        const SizedBox(height: 20),
        BigButton(label: _saving ? 'Opslaan…' : 'Opslaan', icon: Icons.check, height: 56, onPressed: _saving ? null : _save),
        if (editing) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _delete,
            icon: Icon(Icons.delete_outline, color: k.dangerInk),
            label: Text('Combinatie verwijderen', style: TextStyle(color: k.dangerInk)),
          ),
        ],
      ],
    );
  }
}

/// Details van een combinatie: stappen, notitie en video's (afspelen in de
/// app). "Aanpassen" opent pas de editor.
Future<void> showCombinationDetails(BuildContext context, Combination c) =>
    showKineticSheet<void>(context, builder: (_) => _CombinationDetails(id: c.id, fallback: c));

class _CombinationDetails extends StatelessWidget {
  const _CombinationDetails({required this.id, required this.fallback});
  final String id;
  final Combination fallback;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final c = store.combinations.where((x) => x.id == id).firstOrNull ?? fallback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 6, children: [KPill(c.type.label, dense: true)]),
        const SizedBox(height: 10),
        Text(c.name, style: context.t.headline),
        const SizedBox(height: 16),
        if (c.techniques.isNotEmpty) ...[
          const FormLabel('Stappen'),
          for (var i = 0; i < c.techniques.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: KWell(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Text('${i + 1}.', style: context.t.bodyStrong.copyWith(color: k.accent)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(c.techniques[i], style: context.t.bodyStrong)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
        ],
        if (c.note.trim().isNotEmpty) ...[
          const FormLabel('Notitie'),
          KWell(child: Text(c.note.trim(), style: context.t.body)),
          const SizedBox(height: 16),
        ],
        const DetailHeader(icon: Icons.ondemand_video, title: "Video's"),
        if (c.videoUrls.isEmpty)
          Text("Nog geen video's.", style: context.t.caption)
        else
          VideoList(urls: c.videoUrls),
        const SizedBox(height: 20),
        BigButton(
          label: 'Aanpassen',
          icon: Icons.edit_outlined,
          style: KButtonStyle.secondary,
          height: 52,
          onPressed: () {
            Navigator.of(context).pop();
            showCombinationEditor(context, existing: c);
          },
        ),
      ],
    );
  }
}
