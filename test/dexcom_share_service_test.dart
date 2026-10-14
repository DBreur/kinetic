// dexcom_share_service_test.dart — mg/dL↔mmol/L, alle trend-strings, de
// /Date(...)/ -tijdstempelnotatie, en het eenmalig opnieuw inloggen zodra
// een sessie verlopen blijkt (via een nagebootste HTTP-client, zodat dit
// zonder echt netwerk te testen is).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/services/dexcom_share_service.dart';

void main() {
  group('mgdlToMmol', () {
    test('rekent mg/dL om naar mmol/L (/18.0)', () {
      expect(mgdlToMmol(180), closeTo(10.0, 0.001));
      expect(mgdlToMmol(90), closeTo(5.0, 0.001));
    });
  });

  group('trendFromDexcomString', () {
    test('alle bekende Dexcom-trendstrings', () {
      expect(trendFromDexcomString('DoubleUp'), Trend.up);
      expect(trendFromDexcomString('SingleUp'), Trend.up);
      expect(trendFromDexcomString('FortyFiveUp'), Trend.slightUp);
      expect(trendFromDexcomString('Flat'), Trend.flat);
      expect(trendFromDexcomString('FortyFiveDown'), Trend.slightDown);
      expect(trendFromDexcomString('SingleDown'), Trend.down);
      expect(trendFromDexcomString('DoubleDown'), Trend.fastDown);
    });

    test('onbekend of ontbrekend valt terug op flat', () {
      expect(trendFromDexcomString('NotComputable'), Trend.flat);
      expect(trendFromDexcomString(null), Trend.flat);
    });
  });

  group('parseDexcomDate', () {
    test('/Date(ms)/ met omliggende schuine strepen', () {
      final date = parseDexcomDate('/Date(1699999999000)/');
      expect(date, DateTime.fromMillisecondsSinceEpoch(1699999999000));
    });

    test('/Date(ms-0800)/ met tijdzone-suffix — suffix doet er niet toe', () {
      final date = parseDexcomDate('/Date(1699999999000-0800)/');
      expect(date, DateTime.fromMillisecondsSinceEpoch(1699999999000));
    });

    test(
      'Date(ms) zonder schuine strepen — wat de Share-API in de praktijk '
      'stuurt',
      () {
        final date = parseDexcomDate('Date(1699999999000)');
        expect(date, DateTime.fromMillisecondsSinceEpoch(1699999999000));
      },
    );

    test('Date(ms+0200) zonder schuine strepen, met positieve tijdzone', () {
      final date = parseDexcomDate('Date(1699999999000+0200)');
      expect(date, DateTime.fromMillisecondsSinceEpoch(1699999999000));
    });

    test('geeft null bij een onherkenbaar formaat', () {
      expect(parseDexcomDate('niet een datum'), isNull);
    });
  });

  group('DexcomShareService.fetch — opnieuw inloggen bij een verlopen sessie', () {
    const accountId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    const oldSession = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    const newSession = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

    test(
      'een SessionNotValid-fout triggert één nieuwe login en lukt daarna',
      () async {
        var loginCount = 0;
        var readCount = 0;

        final client = MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('AuthenticatePublisherAccount')) {
            return http.Response(jsonEncode(accountId), 200);
          }
          if (path.endsWith('LoginPublisherAccountById')) {
            loginCount++;
            // Eerste keer de oude sessie, de tweede (na de sessiefout) een
            // nieuwe — zo valt te zien dat er echt opnieuw werd ingelogd.
            return http.Response(
              jsonEncode(loginCount == 1 ? oldSession : newSession),
              200,
            );
          }
          if (path.endsWith('ReadPublisherLatestGlucoseValues')) {
            readCount++;
            final sessionId = request.url.queryParameters['sessionId'];
            if (sessionId == oldSession) {
              return http.Response(
                jsonEncode({
                  'Code': 'SessionNotValid',
                  'Message': 'Session not valid',
                }),
                200,
              );
            }
            // Zelfde formaat als de echte Share-API: geen schuine strepen
            // om Date(...) heen.
            return http.Response(
              jsonEncode([
                {'WT': 'Date(1699999999000)', 'Value': 108, 'Trend': 'Flat'},
              ]),
              200,
            );
          }
          return http.Response('not found', 404);
        });

        final service = DexcomShareService(
          username: 'test',
          password: 'secret',
          client: client,
        );

        final snapshot = await service.fetch(count: 1);

        expect(loginCount, 2); // één keer in eerste poging, één keer na de sessiefout
        expect(readCount, 2); // één mislukte poging, één geslaagde
        expect(snapshot.reading, isNotNull);
        expect(snapshot.reading!.mmol, closeTo(mgdlToMmol(108), 0.001));
      },
    );

    test('mislukt inloggen geeft een nette foutmelding, geen crash', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode(null), 200);
      });
      final service = DexcomShareService(
        username: 'test',
        password: 'wrong',
        client: client,
      );

      final snapshot = await service.fetch();

      expect(snapshot.reading, isNull);
      expect(snapshot.message, isNotNull);
    });

    test('een netwerkfout geeft een snapshot terug in plaats van te gooien', () async {
      final client = MockClient((request) async {
        throw Exception('geen netwerk');
      });
      final service = DexcomShareService(
        username: 'test',
        password: 'secret',
        client: client,
      );

      final snapshot = await service.fetch();

      expect(snapshot.reading, isNull);
      expect(snapshot.message, isNotNull);
    });
  });
}
