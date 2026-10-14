// technique_edit_screen_test.dart — smoke test die het hele bewerkformulier
// rendert voor een bestaande techniek met naam/categorie/video, zodat een
// toekomstige regressie (een leeg scherm door een build-fout) meteen opvalt.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kinetic/models/technique.dart';
import 'package:kinetic/repositories/technique_repository.dart';
import 'package:kinetic/screens/technique_edit_screen.dart';

void main() {
  testWidgets(
    'toont alle secties voor een bestaande techniek met naam, categorie en video',
    (tester) async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final technique = Technique(
        id: 't1',
        name: 'Harai Goshi',
        category: 'Takedown',
        favorite: true,
        description: 'Heupworp',
        videoUrls: const ['https://www.tiktok.com/@user/video/12345'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TechniqueEditScreen(
            repository: TechniqueRepository(client),
            userId: 'u1',
            technique: technique,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Techniek aanpassen'), findsOneWidget);
      expect(find.text('NAAM'), findsOneWidget);
      expect(find.text('CATEGORIE'), findsOneWidget);

      // De rest van het formulier staat verder dan het standaard testviewport
      // (vooral nu de van/naar-transitiekiezer meer ruimte inneemt dan de
      // oude chips) — scrollen zodat Flutter die elementen ook echt bouwt.
      final listScrollable = find.byType(Scrollable).first;

      await tester.scrollUntilVisible(
        find.text('BESCHRIJVING (OPTIONEEL)'),
        200,
        scrollable: listScrollable,
      );
      expect(find.text('BESCHRIJVING (OPTIONEEL)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('VIDEO\'S (OPTIONEEL)'),
        200,
        scrollable: listScrollable,
      );
      expect(find.text('VIDEO\'S (OPTIONEEL)'), findsOneWidget);
      // Zonder eigen naam: "Naam geven" met de ingekorte link eronder.
      expect(find.text('tiktok.com/@user/video/12345'), findsOneWidget);
      expect(find.text('Naam geven'), findsOneWidget);

      expect(find.text('Wijzigingen bewaren'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('toont het lege formulier voor een nieuwe techniek', (
    tester,
  ) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TechniqueEditScreen(
          repository: TechniqueRepository(client),
          userId: 'u1',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nieuwe techniek'), findsOneWidget);
    expect(find.text('NAAM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'transitie staat standaard ingeklapt voor een nieuwe techniek en klapt open bij tikken',
    (tester) async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TechniqueEditScreen(
            repository: TechniqueRepository(client),
            userId: 'u1',
          ),
        ),
      );
      await tester.pump();

      final listScrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('TRANSITIE (OPTIONEEL) — VOOR DE KAART'),
        200,
        scrollable: listScrollable,
      );

      // Ingeklapt: de van/naar-chips zijn er nog niet, wel de samenvatting.
      expect(find.text('Niet ingesteld'), findsOneWidget);
      expect(find.text('Van', skipOffstage: false), findsNothing);
      expect(find.text('Staand', skipOffstage: false), findsNothing);

      await tester.tap(find.text('TRANSITIE (OPTIONEEL) — VOOR DE KAART'));
      await tester.pump();

      expect(find.text('Niet ingesteld'), findsNothing);
      expect(find.text('Van'), findsOneWidget);
      expect(find.text('Staand'), findsWidgets);
    },
  );

  testWidgets(
    'transitie staat standaard open als er al een van/naar gekozen is',
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
          home: TechniqueEditScreen(
            repository: TechniqueRepository(client),
            userId: 'u1',
            technique: technique,
          ),
        ),
      );
      await tester.pump();

      final listScrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('TRANSITIE (OPTIONEEL) — VOOR DE KAART'),
        200,
        scrollable: listScrollable,
      );

      expect(find.text('Van'), findsOneWidget);
      expect(find.text('Niet ingesteld'), findsNothing);
    },
  );

  testWidgets(
    'grondposities bij Submission sluiten elkaar niet uit — je kunt er meerdere kiezen',
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
          home: TechniqueEditScreen(
            repository: TechniqueRepository(client),
            userId: 'u1',
            technique: technique,
          ),
        ),
      );
      await tester.pump();

      final listScrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Vanuit welke positie(s) (optioneel)'),
        200,
        scrollable: listScrollable,
      );

      Color? colorOf(String label) =>
          tester.widget<Text>(find.text(label)).style?.color;

      final unselected = colorOf('Half guard');

      await tester.tap(find.text('Mount'));
      await tester.pump();
      await tester.tap(find.text('Guard'));
      await tester.pump();

      // Beide gekozen chips blijven actief — kiezen van "Guard" heft "Mount"
      // niet op, in tegenstelling tot de van/naar-kiezer hierboven.
      expect(colorOf('Mount'), isNot(unselected));
      expect(colorOf('Guard'), isNot(unselected));
      expect(colorOf('Half guard'), unselected);

      // Nogmaals tikken op "Mount" zet hem weer uit, "Guard" blijft staan.
      await tester.tap(find.text('Mount'));
      await tester.pump();
      expect(colorOf('Mount'), unselected);
      expect(colorOf('Guard'), isNot(unselected));
    },
  );
}
