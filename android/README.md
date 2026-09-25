# Call.md — Android

This folder is the **Capacitor Android shell** for Call.md. The same React renderer (`src/renderer`) that runs in Electron now runs inside an Android WebView, with native capabilities via Capacitor plugins. The Bend intelligence core runs as JS (fallback) on device — same formulas as `bend/*.bend`, just transpiled.

## Architecture

```
Electron Desktop:  renderer (Vite)  ↔  HTTP  ↔  Hono/tRPC (Node main, better-sqlite3)
Android:           renderer (WebView) ↔  local (Preferences + IndexedDB) ↔  Bend JS fallback
                                       ↔  CapacitorHttp  ↔  remote tRPC (optional)
                                       ↔  MediaRecorder / Filesystem
```

- **Config / auth**: Desktop uses `safeStorage` + encrypted SQLite row. Android uses `Capacitor Preferences` (`SharedPreferences`, Keystore-backed when hardware supports it) + in-memory `accessToken` in Zustand.
- **DB**: Desktop `better-sqlite3`. Android `IndexedDB` (`src/renderer/lib/android-storage.ts`) with JSON fallback to Preferences. Swap to `@capacitor-community/sqlite` by installing it and replacing `openDB()` — no other code changes needed.
- **Recording**: Desktop `videodb/bin/capture` (darwin-arm64, win32-x64). Android `MediaRecorder` + `getDisplayMedia` (see `src/mobile/capture-android.ts`). Screen capture uses the system MediaProjection dialog — no static permission.
- **Bend**: Desktop can load `bend/call.hvm` via `src/main/services/bend-bridge.service.ts`. Android uses the JS fallback (`fallbackCalcMetrics`) — byte-identical to Bend, just not GPU-parallel. A future WASM build of HVM can be linked via NDK.

## Prerequisites

- Node 22.12+, npm 10+
- Android Studio (Hedgehog+) with SDK 36, NDK optional, JDK 17
- `ANDROID_HOME` set (e.g. `export ANDROID_HOME=$HOME/Android/Sdk`)
- For release signing, a keystore (`android/app/release.keystore` — gitignored)

Check:

```bash
npx cap doctor
# should print: Capacitor Doctor — android ✓
```

## Quick start (debug APK on device/emulator)

```bash
# 1) install deps (once)
npm ci --ignore-scripts

# 2) build renderer for Android (CAPACITOR=1 omits Electron-only widget.html)
npm run build:renderer:android

# 3) copy web assets + sync plugins
npx cap copy android
npx cap sync android   # or: npm run android:sync

# 4) open in Android Studio (first time) — inspect signing, run on device
npm run android:open
# — or CLI:
npm run android:build   # → android/app/build/outputs/apk/debug/app-debug.apk
adb install android/app/build/outputs/apk/debug/app-debug.apk
adb logcat | grep -i "callmd\|Capacitor"

# 5) live reload during development (renderer on Vite, WebView proxies)
npm run dev:android     # vite --host 0.0.0.0
# then in another shell:
npx cap run android --livereload --external
# or manually: npx cap copy android && npx cap open android
```

## Live reload vs production

- `dev:android` + `cap run --livereload` → WebView loads `http://<your-laptop-ip>:51730` (Vite). Fastest.
- `build:renderer:android` + `cap copy` → WebView loads `capacitor://localhost` from `dist/renderer` (bundled). What you ship.

`capacitor.config.ts` has `android.allowMixedContent: true` and `webContentsDebuggingEnabled: true` so `chrome://inspect` works in debug builds.

## Permissions

`android/app/src/main/AndroidManifest.xml` already requests:

- `RECORD_AUDIO` (mic), `CAMERA` (optional), `MODIFY_AUDIO_SETTINGS`
- `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PROJECTION|MICROPHONE` (keeps recording alive in background)
- `POST_NOTIFICATIONS` (5-min warning), `WAKE_LOCK`
- `INTERNET`, `ACCESS_NETWORK_STATE`, `READ_MEDIA_AUDIO`

Runtime prompts: mic is requested via `getUserMedia` on first recording (see `src/renderer/hooks/usePermissions.ts` — Android branch). Screen capture shows the system MediaProjection dialog per session. No persistent `SYSTEM_ALERT_WINDOW` needed.

Foreground service: `android/app/src/main/java/com/videodb/callmd/RecordingService.java` shows a sticky “Call.md is recording” notification while `MediaRecorder` is active. The JS side in `src/mobile/capture-android.ts` starts the service before recording and stops after.

OAuth: `OAuthCallbackActivity` intercepts `com.videodb.callmd://oauth/callback` (was `call-md://` on desktop) and forwards to `MainActivity`. Configure your Google OAuth client with that URI.

## Config

- `capacitor.config.ts` — `appId: com.videodb.callmd`, `webDir: dist/renderer`, `androidScheme: https`
- `VITE_ANDROID_API_URL` — optional remote tRPC URL. If unset, the app runs fully offline (Preferences + IndexedDB + on-device Bend). If set (e.g. `https://api.callmd.internal`), `src/renderer/api/android-trpc.ts` proxies `httpBatchLink` there via `CapacitorHttp`.

```bash
# example: point Android at staging
VITE_ANDROID_API_URL=https://staging.callmd.videodb.io npm run build:renderer:android
npx cap copy android
```

- `VITE_BEND_WASM_URL` — future: point to HVM WASM bundle for GPU-parallel metrics on device.

## Project layout

```
android/                               Capacitor Android project (commit it)
  app/src/main/
    AndroidManifest.xml                permissions + deep links + foreground service
    java/com/videodb/callmd/
      MainActivity.java                BridgeActivity, edge-to-edge, FLAG_KEEP_SCREEN_ON
      RecordingService.java            foreground notification for background recording
      OAuthCallbackActivity.java       com.videodb.callmd://oauth/callback
    res/…                              icons, splash, strings
  capacitor.settings.gradle            auto-generated — do not hand-edit
  variables.gradle                     compileSdk 36, minSdk 24, targetSdk 36

src/renderer/lib/
  platform.ts                          isAndroid() / isElectron() / isWeb()
  android-bridge.ts                    installs window.electronAPI shim on Android
  android-storage.ts                   IndexedDB ↔ Preferences fallback for recordings

src/renderer/
  main.tsx                             installs bridge + StatusBar + SplashScreen + back handling
  api/trpc.ts                          0-port sentinel on Android, remote or mock fetch
  api/android-trpc.ts                  CapacitorHttp helper
  hooks/usePermissions.ts              Android branch uses Permissions API + getUserMedia
  stores/config.store.ts               dual path: electronAPI vs Preferences
  components/layout/NewSidebar.tsx     bottom tab bar on Android

src/mobile/
  capture-android.ts                   MediaRecorder + getDisplayMedia wrapper
```

## Release

1. Create keystore once:
   ```bash
   keytool -genkey -v -keystore android/app/release.keystore -alias callmd -keyalg RSA -keysize 2048 -validity 10000
   # add to android/gradle.properties (gitignored):
   # MYAPP_RELEASE_STORE_FILE=release.keystore
   # MYAPP_RELEASE_KEY_ALIAS=callmd
   # MYAPP_RELEASE_STORE_PASSWORD=…
   # MYAPP_RELEASE_KEY_PASSWORD=…
   ```
2. Wire signing in `android/app/build.gradle` `signingConfigs.release`.
3. Build:
   ```bash
   npm run android:build:release   # → android/app/build/outputs/apk/release/app-release.apk
   # or AAB for Play Store:
   cd android && ./gradlew bundleRelease  # → app/build/outputs/bundle/release/app-release.aab
   ```

CI example (`.github/workflows/android.yml`):
```yaml
- uses: actions/setup-java@v4
  with: { java-version: 17, distribution: temurin }
- uses: android-actions/setup-android@v3
- run: npm ci --ignore-scripts
- run: npm run build:renderer:android && npx cap sync android
- run: cd android && ./gradlew assembleDebug
- uses: actions/upload-artifact@v4
  with: { name: apk, path: android/app/build/outputs/apk/debug/app-debug.apk }
```

## Troubleshooting

- `adb devices` empty → Enable developer options + USB debugging, accept RSA prompt.
- `RECORD_AUDIO` denied → App → Settings → Permissions → Microphone → Allow. On WebView, permission is per-origin; reinstall clears it.
- `chrome://inspect` shows blank → `android:webContentsDebuggingEnabled` only in debug builds; use `assembleDebug` not `assembleRelease`.
- `CapacitorHttp` CORS → On Android `capacitor://localhost` is a secure context; ensure server sends `Access-Control-Allow-Origin: capacitor://localhost` or `https://localhost`.
- DB missing after update → IndexedDB is wiped if the app is uninstalled (but not on update). Preferences survives. For durable history, enable `@capacitor-community/sqlite`.
- Audio only, no system audio → Android 10+ only exposes system audio via `getDisplayMedia({audio:true})` and only when the user picks the system screen; otherwise mic-only is expected.
- Bend not parallel on Android → Expected; JS fallback is single-threaded. HVM→WASM is on the roadmap.

## Bend on Android

`bend/*.bend` typechecks on desktop (`bend check bend/Main.bend`). On Android the app uses `src/main/services/bend-bridge.service.ts` `fallbackCalcMetrics` — same thresholds (45 s monologue, 0.35–0.55 ratio, 180 WPM) transpiled to JS. To run HVM on device, compile Bend to C/WASM and load via NDK/JNI (see `bend/Bend.toml` `ffi`).

## See also

- `capacitor.config.ts`
- `bend/README.md` — Bend rebuild notes
- `README.md` — Desktop (Electron) docs
