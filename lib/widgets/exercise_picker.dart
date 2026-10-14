// exercise_picker.dart — oefening kiezen bij live krachttraining, circuits,
// schema's en training achteraf aanpassen: zoeken, A–Z/Z–A, filteren op
// spiergroep(en) en door de héle lijst scrollen, elke oefening met zijn
// spierfiguurtje. Typ je een naam die niet bestaat, dan voeg je die toe als
// eigen oefening.

import 'package:flutter/material.dart';

import '../core/exercise_library.dart';
import '../models/exercise.dart';
import '../theme/kinetic_theme.dart';
import 'muscle_figure.dart';

class ExercisePicker extends StatefulWidget {
  const ExercisePicker({
    super.key,
    required this.query,
    required this.customExercises,
    required this.onPick,
    required this.onCancel,
  });

  final TextEditingController query;
  final List<Exercise> customExercises;
  final ValueChanged<String> onPick;
  final VoidCallback onCancel;

  @override
  State<ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<ExercisePicker> {
  final Set<String> _groups = {};
  bool _ascending = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColor.surface,
        border: Border.all(color: AppColor.teal.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.query,
                  style: AppText.body,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColor.surfaceRaised,
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Zoek of typ een oefening',
                    hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide.none,
                    ),
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
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.query,
            builder: (context, value, _) {
              final options = filterExercises(
                allExercises(widget.customExercises),
                query: value.text,
                groups: _groups,
                ascending: _ascending,
              );
              final typed = value.text.trim();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 300,
                    child: options.isEmpty
                        ? Center(
                            child: Text(
                              typed.isEmpty
                                  ? 'Geen oefeningen voor deze spiergroep.'
                                  : 'Niets gevonden — voeg "$typed" toe als '
                                        'eigen oefening.',
                              textAlign: TextAlign.center,
                              style: AppText.caption,
                            ),
                          )
                        : Scrollbar(
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: options.length,
                              itemBuilder: (context, i) => Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: ExerciseListTile(
                                  exercise: options[i],
                                  onTap: () => widget.onPick(options[i].name),
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.onCancel,
                          child: const Text('Annuleer'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: typed.isEmpty
                              ? null
                              : () => widget.onPick(typed),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColor.teal,
                            foregroundColor: AppColor.greenInk,
                          ),
                          child: const Text('Eigen oefening'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Eén oefening in een lijst: spierfiguurtje, naam en spiergroepen.
class ExerciseListTile extends StatelessWidget {
  const ExerciseListTile({
    super.key,
    required this.exercise,
    required this.onTap,
    this.trailing,
    this.showDescription = true,
  });

  final Exercise exercise;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showDescription;

  @override
  Widget build(BuildContext context) {
    final groups = exercise.muscleGroups;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
        decoration: BoxDecoration(
          color: AppColor.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            MuscleFigure(groups: groups),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exercise.name, style: AppText.bodyStrong),
                  if (groups.isNotEmpty)
                    Text(
                      groups.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        fontSize: 11,
                        color: AppColor.coralSoft,
                      ),
                    ),
                  if (showDescription && exercise.description.isNotEmpty)
                    Text(
                      exercise.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(fontSize: 11),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A–Z / Z–A-knop.
class SortToggle extends StatelessWidget {
  const SortToggle({
    super.key,
    required this.ascending,
    required this.onChanged,
  });

  final bool ascending;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: ascending ? 'Nu A–Z, tik voor Z–A' : 'Nu Z–A, tik voor A–Z',
      child: OutlinedButton.icon(
        onPressed: () => onChanged(!ascending),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        icon: Icon(
          ascending ? Icons.arrow_downward : Icons.arrow_upward,
          size: 16,
        ),
        label: Text(ascending ? 'A–Z' : 'Z–A'),
      ),
    );
  }
}

/// Horizontaal scrollende spiergroep-chips om op te filteren (meerdere
/// tegelijk mogelijk).
class MuscleGroupFilter extends StatelessWidget {
  const MuscleGroupFilter({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final g in kMuscleGroups)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(g),
                selected: selected.contains(g),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onToggle(g),
              ),
            ),
        ],
      ),
    );
  }
}
