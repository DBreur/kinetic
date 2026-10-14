// dashboard_config.dart — indeling van het dashboard (Vandaag): welke
// blokken in welke volgorde, welke snelle acties in welke volgorde, en of
// de lijsten in de instellingen op slot staan (niet te verslepen). Bewaard
// in profiles.dashboard; een lege of oude waarde valt terug op de
// standaardindeling, en nieuwe blokken/acties komen er vanzelf bij.

import 'package:flutter/material.dart';

enum DashSection { competition, glucose, trainingDay, quickActions, recent }

enum QuickAction {
  finger,
  meal,
  planTraining,
  techniques,
  startMat,
  startStrength,
  library,
  addCompetition,
  biometrics,
}

extension DashSectionInfo on DashSection {
  String get label => switch (this) {
    DashSection.competition => 'Wedstrijd-aftelling',
    DashSection.glucose => 'Glucose & matklaar',
    DashSection.trainingDay => 'Trainingsdag',
    DashSection.quickActions => 'Snelle acties',
    DashSection.recent => 'Laatste sessies',
  };

  IconData get icon => switch (this) {
    DashSection.competition => Icons.emoji_events_outlined,
    DashSection.glucose => Icons.monitor_heart_outlined,
    DashSection.trainingDay => Icons.event_available_outlined,
    DashSection.quickActions => Icons.bolt_outlined,
    DashSection.recent => Icons.history,
  };
}

extension QuickActionInfo on QuickAction {
  String get label => switch (this) {
    QuickAction.finger => 'Vingerprik invoeren',
    QuickAction.meal => 'Maaltijd & insuline',
    QuickAction.planTraining => 'Training plannen',
    QuickAction.techniques => 'Technieken',
    QuickAction.startMat => 'Sambo-training starten',
    QuickAction.startStrength => 'Krachttraining starten',
    QuickAction.library => "Schema's & circuits",
    QuickAction.addCompetition => 'Wedstrijd toevoegen',
    QuickAction.biometrics => 'Biometrie',
  };

  String get subtitle => switch (this) {
    QuickAction.finger => 'Handmatige meting vastleggen',
    QuickAction.meal => 'Meteen een maaltijd loggen, bolus berekenen',
    QuickAction.planTraining => 'Zet een training in je agenda',
    QuickAction.techniques => 'Worpen, klemmen & leerdoelen',
    QuickAction.startMat => 'Live sessie met glucosebewaking',
    QuickAction.startStrength => 'Kies een schema of begin leeg',
    QuickAction.library => 'Krachttraining voorbereiden',
    QuickAction.addCompetition => 'Met gewichtsdoel en aftelling',
    QuickAction.biometrics => 'Glucose-inzichten en trends',
  };

  IconData get icon => switch (this) {
    QuickAction.finger => Icons.water_drop_outlined,
    QuickAction.meal => Icons.restaurant_outlined,
    QuickAction.planTraining => Icons.edit_calendar_outlined,
    QuickAction.techniques => Icons.sports_martial_arts_outlined,
    QuickAction.startMat => Icons.sports_kabaddi_outlined,
    QuickAction.startStrength => Icons.fitness_center,
    QuickAction.library => Icons.view_list_outlined,
    QuickAction.addCompetition => Icons.emoji_events_outlined,
    QuickAction.biometrics => Icons.insights_outlined,
  };

  /// Staat standaard aan (de rest kun je zelf aanzetten).
  bool get defaultOn => switch (this) {
    QuickAction.finger ||
    QuickAction.meal ||
    QuickAction.planTraining ||
    QuickAction.techniques => true,
    _ => false,
  };
}

/// Eén regel in een lijst: wat, en of het aan staat.
class DashItem<T> {
  final T id;
  final bool enabled;
  const DashItem(this.id, this.enabled);

  DashItem<T> withEnabled(bool v) => DashItem(id, v);
}

class DashboardConfig {
  final List<DashItem<DashSection>> sections;
  final List<DashItem<QuickAction>> actions;

  /// Op slot: in de instellingen niet te verslepen (wel aan/uit te zetten).
  final bool locked;

  const DashboardConfig({
    required this.sections,
    required this.actions,
    this.locked = true,
  });

  static const standard = DashboardConfig(
    sections: [
      DashItem(DashSection.competition, true),
      DashItem(DashSection.glucose, true),
      DashItem(DashSection.trainingDay, true),
      DashItem(DashSection.quickActions, true),
      DashItem(DashSection.recent, true),
    ],
    actions: [
      DashItem(QuickAction.finger, true),
      DashItem(QuickAction.meal, true),
      DashItem(QuickAction.planTraining, true),
      DashItem(QuickAction.techniques, true),
      DashItem(QuickAction.startMat, false),
      DashItem(QuickAction.startStrength, false),
      DashItem(QuickAction.library, false),
      DashItem(QuickAction.addCompetition, false),
      DashItem(QuickAction.biometrics, false),
    ],
  );

  Iterable<DashSection> get visibleSections =>
      sections.where((s) => s.enabled).map((s) => s.id);

  Iterable<QuickAction> get visibleActions =>
      actions.where((a) => a.enabled).map((a) => a.id);

  factory DashboardConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return standard;
    return DashboardConfig(
      sections: _read(json['sections'], DashSection.values, (_) => true),
      actions: _read(json['actions'], QuickAction.values, (a) => a.defaultOn),
      locked: (json['locked'] as bool?) ?? true,
    );
  }

  /// Bewaarde volgorde, onbekende namen eruit, nieuwe (nog niet bewaarde)
  /// achteraan met hun standaardstand.
  static List<DashItem<T>> _read<T extends Enum>(
    dynamic raw,
    List<T> all,
    bool Function(T) defaultOn,
  ) {
    final result = <DashItem<T>>[];
    for (final e in (raw as List?) ?? const []) {
      if (e is! Map) continue;
      final match = all.where((v) => v.name == e['id']);
      if (match.isEmpty || result.any((r) => r.id == match.first)) continue;
      result.add(DashItem(match.first, (e['on'] as bool?) ?? true));
    }
    for (final v in all) {
      if (!result.any((r) => r.id == v)) result.add(DashItem(v, defaultOn(v)));
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'sections': [
      for (final s in sections) {'id': s.id.name, 'on': s.enabled},
    ],
    'actions': [
      for (final a in actions) {'id': a.id.name, 'on': a.enabled},
    ],
    'locked': locked,
  };

  DashboardConfig copyWith({
    List<DashItem<DashSection>>? sections,
    List<DashItem<QuickAction>>? actions,
    bool? locked,
  }) => DashboardConfig(
    sections: sections ?? this.sections,
    actions: actions ?? this.actions,
    locked: locked ?? this.locked,
  );
}
