# BNPB

BNPB is a personal relationship manager built with Flutter. It keeps contact
context, reminders, prayer requests, and interaction history completely offline
while offering analytics and export tooling.

## Security & privacy

- Contact data is stored in an encrypted SQLCipher database. The encryption key
  is generated on-device and saved via the platform key store.
- Optional passcode and biometric gating prevents casual access to the app. The
  lock screen appears on launch whenever a passcode is configured.
- CSV, PDF, JSON, and encrypted archive exports allow selective field inclusion. AES
  encrypted archives require a user-supplied passphrase.
- A “Securely purge all data” action overwrites and deletes the encrypted
  database, clears backups, removes credentials, and cancels notifications.
- See the [Privacy Policy & Personal Usage Guidelines](docs/privacy_policy.md)
  for a detailed breakdown of how the app handles sensitive information.

## Documentation

- [Contributing Guidelines](CONTRIBUTING.md)
- [Architecture & Technical Design](docs/ARCHITECTURE.md)
- [Changelog](CHANGELOG.md)
- [Privacy Policy & Personal Usage Guidelines](docs/privacy_policy.md)
- [Optional facial recognition pipeline research](docs/facial_recognition_pipeline.md)
- [ADR 0001 – Platform Selection](docs/adr/0001-platform.md)
- [MVP Scope & Milestones](docs/mvp.md)

## Development

Run the usual Flutter commands during development:

```bash
flutter pub get
flutter analyze
flutter test
```

### Architecture Overview

The Flutter app follows a layered structure so that UI, orchestration, and data
concerns remain isolated:

- `lib/repositories/` – Aggregates data from the local database and exposes
  higher-level analytics or preference APIs.
- `lib/services/` – Coordinates platform integrations such as exports, calendar
  sync, and reminder scheduling.
- `lib/db/` – Sqflite helper used by repositories to persist contacts and
  related records.
- `lib/models/` – Domain entities shared across layers.
- `lib/screens/` & `lib/widgets/` – Presentation layer widgets and composition
  roots.

This structure keeps business rules testable while allowing the presentation
layer to stay declarative.
