import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/combination.dart';

class CombinationRepository {
  CombinationRepository(this._client);

  final SupabaseClient _client;

  Future<List<Combination>> listForUser(String userId) async {
    final rows = await _client
        .from('combinations')
        .select()
        .eq('user_id', userId)
        .order('name');
    return (rows as List)
        .map((r) => Combination.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Combination> create(Combination combination, String userId) async {
    final row = await _client
        .from('combinations')
        .insert(combination.toInsertJson(userId))
        .select()
        .single();
    return Combination.fromJson(row);
  }

  Future<Combination> updateContent(Combination combination) async {
    final row = await _client
        .from('combinations')
        .update({
          'name': combination.name,
          'type': combination.type.name,
          'techniques': combination.techniques,
          'note': combination.note,
          'video_urls': combination.videoUrls,
          'favorite': combination.favorite,
        })
        .eq('id', combination.id)
        .select()
        .single();
    return Combination.fromJson(row);
  }

  /// Eén combinatie opnieuw ophalen (bv. na aanpassen); null als hij
  /// inmiddels verwijderd is.
  Future<Combination?> fetch(String id) async {
    final row = await _client
        .from('combinations')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Combination.fromJson(row);
  }

  Future<Combination> setFavorite(String id, bool favorite) async {
    final row = await _client
        .from('combinations')
        .update({'favorite': favorite})
        .eq('id', id)
        .select()
        .single();
    return Combination.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('combinations').delete().eq('id', id);
  }
}
