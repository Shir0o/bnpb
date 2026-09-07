# BNPB Domain Context & Glossary

BNPB is an offline-first personal relationship companion built with Flutter. It helps users maintain relational context, reminders, prayer requests, and interaction histories while preserving strict user privacy with on-device encryption and optional on-device AI.

## Language

### Release & DevOps

**Release PR**:
An automated pull request opened and maintained by Release Please that collects merged conventional-commit changes, bumps the application semver version in `pubspec.yaml`, and appends formatted release notes to `RELEASE.md`.
_Avoid_: Changelog PR, bump commit

**Version Code (`versionCode`)**:
A monotonically increasing integer derived deterministically at build time from the Git tag (`major * 10000 + minor * 100 + patch`, e.g., `v1.2.0` -> `10200`). Replaces the legacy manual `+buildNumber` suffix in `pubspec.yaml`.
_Avoid_: Build number, patch code

**Internal Testing Track**:
The Google Play Console deployment track designated for private distribution to registered internal testers. Automated CI uploads land here as drafts by default.
_Avoid_: Beta track, closed testing (unless referring to public testing)

**Play App Signing**:
Google Play mechanism where CI signs app bundles with an upload key, and Google re-signs the final split APKs delivered to user devices using the app-signing key.

**Conventional Commit**:
A structured commit/PR title convention (`feat:`, `fix:`, `perf:`, `chore:`) parsed by Release Please to infer semantic version increments and format release notes.
_Avoid_: Freeform title

### Offline & Security

**SQLCipher Database**:
The local SQLite database encrypted with 256-bit AES cipher, with keys secured via platform keychain/KeyStore.
_Avoid_: Local cache, unencrypted DB

**On-Device AI**:
Optional client-side inference executing on local Gemma models via MediaPipe without transmitting user contact data to external cloud servers.
_Avoid_: Cloud AI, API inference

### Core Domain

**Contact**:
A person tracked in BNPB containing biographical details, custom fields, and relational interactions.
_Avoid_: User, lead, profile

**Interaction**:
A logged engagement between the user and a Contact (e.g. coffee, call, meeting) with an optional timestamp, duration, and notes.
_Avoid_: Event, activity, transaction

**Prayer Request**:
A confidential prayer item associated with a Contact or maintained in the personal prayer list.
_Avoid_: Task, ticket
