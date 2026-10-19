import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/state/app_controller.dart';

void main() {
  late int requests;
  late Completer<void> gate;

  AppController controllerWith(List<Map<String, dynamic>> rows) {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((req) async {
        if (req.url.path.contains('glucose_entries')) {
          requests++;
          await gate.future;
          return http.Response(
            jsonEncode(rows),
            200,
            request: req,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200, request: req);
      }),
    );
    return AppController()..debugAttach(
      client,
      AppProfile.defaults('u1').copyWith(glucoseSource: GlucoseSource.finger),
      user: const User(
        id: 'u1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );
  }

  setUp(() {
    requests = 0;
    gate = Completer<void>();
  });

  test(
    'vingerprik-bron: nieuwste meting met trend, gedeelde ophaalactie',
    () async {
      final c = controllerWith([
        {'id': 'b', 'mmol': 7.4, 'at': '2026-10-19T10:00:00Z'},
        {'id': 'a', 'mmol': 6.0, 'at': '2026-10-19T09:00:00Z'},
      ]);
      final first = c.refreshGlucose();
      final second = c.refreshGlucose();
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1, reason: 'tweede aanroep wacht op de lopende');
      gate.complete();
      await Future.wait([first, second]);
      // Na de lopende ronde wordt nog één keer opgehaald.
      expect(requests, 2);
      expect(c.cachedGlucose?.reading?.mmol, 7.4);
      expect(c.cachedGlucose?.reading?.trend, Trend.up);
      expect(c.fingerEntries.value, hasLength(2));
    },
  );

  test('offerGlucoseReading neemt alleen nieuwere metingen over', () {
    final c = controllerWith(const []);
    final t = DateTime(2026, 10, 19, 10);
    c.offerGlucoseReading(GlucoseReading(6.0, Trend.flat, t));
    c.offerGlucoseReading(
      GlucoseReading(5.0, Trend.flat, t.subtract(const Duration(minutes: 5))),
    );
    expect(c.cachedGlucose?.reading?.mmol, 6.0);
    c.offerGlucoseReading(
      GlucoseReading(6.5, Trend.up, t.add(const Duration(minutes: 5))),
    );
    expect(c.cachedGlucose?.reading?.mmol, 6.5);
    expect(c.cachedGlucose?.history, hasLength(2));
  });

  test('polling start en stopt', () {
    final c = controllerWith(const []);
    gate.complete();
    c.startGlucosePolling();
    expect(c.isPollingGlucose, isTrue);
    c.stopGlucosePolling();
    expect(c.isPollingGlucose, isFalse);
  });
}
