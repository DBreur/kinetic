// combination_detail_screen_test.dart — een combinatie opslaan vereist
// alleen een naam, geen enkele techniek: dat is expliciet veranderd zodat je
// een combinatie als plekhouder kunt aanmaken en later aanvullen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kinetic/repositories/combination_repository.dart';
import 'package:kinetic/screens/combination_detail_screen.dart';
import 'package:kinetic/theme/kinetic_theme.dart';

void main() {
  CombinationRepository repository() => CombinationRepository(
    SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
  );

  testWidgets('opslaan zonder naam toont een foutmelding en slaat niet op', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KineticTheme.dark,
        home: CombinationDetailScreen(repository: repository(), userId: 'u1'),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Wijzigingen bewaren'));
    await tester.pump();

    expect(find.text('Geef de combinatie een naam.'), findsOneWidget);
    expect(find.text('Wijzigingen bewaren'), findsOneWidget);
    expect(find.text('Opslaan...'), findsNothing);
  });

  testWidgets(
    'opslaan zonder technieken is toegestaan — alleen de naam is verplicht',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: KineticTheme.dark,
          home: CombinationDetailScreen(
            repository: repository(),
            userId: 'u1',
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Jab-cross-hook');
      await tester.tap(find.text('Wijzigingen bewaren'));
      await tester.pumpAndSettle();

      // Geen blokkerende melding meer over ontbrekende technieken — het
      // opslaan is daadwerkelijk gestart en pas op het (onbereikbare)
      // netwerk misgelopen, niet op de techniekenvalidatie.
      expect(
        find.text('Voeg minstens één techniek aan de combinatie toe.'),
        findsNothing,
      );
      expect(find.text('Opslaan is niet gelukt. Probeer opnieuw.'), findsOneWidget);
    },
  );

  testWidgets(
    'de VIDEO\'S-sectie bouwt zonder te crashen en het invoerveld accepteert tekst',
    (tester) async {
      // Regressietest: de ronde "+"-knop hiernaast erfde zonder expliciete
      // minimumSize de globale OutlinedButton-stijl (Size.fromHeight = een
      // oneindige breedte-eis), wat crasht zodra hij als niet-Expanded kind
      // in deze Row staat — de hele sectie bouwde daardoor niet (geen
      // zichtbaar invoerveld, geen foutmelding op het scherm zelf).
      await tester.pumpWidget(
        MaterialApp(
          theme: KineticTheme.dark,
          home: CombinationDetailScreen(
            repository: repository(),
            userId: 'u1',
          ),
        ),
      );
      await tester.pump();

      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 10; i++) {
        await tester.drag(scrollable, const Offset(0, -400));
        await tester.pump();
      }

      expect(tester.takeException(), isNull);

      final urlField = find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.url,
      );
      expect(urlField, findsOneWidget);

      await tester.enterText(urlField, 'https://example.com/video');
      await tester.pump();
      expect(find.text('https://example.com/video'), findsOneWidget);

      // Niet ook nog op de "+"-knop tikken: dat rendert daarna
      // CollapsibleVideoList, wat een WebView-platforminstantie vereist die
      // in deze testomgeving niet beschikbaar is — los van de crash die
      // deze test moet vastleggen (het veld zelf bouwen zonder te gooien).
      expect(find.widgetWithIcon(OutlinedButton, Icons.add), findsOneWidget);
    },
  );
}
