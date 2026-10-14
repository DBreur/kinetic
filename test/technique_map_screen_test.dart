// technique_map_screen_test.dart — regressietest voor een knoop op de kaart
// die wel getekend werd maar niet reageerde op een tik: de GestureDetector
// rond de kale CustomPaint ving taps niet op zonder een expliciete
// HitTestBehavior.opaque (en een vaste grootte via SizedBox). Zie
// technique_map_screen.dart's _buildMapView().

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kinetic/core/positions.dart';
import 'package:kinetic/models/technique.dart';
import 'package:kinetic/repositories/technique_repository.dart';
import 'package:kinetic/screens/technique_map_screen.dart';

void main() {
  testWidgets('tikken op een knoop selecteert hem en ververst de lijst', (
    tester,
  ) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final technique = Technique(
      id: 't1',
      name: 'Harai Goshi',
      transition: 'Staand -> Clinch',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TechniqueMapScreen(
          repository: TechniqueRepository(client),
          userId: 'u1',
          techniques: [technique],
        ),
      ),
    );
    await tester.pump();

    final canvas = find.byKey(const Key('techniqueMapCanvas'));
    expect(canvas, findsOneWidget);

    final canvasSize = tester.getSize(canvas);
    final staandCenter = positionOffset('Staand', canvasSize);
    final topLeft = tester.getTopLeft(canvas);

    // De kaart (~400px hoog) vult het testviewport al bijna helemaal, dus de
    // selectielijst eronder moet eerst in beeld gescrold worden — anders
    // bouwt de sliver-lijst die elementen nog niet.
    final scrollable = find.byType(Scrollable).first;
    Future<void> scrollToSelectionList() async {
      for (var i = 0; i < 10; i++) {
        await tester.drag(scrollable, const Offset(0, -300));
        await tester.pump();
      }
    }

    Future<void> scrollBackToTop() async {
      for (var i = 0; i < 10; i++) {
        await tester.drag(scrollable, const Offset(0, 300));
        await tester.pump();
      }
    }

    await tester.tapAt(topLeft + staandCenter);
    await tester.pump();
    await scrollToSelectionList();

    expect(find.text('VANUIT STAAND'), findsOneWidget);
    expect(find.text('Harai Goshi'), findsOneWidget);

    // Nogmaals tikken heft de selectie weer op — eerst terug naar de kaart
    // scrollen, want de vorige scroll bracht de knoop zelf uit beeld.
    await scrollBackToTop();
    await tester.tapAt(topLeft + staandCenter);
    await tester.pump();
    await scrollToSelectionList();
    expect(find.text('VANUIT STAAND'), findsNothing);
    expect(find.text('WAAR MOET JE AAN WERKEN'), findsOneWidget);
  });

  testWidgets(
    'tikken op het rondje (badge) midden op een verbindingslijn selecteert die verbinding',
    (tester) async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final technique = Technique(
        id: 't1',
        name: 'Harai Goshi',
        transition: 'Staand -> Clinch',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TechniqueMapScreen(
            repository: TechniqueRepository(client),
            userId: 'u1',
            techniques: [technique],
          ),
        ),
      );
      await tester.pump();

      final canvas = find.byKey(const Key('techniqueMapCanvas'));
      final canvasSize = tester.getSize(canvas);
      final from = positionOffset('Staand', canvasSize);
      final to = positionOffset('Clinch', canvasSize);
      final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
      final topLeft = tester.getTopLeft(canvas);

      await tester.tapAt(topLeft + mid);
      await tester.pump();

      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 10; i++) {
        await tester.drag(scrollable, const Offset(0, -300));
        await tester.pump();
      }

      expect(find.text('STAAND → CLINCH'), findsOneWidget);
      expect(find.text('Harai Goshi'), findsOneWidget);
    },
  );

  testWidgets(
    'een techniek met categorie Submission hoort op de kaart, ook zonder transitie',
    (tester) async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final technique = Technique(
        id: 't1',
        name: 'Kimura',
        category: 'Submission',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TechniqueMapScreen(
            repository: TechniqueRepository(client),
            userId: 'u1',
            techniques: [technique],
          ),
        ),
      );
      await tester.pump();

      // Niet in "NIET OP DE KAART" — categorie Submission is genoeg.
      expect(find.text('NIET OP DE KAART'), findsNothing);
      expect(find.text('Indelen'), findsNothing);

      // Eerst scrollen, dan pas de positie van de kaart opvragen — anders
      // tikken we straks met een intussen verouderde (pre-scroll) topLeft.
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -150));
      await tester.pump();

      final canvas = find.byKey(const Key('techniqueMapCanvas'));
      final canvasSize = tester.getSize(canvas);
      final submissionCenter = positionOffset('Submission', canvasSize);
      final topLeft = tester.getTopLeft(canvas);

      await tester.tapAt(topLeft + submissionCenter);
      await tester.pump();

      for (var i = 0; i < 10; i++) {
        await tester.drag(scrollable, const Offset(0, -300));
        await tester.pump();
      }

      expect(find.text('NAAR SUBMISSION'), findsOneWidget);
      expect(find.text('Kimura'), findsOneWidget);
    },
  );
}
