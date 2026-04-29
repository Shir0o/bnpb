# Changelog

All notable changes to the BNPB project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-04-28

### Added
- Google silent sign-in for improved synchronization flow.
- Filter for active follow-up reminders on the analytics page.
- Comprehensive prayer list export/import tests.

### Changed
- Upgraded Google Sign-In to v7.x for enhanced security and reliability.
- Optimized performance for `buildFullExportPayload`.
- Optimized legacy interactions migration in database helper.
- Improved UI state synchronization for Google Sign-In.

### Removed
- Redundant recognition cues, tags, and specialized meeting search to simplify the UI.
- Unused backup and temporary files.

## [1.0.0] - 2026-03-30

### Added
- Initial release of the BNPB offline-first relationship manager.
- Encrypted storage using SQLCipher and platform-secure key storage.
- Contact management with support for custom fields and interaction history.
- Relationship visualization using graph views.
- Data export in CSV, PDF, and encrypted JSON archive formats.
- Biometric and passcode lock screens.
- Prayer diary and notification scheduling.
- Analytics dashboard with relationship insights.
- Privacy policy and developer guidelines.
