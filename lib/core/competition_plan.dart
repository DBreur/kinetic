// competition_plan.dart — pure logica rond wedstrijden: aftellen, de fase
// waarin je zit, de disciplineregel (sport sambo = alleen sport sambo
// trainen) en de tekst van de dagelijkse aftel-melding. Geen UI, geen
// netwerk, zodat het los te testen is.

import '../models/agenda.dart';

/// Hele kalenderdagen van [now] tot [target] (0 = vandaag, negatief =
/// voorbij). Tijdstip binnen de dag telt niet mee.
int daysUntil(DateTime target, DateTime now) {
  final a = DateTime(now.year, now.month, now.day);
  final b = DateTime(target.year, target.month, target.day);
  // Via UTC rekenen zodat een zomer-/wintertijdwissel geen dag scheelt.
  return DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
}

/// De eerstvolgende wedstrijd die nog niet voorbij is (vandaag telt mee).
Competition? nextCompetition(List<Competition> all, DateTime now) {
  final upcoming = all.where((c) => daysUntil(c.startsAt, now) >= 0).toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return upcoming.isEmpty ? null : upcoming.first;
}

enum CompetitionPhase {
  buildUp(
    'Opbouw',
    'Bouw techniek en conditie op — er is nog ruim tijd.',
  ),
  preparation(
    'Wedstrijdvoorbereiding',
    'Train wedstrijdspecifiek: sparren met wedstrijdregels en -rondes.',
  ),
  taper(
    'Toespitsen',
    'Minder volume, hoge kwaliteit. Scherp blijven, niets nieuws meer.',
  ),
  competitionWeek(
    'Wedstrijdweek',
    'Rust, gewicht in de gaten houden en je wedstrijdplan doornemen.',
  ),
  competitionDay('Wedstrijddag', 'Vandaag is het zover. Vertrouw op je training.'),
  done('Afgelopen', 'Vul je uitslag in en kijk terug op wat werkte.');

  const CompetitionPhase(this.label, this.focus);
  final String label;
  final String focus;
}

CompetitionPhase phaseFor(int days) {
  if (days < 0) return CompetitionPhase.done;
  if (days == 0) return CompetitionPhase.competitionDay;
  if (days <= 3) return CompetitionPhase.competitionWeek;
  if (days <= 14) return CompetitionPhase.taper;
  if (days <= 56) return CompetitionPhase.preparation;
  return CompetitionPhase.buildUp;
}

/// Herinnering welke sambo je moet trainen richting deze wedstrijd, of null
/// als er geen beperking is (beide disciplines).
String? disciplineReminder(Discipline d) => switch (d) {
  Discipline.sport =>
    'Sport sambo: train alleen sport sambo — worpen, houdgrepen en klemmen. '
        'Geen slagen en geen verwurgingen.',
  Discipline.combat =>
    'Combat sambo: neem slagen, trappen en verwurgingen mee in je training.',
  Discipline.both => null,
};

/// Een geplande training die niet bij de discipline van de komende
/// wedstrijd past — alleen relevant tot aan de wedstrijd.
bool conflictsWithCompetition(
  TrainingKind kind,
  DateTime trainingAt,
  Competition? competition,
) {
  if (competition == null) return false;
  if (!trainingAt.isBefore(competition.startsAt)) return false;
  return switch (competition.discipline) {
    Discipline.sport => kind == TrainingKind.combatSambo,
    Discipline.combat => kind == TrainingKind.sportSambo,
    Discipline.both => false,
  };
}

const kMotivation = [
  'Elke ronde op de mat is een ronde die je op de wedstrijd niet meer hoeft te leren.',
  'Discipline wint als motivatie op is. Trek je kimono aan.',
  'Je tegenstander traint vandaag ook.',
  'Kleine stappen, elke dag. Zo word je kampioen.',
  'Grips winnen, posities winnen, wedstrijden winnen.',
  'Moe is een gevoel, geen beslissing.',
  'Train zoals je wilt vechten.',
  'Wat je vandaag drilt, gaat straks vanzelf.',
  'Sterke worpen beginnen bij herhaling.',
  'Op de mat telt alleen wat je gedaan hebt.',
  'Respecteer het proces — de uitslag volgt.',
  'Elke val is oefening om op te staan.',
  'Focus op wat je zelf in de hand hebt: je voorbereiding.',
  'Hoe zwaarder de training, hoe lichter de wedstrijd.',
  'Je lichaam kan meer dan je hoofd denkt.',
  'Vandaag een beetje beter dan gisteren.',
  'Kampioenen worden gemaakt als niemand kijkt.',
  'Blijf hongerig, blijf scherp.',
  'Twijfel verdwijnt door voorbereiding.',
  'Laat de mat zien wie je bent.',
];

/// Motivatie die per dag (en per wedstrijd) wisselt, maar voor dezelfde dag
/// altijd dezelfde is.
String motivationFor(DateTime day, {int seed = 0}) {
  final dayNumber =
      DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  return kMotivation[(dayNumber + seed).abs() % kMotivation.length];
}

class DailyCompetitionMessage {
  final String title;
  final String body;
  const DailyCompetitionMessage(this.title, this.body);
}

/// Tekst van de dagelijkse aftel-melding voor [day].
DailyCompetitionMessage dailyMessage(Competition c, DateTime day) {
  final days = daysUntil(c.startsAt, day);
  final title = switch (days) {
    0 => 'Vandaag: ${c.name}',
    1 => 'Morgen: ${c.name}',
    _ => 'Nog $days dagen tot ${c.name}',
  };
  final rule = switch (c.discipline) {
    Discipline.sport => ' Alleen sport sambo trainen.',
    Discipline.combat => ' Train combat sambo.',
    Discipline.both => '',
  };
  final body =
      '${phaseFor(days).label} · ${motivationFor(day, seed: c.name.length)}$rule';
  return DailyCompetitionMessage(title, body);
}

/// Waar je staat t.o.v. de weging van een wedstrijd.
class WeightStatus {
  /// Bv. "Onder 79,0 kg".
  final String limitLabel;

  /// Gewicht waar je naartoe werkt: het doel, anders de grens.
  final double goalKg;

  /// Kilo's nog te gaan richting [goalKg] (positief = nog afvallen bij
  /// "onder", nog aankomen bij "boven"; 0 of minder = gehaald). Null als je
  /// huidige gewicht onbekend is.
  final double? toGoKg;

  /// Of je nu al binnen de grens zit (los van het doel).
  final bool? withinLimit;

  const WeightStatus({
    required this.limitLabel,
    required this.goalKg,
    required this.toGoKg,
    required this.withinLimit,
  });
}

/// Null als de wedstrijd geen gewichtsgrens en geen doelgewicht heeft.
WeightStatus? weightStatus(Competition c, double? currentKg) {
  final limit = c.weightLimit == WeightLimit.none ? null : c.weightLimitKg;
  final goal = c.targetWeightKg ?? limit;
  if (goal == null) return null;
  String fmt(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  final label = limit == null
      ? 'Doel ${fmt(goal)} kg'
      : '${c.weightLimit.label} ${fmt(limit)} kg';
  final over = c.weightLimit == WeightLimit.over;
  double? toGo;
  bool? within;
  if (currentKg != null) {
    toGo = over ? goal - currentKg : currentKg - goal;
    if (limit != null) {
      within = over ? currentKg >= limit : currentKg <= limit;
    }
  }
  return WeightStatus(
    limitLabel: label,
    goalKg: goal,
    toGoKg: toGo,
    withinLimit: within,
  );
}

/// De geplande training die je nu zou starten: van [before] vóór tot
/// [after] na het geplande begin, alleen sambo/kracht, niet al gestart.
/// Bij meerdere de dichtstbijzijnde.
PlannedTraining? plannedToStartNow(
  List<PlannedTraining> trainings,
  DateTime now, {
  Set<String> alreadyStarted = const {},
  Duration before = const Duration(minutes: 15),
  Duration after = const Duration(minutes: 60),
}) {
  PlannedTraining? best;
  for (final t in trainings) {
    if (alreadyStarted.contains(t.id)) continue;
    if (!(t.kind.isSambo || t.kind == TrainingKind.kracht)) continue;
    if (now.isBefore(t.startsAt.subtract(before))) continue;
    if (now.isAfter(t.startsAt.add(after))) continue;
    if (best == null ||
        t.startsAt.difference(now).abs() < best.startsAt.difference(now).abs()) {
      best = t;
    }
  }
  return best;
}
