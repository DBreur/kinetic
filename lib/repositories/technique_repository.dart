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

  /// Zet de focus (of wist hem met [FocusMode.none]). practice_next volgt
  /// mee, voor andere apps die alleen dat veld kennen.
  Future<void> setFocus(
    String id,
    FocusMode mode, {
    int? trainingsLeft,
    DateTime? until,
  }) async {
    await _client
        .from('techniques')
        .update({
          'focus_mode': mode.name,
          'focus_trainings_left': mode == FocusMode.count
              ? trainingsLeft
              : null,
          'focus_until': mode == FocusMode.until
              ? until?.toUtc().toIso8601String()
              : null,
          'focus_started_at': mode == FocusMode.none
              ? null
              : DateTime.now().toUtc().toIso8601String(),
          'practice_next': mode != FocusMode.none,
        })
        .eq('id', id);
  }

  /// Na een opgeslagen training: alleen de technieken die je écht oefende
  /// tellen af (eerstvolgende → klaar, aantal → één minder).
  Future<void> consumeFocus(List<Technique> practiced) async {
    for (final t in practiced) {
      if (t.focusMode == FocusMode.none || t.focusMode == FocusMode.until) {
        continue;
      }
      final after = t.focusAfterTraining();
      await _client
          .from('techniques')
          .update({
            'focus_mode': after.mode.name,
            'focus_trainings_left': after.left,
            'practice_next': after.mode != FocusMode.none,
          })
          .eq('id', t.id);
    }
  }

  Future<void> delete(String id) async {
    await _client.from('techniques').delete().eq('id', id);
  }
}
