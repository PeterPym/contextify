Based on the commits and file changes, here are the release notes for v1.0.2:

### Added
- Pulsing animation on the indexing status icon to indicate active background processing

### Fixed
- App Store build now properly handles sandbox permissions at startup, fixing issues where transcript monitoring wouldn't start after initial permission grant
- Permission changes made in Settings now immediately trigger transcript provider reconfiguration, eliminating the need to restart the app
- External project switches (e.g., from CLI) now properly create security-scoped bookmarks, fixing monitoring failures for newly-opened projects
- Reduced noise in logs by downgrading expected bookmark warning messages to debug level
