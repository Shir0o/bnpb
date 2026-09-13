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

### Recurring Logs & Suggestions

**Ready-to-log suggestion**:
A prompt to log a recurring Interaction for a Contact, pre-filled from an inferred pattern so the user can confirm it in one step.
_Avoid_: Reminder, quick log, routine

**Recurring log pattern**:
A routine inferred from a Contact's Interaction history, combining an activity identity, a cadence, and an optional payload rule.
_Avoid_: Habit, series, schedule

**Pattern cadence**:
The timing rule of a recurring log pattern, such as daily except Sunday or every seven days.
_Avoid_: Frequency, recurrence

**Payload rule**:
The part of a recurring log pattern that computes the next value to pre-fill, such as the next scripture reference.
_Avoid_: Suggestion content, template

**Scripture advancement**:
A payload rule that reads a Bible reference from the latest Interaction note and computes the next reference in the same reading sequence.
_Avoid_: Verse increment, Bible suggestion

**Pattern identity**:
The stable criteria that bind Interaction logs to the same Recurring log pattern: the Contact, the normalized activity summary, and the medium.
_Avoid_: Activity tag, category

**Pattern span**:
The size of one occurrence of a Recurring log pattern, such as two Bible chapters.
_Avoid_: Increment, step

**Due**:
A state of a Recurring log pattern on one of its Pattern cadence days when no matching Interaction has been logged for that day.
_Avoid_: Active, pending

**Overdue**:
A Recurring log pattern is overdue when a cadence day passed without a matching Interaction; it is surfaced on the next cadence day rather than immediately.
_Avoid_: Missed, late

**Cross-book session**:
A single occurrence of a scripture-reading Recurring log pattern whose Payload rule spans more than one Bible book, such as Psalm 150 followed by Proverbs 1.
_Avoid_: Multi-book, boundary case
