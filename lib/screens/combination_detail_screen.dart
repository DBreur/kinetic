// combination_detail_screen.dart — een combinatie van technieken beheren:
// naam, type (strikes/takedowns/gemixed) en de technieken in volgorde.

import 'package:flutter/material.dart';

import '../models/combination.dart';
import '../models/technique.dart';
import '../repositories/combination_repository.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/inline_video_player.dart';

class CombinationDetailScreen extends StatefulWidget {
  const CombinationDetailScreen({
    super.key,
    required this.repository,
    required this.userId,
    this.combination,
    this.existingTechniques = const [],
  });

  final CombinationRepository repository;
  final String userId;

  /// null = nieuwe combinatie, wordt aangemaakt bij opslaan.
  final Combination? combination;
  final List<Technique> existingTechniques;

  @override
  State<CombinationDetailScreen> createState() =>
      _CombinationDetailScreenState();
}

class _CombinationDetailScreenState extends State<CombinationDetailScreen> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late ComboType _type;
  late List<String> _techniques;
  late List<String> _videoUrls;
  final _techniqueInput = TextEditingController();
  final _newVideoUrl = TextEditingController();
  bool _busy = false;

  bool get _isNew => widget.combination == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.combination?.name ?? '');
    _note = TextEditingController(text: widget.combination?.note ?? '');
    _type = widget.combination?.type ?? ComboType.mixed;
    _techniques = List.of(widget.combination?.techniques ?? const []);
    _videoUrls = List.of(widget.combination?.videoUrls ?? const []);
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _techniqueInput.dispose();
    _newVideoUrl.dispose();
    super.dispose();
  }

  void _addVideoUrl() {
    final url = _newVideoUrl.text.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ongeldige videolink.')));
      return;
    }
    setState(() {
      _videoUrls.add(url);
      _newVideoUrl.clear();
    });
  }

  void _removeVideoUrl(int i) => setState(() => _videoUrls.removeAt(i));

  void _addTechnique(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _techniques.add(trimmed);
      _techniqueInput.clear();
    });
  }

  void _removeTechniqueAt(int i) => setState(() => _techniques.removeAt(i));

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _techniques.removeAt(oldIndex);
      _techniques.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geef de combinatie een naam.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isNew) {
        await widget.repository.create(
          Combination(
            id: '',
            name: name,
            type: _type,
            techniques: _techniques,
            note: _note.text.trim(),
            videoUrls: _videoUrls,
          ),
          widget.userId,
        );
      } else {
        await widget.repository.updateContent(
          widget.combination!.copyWith(
            name: name,
            type: _type,
            techniques: _techniques,
            note: _note.text.trim(),
            videoUrls: _videoUrls,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opslaan is niet gelukt. Probeer opnieuw.'),
          ),
        );
      }
    }
  }

  Future<void> _delete() async {
    if (widget.combination == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text('Combinatie verwijderen?', style: AppText.cardTitle),
        content: Text(
          'Dit verwijdert alleen de combinatie zelf, niet de losse technieken.',
          style: AppText.body.copyWith(color: AppColor.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuleer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: AppColor.red),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await widget.repository.delete(widget.combination!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        backgroundColor: AppColor.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _isNew ? 'Nieuwe combinatie' : 'Combinatie aanpassen',
          style: AppText.bodyStrong.copyWith(fontSize: 14),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? .6 : 1,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
            children: [
              Text('NAAM', style: AppText.overline),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                style: AppText.bodyStrong,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColor.surface,
                  hintText: 'Naam van de combinatie',
                  hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('TYPE', style: AppText.overline),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in ComboType.values)
                    InkWell(
                      onTap: () => setState(() => _type = t),
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: _type == t
                              ? AppColor.tealWash
                              : AppColor.surface,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          t.label,
                          style: AppText.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _type == t
                                ? AppColor.tealBright
                                : AppColor.inkMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('TECHNIEKEN (IN VOLGORDE)', style: AppText.overline),
              const SizedBox(height: 10),
              if (_techniques.isEmpty)
                Text('Nog geen technieken toegevoegd.', style: AppText.caption)
              else
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: _reorder,
                  children: [
                    for (var i = 0; i < _techniques.length; i++)
                      Padding(
                        key: ValueKey('$i-${_techniques[i]}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColor.surface,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${i + 1}.',
                                style: AppText.caption.copyWith(
                                  color: AppColor.inkFaint,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _techniques[i],
                                  style: AppText.body,
                                ),
                              ),
                              InkWell(
                                onTap: () => _removeTechniqueAt(i),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: AppColor.inkFaint,
                                  ),
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: i,
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.drag_handle,
                                    size: 18,
                                    color: AppColor.inkFaint,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _techniqueInput,
                      style: AppText.body,
                      onSubmitted: _addTechnique,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: .05),
                        hintText: 'Techniek toevoegen — of kies uit je lijst',
                        hintStyle: AppText.body.copyWith(
                          color: AppColor.inkGhost,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _addTechnique(_techniqueInput.text),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (widget.existingTechniques.isNotEmpty) ...[
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final q = _techniqueInput.text.trim().toLowerCase();
                    final options = widget.existingTechniques
                        .where(
                          (t) => q.isEmpty || t.name.toLowerCase().contains(q),
                        )
                        .toList();
                    if (options.isEmpty) return const SizedBox.shrink();
                    return Container(
                      constraints: const BoxConstraints(maxHeight: 140),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .04),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        children: [
                          for (final t in options)
                            InkWell(
                              onTap: () => _addTechnique(t.name),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Text(t.name, style: AppText.body),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 20),
              Text('NOTITIE (OPTIONEEL)', style: AppText.overline),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                maxLines: 3,
                minLines: 2,
                style: AppText.body,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColor.surface,
                  hintText: 'Waar let je op bij deze combinatie?',
                  hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('VIDEO\'S (OPTIONEEL)', style: AppText.overline),
              const SizedBox(height: 10),
              for (var i = 0; i < _videoUrls.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColor.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _videoUrls[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body,
                        ),
                      ),
                      InkWell(
                        onTap: () => _removeVideoUrl(i),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: AppColor.inkFaint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newVideoUrl,
                      keyboardType: TextInputType.url,
                      style: AppText.body,
                      onSubmitted: (_) => _addVideoUrl(),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColor.surface,
                        hintText: 'Link naar een video',
                        hintStyle: AppText.body.copyWith(
                          color: AppColor.inkGhost,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _addVideoUrl,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(Icons.add, size: 18),
                  ),
                ],
              ),
              if (_videoUrls.isNotEmpty) ...[
                const SizedBox(height: 10),
                CollapsibleVideoList(urls: _videoUrls),
              ],
              if (!_isNew) ...[
                const SizedBox(height: 30),
                Text(
                  'VERWIJDEREN',
                  style: AppText.overline.copyWith(color: AppColor.redBright),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColor.redBright,
                    side: const BorderSide(color: AppColor.red),
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: const Text('Combinatie verwijderen'),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Opslaan...' : 'Wijzigingen bewaren'),
          ),
        ),
      ),
    );
  }
}
