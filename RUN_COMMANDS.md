# Run commands for installing the APK or running the debug APK

Both sections offer two equivalent options: pass the values inline, or load them from `dart_defines.json`.

## Installing (release APK)

**PowerShell (Windows): inline values**

```powershell
flutter clean
flutter pub get
flutter build apk --release `
  --dart-define="SUPABASE_URL=https://wpexdeglubtzkdejehkj.supabase.co" `
  --dart-define="SUPABASE_PUBLISHABLE_KEY=sb_publishable_zzZXBVJMVGY5BL5HiY95BA_S7Oqx7ZC" `
  --dart-define="NIGHTSCOUT_URL=https://cgm-remote-monitor-latest-urlj.onrender.com"
```

**PowerShell (Windows): from file**

```powershell
flutter clean
flutter pub get
flutter build apk --release --dart-define-from-file=dart_defines.json
```

## Debugging

**PowerShell (Windows): inline values**

```powershell
flutter run `
  --dart-define="SUPABASE_URL=https://wpexdeglubtzkdejehkj.supabase.co" `
  --dart-define="SUPABASE_PUBLISHABLE_KEY=sb_publishable_zzZXBVJMVGY5BL5HiY95BA_S7Oqx7ZC" `
  --dart-define="NIGHTSCOUT_URL=https://cgm-remote-monitor-latest-urlj.onrender.com"
```

**PowerShell (Windows): from file**

```powershell
flutter run --dart-define-from-file=dart_defines.json
```

## `dart_defines.json`

Place this in the project root:

```json
{
  "SUPABASE_URL": "https://wpexdeglubtzkdejehkj.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_zzZXBVJMVGY5BL5HiY95BA_S7Oqx7ZC",
  "NIGHTSCOUT_URL": "https://cgm-remote-monitor-latest-urlj.onrender.com"
}
```