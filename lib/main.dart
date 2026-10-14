import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/kinetic_localizations.dart';
import 'services/system_bars.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell_screen.dart';
import 'state/app_controller.dart';
import 'theme/kinetic_theme.dart' as color;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Zonder dit toont een widget die niet kan renderen (een bug) een volledig
  // lege/grijze vlek in een release-build — dit geeft in plaats daarvan
  // altijd een zichtbare, begrijpelijke melding, met de technische details
  // in de devconsole voor het debuggen.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('Widget kon niet worden weergegeven: ${details.exception}');
    return Container(
      color: color.AppColor.bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Text(
        'Er ging iets mis bij het weergeven van dit onderdeel.',
        textAlign: TextAlign.center,
        style: color.AppText.caption,
      ),
    );
  };
  await initializeDateFormatting('nl_NL');
  final controller = AppController();
  await controller.boot();
  runApp(MyApp(controller: controller));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Kinetic',
          theme: color.KineticTheme.dark,
          locale: kineticLocale,
          supportedLocales: const [kineticLocale],
          localizationsDelegates: kineticLocalizationsDelegates(
            controller.profile?.weekStart ?? 1,
          ),
          // Tijden altijd als 19:00, niet 7:00 PM — ook in tijdkiezers.
          builder: kineticAppBuilder,
          home: _Home(controller: controller),
        );
      },
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.state) {
      AppBootState.loading => const _BootLoading(),
      AppBootState.needsConfig => const _MissingConfigScreen(),
      AppBootState.signedOut => AuthScreen(controller: controller),
      AppBootState.needsOnboarding => OnboardingScreen(controller: controller),
      AppBootState.ready => ShellScreen(controller: controller),
    };
  }
}

class _BootLoading extends StatelessWidget {
  const _BootLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: color.AppColor.bg,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: color.AppColor.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Supabase configureren', style: color.AppText.display),
              const SizedBox(height: 12),
              Text(
                'Start de app met --dart-define-from-file=dart_defines.json (SUPABASE_URL en SUPABASE_PUBLISHABLE_KEY). '
                'Zonder deze waarden worden er geen wachtwoorden of sessies lokaal opgeslagen.',
                style: color.AppText.body.copyWith(
                  color: color.AppColor.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
