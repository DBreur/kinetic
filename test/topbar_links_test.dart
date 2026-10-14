import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/agenda.dart';
import 'package:kinetic/widgets/kinetic.dart';

void main() {
  group('topbalk om de camera heen', () {
    const width = 412.0;
    const title = 75.0;

    test('geen camera: alles normaal, niets verschoven', () {
      final l = topBarLayout(width: width, titleWidth: title);
      expect(l.leftInset, 0);
      expect(l.hole, 0);
      expect(l.fallbackBelow, isFalse);
    });

    test('camera rechts: klok/glucose links, knoppen rechts ervan', () {
      final l = topBarLayout(
        width: width,
        titleWidth: title,
        cutout: const Rect.fromLTWH(265, 6, 28, 28),
      );
      expect(l.split, isTrue);
      expect(l.hole, closeTo(40, .01)); // 28 + 2× 6 marge
      expect(l.fallbackBelow, isFalse);
    });

    test('camera in het midden: alles rechts van de camera', () {
      // Klok + pil (getal) en alleen het profielrondje.
      final l = topBarLayout(
        width: width,
        titleWidth: title,
        cutout: const Rect.fromLTWH(192, 6, 28, 28),
        infoWidth: 110,
        actionsWidth: 50,
      );
      expect(l.split, isFalse);
      expect(l.clusterBeforeHole, isFalse);
      expect(l.fallbackBelow, isFalse);
    });

    test('Eten (met exportknop), camera rechts: nog steeds gesplitst', () {
      final l = topBarLayout(
        width: width,
        titleWidth: 60,
        cutout: const Rect.fromLTWH(265, 6, 28, 28),
        infoWidth: 104,
        actionsWidth: 98,
      );
      expect(l.split, isTrue);
      expect(l.beforeHole, greaterThanOrEqualTo(104));
      expect(l.afterHole, greaterThanOrEqualTo(98));
    });

    test('camera links: logo en titel schuiven op', () {
      final l = topBarLayout(
        width: width,
        titleWidth: title,
        cutout: const Rect.fromLTWH(22, 6, 28, 28),
      );
      expect(l.leftInset, greaterThan(0));
      expect(l.fallbackBelow, isFalse);
    });

    test('nergens plek (smal scherm): balk zakt onder de camera', () {
      final l = topBarLayout(
        width: 260,
        titleWidth: title,
        cutout: const Rect.fromLTWH(170, 6, 28, 28),
      );
      expect(l.fallbackBelow, isTrue);
    });

    test('uitsparing buiten de balk wordt genegeerd', () {
      final l = topBarLayout(
        width: width,
        titleWidth: title,
        cutout: const Rect.fromLTWH(900, 6, 28, 28),
      );
      expect(l.hole, 0);
      expect(l.beforeHole, greaterThan(0));
      expect(l.fallbackBelow, isFalse);
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
