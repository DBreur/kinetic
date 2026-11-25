// seed_data.dart: realistische nepdata voor widget-tests en de
// design-screenshots (tool/design_shots_test.dart). Geen Supabase nodig.

import 'dart:math' as math;

import 'package:kinetic/core/meal_impact.dart';
import 'package:kinetic/models/competition.dart';
import 'package:kinetic/models/food_log_entry.dart';
import 'package:kinetic/models/food_preset.dart';
import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/models/kinetic_profile.dart';
import 'package:kinetic/models/library.dart';
import 'package:kinetic/models/planned_training.dart';
import 'package:kinetic/models/technique_system.dart';
import 'package:kinetic/models/technique.dart';
import 'package:kinetic/models/training_session.dart';
import 'package:kinetic/models/weigh_in.dart';
import 'package:kinetic/services/heart_rate_source.dart';
import 'package:kinetic/core/sparring_timer.dart';
import 'package:kinetic/state/kinetic_store.dart';

final seedNow = DateTime(2026, 11, 24, 17, 50);

class FixedHeartRate implements HeartRateSource {
  FixedHeartRate(this.bpm);
  @override
  int bpm;
  @override
  bool get isSimulated => true;
  @override
  void update(SparringPhase? phase, DateTime now) {}
}

/// Store met seed-data. [clock] is aanpasbaar zodat tests tijd kunnen laten
/// verstrijken.
/// Een stuk van de echte bibliotheek (technique_library).
const seedLibrary = [
  LibraryTechnique(id: 'harai-goshi', name: 'Harai Goshi', category: 'Takedown', subcategory: 'Throw', disciplines: ['judo', 'sambo'], difficulty: 2, description: 'Breek de balans naar voren-rechts, laad de heup en veeg het bovenbeen weg.'),
  LibraryTechnique(id: 'seoi-nage', name: 'Seoi Nage', category: 'Takedown', subcategory: 'Throw', disciplines: ['judo', 'sambo'], difficulty: 2, description: 'Draai in onder de schouder en werp over je rug.'),
  LibraryTechnique(id: 'uchi-mata', name: 'Uchi Mata', category: 'Takedown', subcategory: 'Throw', disciplines: ['judo', 'sambo'], difficulty: 3, description: 'Binnenkant-dijworp vanuit een sterke kraaggreep.'),
  LibraryTechnique(id: 'single-leg', name: 'Single leg takedown', category: 'Takedown', subcategory: 'Takedown', disciplines: ['wrestling', 'mma', 'sambo'], difficulty: 1, description: 'Niveauwissel, pak een been en ren de hoek om.'),
  LibraryTechnique(id: 'jab', name: 'Jab', category: 'Strike', subcategory: 'Punch', disciplines: ['boxing', 'mma', 'kickboxing'], difficulty: 1, strikeCode: '1', description: 'Snelle rechte stoot met de voorste hand.'),
  LibraryTechnique(id: 'liver-hook', name: 'Liver hook', category: 'Strike', subcategory: 'Punch', disciplines: ['boxing', 'mma'], difficulty: 2, description: 'Korte hoek met links op de lever, knie licht gebogen.'),
  LibraryTechnique(id: 'low-kick', name: 'Low calf kick', category: 'Strike', subcategory: 'Kick', disciplines: ['kickboxing', 'muay_thai', 'mma'], difficulty: 1, description: 'Trap met het scheenbeen op de kuit van het voorste been.'),
  LibraryTechnique(id: 'armbar-guard', name: 'Armbar from guard', category: 'Submission', subcategory: 'Armlock', disciplines: ['bjj', 'sambo', 'judo'], difficulty: 1, description: 'Heup omhoog, been over het hoofd, knieen samen.'),
  LibraryTechnique(id: 'rolling-kneebar', name: 'Rolling kneebar', category: 'Submission', subcategory: 'Leglock', disciplines: ['sambo', 'bjj'], difficulty: 3, description: 'Kani basami-achtige entry, rol en klem de knie tegen je heup.'),
  LibraryTechnique(id: 'rnc', name: 'Rear naked choke', category: 'Submission', subcategory: 'Choke', disciplines: ['bjj', 'mma'], difficulty: 1, description: 'Arm onder de kin, hand op de biceps, hoofd erachter.'),
  LibraryTechnique(id: 'flower-sweep', name: 'Flower sweep', category: 'Overig', subcategory: 'Sweep', disciplines: ['bjj'], difficulty: 1, description: 'Arm en been aan dezelfde kant pakken, slinger en rol.'),
  LibraryTechnique(id: 'toreando', name: 'Toreando pass', category: 'Overig', subcategory: 'Pass', disciplines: ['bjj'], difficulty: 1, description: 'Pak de knieen, duw de benen opzij en loop eromheen.'),
  LibraryTechnique(id: 'kesa-gatame', name: 'Kesa gatame', category: 'Overig', subcategory: 'Control', disciplines: ['judo', 'sambo'], difficulty: 1, description: 'Zit naast de tegenstander, arm onder je oksel.'),
  LibraryTechnique(id: 'sprawl', name: 'Sprawl', category: 'Overig', subcategory: 'Defense', disciplines: ['wrestling', 'mma'], difficulty: 1, description: 'Heupen naar de mat, benen naar achteren.'),
];

KineticStore seededStore({
  DateTime Function()? clock,
  double latestMmol = 6.5,
  Trend trend = Trend.flat,
  int heartRate = 164,
  bool darkMode = true,
}) {
  final store = KineticStore(
    clock: clock ?? () => seedNow,
    heartRateSource: FixedHeartRate(heartRate),
    enableWakelock: false,
  );
  final now = (clock ?? () => seedNow)();
  final history = <GlucosePoint>[
    for (var i = 287; i >= 1; i--)
      GlucosePoint(
        now.subtract(Duration(minutes: 5 * i + 2)),
        double.parse((7.0 + 1.9 * math.sin(i / 14) + 0.8 * math.sin(i / 4.3)).toStringAsFixed(1)),
      ),
    GlucosePoint(now.subtract(const Duration(minutes: 2)), latestMmol),
  ];
  store.seedForPreview(
    email: 'atleet@example.com',
    profile: const KineticProfile(
      id: 'user-1',
      dexcomUsername: 'atleet',
      weightKg: 78.4,
      trainingLimit: 5.0,
      foodPresets: [
        FoodPreset(singular: 'Appel', plural: 'Appels', carbs: 16, unitAmount: 135, unitLabel: 'g'),
        FoodPreset(singular: 'Glas melk', plural: 'Glazen melk', carbs: 4, unitAmount: 80, unitLabel: 'ml'),
        FoodPreset(singular: 'Banaan', plural: 'Bananen', carbs: 23),
      ],
      trainingPresets: [
        FoodPreset(singular: 'Dextro', plural: "Dextro's", carbs: 3),
        FoodPreset(singular: 'Sportdrank', plural: 'Sportdranken', carbs: 30, unitAmount: 500, unitLabel: 'ml'),
      ],
    ),
    glucose: GlucoseSnapshot(
      reading: GlucoseReading(latestMmol, trend, now.subtract(const Duration(minutes: 2))),
      history: history,
    ),
    waterMl: 3200,
    darkMode: darkMode,
    library: seedLibrary,
    plannedTrainings: [
      PlannedTraining(
        id: 'p1',
        startsAt: DateTime(now.year, now.month, now.day, 18, 30),
        kind: TrainingKind.combatSambo,
        title: 'Combat Sambo',
        location: 'Dojo Noord',
        durationMinutes: 75,
        techniqueIds: const ['harai-goshi'],
      ),
    ],
    systems: [
      TechniqueSystem(
        id: 'sys1',
        name: 'Clinch naar worp',
        notes: 'Vanuit over-under naar heupworp of single leg.',
        nodes: const [
          SystemNode(id: 'n1', label: 'Clinch (over-under)'),
          SystemNode(id: 'n2', label: 'Harai Goshi', kind: SystemNodeKind.technique),
          SystemNode(id: 'n3', label: 'Single leg', kind: SystemNodeKind.technique),
          SystemNode(id: 'n4', label: 'Kesa gatame', kind: SystemNodeKind.finish),
        ],
        edges: const [
          SystemEdge(from: 'n1', to: 'n2'),
          SystemEdge(from: 'n1', to: 'n3'),
          SystemEdge(from: 'n2', to: 'n4'),
          SystemEdge(from: 'n3', to: 'n4'),
        ],
        createdAt: now.subtract(const Duration(days: 3)),
      ),
    ],
    food: [
      FoodLogEntry(id: 'f3', at: now.subtract(const Duration(hours: 2)), description: 'Rijst met kip', carbs: 70, protein: 45, fat: 14, insulinUnits: 5, context: MealContext.recovery, mmol: 7.1),
      FoodLogEntry(id: 'f2', at: now.subtract(const Duration(hours: 6)), description: 'Banaan + Dextrose Gel', carbs: 45, protein: 2, fat: 1, context: MealContext.preTraining, mmol: 6.2),
      FoodLogEntry(id: 'f1', at: now.subtract(const Duration(hours: 10)), description: 'Havermout, kwark, noten', carbs: 50, protein: 98, fat: 37, insulinUnits: 4.5, context: MealContext.recovery, mmol: 6.8),
    ],
    weighIns: [
      for (var i = 0; i < 8; i++)
        WeighIn(id: 'w$i', measuredAt: now.subtract(Duration(days: i * 3, hours: 10)), weightKg: double.parse((78.4 + i * 0.25).toStringAsFixed(1))),
    ],
    competitions: [
      Competition(
        id: 'c1',
        name: 'Combat Sambo Open',
        startsAt: DateTime(now.year, now.month, now.day).add(const Duration(days: 18, hours: 9)),
        discipline: 'combat',
        location: 'Sporthal Noord',
        weightClass: '-77 kg',
        weightLimitType: WeightLimitType.under,
        weightLimitKg: 77.0,
      ),
    ],
    allCompetitions: [
      Competition(
        id: 'c1',
        name: 'Combat Sambo Open',
        startsAt: DateTime(now.year, now.month, now.day).add(const Duration(days: 18, hours: 9)),
        discipline: 'combat',
        location: 'Sporthal Noord',
        weightClass: '-77 kg',
        weightLimitType: WeightLimitType.under,
        weightLimitKg: 77.0,
      ),
      Competition(
        id: 'c0',
        name: 'NK Combat Sambo',
        startsAt: DateTime(now.year - 1, 11, 8, 9),
        discipline: 'combat',
        weightClass: '-77 kg',
        weightLimitType: WeightLimitType.under,
        weightLimitKg: 77.0,
        resultPlace: 1,
        resultWins: 4,
        resultLosses: 0,
      ),
    ],
    techniques: [
      Technique.fromJson({
        'id': 'harai-goshi',
        'name': 'Harai Goshi',
        'category': 'Takedown',
        'library_id': 'harai-goshi',
        'focus_mode': 'next',
        'favorite': true,
        'learning_goal': 'Heupworp vanuit clinch',
        'updates': [
          {'at': '2026-11-10T18:00:00Z', 'rating': 4, 'positions': [{'reps': 1200}]},
          {'at': '2026-11-17T18:00:00Z', 'rating': 5, 'positions': [{'reps': 1250}]},
        ],
      }),
      Technique.fromJson({
        'id': 'liver-punch',
        'name': 'Liver Punch Setup',
        'category': 'Strike',
        'focus_mode': 'next',
        'learning_goal': 'Lever',
        'updates': [
          {'at': '2026-11-12T18:00:00Z', 'rating': 4, 'positions': [{'reps': 800}]},
        ],
      }),
      Technique.fromJson({'id': 'low-kick', 'name': 'Low Calf Kick', 'category': 'Kick', 'learning_goal': 'Kuit'}),
      Technique.fromJson({'id': 'single-leg', 'name': 'Single Leg Entry', 'category': 'Takedown'}),
      Technique.fromJson({'id': 'armbar', 'name': 'Armbar', 'category': 'Submission'}),
      Technique.fromJson({'id': 'sprawl', 'name': 'Sprawl', 'category': 'Verdediging'}),
    ],
    sessions: [
      for (var d = 0; d < 6; d++)
        TrainingSession(
          id: 's$d',
          kind: d == 4 ? 'kracht' : 'sambo',
          title: d == 4 ? 'Kracht' : (d.isEven ? 'Combat sambo' : 'Sport sambo'),
          startedAt: now.subtract(Duration(days: d + 1, hours: 1)),
          durationMinutes: 60 + d * 7,
          glucoseSeries: [
            for (var i = 0; i < 12; i++)
              GlucosePoint(now.subtract(Duration(days: d + 1, hours: 1)).add(Duration(minutes: i * 6)), 7.8 - i * 0.25 + (d == 2 ? -1.5 : 0)),
          ],
          blocks: [
            {'kind': 'sparring', 'name': 'Sparring', 'rounds': 4, 'minutes': 20},
            {'kind': 'technique', 'name': 'Harai Goshi', 'covered': true, 'counts': {'success': 4, 'attempts': 7, 'countered': 1}},
          ],
        ),
    ],
  );
  return store;
}
