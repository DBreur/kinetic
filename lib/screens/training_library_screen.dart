// training_library_screen.dart — "Bibliotheek" op de Train-pagina:
// trainingsschema's, circuits en eigen oefeningen op één plek (stond eerder
// in de instellingen). Elk tabblad praat direct met zijn eigen repository.

import 'package:flutter/material.dart';

import '../core/exercise_library.dart';
import '../models/agenda.dart' show normalizeUrl;
import '../models/exercise.dart';
import '../models/workout_template.dart';
import '../repositories/circuit_repository.dart';
import '../repositories/exercise_repository.dart';
import '../repositories/workout_template_repository.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/kinetic.dart';
import '../widgets/video_link_row.dart';
import 'circuit_edit_screen.dart';
import 'exercise_history_screen.dart';
import 'workout_template_edit_screen.dart';

enum LibraryTab { templates, circuits, exercises }

class TrainingLibraryScreen extends StatefulWidget {
  const TrainingLibraryScreen({
    super.key,
    required this.controller,
    this.initialTab = LibraryTab.templates,
  });

  final AppController controller;
  final LibraryTab initialTab;

  @override
  State<TrainingLibraryScreen> createState() => _TrainingLibraryScreenState();
}

class _TrainingLibraryScreenState extends State<TrainingLibraryScreen> {
  late LibraryTab _tab = widget.initialTab;
  late final WorkoutTemplateRepository _templateRepo;
  late final CircuitRepository _circuitRepo;
  late final ExerciseRepository _exerciseRepo;
  List<WorkoutTemplate> _templates = [];
  List<Circuit> _circuits = [];
  List<Exercise> _exercises = [];
  bool _loading = true;

  String get _userId => widget.controller.user!.id;

  @override
  void initState() {
    super.initState();
    final client = widget.controller.client!;
    _templateRepo = WorkoutTemplateRepository(client);
    _circuitRepo = CircuitRepository(client);
    _exerciseRepo = ExerciseRepository(client);
    _load();
  }

  Future<void> _load() async {
    if (widget.controller.user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        _templateRepo.listForUser(_userId),
        _circuitRepo.listForUser(_userId),
        _exerciseRepo.listForUser(_userId),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<WorkoutTemplate>;
        _circuits = results[1] as List<Circuit>;
        _exercises = results[2] as List<Exercise>;
      });
    } catch (_) {
      // Lijsten blijven leeg/oud; pull-to-refresh probeert het opnieuw.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openTemplateEditor({WorkoutTemplate? existing}) async {
    final result = await Navigator.push<WorkoutTemplateEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutTemplateEditScreen(
          controller: widget.controller,
          template: existing,
        ),
      ),
    );
    if (result != null) _load();
  }

  Future<void> _openCircuitEditor({Circuit? existing}) async {
    final result = await Navigator.push<CircuitEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CircuitEditScreen(controller: widget.controller, circuit: existing),
      ),
    );
    if (result != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'KINETIC',
              style: AppText.cardTitle.copyWith(height: 1, letterSpacing: 1.6),
            ),
            const SizedBox(height: 3),
            const KLabel('Bibliotheek'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: KSegmented<LibraryTab>(
              options: const [
                (LibraryTab.templates, "Schema's", null),
                (LibraryTab.circuits, 'Circuits', null),
                (LibraryTab.exercises, 'Oefeningen', null),
              ],
              selected: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: switch (_tab) {
                LibraryTab.templates => _templateList(),
                LibraryTab.circuits => _circuitList(),
                LibraryTab.exercises => _ExercisesTab(
                  repository: _exerciseRepo,
                  userId: _userId,
                  controller: widget.controller,
                  exercises: _exercises,
                  loading: _loading,
                  onChanged: (next) => setState(() => _exercises = next),
                ),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateList() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [
      Text(
        'Vaste oefeningen en sets (bv. "Dag 1") die je bij het starten van een '
        'krachttraining als startpunt kiest — daarna blijft alles aanpasbaar.',
        style: AppText.caption,
      ),
      const SizedBox(height: 12),
      if (!_loading && _templates.isEmpty) _empty('Nog geen schema\'s.'),
      for (final t in _templates)
        _LibraryRow(
          icon: Icons.view_list_outlined,
          title: t.name,
          subtitle:
              '${t.exercises.length} oefening${t.exercises.length == 1 ? '' : 'en'}'
              '${t.circuits.isEmpty ? '' : ' · ${t.circuits.length} circuit${t.circuits.length == 1 ? '' : 's'}'}',
          onTap: () => _openTemplateEditor(existing: t),
        ),
      const SizedBox(height: 4),
      FilledButton.icon(
        onPressed: () => _openTemplateEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nieuw schema'),
      ),
    ],
  );

  Widget _circuitList() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [
      Text(
        'Oefeningen die je in rondes doorloopt — op tijd, herhalingen of tot '
        'verzuring, met rust na elke oefening (of juist niet). Ook een '
        'warming-up is een circuit.',
        style: AppText.caption,
      ),
      const SizedBox(height: 12),
      if (!_loading && _circuits.isEmpty) _empty('Nog geen circuits.'),
      for (final c in _circuits)
        _LibraryRow(
          icon: Icons.loop,
          title: c.name,
          subtitle: c.summary,
          onTap: () => _openCircuitEditor(existing: c),
          onStart: () => widget.controller.startCircuitTraining(c),
        ),
      const SizedBox(height: 4),
      FilledButton.icon(
        onPressed: () => _openCircuitEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nieuw circuit'),
      ),
    ],
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: AppText.caption),
  );
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onStart,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Als gezet: een startknop in plaats van het pijltje.
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: KCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColor.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 20, color: AppColor.slate),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
          if (onStart != null)
            IconButton(
              tooltip: 'Start als training',
              onPressed: onStart,
              icon: const Icon(Icons.play_circle_outline),
              color: AppColor.coral,
            )
          else
            const Icon(Icons.chevron_right, color: AppColor.inkFaint),
        ],
      ),
    ),
  );
}

/// Oefeningen-tabblad: de vroegere oefeningen-modal uit de instellingen,
/// nu als volwaardige lijst.
class _ExercisesTab extends StatelessWidget {
  const _ExercisesTab({
    required this.repository,
    required this.userId,
    required this.controller,
    required this.exercises,
    required this.loading,
    required this.onChanged,
  });

  final ExerciseRepository repository;
  final String userId;
  final AppController controller;
  final List<Exercise> exercises;
  final bool loading;
  final ValueChanged<List<Exercise>> onChanged;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [
      Text(
        'Alle oefeningen die je tijdens krachttraining kunt kiezen. Tik op '
        "een oefening voor spiergroepen, een beschrijving of video's.",
        style: AppText.caption,
      ),
      const SizedBox(height: 12),
      if (loading)
        const Center(child: CircularProgressIndicator())
      else
        _ExercisesSheet(
          key: ValueKey(exercises.length),
          repository: repository,
          userId: userId,
          exercises: exercises,
          controller: controller,
          onChanged: onChanged,
        ),
    ],
  );
}

/// Modal met de eigen oefeningcatalogus — bewerken, verwijderen en
/// toevoegen. Anders dan de eetlogboek-presets (die op het profiel staan)
/// leeft dit in een eigen tabel, dus elke actie hier praat direct met de
/// repository in plaats van pas bij "Wijzigingen opslaan".
class _ExercisesSheet extends StatefulWidget {
  const _ExercisesSheet({
    super.key,
    required this.repository,
    required this.userId,
    required this.exercises,
    required this.controller,
    required this.onChanged,
  });

  final ExerciseRepository repository;
  final String userId;
  final List<Exercise> exercises;
  final AppController controller;
  final ValueChanged<List<Exercise>> onChanged;

  @override
  State<_ExercisesSheet> createState() => _ExercisesSheetState();
}

class _ExercisesSheetState extends State<_ExercisesSheet> {
  late List<Exercise> _exercises;
  bool _busy = false;
  final _query = TextEditingController();
  final Set<String> _groups = {};
  bool _ascending = true;

  @override
  void initState() {
    super.initState();
    _exercises = List.of(widget.exercises);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(_exercises);

  void _openHistory(String name) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseHistoryScreen(
          exerciseName: name,
          controller: widget.controller,
        ),
      ),
    );
  }

  Future<void> _add() async {
    final result = await showExerciseDialog(context);
    if (result == null) return;
    await _create(result);
  }

  Future<void> _create(Exercise exercise) async {
    final key = exercise.name.trim().toLowerCase();
    if (_exercises.any((e) => e.name.trim().toLowerCase() == key)) {
      _failed('"${exercise.name.trim()}" staat al in je oefeningen.');
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await widget.repository.create(exercise, widget.userId);
      setState(() {
        _exercises = [..._exercises, created];
        _busy = false;
      });
      _emit();
    } catch (_) {
      _failed('Opslaan is niet gelukt. Probeer opnieuw.');
    }
  }

  void _failed(String message) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Aanpassen — een oefening uit de vaste lijst wordt daarbij een eigen
  /// oefening (met jouw spiergroepen, beschrijving en video's).
  Future<void> _edit(Exercise exercise) async {
    final result = await showExerciseDialog(context, existing: exercise);
    if (result == null) return;
    if (!exercise.isSaved) return _create(result);
    final i = _exercises.indexWhere((e) => e.id == exercise.id);
    if (i < 0) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.updateContent(
        _exercises[i].copyWith(
          name: result.name,
          description: result.description,
          videoUrls: result.videoUrls,
          muscleGroups: result.muscleGroups,
        ),
      );
      setState(() {
        _exercises[i] = updated;
        _busy = false;
      });
      _emit();
    } catch (_) {
      _failed('Opslaan is niet gelukt. Probeer opnieuw.');
    }
  }

  Future<void> _delete(Exercise exercise) async {
    final i = _exercises.indexWhere((e) => e.id == exercise.id);
    if (i < 0) return;
    final removed = _exercises[i];
    setState(() => _exercises.removeAt(i));
    _emit();
    try {
      await widget.repository.delete(removed.id);
    } catch (_) {
      if (mounted) {
        setState(() => _exercises.insert(i, removed));
        _emit();
        _failed('Verwijderen is niet gelukt. Probeer opnieuw.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = filterExercises(
      allExercises(_exercises),
      query: _query.text,
      groups: _groups,
      ascending: _ascending,
    );
    return AbsorbPointer(
      absorbing: _busy,
      child: Opacity(
        opacity: _busy ? .6 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    style: AppText.body,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Zoek een oefening',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SortToggle(
                  ascending: _ascending,
                  onChanged: (v) => setState(() => _ascending = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MuscleGroupFilter(
              selected: _groups,
              onToggle: (g) => setState(() {
                if (!_groups.remove(g)) _groups.add(g);
              }),
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Geen oefeningen gevonden.',
                  style: AppText.caption,
                ),
              )
            else
              for (final e in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ExerciseListTile(
                    exercise: e,
                    onTap: () => _edit(e),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Voortgang',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _openHistory(e.name),
                          icon: const Icon(
                            Icons.show_chart,
                            size: 16,
                            color: AppColor.inkFaint,
                          ),
                        ),
                        if (e.isSaved)
                          IconButton(
                            tooltip: 'Verwijderen',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _delete(e),
                            icon: const Icon(
                              Icons.close,
                              size: 16,
                              color: AppColor.inkFaint,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Oefening toevoegen'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Exercise?> showExerciseDialog(
  BuildContext context, {
  Exercise? existing,
}) {
  final name = TextEditingController(text: existing?.name ?? '');
  final description = TextEditingController(text: existing?.description ?? '');
  final newVideo = TextEditingController();
  final videoUrls = List<String>.of(existing?.videoUrls ?? const []);
  final muscleGroups = <String>{...?existing?.muscleGroups};
  return showDialog<Exercise>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        void addVideo({bool askLabel = true}) {
          final url = normalizeUrl(newVideo.text);
          if (url.isEmpty) return;
          setState(() {
            videoUrls.add(url);
            newVideo.clear();
          });
          if (askLabel) editVideoLabel(c, url);
        }

        return AlertDialog(
          backgroundColor: AppColor.surface,
          title: Text(
            existing == null ? 'Oefening toevoegen' : 'Oefening aanpassen',
            style: AppText.cardTitle,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: name,
                  style: AppText.body,
                  decoration: const InputDecoration(
                    labelText: 'Naam (bv. Deadlift)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: description,
                  style: AppText.body,
                  maxLines: 5,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Beschrijving (optioneel)',
                    hintText: 'Hoe voer je hem uit, waar let je op?',
                  ),
                ),
                const SizedBox(height: 14),
                Text('Spiergroepen (optioneel)', style: AppText.caption),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in kMuscleGroups)
                      FilterChip(
                        label: Text(g),
                        selected: muscleGroups.contains(g),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() {
                          if (!muscleGroups.remove(g)) muscleGroups.add(g);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text("Video's (optioneel)", style: AppText.caption),
                const SizedBox(height: 6),
                for (var i = 0; i < videoUrls.length; i++)
                  VideoLinkRow(
                    url: videoUrls[i],
                    onRemove: () => setState(() => videoUrls.removeAt(i)),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newVideo,
                        keyboardType: TextInputType.url,
                        style: AppText.body,
                        onSubmitted: (_) => addVideo(),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Link naar video',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Video toevoegen',
                      onPressed: () => addVideo(),
                      icon: const Icon(Icons.add_link, color: AppColor.ice),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuleer'),
            ),
            FilledButton(
              onPressed: () {
                final n = name.text.trim();
                if (n.isEmpty) return;
                // Een link die nog in het veld staat telt ook mee.
                addVideo(askLabel: false);
                Navigator.pop(
                  c,
                  Exercise(
                    id: existing?.id ?? '',
                    name: n,
                    description: description.text.trim(),
                    videoUrls: videoUrls,
                    // In de volgorde van kMuscleGroups, voor een vast beeld.
                    muscleGroups: [
                      for (final g in kMuscleGroups)
                        if (muscleGroups.contains(g)) g,
                    ],
                  ),
                );
              },
              child: const Text('Opslaan'),
            ),
          ],
        );
      },
    ),
  );
}
