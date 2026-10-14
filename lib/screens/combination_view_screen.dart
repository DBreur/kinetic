// combination_view_screen.dart — een combinatie bekijken, zoals
// technique_detail_screen.dart dat voor een techniek doet: alles in één
// overzicht, met de ster en "Aanpassen" rechtsboven. Aanpassen gaat naar
// combination_detail_screen.dart (het bewerkscherm).

import 'package:flutter/material.dart';

import '../models/combination.dart';
import '../models/technique.dart';
import '../repositories/combination_repository.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/inline_video_player.dart';
import '../widgets/kinetic.dart';
import 'combination_detail_screen.dart';

class CombinationViewScreen extends StatefulWidget {
  const CombinationViewScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.combination,
    this.existingTechniques = const [],
  });

  final CombinationRepository repository;
  final String userId;
  final Combination combination;
  final List<Technique> existingTechniques;

  @override
  State<CombinationViewScreen> createState() => _CombinationViewScreenState();
}

class _CombinationViewScreenState extends State<CombinationViewScreen> {
  late Combination _combo = widget.combination;
  bool _changed = false;
  bool _busy = false;

  Future<void> _toggleFavorite() async {
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.setFavorite(
        _combo.id,
        !_combo.favorite,
      );
      if (!mounted) return;
      setState(() {
        _combo = updated;
        _changed = true;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Favoriet opslaan is niet gelukt.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEdit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CombinationDetailScreen(
          repository: widget.repository,
          userId: widget.userId,
          combination: _combo,
          existingTechniques: widget.existingTechniques,
        ),
      ),
    );
    if (changed != true || !mounted) return;
    _changed = true;
    final fresh = await widget.repository.fetch(_combo.id).catchError(
      (_) => _combo,
    );
    if (!mounted) return;
    if (fresh == null) {
      // Verwijderd vanuit het bewerkscherm.
      Navigator.pop(context, true);
      return;
    }
    setState(() => _combo = fresh);
  }

  Technique? _catalogFor(String name) {
    final lower = name.toLowerCase();
    for (final t in widget.existingTechniques) {
      if (t.name.toLowerCase() == lower) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = _combo;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => Navigator.pop(context, _changed),
          ),
          title: Text(
            c.name,
            style: AppText.bodyStrong,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: c.favorite ? 'Geen favoriet meer' : 'Favoriet',
              onPressed: _busy ? null : _toggleFavorite,
              icon: Icon(
                c.favorite ? Icons.star : Icons.star_border,
                color: c.favorite ? AppColor.amberBright : AppColor.inkMuted,
              ),
            ),
            TextButton(onPressed: _openEdit, child: const Text('Aanpassen')),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            24 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                KTag(c.type.label, color: AppColor.coralSoft),
                KTag(
                  '${c.techniques.length} techniek${c.techniques.length == 1 ? '' : 'en'}',
                  color: AppColor.inkMuted,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            KCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const KCardHeader(
                    icon: Icons.call_merge,
                    iconColor: AppColor.coral,
                    label: 'Volgorde',
                  ),
                  const SizedBox(height: AppSpace.md),
                  if (c.techniques.isEmpty)
                    Text(
                      'Nog geen technieken — tik op Aanpassen om ze toe te voegen.',
                      style: AppText.caption,
                    ),
                  for (var i = 0; i < c.techniques.length; i++)
                    _StepRow(
                      index: i,
                      name: c.techniques[i],
                      technique: _catalogFor(c.techniques[i]),
                      isLast: i == c.techniques.length - 1,
                    ),
                ],
              ),
            ),
            if (c.note.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              KCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const KLabel('Notitie'),
                    const SizedBox(height: 6),
                    Text(c.note, style: AppText.body),
                  ],
                ),
              ),
            ],
            if (c.videoUrls.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              CollapsibleVideoList(urls: c.videoUrls),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.name,
    required this.technique,
    required this.isLast,
  });

  final int index;
  final String name;
  final Technique? technique;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final t = technique;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColor.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '${index + 1}',
                  style: AppText.bodyStrong.copyWith(color: AppColor.coralSoft),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AppColor.surfaceHighest),
                ),
            ],
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14, top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppText.bodyStrong),
                  if (t != null)
                    Text(
                      [
                        t.category,
                        if (t.learningStatus != LearningStatus.none)
                          t.learningStatus.label,
                      ].join(' · '),
                      style: AppText.caption,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
