# Run commands: Kinetic 2.0

Supabase-sleutels staan in `dart_defines.json` (staat in `.gitignore`):

```json
{
  "SUPABASE_URL": "https://wpexdeglubtzkdejehkj.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_..."
}
```

Zie `dart_defines.example.json` voor de vorm.

## Debuggen

```powershell
flutter run --dart-define-from-file=dart_defines.json
```

In VS Code doet de launch-configuratie "Kinetic" hetzelfde.

## Release-APK

```powershell
flutter build apk --release --dart-define-from-file=dart_defines.json
```

> **Let op vóór installeren op je telefoon:** het build-nummer in `pubspec.yaml`
> (`version: x.y.z+N`) moet hoger zijn dan dat van de geïnstalleerde app
> (`adb shell dumpsys package com.example.kinetic | findstr versionCode`).
> Anders weigert Android de update. `flutter run` verwijdert de app dan en
> daarmee het Dexcom-wachtwoord uit de versleutelde opslag.

## Tests

```powershell
flutter test                                   # unit + widget tests
flutter test tool/design_shots_test.dart --dart-define=SHOTS_DIR=build/shots
```

De tweede rendert alle schermen met seed-data naar PNG (zonder Supabase).

## Supabase

- Project ref: `wpexdeglubtzkdejehkj`. CLI gekoppeld met `supabase link --project-ref wpexdeglubtzkdejehkj --workdir lib`.
- Migraties staan in `lib/supabase/migrations/` en zijn met de hand of via de Management API gedraaid.
  **Gebruik geen `supabase db push`**: de migratiehistorie van de CLI is leeg, dus die zou alles opnieuw draaien.
- Tabellen die de app gebruikt: `profiles`, `food_log_entries` (maaltijden, sinds 202611240001 met
  `protein`/`fat`/`context`), `weigh_ins`, `competitions`, `techniques`, `training_sessions`, `glucose_entries`.
