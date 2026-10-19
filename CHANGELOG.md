# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [1.1.1] - 2026-10-19

### Fixed

- Sign release APKs with one persistent release keystore restored from GitHub Actions secrets.
- Reject release builds without signing configuration and verify the expected certificate before publishing.

### Migration

- Older GitHub releases used different temporary debug keys. Uninstall those versions once before installing 1.1.1; local app data is cleared. Future releases retain the new signing identity and support installation as updates.

## [1.1.0] - 2026-10-19

### Added

- Shared disk cache for light and dark map tiles, with storage and cache controls in Settings.
- Collapsible map details, independent route layers, and improved schedules and route discovery.
- Automated coverage for networking, caching, map interactions, and background alert recovery.

### Changed

- Load coordinates, route geometry, and arrival estimates independently, with cached data shown immediately.
- Share and prioritize network requests, cancel unused work, and retry failed live updates with backoff.
- Coordinate foreground and background polling and persist alert notification claims to prevent duplicates.
- Reuse OpenStreetMap tiles across themes with local dark-mode rendering.
- Pin the release workflow to Flutter 3.41.9 and run analysis and tests before building the APK.

### Fixed

- Prevent historical bus positions from triggering stop alerts.
- Retain last-known positions and active alerts when live requests fail.

## [0.1.0] - 2026-05-03

### Added

- Initial repository hygiene and documentation setup.
- Stack-specific `.gitignore` for Flutter/Android development.
- `README.md` with setup, run, build, configuration, and troubleshooting guidance.
- `LICENSE` (MIT).
- `CONTRIBUTING.md` contribution workflow and quality checklist.
