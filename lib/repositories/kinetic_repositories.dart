// kinetic_repositories.dart: Supabase-toegang voor profiel, wedstrijden,
// technieken, sessies en vingerprikwaarden. Alle tabellen bestaan al en
// hebben RLS (auth.uid() = user_id); hier wordt geen schema aangepast.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/competition.dart';
import '../models/glucose.dart';
import '../models/kinetic_profile.dart';
import '../models/library.dart';
import '../models/planned_training.dart';
import '../models/technique.dart';
import '../models/training_session.dart';
import '../services/nightscout_credentials.dart';

class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  /// Leest het profiel, of maakt een minimaal profiel aan (alle andere
  /// kolommen krijgen hun database-default).
  Future<KineticProfile> getOrCreate(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row != null) return _withLocalToken(KineticProfile.fromJson(row));
    try {
      await _client.from('profiles').insert({'id': userId});
    } on PostgrestException catch (e) {
      // Vlak na inloggen is de auth-context soms nog niet doorgedrongen (RLS
      // 42501); één korte herkansing lost dat op.
      if (e.code != '42501') rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _client.from('profiles').insert({'id': userId});
    }
    return KineticProfile(id: userId);
  }

  Future<KineticProfile> _withLocalToken(KineticProfile p) async {
    if (p.nightscoutToken.trim().isNotEmpty) return p;
    final local = await NightscoutCredentials.read();
    if (local == null || local.isEmpty) return p;
    return p.copyWith(nightscoutToken: local);
  }

  /// Werkt alleen de opgegeven kolommen bij; de rest van het profiel blijft
  /// precies zoals het was.
  Future<void> updateFields(String userId, Map<String, dynamic> fields) async {
    await _client
        .from('profiles')
        .update({
          ...fields,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', userId);
  }
}

class CompetitionRepository {
  CompetitionRepository(this._client);
  final SupabaseClient _client;

  /// Wedstrijden vanaf vandaag, eerstvolgende eerst.
  Future<List<Competition>> upcoming(String userId) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day).toUtc();
    final rows = await _client
        .from('competitions')
        .select()
        .eq('user_id', userId)
        .gte('starts_at', from.toIso8601String())
        .order('starts_at');
    return (rows as List)
        .map((r) => Competition.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Alle wedstrijden (agenda + historie), nieuwste eerst.
  Future<List<Competition>> all(String userId) async {
    final rows = await _client
        .from('competitions')
        .select()
        .eq('user_id', userId)
        .order('starts_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((r) => Competition.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> setTargetWeight(String id, double? kg) async {
    await _client
        .from('competitions')
        .update({
          'target_weight_kg': kg,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }
}

class TechniqueRepository {
  TechniqueRepository(this._client);
  final SupabaseClient _client;

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

  Future<Technique> create(String userId, String name, String category) async {
    final row = await _client
        .from('techniques')
        .insert({'user_id': userId, 'name': name, 'category': category})
        .select()
        .single();
    return Technique.fromJson(row);
  }

  /// Eigen kopie van een bibliotheektechniek (bij focus of +1 rep).
  Future<Technique> createFromLibrary(String userId, LibraryTechnique lib) async {
    final row = await _client
        .from('techniques')
        .insert({
          'user_id': userId,
          'name': lib.name,
          'category': lib.category,
          'description': lib.description,
          'transition': lib.category == 'Strike' ? '' : lib.transition,
          'video_urls': lib.videoUrls,
          'tags': lib.tags.take(20).toList(),
          'library_id': lib.id,
        })
        .select()
        .single();
    return Technique.fromJson(row);
  }

  /// Voegt een update met [reps] herhalingen toe aan de bestaande historie
  /// (zelfde formaat als de oude app: {at, rating, note, positions}).
  Future<Technique> addReps(String id, int reps, DateTime at) async {
    final row = await _client.from('techniques').select('updates').eq('id', id).single();
    final updates = [...((row['updates'] as List?) ?? const [])];
    updates.add({
      'at': at.toUtc().toIso8601String(),
      'rating': 0,
      'note': '',
      'positions': [
        {'position': '', 'rating': 0, 'reps': reps, 'went_well': '', 'to_improve': ''},
      ],
    });
    final saved = await _client
        .from('techniques')
        .update({'updates': updates, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .select()
        .single();
    return Technique.fromJson(saved);
  }

  /// "Focus in Sessie" aan = focus_mode 'next' (eerstvolgende training),
  /// zoals de oude app het ook opsloeg.
  Future<void> setFocus(String id, bool on) async {
    await _client
        .from('techniques')
        .update({
          'focus_mode': on ? 'next' : 'none',
          'practice_next': false,
          'focus_trainings_left': null,
          'focus_until': null,
          'focus_started_at': on ? DateTime.now().toUtc().toIso8601String() : null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }
}

class SessionRepository {
  SessionRepository(this._client);
  final SupabaseClient _client;

  Future<List<TrainingSession>> listForUser(String userId) async {
    final rows = await _client
        .from('training_sessions')
        .select()
        .eq('user_id', userId)
        .order('started_at', ascending: false)
        .limit(300);
    return (rows as List)
        .map((r) => TrainingSession.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<TrainingSession> create(TrainingSession s, String userId) async {
    final row = await _client
        .from('training_sessions')
        .insert(s.toInsertJson(userId))
        .select()
        .single();
    return TrainingSession.fromJson(row);
  }
}

/// Handmatige (vingerprik)waarden in `glucose_entries`.
class GlucoseEntryRepository {
  GlucoseEntryRepository(this._client);
  final SupabaseClient _client;

  Future<List<GlucosePoint>> since(String userId, DateTime from) async {
    final rows = await _client
        .from('glucose_entries')
        .select('mmol, at')
        .eq('user_id', userId)
        .gte('at', from.toUtc().toIso8601String())
        .order('at');
    return [
      for (final r in rows as List)
        GlucosePoint(
          DateTime.parse(r['at'] as String).toLocal(),
          (r['mmol'] as num).toDouble(),
        ),
    ];
  }

  Future<void> add(String userId, double mmol, DateTime at) async {
    await _client.from('glucose_entries').insert({
      'user_id': userId,
      'mmol': double.parse(mmol.toStringAsFixed(1)),
      'at': at.toUtc().toIso8601String(),
    });
  }
}


/// De gedeelde bibliotheek (alleen-lezen voor ingelogde gebruikers).
class LibraryRepository {
  LibraryRepository(this._client);
  final SupabaseClient _client;

  Future<List<LibraryTechnique>> techniques() async {
    final rows = await _client.from('technique_library').select().order('name');
    return (rows as List)
        .map((r) => LibraryTechnique.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}

class PlannedTrainingRepository {
  PlannedTrainingRepository(this._client);
  final SupabaseClient _client;

  /// Geplande trainingen vanaf het begin van vandaag.
  Future<List<PlannedTraining>> upcoming(String userId, DateTime from) async {
    final rows = await _client
        .from('planned_trainings')
        .select()
        .eq('user_id', userId)
        .gte('starts_at', from.toUtc().toIso8601String())
        .order('starts_at')
        .limit(20);
    return (rows as List)
        .map((r) => PlannedTraining.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
