// technique_edit_screen.dart — een techniek aanmaken of structureel aanpassen
//
// Naam, categorie, transitie, beschrijving, video's en de favoriet-status.
// Bereikbaar via "Aanpassen" op technique_detail_screen.dart (of meteen bij
// het aanmaken van een nieuwe techniek). Het loggen van updates (hoe ging
// het) gebeurt op het detailscherm zelf, niet hier — dat is geen structurele
// wijziging van de techniek.

import 'package:flutter/material.dart';

import '../core/positions.dart';
import '../models/technique.dart';
import '../repositories/technique_repository.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/ground_position_tags.dart';
import '../widgets/video_link_row.dart';
import '../widgets/block_widgets.dart' show kBlockCategories;

/// Resultaat van het bewerkscherm: de opgeslagen techniek, een signaal dat
/// hij is verwijderd, of null als er niets is gewijzigd.
class TechniqueEditResult {
  final Technique? technique;
  final bool deleted;
  const TechniqueEditResult.saved(this.technique) : deleted = false;
  const TechniqueEditResult.deleted() : technique = null, deleted = true;
}

class TechniqueEditScreen extends StatefulWidget {
  const TechniqueEditScreen({
    super.key,
    required this.repository,
    required this.userId,
    this.technique,
    this.initialName = '',
    this.initialCategory = 'Takedown',
  });

  final TechniqueRepository repository;
  final String userId;

  /// null = nieuwe techniek.
  final Technique? technique;
  final String initialName;
  final String initialCategory;

  @override
  State<TechniqueEditScreen> createState() => _TechniqueEditScreenState();
}

class _TechniqueEditScreenState extends State<TechniqueEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  final _newVideoUrl = TextEditingController();
  late List<String> _videoUrls;
  late String _category;
  String? _van;
  String? _naar;
  late List<String> _groundPositions;
  late bool _transitionExpanded;
  late bool _favorite;
  bool _busy = false;

  bool get _isNew => widget.technique == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.technique?.name ?? widget.initialName,
    );
    _description = TextEditingController(
      text: widget.technique?.description ?? '',
    );
    _videoUrls = List.of(widget.technique?.videoUrls ?? const []);
    _category = widget.technique?.category ?? widget.initialCategory;
    final parsed = parseTransition(widget.technique?.transition ?? '');
    _van = parsed?.from;
    _naar = parsed?.to;
    _groundPositions = List.of(widget.technique?.groundPositions ?? const []);
    // Standaard ingeklapt voor een nieuwe/nog lege transitie, zodat je niet
    // meteen alle posities ziet — al gekozen? Dan meteen open, zodat je niet
    // per ongeluk denkt dat de keuze weg is.
    _transitionExpanded = _van != null || _naar != null;
    _favorite = widget.technique?.favorite ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _newVideoUrl.dispose();
    super.dispose();
  }

  void _addVideoUrl() {
    final url = _newVideoUrl.text.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ongeldige videolink.')));
      return;
    }
    setState(() {
      _videoUrls.add(url);
      _newVideoUrl.clear();
    });
    // Meteen een naam laten geven (overslaan mag).
    editVideoLabel(context, url);
  }

  void _removeVideoUrl(int i) => setState(() => _videoUrls.removeAt(i));

  /// Chips voor één kant (van/naar) van de transitie — de kant die al aan de
  /// andere zijde gekozen is, kan hier niet nogmaals gekozen worden. "Van"
  /// krijgt alleen de posities ([kPositions]); "naar" ook de afgeronde
  /// scores ([kOutcomes]) — je kunt wel ergens vertrekken, maar niet vanuit
  /// een ippon.
  Widget _positionChips({
    required List<String> options,
    required String? selected,
    required String? disabled,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in options)
          InkWell(
            onTap: p == disabled ? null : () => onSelect(p),
            borderRadius: BorderRadius.circular(99),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: selected == p ? AppColor.tealWash : AppColor.surface,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                p,
                style: AppText.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: p == disabled
                      ? AppColor.inkGhost
                      : selected == p
                      ? AppColor.tealBright
                      : AppColor.inkMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Chips voor de (optionele) grondposities van een afwerking — in
  /// tegenstelling tot [_positionChips] sluiten deze elkaar niet uit: elke
  /// chip schakelt onafhankelijk aan/uit, want eenzelfde afwerking lukt vaak
  /// vanuit meer dan één positie.
  Widget _multiPositionChips({
    required List<String> options,
    required List<String> selected,
    required ValueChanged<String> onToggle,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in options)
          InkWell(
            onTap: () => onToggle(p),
            borderRadius: BorderRadius.circular(99),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: selected.contains(p)
                    ? AppColor.tealWash
                    : AppColor.surface,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                p,
                style: AppText.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected.contains(p)
                      ? AppColor.tealBright
                      : AppColor.inkMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geef de techniek een naam.')),
      );
      return;
    }
    setState(() => _busy = true);
    final transition = (_van != null && _naar != null) ? '$_van -> $_naar' : '';
    // Alleen relevant bij categorie Submission — anders niet bewaren, zodat
    // er geen verweesde waarden achterblijven nadat de categorie is
    // gewijzigd.
    final groundPositions = _category == 'Submission'
        ? _groundPositions
        : <String>[];
    try {
      final Technique saved;
      if (_isNew) {
        saved = await widget.repository.create(
          Technique(
            id: '',
            name: name,
            category: _category,
            transition: transition,
            favorite: _favorite,
            description: _description.text.trim(),
            videoUrls: _videoUrls,
            groundPositions: groundPositions,
          ),
          widget.userId,
        );
      } else {
        saved = await widget.repository.updateContent(
          widget.technique!.copyWith(
            name: name,
            category: _category,
            transition: transition,
            favorite: _favorite,
            description: _description.text.trim(),
            videoUrls: _videoUrls,
            groundPositions: groundPositions,
          ),
        );
      }
      if (mounted) {
        Navigator.pop(context, TechniqueEditResult.saved(saved));
      }
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
    if (widget.technique == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text('Techniek verwijderen?', style: AppText.cardTitle),
        content: Text(
          'Je eigen updates verdwijnen. Trainingen waarin deze techniek is behandeld blijven staan.',
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
      await widget.repository.delete(widget.technique!.id);
      if (mounted) {
        Navigator.pop(context, const TechniqueEditResult.deleted());
      }
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
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: Text(
          _isNew ? 'Nieuwe techniek' : 'Techniek aanpassen',
          style: AppText.bodyStrong.copyWith(fontSize: 14),
        ),
        actions: [
          IconButton(
            onPressed: () => setState(() => _favorite = !_favorite),
            icon: Icon(
              _favorite ? Icons.star : Icons.star_border,
              color: _favorite ? AppColor.amberBright : AppColor.inkMuted,
            ),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? .6 : 1,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              100 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              Text('NAAM', style: AppText.overline),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                style: AppText.bodyStrong,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColor.surface,
                  hintText: 'Naam van de techniek',
                  hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('CATEGORIE', style: AppText.overline),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in kBlockCategories)
                    InkWell(
                      onTap: () => setState(() => _category = c),
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: _category == c
                              ? AppColor.tealWash
                              : AppColor.surface,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          c,
                          style: AppText.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _category == c
                                ? AppColor.tealBright
                                : AppColor.inkMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (_category == 'Submission') ...[
                const SizedBox(height: 14),
                Text(
                  'Vanuit welke positie(s) (optioneel)',
                  style: AppText.caption.copyWith(fontSize: 10),
                ),
                const SizedBox(height: 6),
                _multiPositionChips(
                  options: kGroundPositions,
                  selected: _groundPositions,
                  onToggle: (p) => setState(() {
                    if (!_groundPositions.remove(p)) _groundPositions.add(p);
                  }),
                ),
              ],
              const SizedBox(height: 20),
              InkWell(
                onTap: () =>
                    setState(() => _transitionExpanded = !_transitionExpanded),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TRANSITIE (OPTIONEEL) — VOOR DE KAART',
                              style: AppText.overline,
                            ),
                            if (!_transitionExpanded) ...[
                              const SizedBox(height: 4),
                              if (_van != null && _naar != null)
                                TransitionTag(transition: '$_van -> $_naar')
                              else
                                Text('Niet ingesteld', style: AppText.caption),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        _transitionExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: AppColor.inkFaint,
                      ),
                    ],
                  ),
                ),
              ),
              if (_transitionExpanded) ...[
                const SizedBox(height: 10),
                Text('Van', style: AppText.caption.copyWith(fontSize: 10)),
                const SizedBox(height: 6),
                _positionChips(
                  options: kPositions,
                  selected: _van,
                  disabled: _naar,
                  onSelect: (p) => setState(() => _van = _van == p ? null : p),
                ),
                const SizedBox(height: 14),
                Text('Naar', style: AppText.caption.copyWith(fontSize: 10)),
                const SizedBox(height: 6),
                _positionChips(
                  options: kAllNodes,
                  selected: _naar,
                  disabled: _van,
                  onSelect: (p) => setState(() => _naar = _naar == p ? null : p),
                ),
              ],
              const SizedBox(height: 20),
              Text('BESCHRIJVING (OPTIONEEL)', style: AppText.overline),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                maxLines: 4,
                minLines: 3,
                style: AppText.body,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColor.surface,
                  hintText: 'Hoe voer je hem uit, waar let je op?',
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
                VideoLinkRow(
                  url: _videoUrls[i],
                  onRemove: () => _removeVideoUrl(i),
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
                  child: const Text('Techniek verwijderen'),
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
