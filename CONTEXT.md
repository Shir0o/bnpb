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
A prompt to record a Pattern occurrence, pre-filled from its Recurring log pattern, with actual attendees confirmed when logging.
_Avoid_: Reminder, quick log, routine

**Recurring log pattern**:
A recurring engagement with one or more Contacts, combining an activity identity, a cadence, regular participants, and an optional payload rule. Individual occurrences can have different attendees without becoming different patterns.
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
The enduring identity of a Recurring log pattern, independent of who attends an individual occurrence.
_Avoid_: Activity tag, category

**Pattern occurrence**:
A single instance of a Recurring log pattern, with its own actual attendees and Interaction details. Editing an occurrence does not change the saved pattern's regular participants, cadence, or defaults.
_Avoid_: Event, separate pattern

**Regular participants**:
The Contacts normally expected to participate in a Recurring log pattern, distinct from the actual attendees of any one Pattern occurrence.
_Avoid_: Attendees, fixed membership

**Saved pattern defaults**:
The editable name, regular participants, cadence, medium, and note or scripture settings used to pre-fill future suggestions for a Recurring log pattern. Changing these defaults does not rewrite past Interaction logs.
_Avoid_: Occurrence details

**Pattern combination**:
A user-confirmed consolidation of recurring log patterns that represent the same recurring engagement into one pattern. Similar activities alone do not establish that patterns should be combined.
_Avoid_: Automatic merge

**Completed occurrence**:
A Pattern occurrence recorded with its actual attendees, even when only a subset of the regular participants attended. Completion satisfies the pattern for that occurrence without recording Interactions or leaving an overdue occurrence for absent Contacts.
_Avoid_: Full attendance

**Pattern span**:
The size of one occurrence of a Recurring log pattern, such as two Bible chapters.
_Avoid_: Increment, step

**Due**:
A state of a Recurring log pattern on one of its Pattern cadence days when its expected occurrence has not been completed.
_Avoid_: Active, pending

**Overdue**:
A Recurring log pattern is overdue when a cadence day passed without a matching Interaction; it is surfaced on the next cadence day rather than immediately.
_Avoid_: Missed, late

**Cross-book session**:
A single occurrence of a scripture-reading Recurring log pattern whose Payload rule spans more than one Bible book, such as Psalm 150 followed by Proverbs 1.
_Avoid_: Multi-book, boundary case

### Time Tracker Sync & Staging

**Time Tracker Record**:
An individual row exported by Simple Time Tracker with an activity name, start/end timestamps, duration, comment, and tags (specifically tagged with `Contact`).
_Avoid_: STT event, time log item

**Candidate Interaction**:
An in-memory parsed representation of a Time Tracker Record mapped to potential BNPB Contact(s) and Interaction fields, staged for user review.
_Avoid_: Draft interaction, pending import

**Name marker**:
A user-configurable prefix (default `w/` or `with `) in a Time Tracker Record's comment that signals a contact name follows, used by the deterministic matcher to associate the record with a Contact. When no marker is present, the matcher scans the whole comment but requires a stronger name signature (full name, first+last, or nickname) to avoid false associations; a bare first name is only accepted directly after a marker.
_Avoid_: Pattern, regex, delimiter

**Import Staging Queue**:
A reviewable, dismissible queue presented on app launch (and accessible from the interaction dashboard) where candidate interactions can be inspected, edited, assigned to contacts, selected, and committed to the database.
_Avoid_: Import popup, review dialog

**Interaction Fingerprint**:
A deterministic hash of the time tracker record's start timestamp, duration, activity name, and raw comment used for idempotent deduplication.
_Avoid_: Sync hash, record ID

