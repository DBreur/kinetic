import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workout_template.dart';

class WorkoutTemplateRepository {
  WorkoutTemplateRepository(this._client);

  final SupabaseClient _client;

  Future<List<WorkoutTemplate>> listForUser(String userId) async {
    final rows = await _client
        .from('workout_templates')
        .select()
        .eq('user_id', userId)
        .order('name');
    return (rows as List)
        .map((r) => WorkoutTemplate.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<WorkoutTemplate> create(
    WorkoutTemplate template,
    String userId,
  ) async {
    final row = await _client
        .from('workout_templates')
        .insert(template.toInsertJson(userId))
        .select()
        .single();
    return WorkoutTemplate.fromJson(row);
  }

  Future<WorkoutTemplate> updateContent(WorkoutTemplate template) async {
    final row = await _client
        .from('workout_templates')
        .update({
          'name': template.name,
          'exercises': template.exercises.map((e) => e.toJson()).toList(),
          'circuits': template.circuits.map((c) => c.toJson()).toList(),
        })
        .eq('id', template.id)
        .select()
        .single();
    return WorkoutTemplate.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('workout_templates').delete().eq('id', id);
  }
}
