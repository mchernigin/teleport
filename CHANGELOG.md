# Changelog

Format is based on [_Keep a changelog_](https://keepachangelog.com) and uses
[_Semantic versioning_](https://semver.org).

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
