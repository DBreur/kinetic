# Run commands for installing the APK or running the debug APK

Both sections offer two equivalent options: pass the values inline, or load them from `dart_defines.json`.

## Installing (release APK)

**Recommended: bump the version and build in one step**

```powershell
.\build_apk.ps1                # 1.0.0+1 -> 1.0.0+2 (build number only)
.\build_apk.ps1 -Bump patch    # 1.0.0+1 -> 1.0.1+2 (also: minor, major)
.\build_apk.ps1 -Clean         # runs flutter clean first
```

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

## Spotify (one-time setup)

The Spotify button during a training uses the Spotify app on your phone. You need **Spotify Premium** for skip and queue.

1. Go to <https://developer.spotify.com/dashboard> and create an app (choose **Android** as the platform).
2. Add the Android package `com.example.kinetic` with the SHA-1 fingerprint of the signing key. The release build is currently signed with the debug key, so print that fingerprint with:

   ```powershell
   keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
   ```

   Copy the line that starts with `SHA1:`.
3. Add the Redirect URI `kinetic://spotify-auth` (exactly this value).
4. Put the Client ID in `dart_defines.json`:

   ```json
   "SPOTIFY_CLIENT_ID": "<your client id>"
   ```

5. Build again with `.\build_apk.ps1`.

## Database migrations

Run new files from `lib/supabase/migrations/` once in the Supabase dashboard (SQL Editor). The latest one is `202610200001_alarm_snooze_rest_and_weigh_ins.sql`, which adds the snooze time, the default rest and weighing with dates.
