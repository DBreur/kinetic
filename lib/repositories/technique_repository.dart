import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/technique.dart';

class TechniqueRepository {
  TechniqueRepository(this._client);

  final SupabaseClient _client;

  /// Voor andere repositories die bij dezelfde verbinding horen.
  SupabaseClient get client => _client;

  Future<List<Technique>> listForUser(String userId) async {
    final rows = await _client
        .from('techniques')
        .select()
        .eq('user_id', userId)
        .order('sort_order')
        .order('name');
    return (rows as List)
        .map((r) => Technique.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Technique> create(Technique technique, String userId) async {
    final row = await _client
        .from('techniques')
        .insert(technique.toInsertJson(userId))
        .select()
        .single();
    return Technique.fromJson(row);
  }

  Future<Technique> updateContent(Technique technique) async {
    final row = await _client
        .from('techniques')
        .update({
          'name': technique.name,
          'category': technique.category,
          'transition': technique.transition,
          'favorite': technique.favorite,
          'description': technique.description,
          'video_urls': technique.videoUrls,
          'updates': technique.updates.map((u) => u.toJson()).toList(),
          'sort_order': technique.sortOrder,
          'learning_status': technique.learningStatus.name,
          'planned_for': technique.plannedFor?.toUtc().toIso8601String(),
          'learning_goal': technique.learningGoal,
          'learning_started_at': technique.learningStartedAt
              ?.toUtc()
              .toIso8601String(),
          'ground_positions': technique.groundPositions,
        })
        .eq('id', technique.id)
        .select()
        .single();
    return Technique.fromJson(row);
  }

  /// Zet of wist "oefenen bij de eerstvolgende training".
  Future<void> setPracticeNext(String id, bool value) async {
    await _client
        .from('techniques')
        .update({'practice_next': value})
        .eq('id', id);
  }

  /// Wist "oefenen bij de eerstvolgende training" voor deze technieken
  /// (na een opgeslagen training).
  Future<void> clearPracticeNext(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('techniques')
        .update({'practice_next': false})
        .inFilter('id', ids);
  }

  Future<void> delete(String id) async {
    await _client.from('techniques').delete().eq('id', id);
  }
}
