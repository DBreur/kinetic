import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/training_session.dart';

class SessionRepository {
  SessionRepository(this._client);

  final SupabaseClient _client;

  Future<List<TrainingSession>> listForUser(String userId) async {
    final rows = await _client
        .from('training_sessions')
        .select()
        .eq('user_id', userId)
        .order('started_at', ascending: false);
    return (rows as List)
        .map((r) => TrainingSession.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<TrainingSession> create(TrainingSession session, String userId) async {
    final row = await _client
        .from('training_sessions')
        .insert(session.toInsertJson(userId))
        .select()
        .single();
    return TrainingSession.fromJson(row);
  }

  Future<TrainingSession> updateNote(String id, String note) async {
    final row = await _client
        .from('training_sessions')
        .update({'note': note})
        .eq('id', id)
        .select()
        .single();
    return TrainingSession.fromJson(row);
  }

  /// Slaat het volledige nabewerkte resultaat op: naam, notitie,
  /// blokken/oefeningen die zijn toegevoegd, aangepast of verwijderd in het
  /// aanpassingstabblad.
  Future<TrainingSession> updateContent(TrainingSession session) async {
    final row = await _client
        .from('training_sessions')
        .update({
          'title': session.title,
          'note': session.note,
          'started_at': session.startedAt.toUtc().toIso8601String(),
          'duration_minutes': session.durationMinutes,
          'blocks': session.blocks.map((b) => b.toJson()).toList(),
          'exercises': session.exercises.map((e) => e.toJson()).toList(),
          'nutrition': session.nutrition.map((n) => n.toJson()).toList(),
        })
        .eq('id', session.id)
        .select()
        .single();
    return TrainingSession.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('training_sessions').delete().eq('id', id);
  }

  /// Elke keer dat deze oefening werd gedaan, nieuwste eerst — gebruikt om
  /// een nieuwe oefening voor te vullen (net als in Lyfta), voor het
  /// voortgangsscherm, en om het persoonlijk record te bepalen.
  Future<List<ExercisePerformance>> performanceHistory(
    String userId,
    String exerciseName, {
    int limit = 50,
  }) async {
    final rows = await _client
        .from('training_sessions')
        .select('exercises, started_at')
        .eq('user_id', userId)
        .eq('kind', 'kracht')
        .order('started_at', ascending: false)
        .limit(limit);
    final history = <ExercisePerformance>[];
    for (final row in rows as List) {
      final exercises = (row['exercises'] as List?) ?? [];
      for (final e in exercises) {
        if ((e as Map)['name'] == exerciseName) {
          final sets = (e['sets'] as List)
              .map((s) => ExerciseSet.fromJson(s as Map<String, dynamic>))
              .toList();
          if (sets.isNotEmpty) {
            history.add(
              ExercisePerformance(
                date: DateTime.parse(row['started_at'] as String).toLocal(),
                sets: sets,
              ),
            );
          }
        }
      }
    }
    return history;
  }

  /// Zelfde als [performanceHistory], maar voor alle oefeningen tegelijk —
  /// gebruikt door het voortgangsoverzicht dat alle ooit gelogde oefeningen
  /// laat zien in plaats van er één.
  Future<Map<String, List<ExercisePerformance>>> allExercisePerformances(
    String userId, {
    int limit = 200,
  }) async {
    final rows = await _client
        .from('training_sessions')
        .select('exercises, started_at')
        .eq('user_id', userId)
        .eq('kind', 'kracht')
        .order('started_at', ascending: false)
        .limit(limit);
    final byName = <String, List<ExercisePerformance>>{};
    for (final row in rows as List) {
      final exercises = (row['exercises'] as List?) ?? [];
      final date = DateTime.parse(row['started_at'] as String).toLocal();
      for (final e in exercises) {
        final name = (e as Map)['name'] as String;
        final sets = (e['sets'] as List)
            .map((s) => ExerciseSet.fromJson(s as Map<String, dynamic>))
            .toList();
        if (sets.isEmpty) continue;
        (byName[name] ??= []).add(ExercisePerformance(date: date, sets: sets));
      }
    }
    return byName;
  }
}
