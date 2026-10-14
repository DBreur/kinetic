import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/core/positions.dart';
import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/models/technique.dart';
import 'package:kinetic/services/video_labels.dart';
import 'package:kinetic/widgets/ground_position_tags.dart';
import 'package:kinetic/widgets/inline_video_player.dart';

void main() {
  group('Striking', () {
    test('is een startpositie en parseert naar Takedown', () {
      expect(kPositions, contains('Striking'));
      expect(parseTransition('Striking -> Takedown'), (
        from: 'Striking',
        to: 'Takedown',
      ));
    });

    test('valt onder Staand als er geen eigen categorie is', () {
      const t = Technique(
        id: '1',
        name: 'Jab → double leg',
        transition: 'Striking -> Takedown',
        category: '',
      );
      expect(effectiveCategory(t), 'Takedown');
      const t2 = Technique(
        id: '2',
        name: 'Slag naar clinch',
        transition: 'Striking -> Clinch',
        category: '',
      );
      expect(effectiveCategory(t2), 'Staand');
    });

    test('knopen op de bovenste rij overlappen niet', () {
      const size = Size(kMapWidth, kMapHeight);
      final striking = nodeRect('Striking', size);
      final staand = nodeRect('Staand', size);
      final clinch = nodeRect('Clinch', size);
      expect(striking.overlaps(staand), isFalse);
      expect(staand.overlaps(clinch), isFalse);
      expect(striking.left, greaterThanOrEqualTo(0));
      expect(clinch.right, lessThanOrEqualTo(kMapWidth));
    });
  });

  testWidgets('transitie wordt als tag met van → naar getoond', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GroundPositionTags(
            transition: 'Striking -> Takedown',
            positions: ['Mount'],
          ),
        ),
      ),
    );
    expect(find.text('Striking'), findsOneWidget);
    expect(find.text('Takedown'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.text('Mount'), findsOneWidget);
  });

  group('VideoLabels', () {
    tearDown(() => VideoLabels.attach(const {}, null));

    test('eigen naam, anders Video n; leeg wist de naam', () async {
      Map<String, String>? saved;
      VideoLabels.attach(const {}, (m) async => saved = m);
      expect(VideoLabels.titleFor('https://a', 1), 'Video 2');
      await VideoLabels.setLabel(' https://a ', 'Instap');
      expect(VideoLabels.titleFor('https://a', 1), 'Instap');
      expect(saved, {'https://a': 'Instap'});
      await VideoLabels.setLabel('https://a', '  ');
      expect(VideoLabels.labelOf('https://a'), isNull);
      expect(saved, isEmpty);
    });

    test('profiel leest en schrijft video_labels', () {
      final p = AppProfile.fromJson({
        ...AppProfile.defaults('u').toJson(),
        'video_labels': {'https://a': 'Instap', 'x': 3},
      });
      expect(p.videoLabels, {'https://a': 'Instap'});
      expect(p.toJson()['video_labels'], {'https://a': 'Instap'});
    });

    testWidgets('videolijst toont de eigen naam', (tester) async {
      VideoLabels.attach({'https://a': 'Detail grip'}, null);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CollapsibleVideoList(urls: ['https://a', 'https://b']),
          ),
        ),
      );
      expect(find.text('Detail grip'), findsOneWidget);
      expect(find.text('Video 2'), findsOneWidget);
    });
  });
}
