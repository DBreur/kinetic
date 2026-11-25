# Run commands: Kinetic 2.0

Supabase-sleutels staan in `dart_defines.json` (staat in `.gitignore`):

```json
{
  "SUPABASE_URL": "https://wpexdeglubtzkdejehkj.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_..."
}
```

Zie `dart_defines.example.json` voor de vorm. Zonder dit bestand kun je in de
app niet inloggen; bouw je op een andere computer, zet het daar eerst neer.

## Debuggen

```powershell
flutter run --dart-define-from-file=dart_defines.json
```

In VS Code doet de launch-configuratie "Kinetic" hetzelfde.

Draadloos via adb valt `flutter run` soms weg. Dan bouwen en zelf installeren:

```powershell
flutter build apk --debug --dart-define-from-file=dart_defines.json
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb shell monkey -p com.example.kinetic -c android.intent.category.LAUNCHER 1
```

## Release-APK

```powershell
flutter build apk --release --dart-define-from-file=dart_defines.json
```

De APK staat daarna in `build\app\outputs\flutter-apk\`, zowel als
`app-release.apk` als met versienaam: **`kinetic-<versie>-b<build>.apk`**
(bv. `kinetic-2.0.0-b23.apk`). Versie en buildnummer komen uit
`version: 2.0.0+23` in `pubspec.yaml`; de hernoeming zit in
`android/app/build.gradle.kts`.

Kleiner bestand (alleen 64-bit telefoons, dat zijn vrijwel alle toestellen
van de laatste jaren): voeg `--target-platform android-arm64` toe.

> **Vóór elke nieuwe release:** verhoog het buildnummer in `pubspec.yaml`
> (`version: 2.0.0+23` → `2.0.0+24`). Het buildnummer moet hoger zijn dan dat
> van de geïnstalleerde app
> (`adb shell dumpsys package com.example.kinetic | findstr versionCode`),
> anders weigert Android de update. Verwijderen en opnieuw installeren wist
> ook het Dexcom-wachtwoord uit de versleutelde opslag (de rest staat in Supabase).

> **Ondertekening:** de release wordt nog met de debug-sleutel van deze
> computer ondertekend. Updates over een bestaande installatie heen werken
> alleen met dezelfde sleutel: bouw dus steeds op dezelfde computer (of stel
> een eigen keystore in vóór je naar de Play Store gaat).

## Launcher-icoon

De iconen in `android/app/src/main/res/` (`mipmap-*/ic_launcher.png` en
`drawable-*/ic_launcher_foreground.png`) zijn gemaakt uit
`kinetic-design/kinetic_logo/screen.png`; achtergrondkleur `#0B0F14` in
`values/colors.xml`. Na een nieuw logo die bestanden opnieuw genereren
(legacy 48 dp, adaptive voorgrond 108 dp per dichtheid).

## Tests

```powershell
flutter analyze
flutter test                                   # unit + widget tests
flutter test tool/design_shots_test.dart --dart-define=SHOTS_DIR=build/shots
```

De laatste rendert alle schermen met seed-data naar PNG (zonder Supabase).

## Supabase

- Project ref: `wpexdeglubtzkdejehkj`. CLI gekoppeld met `supabase link --project-ref wpexdeglubtzkdejehkj --workdir lib`.
- Migraties staan in `lib/supabase/migrations/` en zijn met de hand (SQL Editor) of via de Management API gedraaid.
  **Gebruik geen `supabase db push`**: de migratiehistorie van de CLI is leeg, dus die zou alles opnieuw draaien.
- Laatst gedraaid: `202611250001_technique_videos_bucket.sql` (privé-bucket `technique-videos` voor eigen video's), 25-11-2026.
- Tabellen die de app gebruikt: `profiles` (o.a. presets, `bolus_periods`, `correction_*`),
  `food_log_entries` (maaltijden met macro's, `context` en insuline voeding/correctie/totaal),
  `weigh_ins`, `competitions`, `techniques`, `technique_library`, `combinations`, `systems`,
  `planned_trainings`, `training_sessions`, `glucose_entries`, en Storage-bucket `technique-videos`.
