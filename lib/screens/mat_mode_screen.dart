// mat_mode_screen.dart — live sessie op de mat
//
// Dit scherm is een "view" over MatSessionController: alle data (blokken,
// glucose, timers) leeft in de controller, niet hier. Zo blijft de sessie
// gewoon doorlopen (klok, Nightscout-polling, alarm) als je dit scherm
// verlaat om naar een ander tabblad te gaan — zie ShellScreen voor de
// permanente balk die de actieve sessie laat zien en heropent.
//
// Twee standen:
//   list  — vink aan wat je vanavond hebt gedaan; voeg zelf technieken,
//           warming-up of sparren toe (met eigen duur/rondes/notitie).
//           technieken staan in hun eigen groep en zijn te verslepen;
//           warming-up/sparren staan in een eigen groep eronder.
//   focus — beoordeel/noteer één blok.

import 'package:flutter/material.dart';
import '../models/glucose.dart';
import '../models/technique.dart';
import '../models/training_session.dart';
import '../state/mat_session_controller.dart';
import '../services/system_bars.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic.dart';
import '../widgets/block_widgets.dart';
import '../widgets/manual_glucose.dart';
import '../widgets/nutrition_log.dart';
import '../widgets/inline_video_player.dart';

export '../models/training_session.dart' show BlockKind;
export '../widgets/block_widgets.dart' show TechniqueEntry;

// ───────────────────────────── scherm ───────────────────────────────────────

class MatModeScreen extends StatefulWidget {
  final MatSessionController controller;

  const MatModeScreen({super.key, required this.controller});

  @override
  State<MatModeScreen> createState() => _MatModeScreenState();
}

class _MatModeScreenState extends State<MatModeScreen> {
  final _listScroll = ScrollController();

  MatSessionController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    // Op de mat: volledig scherm, systeemknoppen pas na een veeg.
    SystemBars.enterSession();
  }

  @override
  void dispose() {
    SystemBars.exitSession();
    _listScroll.dispose();
    super.dispose();
  }

  /// Scrolt de lijst naar beneden zodat het toevoegformulier (of de zojuist
  /// toegevoegde rij) niet buiten beeld blijft staan onder de "+"-knop.
  void _scrollToBottomOfList() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_listScroll.hasClients) return;
      _listScroll.animateTo(
        _listScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Verwijderen kan altijd — met een "ongedaan maken" voor als het per
  /// ongeluk gebeurde.
  void _removeBlock(int i) {
    final removed = _c.blocks[i];
    _c.removeBlockAt(i);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${removed.name} verwijderd'),
        action: SnackBarAction(
          label: 'Ongedaan maken',
          onPressed: () => _c.insertBlockAt(i, removed),
        ),
      ),
    );
  }

  void _openNutritionSheet() {
    showNutritionSheet(
      context,
      presets: _c.appController.profile?.carbPresets ?? const [],
      entries: _c.nutrition,
      onPick: _c.logNutrition,
      onRemove: _c.removeNutrition,
    );
  }

  Future<void> _confirmStop() async {
    if (_c.saving) return;
    final noteController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text('Sessie afsluiten?', style: AppText.cardTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Je beoordelingen en notities worden opgeslagen.',
              style: AppText.body.copyWith(color: AppColor.inkMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: noteController,
              maxLines: 3,
              minLines: 2,
              style: AppText.body,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColor.surfaceRaised,
                hintText: 'Notitie over de hele training (optioneel)',
                hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'continue'),
            child: const Text('Doorgaan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            style: TextButton.styleFrom(foregroundColor: AppColor.redBright),
            child: const Text('Niet opslaan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'save'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: const Text('Afsluiten'),
          ),
        ],
      ),
    );
    if (!mounted || result == null || result == 'continue') return;

    if (result == 'discard') {
      Navigator.pop(context, false);
      return;
    }

    final ok = await _c.saveSession(noteController.text.trim());
    if (mounted) Navigator.pop(context, ok);
  }

  Future<void> _renameBlock(TechniqueEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text('Naam aanpassen', style: AppText.cardTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.body,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: .05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuleer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    setState(() => entry.name = result);
    _c.touch();
  }

  /// Video's van de gekoppelde catalogustechniek, zodat je ze ook tijdens de
  /// sessie kunt bekijken — leeg als er geen (gekoppelde) video's zijn. Komt
  /// het blok uit een combinatie (zie `comboId`), dan tellen ook de video's
  /// van die combinatie mee.
  List<String> _matchingVideoUrls(TechniqueEntry entry) {
    if (entry.kind != BlockKind.technique) return const [];
    final urls = <String>[];
    for (final t in _c.knownTechniques) {
      if (t.name.toLowerCase() == entry.name.toLowerCase()) {
        urls.addAll(t.videoUrls);
        break;
      }
    }
    if (entry.comboId != null) {
      for (final c in _c.knownCombinations) {
        if (c.id == entry.comboId) {
          urls.addAll(c.videoUrls);
          break;
        }
      }
    }
    return urls;
  }

  /// Technieken die vandaag gepland staan, die je bij "de eerstvolgende
  /// training" wilde oefenen, of al bezig zijn — een herinnering bovenaan de
  /// sessie, los van wat je er al wel/niet aan hebt toegevoegd.
  List<Technique> _todaysPlanning() {
    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;
    return _c.knownTechniques
        .where(
          (t) =>
              t.practiceNext ||
              (t.plannedFor != null && isToday(t.plannedFor!)) ||
              t.learningStatus == LearningStatus.learning,
        )
        .toList();
  }

  /// Voegt een geplande techniek toe als blok — tikken op een techniek die
  /// al in de sessie staat opent die in plaats van hem dubbel toe te voegen.
  void _addPlannedTechnique(Technique t) {
    final existingIdx = _c.blocks.indexWhere(
      (b) => b.name.toLowerCase() == t.name.toLowerCase(),
    );
    if (existingIdx != -1) {
      _c.openFocus(existingIdx);
      return;
    }
    _c.addBlock(
      TechniqueEntry(
        kind: BlockKind.technique,
        name: t.name,
        meta: t.category,
        transition: t.transition,
        catalogLinked: true,
      ),
      openAfter: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColor.bg,
        // Bovenkant niet inspringen: de glucosebalk loopt zelf door tot de
        // rand (ook achter de camera-uitsparing) en zet zijn inhoud eronder.
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              Column(
                children: [
                  GlucoseBand(
                    reading: _c.reading,
                    elapsed: _c.elapsed,
                    isPaused: _c.isPaused,
                    showPauseButton: _c.showPauseButton,
                    onStop: _confirmStop,
                    onMinimize: () => Navigator.pop(context),
                    onTogglePause: _c.isPaused ? _c.resume : _c.pause,
                    onEnterReading: _c.isFinger
                        ? () => _c.recordManualReading(context)
                        : null,
                  ),
                  Expanded(
                    child: _c.mode == 'list' ? _buildList() : _buildFocus(),
                  ),
                ],
              ),
              if (_c.saving)
                Container(
                  color: Colors.black.withValues(alpha: .55),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    final doneCount = _c.coveredIdx.length;
    final blocks = _c.blocks;
    final techniques = <int>[
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].kind == BlockKind.technique) i,
    ];
    final others = <int>[
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].kind != BlockKind.technique) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: KCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const KDot(color: AppColor.coral, size: 8),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _c.title,
                        style: AppText.cardTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    KPill(
                      text: '$doneCount / ${blocks.length} behandeld',
                      color: AppColor.ice,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  child: LinearProgressIndicator(
                    value: blocks.isEmpty ? 0 : doneCount / blocks.length,
                    minHeight: 4,
                    backgroundColor: AppColor.surfaceHighest,
                    valueColor: const AlwaysStoppedAnimation(AppColor.coral),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vink aan wat je hebt gedaan. Tik op de naam om te beoordelen en te noteren.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            controller: _listScroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (_c.isFinger) ...[
                FingerHistoryStrip(
                  entries: _c.fingerEntries,
                  onTapEntry: (e) => _c.editFingerEntry(context, e),
                ),
                const SizedBox(height: 14),
              ],
              NutritionQuickButton(
                count: _c.nutrition.length,
                onTap: _openNutritionSheet,
              ),
              if (_todaysPlanning().isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('VANDAAG OP DE PLANNING', style: AppText.overline.copyWith(color: AppColor.ink)),
                const SizedBox(height: 10),
                for (final t in _todaysPlanning())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => _addPlannedTechnique(t),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: AppColor.tealWash,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.name,
                                style: AppText.bodyStrong.copyWith(
                                  color: AppColor.tealBright,
                                ),
                              ),
                            ),
                            if (blocks.every(
                              (b) => b.name.toLowerCase() != t.name.toLowerCase(),
                            ))
                              const Icon(
                                Icons.add,
                                size: 18,
                                color: AppColor.tealBright,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 18),
              Text('TECHNIEKEN', style: AppText.overline.copyWith(color: AppColor.ink)),
              const SizedBox(height: 10),
              if (techniques.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Nog geen technieken toegevoegd.',
                    style: AppText.caption,
                  ),
                )
              else
                // Geen Dismissible hier: swipe-to-delete botst met de
                // sleepgebaren van ReorderableListView (de swipe werd erdoor
                // geslikt, waardoor verwijderen leek te zijn stukgegaan).
                // Verwijderen gaat hier via het kruisje in de rij.
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: _c.reorderTechnique,
                  children: [
                    for (var pos = 0; pos < techniques.length; pos++)
                      Padding(
                        key: ValueKey(blocks[techniques[pos]].id),
                        padding: EdgeInsets.zero,
                        child: _BlockRow(
                          entry: blocks[techniques[pos]],
                          onToggle: () => _c.toggleCovered(techniques[pos]),
                          onOpen: () => _c.openFocus(techniques[pos]),
                          onDelete: () => _removeBlock(techniques[pos]),
                          dragHandle: ReorderableDragStartListener(
                            index: pos,
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.drag_handle,
                                size: 18,
                                color: AppColor.inkFaint,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 18),
              Text('WARMING-UP & SPARREN', style: AppText.overline.copyWith(color: AppColor.ink)),
              const SizedBox(height: 10),
              if (others.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Nog geen warming-up of sparren toegevoegd.',
                    style: AppText.caption,
                  ),
                )
              else
                for (final i in others) _dismissibleRow(index: i),
              if (_c.adding)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BlockAddForm(
                    onSubmit: _c.addBlock,
                    onCancel: () => _c.setAdding(false),
                    existingTechniques: _c.knownTechniques,
                    existingCombinations: _c.knownCombinations,
                  ),
                )
              else
                AddBlockButton(
                  onTap: () {
                    _c.setAdding(true);
                    _scrollToBottomOfList();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dismissibleRow({Key? key, required int index, Widget? dragHandle}) {
    final entry = _c.blocks[index];
    return Dismissible(
      key: key ?? ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _removeBlock(index),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: AppColor.red.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Icon(Icons.delete_outline, color: AppColor.redBright),
      ),
      child: _BlockRow(
        entry: entry,
        onToggle: () => _c.toggleCovered(index),
        onOpen: () => _c.openFocus(index),
        dragHandle: dragHandle,
      ),
    );
  }

  Widget _buildFocus() {
    final covered = _c.coveredIdx;
    final pos = covered.indexOf(_c.focusIndex);
    final t = _c.blocks[_c.focusIndex];
    final total = covered.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              InkWell(
                onTap: _c.backToList,
                child: Text(
                  '← Lijst',
                  style: AppText.overline.copyWith(
                    color: AppColor.coralSoft,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${pos >= 0 ? pos + 1 : 0} / $total',
                style: AppText.overline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : (pos + 1) / total,
                    minHeight: 3,
                    backgroundColor: AppColor.line,
                    valueColor: const AlwaysStoppedAnimation(AppColor.coral),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: _FocusCard(
              key: ValueKey(t.id),
              entry: t,
              videoUrls: _matchingVideoUrls(t),
              onRename: () => _renameBlock(t),
              onRate: (r) {
                t.rating = r;
                _c.touch();
              },
              onNote: (n) {
                t.note = n;
                _c.touch();
              },
              onMinutesChanged: (m) {
                t.minutes = m;
                _c.touch();
              },
              onRestrictionsChanged: (r) {
                t.roundRestrictions = r;
                _c.touch();
              },
              onRoundsChanged: (m, g) {
                t.roundMinutes = m;
                t.roundGoals = g;
                _c.touch();
              },
              onGoalsChanged: (g) {
                t.goals = g;
                _c.touch();
              },
              onRestChanged: (r) {
                t.restSeconds = r;
                _c.touch();
              },
              onLoggedAtChanged: (at) {
                t.loggedAt = at;
                _c.touch();
              },
              onPrev: _c.prevFocus,
              onNext: _c.nextFocus,
              isLast: pos == total - 1,
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────── rij in de lijstweergave ──────────────────────────────

class _BlockRow extends StatelessWidget {
  final TechniqueEntry entry;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final Widget? dragHandle;
  final VoidCallback? onDelete;
  const _BlockRow({
    required this.entry,
    required this.onToggle,
    required this.onOpen,
    this.dragHandle,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: entry.covered ? AppColor.tealWash : AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border(
          left: BorderSide(
            color: entry.covered
                ? AppColor.coralSoft
                : kBlockKindAccent[entry.kind]!.withValues(alpha: .5),
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: entry.covered ? AppColor.coralSoft : Colors.transparent,
                border: Border.all(
                  color: entry.covered ? AppColor.coralSoft : AppColor.inkFaint,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: entry.covered
                  ? const Icon(Icons.check, size: 14, color: AppColor.coralInk)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: AppText.cardTitle.copyWith(
                      fontSize: 16,
                      color: entry.covered ? AppColor.ink : AppColor.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(blockMetaLine(entry), style: AppText.caption),
                ],
              ),
            ),
          ),
          if (entry.note.trim().isNotEmpty)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(left: 8),
              decoration: const BoxDecoration(
                color: AppColor.ice,
                shape: BoxShape.circle,
              ),
            ),
          if (entry.kind == BlockKind.technique && entry.rating > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '★' * entry.rating,
                style: AppText.caption.copyWith(color: AppColor.amberBright),
              ),
            ),
          if (onDelete != null)
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: AppColor.inkFaint),
              ),
            ),
          ?dragHandle,
        ],
      ),
    );
  }
}

// ───────────────────── glucosebalk bovenin ──────────────────────────────────

/// Volle breedte, kleur volgt de waarde. Geen AppBar — die kan niet
/// van kleur wisselen zonder dat het schokt.
class GlucoseBand extends StatelessWidget {
  final GlucoseReading reading;
  final Duration elapsed;
  final VoidCallback onStop;
  final bool isPaused;
  final bool showPauseButton;

  /// Verlaat het scherm zonder de sessie te beëindigen — de sessie blijft
  /// op de achtergrond doorlopen en is terug te vinden via de balk
  /// bovenin op elk ander scherm.
  final VoidCallback? onMinimize;
  final VoidCallback? onTogglePause;

  /// Alleen ingevuld bij vingerprik: toont een potloodje om een nieuwe
  /// meting in te voeren.
  final VoidCallback? onEnterReading;

  const GlucoseBand({
    super.key,
    required this.reading,
    required this.elapsed,
    required this.onStop,
    this.isPaused = false,
    this.showPauseButton = false,
    this.onMinimize,
    this.onTogglePause,
    this.onEnterReading,
  });

  static const _icon = {
    Trend.up: '↑',
    Trend.slightUp: '↗',
    Trend.flat: '→',
    Trend.slightDown: '↘',
    Trend.down: '↓',
    Trend.fastDown: '↓↓',
  };

  @override
  Widget build(BuildContext context) {
    final state = glucoseStateFor(reading.mmol);
    final color = glucoseColor(state);
    final soft = AppColor.inkMuted;

    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: .12), AppColor.bg),
        border: Border(bottom: BorderSide(color: color, width: 3)),
      ),
      padding: EdgeInsets.fromLTRB(
        8,
        10 + MediaQuery.paddingOf(context).top,
        12,
        12,
      ),
      child: Row(
        children: [
          if (onMinimize != null)
            IconButton(
              tooltip: 'Minimaliseren',
              onPressed: onMinimize,
              icon: Icon(Icons.keyboard_arrow_down, color: soft),
            )
          else
            const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    reading.mmol.toStringAsFixed(1).replaceAll('.', ','),
                    style: AppText.metric.copyWith(fontSize: 34, color: color),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _icon[reading.trend]!,
                    style: AppText.cardTitle.copyWith(color: color),
                  ),
                  if (onEnterReading != null)
                    InkWell(
                      onTap: onEnterReading,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.edit, size: 16, color: soft),
                      ),
                    ),
                ],
              ),
              const KLabel('mmol/L'),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isPaused ? 'Gepauzeerd · $mm:$ss' : '$mm:$ss',
                style: AppText.cardTitle.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: isPaused ? AppColor.amber : AppColor.ink,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KClock(
                    style: AppText.overline.copyWith(color: AppColor.ink),
                  ),
                  const KLabel(' · sessie'),
                ],
              ),
            ],
              ),
            ),
          ),
          if (showPauseButton && onTogglePause != null)
            IconButton(
              tooltip: isPaused ? 'Hervatten' : 'Pauzeren',
              onPressed: onTogglePause,
              icon: Icon(
                isPaused ? Icons.play_arrow : Icons.pause,
                color: AppColor.ink,
              ),
            )
          else
            const SizedBox(width: 10),
          InkWell(
            onTap: onStop,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColor.coral,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                'Stop',
                style: AppText.bodyStrong.copyWith(color: AppColor.coralInk),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────── focuskaart: één blok beoordelen ──────────────────────

class _FocusCard extends StatelessWidget {
  final TechniqueEntry entry;
  final List<String> videoUrls;
  final VoidCallback onRename;
  final ValueChanged<int> onRate;
  final ValueChanged<String> onNote;
  final ValueChanged<int> onMinutesChanged;
  final void Function(List<int> minutes, List<List<SparGoal>> goals)
  onRoundsChanged;
  final ValueChanged<List<List<SparGoal>>> onRestrictionsChanged;
  final ValueChanged<List<SparGoal>> onGoalsChanged;
  final ValueChanged<List<int>> onRestChanged;
  final ValueChanged<DateTime> onLoggedAtChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool isLast;
  const _FocusCard({
    super.key,
    required this.entry,
    this.videoUrls = const [],
    required this.onRename,
    required this.onRate,
    required this.onNote,
    required this.onMinutesChanged,
    required this.onRoundsChanged,
    required this.onRestrictionsChanged,
    required this.onGoalsChanged,
    required this.onRestChanged,
    required this.onLoggedAtChanged,
    required this.onPrev,
    required this.onNext,
    required this.isLast,
  });

  Future<void> _pickLoggedAt(BuildContext context) async {
    final base = entry.loggedAt ?? DateTime.now();
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return;
    onLoggedAtChanged(
      DateTime(base.year, base.month, base.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTech = entry.kind == BlockKind.technique;
    final accent = kBlockKindAccent[entry.kind]!;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.name,
                        style: AppText.display,
                      ),
                    ),
                    InkWell(
                      onTap: onRename,
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 20,
                          color: AppColor.inkFaint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => _pickLoggedAt(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          blockMetaLine(entry),
                          style: AppText.body.copyWith(
                            color: AppColor.inkMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.schedule,
                        size: 14,
                        color: AppColor.inkFaint,
                      ),
                    ],
                  ),
                ),
                if (videoUrls.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  CollapsibleVideoList(urls: videoUrls),
                ],
                const SizedBox(height: 18),
                if (isTech) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.surfaceRaised,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: NumberStepper(
                      label: 'GEOEFEND',
                      value: entry.minutes,
                      suffix: ' min',
                      accent: accent,
                      onDown: () =>
                          onMinutesChanged((entry.minutes - 1).clamp(0, 180)),
                      onUp: () =>
                          onMinutesChanged((entry.minutes + 1).clamp(0, 180)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('HOE GING HET?', style: AppText.overline),
                  const SizedBox(height: 12),
                  StarRow(rating: entry.rating, onRate: onRate),
                ] else if (entry.kind == BlockKind.warmup)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.surfaceRaised,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: NumberStepper(
                      label: 'DUUR',
                      value: entry.minutes,
                      suffix: ' min',
                      accent: accent,
                      onDown: () =>
                          onMinutesChanged((entry.minutes - 2).clamp(0, 180)),
                      onUp: () =>
                          onMinutesChanged((entry.minutes + 2).clamp(0, 180)),
                    ),
                  )
                else ...[
                  Text('RONDES', style: AppText.overline),
                  const SizedBox(height: 10),
                  RoundsEditor(
                    roundMinutes: entry.roundMinutes,
                    roundGoals: entry.roundGoals,
                    restSeconds: entry.restSeconds,
                    roundRestrictions: entry.roundRestrictions,
                    onRestrictionsChanged: onRestrictionsChanged,
                    accent: accent,
                    onChanged: onRoundsChanged,
                    onRestChanged: onRestChanged,
                  ),
                  const SizedBox(height: 18),
                  Text('ALGEMENE DOELEN', style: AppText.overline),
                  const SizedBox(height: 10),
                  GoalsEditor(goals: entry.goals, onChanged: onGoalsChanged),
                ],
                const SizedBox(height: 14),
                NoteField(
                  value: entry.note,
                  onChanged: onNote,
                  hint: 'Notitie bij ${kBlockKindNoun[entry.kind]}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: OutlinedButton(
                  onPressed: onPrev,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: AppColor.surfaceHighest),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: AppColor.inkMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: Text(isLast ? 'Terug naar lijst' : 'Volgende'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
