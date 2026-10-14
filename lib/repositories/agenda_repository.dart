import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/agenda.dart';

/// Geplande trainingen en wedstrijden (één repository: ze worden altijd
/// samen getoond in de Agenda).
class AgendaRepository {
  AgendaRepository(this._client);

  final SupabaseClient _client;

  Future<List<PlannedTraining>> trainings(String userId) async {
    final rows = await _client
        .from('planned_trainings')
        .select()
        .eq('user_id', userId)
        .order('starts_at');
    return (rows as List)
        .map((r) => PlannedTraining.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<PlannedTraining> saveTraining(
    PlannedTraining t,
    String userId,
  ) async {
    final row = t.id.isEmpty
        ? await _client
              .from('planned_trainings')
              .insert({...t.toJson(), 'user_id': userId})
              .select()
              .single()
        : await _client
              .from('planned_trainings')
              .update(t.toJson())
              .eq('id', t.id)
              .select()
              .single();
    return PlannedTraining.fromJson(row);
  }

  Future<void> deleteTraining(String id) async {
    await _client.from('planned_trainings').delete().eq('id', id);
  }

  Future<List<Competition>> competitions(String userId) async {
    final rows = await _client
        .from('competitions')
        .select()
        .eq('user_id', userId)
        .order('starts_at');
    return (rows as List)
        .map((r) => Competition.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Competition> saveCompetition(Competition c, String userId) async {
    final row = c.id.isEmpty
        ? await _client
              .from('competitions')
              .insert({...c.toJson(), 'user_id': userId})
              .select()
              .single()
        : await _client
              .from('competitions')
              .update(c.toJson())
              .eq('id', c.id)
              .select()
              .single();
    return Competition.fromJson(row);
  }

  Future<void> deleteCompetition(String id) async {
    await _client.from('competitions').delete().eq('id', id);
  }
}
