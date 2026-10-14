import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/exercise.dart';

class ExerciseRepository {
  ExerciseRepository(this._client);

  final SupabaseClient _client;

  Future<List<Exercise>> listForUser(String userId) async {
    final rows = await _client
        .from('exercises')
        .select()
        .eq('user_id', userId)
        .order('name');
    return (rows as List)
        .map((r) => Exercise.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Exercise> create(Exercise exercise, String userId) async {
    final row = await _client
        .from('exercises')
        .insert(exercise.toInsertJson(userId))
        .select()
        .single();
    return Exercise.fromJson(row);
  }

  Future<Exercise> updateContent(Exercise exercise) async {
    final row = await _client
        .from('exercises')
        .update({'name': exercise.name, 'description': exercise.description})
        .eq('id', exercise.id)
        .select()
        .single();
    return Exercise.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('exercises').delete().eq('id', id);
  }
}
