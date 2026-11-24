// main.dart: Kinetic 2.0. Start Supabase, het Kinetic Dark Theme en de
// routes uit de spec: 5 tabs in de shell plus de full-screen stack-schermen.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/auth_screen.dart';
import 'screens/competitions_screen.dart';
import 'screens/live_session_screen.dart';
import 'screens/ronde_rust_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/telemetrie_export_screen.dart';
import 'state/kinetic_store.dart';
import 'theme/kinetic_theme.dart';
import 'widgets/kinetic_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Een widget die niet kan renderen toont een begrijpelijke melding in
  // plaats van een grijze vlek in een release-build.
  ErrorWidget.builder = (details) {
    debugPrint('Widget kon niet worden weergegeven: ${details.exception}');
    return Container(
      color: KColor.bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Text(
        'Er ging iets mis bij het weergeven van dit onderdeel.',
        textAlign: TextAlign.center,
        style: KText.caption,
      ),
    );
  };
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: KColor.surface,
  ));
  final store = KineticStore();
  runApp(KineticApp(store: store));
  await store.boot();
}

class KineticApp extends StatelessWidget {
  const KineticApp({super.key, required this.store});
  final KineticStore store;

  @override
  Widget build(BuildContext context) {
    return KineticScope(
      store: store,
      child: MaterialApp(
        title: 'Kinetic',
        debugShowCheckedModeBanner: false,
        theme: kineticTheme(),
        darkTheme: kineticTheme(),
        themeMode: ThemeMode.dark,
        home: const _Home(),
        onGenerateRoute: (settings) {
          final Widget? page = switch (settings.name) {
            '/live-session' => const LiveSessionScreen(),
            '/ronde-rust' => const RondeRustScreen(),
            '/competitions' => const CompetitionsScreen(),
            '/telemetrie-export' => const TelemetrieExportScreen(),
            _ => null,
          };
          if (page == null) return null;
          // Live-schermen schuiven als full-screen modal van onderen in.
          final modal = settings.name == '/live-session' || settings.name == '/ronde-rust';
          return MaterialPageRoute<void>(
            settings: settings,
            fullscreenDialog: modal,
            builder: (_) => page,
          );
        },
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    return switch (store.state) {
      BootState.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
      BootState.needsConfig => const _MissingConfig(),
      BootState.signedOut => const AuthScreen(),
      BootState.ready => const ShellScreen(),
    };
  }
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Supabase configureren', style: KText.display),
              const SizedBox(height: 12),
              Text(
                'Start de app met --dart-define-from-file=dart_defines.json '
                '(SUPABASE_URL en SUPABASE_PUBLISHABLE_KEY).',
                style: KText.body.copyWith(color: KColor.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
