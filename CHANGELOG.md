# Changelog

Format is based on [_Keep a changelog_](https://keepachangelog.com) and uses
[_Semantic versioning_](https://semver.org).

## [0.3.0] - 2026-05-10
### Added
- Added General settings for launch at login, subscription config ordering, menu bar picker latency display, and menu bar icon animation.
- Added latency-based ordering for subscription configs in Settings and the menu bar picker.
- Added a subtle animated menu bar icon with cached portal particle frames.
- Added app icon, helper version, copyright, and license information to the About settings page.

### Changed
- Reworked Settings to use a native macOS sidebar/form layout.
- Simplified Nerd Shit settings to focus on logs with direct refresh and copy actions.
- Improved Teleport mode labeling and disabled mode changes while a connection session is active.
- Updated bundled subscription defaults.

### Fixed
- Stabilized the menu bar connection picker during subscription and health updates.
- Avoided blocking the UI when switching Teleport modes while disconnected.
- Disabled subscription health-check actions while checks are queued or running.

## [0.2.0] - 2026-05-10
### Added
- VPN mode is now the default connection mode.
- Bundled subscription sources are seeded on first launch.

### Changed
- Privileged helper runtime state, VPN logs, and VPN config now live under a root-owned private helper directory.
- App configuration secrets are migrated from plaintext state to Keychain-backed storage.
- VPN logs are read through authenticated helper IPC instead of direct world-readable files.

### Fixed
- Hardened privileged helper request validation, peer authorization, process termination, and shell output handling.
- Verified privileged install artifacts before installing helper/Xray binaries as root.
- Rejected duplicate connection query parameters instead of crashing on malformed subscription links.
- Improved subscription list display and duplicate display-name handling.

## [0.1.0] - 2025-05-07
### Added
- Initial version
