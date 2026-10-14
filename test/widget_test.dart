import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/main.dart';
import 'package:kinetic/state/app_controller.dart';

void main() {
  testWidgets('shows Supabase configuration message without dart defines', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(controller: AppController()..state = AppBootState.needsConfig),
    );

    expect(find.text('Supabase configureren'), findsOneWidget);
  });
}
