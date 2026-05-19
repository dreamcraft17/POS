# e+e POS

Flutter-based Point of Sale app.

## Prerequisites

- Flutter SDK (Dart 3.3+)
- Android SDK + Android Studio (for Android builds)

## Setup

1. Install dependencies:
   - `flutter pub get`
2. Run app in debug:
   - `flutter run`

## API Configuration

`lib/config.dart` reads API URL from dart-define:

- Key: `API_URL`
- Default: `https://cafepos2.epluseglobal.com/pos-api/public`

Example run:

- `flutter run --dart-define=API_URL=https://your-api-host/pos-api/public`

## Android Release Signing

Release signing values can be loaded from:

- `android/gradle.properties`, or
- Environment variables (`RELEASE_STORE_FILE`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, `RELEASE_KEY_PASSWORD`)

Recommended local setup:

1. Copy `android/gradle.properties.local.example` to `android/gradle.properties.local`.
2. Fill in your real keystore values in `android/gradle.properties.local`.
3. Pass those values as environment variables when building release, or place them in your local/private Gradle config.

Important: never commit real passwords or private keystore files.

## Useful Commands

- Static analyze: `flutter analyze`
- Run tests: `flutter test`
- Build APK release: `flutter build apk --release`

## Performance notes

- Use one shared API client: `ApiService.shared()` (session/cookies reused).
- Offline sync at startup: `SyncManager` only (`offline_queue` table). Do not also start `SyncService.start()` unless you migrate to the `outbox` table.
- Tax settings: `taxSettingsProvider` — cart updates after saving taxes in Settings.
- Search on POS home is debounced (180ms) to reduce rebuild churn while typing.

## Project layout (lib)

| Area | Path |
|------|------|
| POS screen | `pages/pos_home.dart`, `widgets/menu_grid.dart`, `widgets/cart_panel.dart` |
| API | `services/api_service.dart`, `config.dart` |
| Offline | `services/sync_manager.dart`, `repositories/offline_queue_repo.dart` |
| Local DB | `db/local_db.dart`, repos under `repositories/` |
| Settings | `pages/settings_page.dart`, `widgets/settings/` |
| Printing | `widgets/bill_receipt.dart`, `services/printer_prefs.dart` |
