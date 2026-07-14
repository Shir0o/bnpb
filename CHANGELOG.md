# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Created a Git `post-checkout` hook to automatically copy `AGENTS.md` and `CLAUDE.md` to newly created worktrees.

### Changed
- Removed `AGENTS.md` from upstream tracking and git-index while retaining it locally.
- Added `AGENTS.md` and `CLAUDE.md` to `.gitignore` to prevent future tracking.
- Initialized `CHANGELOG.md` using the repository's git commit history.
- **Crisp Utility Theme Foundation**: Added `placeholder` and `navBg` design tokens, a shared `InputDecorationTheme`, and a themed `FloatingActionButtonThemeData` to `buildAppTheme` in `main.dart`.
- **Dark Mode Fixes**: Replaced dozens of hardcoded light-mode hex colors with theme-aware `ColorScheme`/`CrispColorScheme` roles across Settings, Home, Analytics, Add Contact, Add Family, AI Settings, Prayer Diary, and the relationship/people-card widgets, fixing surfaces and text that previously stayed light-colored in dark mode.
- Hardened `design_token_usage_test.dart` to also flag hardcoded Crisp Utility token hex values (not just named `Colors.*` swatches), and expanded its coverage to the newly-fixed files.
- Replaced the remaining stock `SwitchListTile`/`Switch.adaptive` toggles in Notification Settings and the contact "Mark for prayer" control with the shared `CrispSwitch` widget for visual consistency.
- **Crisp Toast**: Added `CrispToast`, a floating pill notification matching the Crisp Utility design's `showToast`, and swept nearly every informational `SnackBar` call site across the app (Home, Settings, AI Settings, Notification Settings, Prayer Diary/List/Request, Add Contact/Family, Ask, Contact Details, backup restore) to use it instead. Left in place the one `SnackBar` with an "Undo" action, since the design has no action-button equivalent.
- **Bottom Nav & FAB**: Restyled the main `NavigationBar` in place (translucent `navBg`, green-tint active pill, line icons in both states, hairline top border, "Add Contact"→"Add" label) to match the Crisp Utility design, and gave the Prayer Diary FAB its exact 56x56/18px-radius rounded-square shape with a soft green shadow.
- **Tier 2 Conformance Sweep**: Brought Contact Details, Notification Settings, Relationship Explorer, Ask, and Import Duplicate Review in line with the Crisp Utility card/button language — flat bordered cards (`surfaceContainerLow` + hairline border) in place of elevated `Card`s, `FilledButton` in place of `ElevatedButton` in confirmation dialogs, outlined icons for edit/delete actions, and removal of `OutlineInputBorder()` overrides so text fields inherit the shared filled `InputDecorationTheme`. Also flattened the Contact Details autocomplete popup to match the card border style and deduplicated the interaction-participant chip builder shared between `ContactDetailsPage` and `InteractionDetailPage`.

## [1.2.0] - 2026-07-14

### Added
- **Custom Settings Switches**: Implemented custom switch toggles (`crisp_switch.dart`) for the settings page to align with the "Crisp Utility" design.
- **UI Redesign**: Complete visual redesign of Home, Analytics, and Add Contact pages matching the "Crisp Utility" mockup using Material 3 design tokens.
- **Dark Mode**: Implemented a dark mode theme toggle, custom font size configuration in settings, scaled up title fonts, and gesture-based multi-select.
- **Scroll Improvements**: Added scroll anchoring and automatic hiding of the top bar on scroll down across all pages.
- **Inline Creation**: Added inline contact creation within the selection sheet on the prayer list page.
- **Add Family**: Introduced a bulk "Add Family" flow for entering multiple related contacts at once.
- **Interaction De-duplication**: Added interaction de-duplication settings, dry run previews, and detail comparisons.
- **On-Device AI Scaffold**: Integrated on-device AI functionality (via `flutter_gemma`) including AutoTag suggestions, per-contact interaction summaries, and follow-up suggestion settings.

### Changed
- **Follow-up Refinements**: Refined follow-up suggestion logic with fallback heuristics.
- **UI Tweaks**: Replaced subtract icon with swipe-left for removal on the prayer list page, and deferred notification permission prompt until first scheduling intent.
- **Gemini Purging**: Made legacy Gemini purging one-shot and non-blocking.

### Optimized
- **Database / Queries**: 
  - Resolved multiple N+1 SQLite queries across `ensureDefaults`, import service prayer lists/contacts, prayer request synchronization, and `_mergePrayerLists`.
  - Batched sequential DB insertions and chunked fetching for `_getInteractionSyncId` and `replacePrayerRequestsForContact`.
- **Parallel Execution**: 
  - Parallelized secure file wiping, backup deletion, `SharedPreferences` cleanup, reminder cancellation, and export payload generation using `Future.wait`.

### Removed
- Removed the voice-to-note dictation button, prayer-request clustering, and legacy `InteractionSummary` / `OutreachDraft` features to simplify the codebase.

### Fixed
- Resolved `ListTile` layout assertions and SQLite double-quoted literal warnings.
- Fixed MediaPipe Proguard rules and added internet permission for release Android builds.

## [1.1.0] - 2026-04-28

### Added
- Google silent sign-in for improved synchronization flow.
- Filter for active follow-up reminders on the analytics page.
- Comprehensive prayer list export/import tests.
- **Intelligent Follow-up Recommendations**: AI-driven suggestions based on interaction gaps, prayer requests, and meeting notes.

### Changed
- Upgraded Google Sign-In to v7.x for enhanced security and reliability.
- Optimized performance for `buildFullExportPayload`.
- Optimized legacy interactions migration in database helper.
- Improved UI state synchronization for Google Sign-In.

### Removed
- Redundant recognition cues, tags, and specialized meeting search to simplify the UI.
- Unused backup and temporary files.
- `speech_to_text` dependency and related voice-capture UI logic.

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
