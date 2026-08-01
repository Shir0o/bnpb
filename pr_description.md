💡 **What:** 
- Replaced `HideOnScrollScaffold` with standard `Scaffold` on Prayer List Page (`lib/screens/prayer_lists_page.dart`) and Prayer Diary Page (`lib/screens/prayer_diary_page.dart`) so top app bar headers remain fixed and visible during scrolling per design specifications.
- Added `BackupService().exportBackup()` triggers on all Prayer List mutations (list creation, adding contacts, removing contacts, UNDO actions, and macOS desktop toggles) and updated `buildFullExportPayload` in `ExportService` to automatically include prayer lists in JSON and encrypted archive exports.
- Updated `_openLogInteractionForContact` in `HomePage` (`lib/screens/home_page.dart`) to prefill `LogInteractionSheet` with the contact's most recent interaction details for quick repeat interaction logging, and added `_normalizeMedium` handling in `LogInteractionSheet`.

🎯 **Why:** 
- The Crisp Utility design reference specifies fixed, non-disappearing top headers for prayer screens reached from Home.
- Prayer list modifications were previously missing auto-backup triggers, causing backup snapshots to miss updated prayer list memberships.
- Quick logging from Home page suggestions requires prefilling previous interaction context (summary, medium, duration, location, participants) for one-tap logging.

📊 **Measured Improvement:**
- **Design Conformance**: Fixed header scrolling on prayer screens to match design spec.
- **Data Protection**: Prayer list memberships are now automatically backed up and restored across database snapshots and exports.
- **Test Suite Results**: 221/221 unit & widget tests passed cleanly (`flutter test`), including new coverage for prayer list export payloads.
