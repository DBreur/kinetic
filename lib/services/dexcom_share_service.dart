// dexcom_share_service.dart — haalt glucosewaarden rechtstreeks van Dexcom
// op via de niet-officiële "Share"-API (hetzelfde endpoint dat de Dexcom-app
// gebruikt om waarden te delen met volgers). Niet officieel ondersteund door
// Dexcom en kan zonder aankondiging veranderen — zie de instellingenscherm-
// disclaimer. De applicationId hieronder is het publiek bekende, vaste id dat
// ook andere open-source Dexcom Share-clients (bv. pydexcom, xDrip+) gebruiken
// om zich als de Dexcom-app voor te doen; het is geen geheim van de gebruiker.
//
// Vereist dat "Delen" aanstaat in de Dexcom-app van de gebruiker zelf.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/glucose.dart';
import 'glucose_provider.dart';

const _applicationId = 'd8665ade-9673-4e27-9ff6-92db4ce13d13';
const _zeroGuid = '00000000-0000-0000-0000-000000000000';

/// Dexcom's trend-string → onze eigen [Trend]-enum — exact dezelfde
/// richtingen als Nightscout's `direction`-veld, dus hergebruiken we hier
/// bewust niet dezelfde namen (dit zijn Dexcom's eigen Share-API-waarden).
Trend trendFromDexcomString(String? trend) {
  switch (trend) {
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

/// Dexcom geeft tijdstempels als `Date(1699999999000)` of
/// `Date(1699999999000+0200)` (.NET JSON-datumnotatie) — soms mét
/// omliggende schuine strepen (`/Date(...)/ `), soms zonder (wat de Share-
/// API in de praktijk blijkt te sturen); beide worden hier geaccepteerd.
/// Pakt alleen het epoch-millisecondendeel, de tijdzone-suffix doet er niet
/// toe omdat [DateTime.fromMillisecondsSinceEpoch] al in UTC-epoch rekent.
DateTime? parseDexcomDate(String raw) {
  final match = RegExp(r'Date\((-?\d+)').firstMatch(raw);
  if (match == null) return null;
  final ms = int.tryParse(match.group(1)!);
  if (ms == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

class DexcomShareService implements GlucoseProvider {
  DexcomShareService({
    required this.username,
    required this.password,
    this.server = 'shareous1.dexcom.com',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String username;
  final String password;
  final String server;
  final http.Client _client;

  String? _sessionId;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.https(server, '/ShareWebServices/Services/$path', query);

  Map<String, String> get _headers => const {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// `AuthenticatePublisherAccount` → `LoginPublisherAccountById` — Dexcom
  /// Share vereist deze twee aparte stappen (de eerste zet de gebruikersnaam
  /// om naar een accountId, de tweede wisselt dat in voor een sessionId).
  Future<String?> _login() async {
    try {
      final authResponse = await _client.post(
        _uri('General/AuthenticatePublisherAccount'),
        headers: _headers,
        body: jsonEncode({
          'accountName': username,
          'password': password,
          'applicationId': _applicationId,
        }),
      );
      if (authResponse.statusCode != 200) return null;
      final accountId = _decodeGuid(authResponse.body);
      if (accountId == null) return null;

      final loginResponse = await _client.post(
        _uri('General/LoginPublisherAccountById'),
        headers: _headers,
        body: jsonEncode({
          'accountId': accountId,
          'password': password,
          'applicationId': _applicationId,
        }),
      );
      if (loginResponse.statusCode != 200) return null;
      return _decodeGuid(loginResponse.body);
    } catch (_) {
      return null;
    }
  }

  String? _decodeGuid(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! String || decoded.isEmpty || decoded == _zeroGuid) {
        return null;
      }
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response> _readValues(String sessionId, int count) {
    return _client.post(
      _uri('Publisher/ReadPublisherLatestGlucoseValues', {
        'sessionId': sessionId,
        'minutes': '1440',
        'maxCount': '$count',
      }),
      headers: _headers,
    );
  }

  /// Een verlopen/ongeldige sessie geeft geen gewone HTTP-foutcode terug,
  /// maar 200 met een foutobject zoals `{"Code":"SessionNotValid",...}`.
  bool _isSessionError(http.Response response) {
    if (response.statusCode == 500 || response.statusCode == 401) return true;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['Code'] is String) {
        return (decoded['Code'] as String).startsWith('Session');
      }
    } catch (_) {
      // Geen JSON-foutobject — geen sessiefout.
    }
    return false;
  }

  @override
  Future<GlucoseSnapshot> fetch({int count = 20}) async {
    const loginFailedMessage =
        'Inloggen bij Dexcom is niet gelukt. Controleer gebruikersnaam, '
        'wachtwoord en server.';
    try {
      _sessionId ??= await _login();
      if (_sessionId == null) {
        return const GlucoseSnapshot(
          reading: null,
          history: [],
          message: loginFailedMessage,
        );
      }

      var response = await _readValues(_sessionId!, count);
      if (_isSessionError(response)) {
        // Eén keer opnieuw inloggen — een sessionId kan verlopen terwijl de
        // app op de achtergrond draait.
        _sessionId = await _login();
        if (_sessionId == null) {
          return const GlucoseSnapshot(
            reading: null,
            history: [],
            message: loginFailedMessage,
          );
        }
        response = await _readValues(_sessionId!, count);
      }

      if (response.statusCode != 200) {
        return GlucoseSnapshot(
          reading: null,
          history: const [],
          message: 'Dexcom gaf HTTP ${response.statusCode}.',
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
        final mgdl = item['Value'];
        final wt = item['WT'];
        if (mgdl is! num || wt is! String) continue;
        final at = parseDexcomDate(wt);
        if (at == null) continue;
        readings.add(
          GlucoseReading(
            mgdlToMmol(mgdl),
            trendFromDexcomString(item['Trend'] as String?),
            at,
          ),
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
      final history = readings
          .take(10)
          .toList()
          .reversed
          .map((r) => GlucosePoint(r.at, r.mmol))
          .toList();

      return GlucoseSnapshot(reading: latest, history: history);
    } catch (_) {
      return const GlucoseSnapshot(
        reading: null,
        history: [],
        message: 'Kan Dexcom niet bereiken.',
      );
    }
  }
}
