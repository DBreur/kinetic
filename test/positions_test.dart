import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/positions.dart';
import 'package:kinetic/models/technique.dart';

void main() {
  group('kPositions/kOutcomes/kAllNodes', () {
    test('de afgeronde scores staan niet tussen de vertrekposities', () {
      expect(kPositions, isNot(contains('Takedown')));
      expect(kPositions, isNot(contains('Submission')));
    });

    test('kAllNodes bevat zowel de posities als de afgeronde scores', () {
      expect(kAllNodes, containsAll(kPositions));
      expect(kAllNodes, containsAll(kOutcomes));
    });
  });

  group('parseTransition', () {
    test('accepteert ->, → en > als scheidingsteken', () {
      expect(
        parseTransition('Staand -> Grond boven'),
        (from: 'Staand', to: 'Grond boven'),
      );
      expect(
        parseTransition('Staand → Grond boven'),
        (from: 'Staand', to: 'Grond boven'),
      );
      expect(
        parseTransition('Staand > Grond boven'),
        (from: 'Staand', to: 'Grond boven'),
      );
    });

    test('negeert spaties en hoofdletters', () {
      expect(
        parseTransition('  staand   ->   GROND BOVEN  '),
        (from: 'Staand', to: 'Grond boven'),
      );
      expect(parseTransition('Staand->GrondBoven'), isNull);
    });

    test('geeft null bij een lege string', () {
      expect(parseTransition(''), isNull);
      expect(parseTransition('   '), isNull);
    });

    test('geeft null bij een onbekende positie', () {
      expect(parseTransition('Ergens -> Grond boven'), isNull);
      expect(parseTransition('Staand -> Nergens'), isNull);
    });

    test('geeft null zonder scheidingsteken', () {
      expect(parseTransition('Staand Grond boven'), isNull);
    });

    test('accepteert Takedown/Submission als "naar" — een afgeronde score', () {
      expect(
        parseTransition('Staand -> Takedown'),
        (from: 'Staand', to: 'Takedown'),
      );
      expect(
        parseTransition('Grond boven -> Submission'),
        (from: 'Grond boven', to: 'Submission'),
      );
    });
  });

  group('isOnMap', () {
    test('een geldige transitie hoort altijd op de kaart', () {
      expect(
        isOnMap(
          const Technique(
            id: 't1',
            name: 'Test',
            transition: 'Staand -> Klem',
          ),
        ),
        isTrue,
      );
    });

    test('categorie Submission hoort op de kaart, ook zonder transitie', () {
      expect(
        isOnMap(
          const Technique(id: 't1', name: 'Test', category: 'Submission'),
        ),
        isTrue,
      );
    });

    test('zonder transitie en zonder categorie Submission hoort hij er niet bij', () {
      expect(
        isOnMap(const Technique(id: 't1', name: 'Test', category: 'Strike')),
        isFalse,
      );
      expect(isOnMap(const Technique(id: 't1', name: 'Test')), isFalse);
    });
  });

  group('arrivesAt', () {
    test('via een geldige transitie', () {
      const t = Technique(id: 't1', name: 'Test', transition: 'Staand -> Klem');
      expect(arrivesAt(t, 'Klem'), isTrue);
      expect(arrivesAt(t, 'Staand'), isFalse);
    });

    test('categorie Submission zonder transitie telt mee bij Submission', () {
      const t = Technique(id: 't1', name: 'Test', category: 'Submission');
      expect(arrivesAt(t, 'Submission'), isTrue);
      expect(arrivesAt(t, 'Takedown'), isFalse);
    });

    test('categorie Submission telt niet mee bij een ander knooppunt', () {
      const t = Technique(id: 't1', name: 'Test', category: 'Submission');
      expect(arrivesAt(t, 'Klem'), isFalse);
    });

    test('een expliciete transitie gaat voor categorie Submission', () {
      // Tegenstrijdige data (categorie Submission, maar een transitie die
      // ergens anders naartoe gaat) — de transitie is dan leidend.
      const t = Technique(
        id: 't1',
        name: 'Test',
        category: 'Submission',
        transition: 'Staand -> Takedown',
      );
      expect(arrivesAt(t, 'Takedown'), isTrue);
      expect(arrivesAt(t, 'Submission'), isFalse);
    });
  });

  group('effectiveCategory', () {
    Technique techniqueWith({String category = 'Overig', String transition = ''}) =>
        Technique(id: 't1', name: 'Test', category: category, transition: transition);

    test('gebruikt een bestaande, betekenisvolle categorie', () {
      final t = techniqueWith(category: 'Submission', transition: 'Staand -> Klem');
      expect(effectiveCategory(t), 'Submission');
    });

    test('leidt Staand af uit Staand/Clinch-transities als categorie leeg/Overig is', () {
      expect(effectiveCategory(techniqueWith(transition: 'Staand -> Grond boven')), 'Staand');
      expect(effectiveCategory(techniqueWith(transition: 'Clinch -> Klem')), 'Staand');
    });

    test('leidt Grondwerk af uit overige transities', () {
      expect(effectiveCategory(techniqueWith(transition: 'Grond boven -> Klem')), 'Grondwerk');
    });

    test('valt terug op Overig zonder parsebare transitie', () {
      expect(effectiveCategory(techniqueWith()), 'Overig');
    });

    test('leidt Takedown/Submission af uit een transitie die daar eindigt', () {
      expect(
        effectiveCategory(techniqueWith(transition: 'Staand -> Takedown')),
        'Takedown',
      );
      expect(
        effectiveCategory(
          techniqueWith(transition: 'Grond boven -> Submission'),
        ),
        'Submission',
      );
    });
  });

  group('groupConnections', () {
    Technique rated(String name, String transition, int rating) => Technique(
      id: name,
      name: name,
      transition: transition,
      updates: [TechniqueUpdate(at: DateTime(2026, 1, 1), rating: rating)],
    );

    test('groepeert per positiepaar en negeert technieken zonder transitie', () {
      final techniques = [
        rated('A', 'Staand -> Grond boven', 4),
        rated('B', 'Staand -> Grond boven', 2),
        Technique(id: 'c', name: 'C', transition: ''),
      ];
      final groups = groupConnections(techniques);
      expect(groups, hasLength(1));
      expect(groups.single.from, 'Staand');
      expect(groups.single.to, 'Grond boven');
      expect(groups.single.techniques, hasLength(2));
    });

    test('gemiddelde beheersing bepaalt de kleur', () {
      final techniques = [
        rated('A', 'Staand -> Klem', 5),
        rated('B', 'Staand -> Klem', 3),
      ];
      final group = groupConnections(techniques).single;
      expect(group.averageMastery, 4.0);
      expect(group.color, colorForMasteryScore(4.0));
    });

    test('gestippeld (everRated = false) als geen enkele techniek ooit is beoordeeld', () {
      final techniques = [
        Technique(id: 'a', name: 'A', transition: 'Staand -> Klem'),
        Technique(id: 'b', name: 'B', transition: 'Staand -> Klem'),
      ];
      final group = groupConnections(techniques).single;
      expect(group.everRated, isFalse);
    });

    test('everRated = true zodra één techniek ooit is beoordeeld', () {
      final techniques = [
        Technique(id: 'a', name: 'A', transition: 'Staand -> Klem'),
        rated('B', 'Staand -> Klem', 3),
      ];
      final group = groupConnections(techniques).single;
      expect(group.everRated, isTrue);
    });
  });

  group('arrowAnchorPoint', () {
    const targetRect = Rect.fromLTWH(100, 100, 40, 20); // center (120, 110)
    const center = Offset(120, 110);

    test('horizontale lijn: anchor ligt op de rand min 8px, niet op een vast percentage', () {
      const from = Offset(0, 110);
      final anchor = arrowAnchorPoint(from, center, targetRect, pullBack: 8);
      // De rand ligt op x=100 (links van het doelvak); anchor moet 8px terug.
      expect(anchor.dx, closeTo(92, 0.001));
      expect(anchor.dy, closeTo(110, 0.001));
    });

    test('verticale lijn: anchor ligt op de rand min 8px', () {
      const from = Offset(120, 0);
      final anchor = arrowAnchorPoint(from, center, targetRect, pullBack: 8);
      expect(anchor.dx, closeTo(120, 0.001));
      expect(anchor.dy, closeTo(92, 0.001)); // rand op y=100, terug naar 92
    });

    test('schuine lijn: anchor ligt op de rand-kruising min 8px, niet op 92% van de lijn', () {
      const from = Offset(0, 0);
      final anchor = arrowAnchorPoint(from, center, targetRect, pullBack: 8);
      // De lijn van (0,0) naar (120,110) kruist het linker- of bovenvlak van
      // het rechthoekige doelvak eerder dan 92% van de totale lijnlengte.
      final totalLength = (center - from).distance;
      final anchorDistanceFromStart = (anchor - from).distance;
      expect(anchorDistanceFromStart, lessThan(totalLength * 0.92));
      // En het anchor-punt ligt niet binnen het doelvak.
      expect(targetRect.contains(anchor), isFalse);
    });
  });
}
