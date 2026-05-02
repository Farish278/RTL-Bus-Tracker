# RTL Bus Tracker

Android-first Flutter application for tracking RTL bus routes, live vehicle positions, stop ETAs, and nearby stop alerts.

## Key Features

- Live bus tracking on map (`flutter_map`)
- Route and stop exploration by area
- Stop ETAs and route schedule views
- Distance-based alert notifications for selected stops
- Cache-first startup for faster initial load
- Theme customization (system/light/dark + accent themes)

## Tech Stack

- Flutter `3.41.9`
- Dart `3.11.5`
- State management: `flutter_riverpod`
- Navigation: `go_router`
- Networking: `dio`
- Local storage: `sqflite`, `shared_preferences`
- Maps: `flutter_map`, `latlong2`
- Background/alerts: `flutter_background_service`, `workmanager`, `flutter_local_notifications`
- Platform: Android (primary)

## Requirements

- Flutter SDK `3.41.9` (or compatible with Dart `3.11.5`)
- Android Studio + Android SDK
- At least one Android emulator or physical Android device

## Installation

1. Clone the repository.
2. Install dependencies:

```bash
flutter pub get
```

## Run Locally

```bash
flutter run
```

Useful variants:

```bash
flutter run -d <device-id>
flutter run --release -d <device-id>
```

## Build / Release

Build Android APK (debug):

```bash
flutter build apk --debug
```

Build Android APK (release):

```bash
flutter build apk --release
```

Note:
- `android/app/build.gradle.kts` currently signs release builds with the debug signing config for internal testing. Configure proper release signing before production distribution.

## Configuration / Environment Variables

This project currently uses in-code app configuration in `lib/core/config/app_config.dart` (for example API base URL and default map area).

No runtime `.env` loader is configured in code at this time.

Android local machine config:
- `android/local.properties` is required locally (Flutter SDK path) and is intentionally not tracked.

## Project Structure

```text
rtl_bus_tracker/
+- android/
+- assets/
+- lib/
¦  +- app/
¦  +- core/
¦  +- features/
¦     +- map/
¦     +- settings/
+- test/
+- pubspec.yaml
+- README.md
```

Main entry points:
- App bootstrap: `lib/main.dart`
- App shell/router/theme: `lib/app/`
- Android app module: `android/app/`

## Troubleshooting

- `flutter` command not found:
  - Ensure Flutter is installed and added to `PATH`.
- Android build fails with SDK/Gradle issues:
  - Open Android Studio once and let it install/update required SDK components.
- Stale/corrupt build output:

```bash
flutter clean
flutter pub get
```

- No connected devices:

```bash
flutter devices
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
