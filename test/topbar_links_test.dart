import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/agenda.dart';
import 'package:kinetic/widgets/kinetic.dart';

void main() {
  group('topbalk om de camera heen', () {
    const width = 412.0;
    const title = 75.0;
    // Echte breedtes: klok, glucose (getal), export, profiel.
    const clock = 52.0, pill = 51.0, export = 48.0, avatar = 50.0;

    test('geen camera: één vak, geen gat', () {
      final l = topBarLayout(width: width, titleWidth: title);
      expect(l.leftInset, 0);
      expect(l.hole, 0);
      expect(l.beforeHole, greaterThan(200));
    });

    test('camera rechts op Vandaag: glucose links, klok + profiel rechts', () {
      final l = topBarLayout(
        width: width,
        titleWidth: title,
        cutout: const Rect.fromLTWH(265, 6, 28, 28),
      );
      expect(l.hole, closeTo(40, .01)); // 28 + 2× 6 marge
      final k = placeTopBarItems(
        const [clock, pill, avatar],
        before: l.beforeHole,
        after: l.afterHole,
        hasHole: true,
      );
      expect(k, isNotNull);
      // Zo veel mogelijk rechts: profiel blijft in de hoek.
      expect(k, lessThan(3));
    });

    test('camera rechts op Eten (met export): past nog om de camera', () {
      final l = topBarLayout(
        width: width,
        titleWidth: 50,
        cutout: const Rect.fromLTWH(265, 6, 28, 28),
      );
      expect(
        placeTopBarItems(
          const [clock, pill, export, avatar],
          before: l.beforeHole,
          after: l.afterHole,
          hasHole: true,
        ),
        isNotNull,
      );
    });

    test('camera links: logo en titel schuiven op, geen gat', () {
      final l = topBarLayout(
        width: width,
        titleWidth: title,
        cutout: const Rect.fromLTWH(22, 6, 28, 28),
      );
      expect(l.leftInset, greaterThan(0));
      expect(l.hole, 0);
    });

    test('past nergens: null (dan zakt de balk onder de camera)', () {
      expect(
        placeTopBarItems(
          const [clock, pill, export, avatar],
          before: 40,
          after: 40,
          hasHole: true,
        ),
        isNull,
      );
    });

    test('uitsparing buiten de balk wordt genegeerd', () {
      final l = topBarLayout(
        width: width,
        titleWidth: title,
        cutout: const Rect.fromLTWH(900, 6, 28, 28),
      );
      expect(l.hole, 0);
      expect(l.beforeHole, greaterThan(0));
    });

    test('alleen een uitsparing bovenin telt', () {
      const low = DisplayFeature(
        bounds: Rect.fromLTWH(100, 300, 30, 30),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );
      expect(topCutout(const [low], 64), isNull);
    });
  });

  group('wedstrijdlinks', () {
    test('https wordt aangevuld, leeg blijft leeg', () {
      expect(normalizeUrl('sambo.nl/regels'), 'https://sambo.nl/regels');
      expect(normalizeUrl(' http://x.nl '), 'http://x.nl');
      expect(normalizeUrl('https://y.nl'), 'https://y.nl');
      expect(normalizeUrl('   '), '');
    });

    test('links overleven toJson/fromJson', () {
      final c = Competition(
        id: 'c',
        name: 'NK',
        startsAt: DateTime(2026, 11, 1),
        rulesUrl: 'sambo.nl/reglement',
        websiteUrl: 'https://nk-sambo.nl',
      );
      final back = Competition.fromJson({...c.toJson(), 'id': 'c'});
      expect(back.rulesUrl, 'https://sambo.nl/reglement');
      expect(back.websiteUrl, 'https://nk-sambo.nl');
      expect(Competition.fromJson({
        'id': 'x',
        'name': 'oud',
        'starts_at': '2026-11-01T10:00:00Z',
      }).rulesUrl, '');
    });
  });
}
