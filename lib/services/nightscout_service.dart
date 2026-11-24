import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../models/glucose.dart';
import 'glucose_provider.dart';

class NightscoutService implements GlucoseProvider {
  NightscoutService({this.baseUrl, this.token});

  final String? baseUrl;
  final String? token;

  @override
  Future<GlucoseSnapshot> fetch({int count = 20}) async {
    final url = (baseUrl ?? AppConfig.nightscoutUrl).trim();

    if (url.isEmpty) {
      return const GlucoseSnapshot.unconfigured();
    }

    final cleanUrl = url.replaceFirst(RegExp(r'/$'), '');

    final uri = Uri.tryParse('$cleanUrl/api/v1/entries.json?count=$count');
    if (uri == null || !isSafeNightscoutUri(uri)) {
      return const GlucoseSnapshot(
        reading: null,
        history: [],
        message:
            'Nightscout-adres moet met https:// beginnen (je token wordt '
            'anders onversleuteld verstuurd).',
      );
    }

    try {
      final response = await http
          .get(
            uri,
            headers: token != null && token!.isNotEmpty
                ? {'Authorization': 'Bearer $token'}
                : null,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return GlucoseSnapshot(
          reading: null,
          history: const [],
          message: 'Nightscout gaf HTTP ${response.statusCode}.',
        );
      }

      final data = jsonDecode(response.body);

      if (data is! List || data.isEmpty) {
        return const GlucoseSnapshot(
          reading: null,
          history: [],
          message: 'Geen glucosegegevens gevonden.',
        );
      }

      final readings = <GlucoseReading>[];

      for (final item in data) {
        if (item is! Map) continue;

        final mgdl = item['sgv'];
        final dateMs = item['date'];

        if (mgdl is! num || dateMs is! num) continue;

        final mmol = mgdl.toDouble() / 18.0;
        final at = DateTime.fromMillisecondsSinceEpoch(dateMs.toInt());

        readings.add(
          GlucoseReading(mmol, _trendFromDirection(item['direction']), at),
        );
      }

      if (readings.isEmpty) {
        return const GlucoseSnapshot(
          reading: null,
          history: [],
          message: 'Geen geldige glucosegegevens gevonden.',
        );
      }

      readings.sort((a, b) => b.at.compareTo(a.at));

      final latest = readings.first;

      // Oudste eerst, nieuwste laatst — zodat de curve links-oud/rechts-nu
      // klopt met de tijdlabels eronder.
      final history = readings
          .take(count)
          .toList()
          .reversed
          .map((r) => GlucosePoint(r.at, r.mmol))
          .toList();

      return GlucoseSnapshot(reading: latest, history: history);
    } catch (e) {
      return GlucoseSnapshot(
        reading: null,
        history: const [],
        message: 'Kan Nightscout niet bereiken.',
      );
    }
  }

  Trend _trendFromDirection(dynamic direction) {
    switch (direction) {
      case 'DoubleUp':
      case 'SingleUp':
        return Trend.up;

      case 'FortyFiveUp':
        return Trend.slightUp;

      case 'Flat':
        return Trend.flat;

      case 'FortyFiveDown':
        return Trend.slightDown;

      case 'SingleDown':
        return Trend.down;

      case 'DoubleDown':
        return Trend.fastDown;

      default:
        return Trend.flat;
    }
  }
}

/// Alleen https: het API-token gaat mee in de header en mag nooit
/// onversleuteld over het netwerk (Android blokkeert http ook standaard).
bool isSafeNightscoutUri(Uri uri) => uri.scheme == 'https' && uri.host.isNotEmpty;
