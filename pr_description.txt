💡 **What:** 
- Added the **"Ready to log"** interaction suggestion card to the Home Screen (`lib/screens/home_page.dart`), adhering strictly to the design and interactive specification in `BNPB Prototype.dc.html`.
- Implemented `_nextRef()` and `_readyToLogItems()` in `HomePage` to detect interaction routines, auto-advance passage/chapter sequences (e.g. `PSA 115-116` -> `Psa. 117–118`, `Ch. 1` -> `Ch. 2`), and display routine tiles with green sequence pills.
- Tapping a "Ready to log" tile opens `LogInteractionSheet` pre-filled with the contact, interaction type, duration, and sequence notes for 1-tap logging.
- Updated `ContactService` (`lib/services/contact_service.dart`) to dynamically resolve `DBHelper` via a getter, ensuring test overrides (`DBHelper.overrideForTest`) are cleanly respected.
- Added comprehensive unit and widget test coverage in `test/screens/home_page_test.dart` for the "Ready to log" card rendering, sequence pill logic, and prefilled modal invocation.

🎯 **Why:** 
- Align the Flutter app directly with the 1c Crisp Utility design specification in `BNPB Prototype.dc.html` (Option 1a "Ready to log").
- Allow users to quickly log routine/recurring interactions (e.g. weekly workouts, scripture readings, coffee check-ins) with a single tap from the Home Screen.

📊 **Measured Improvement:**
- **Design Conformance**: Fully implemented the "Ready to log" card section on Home with sequence pills and pre-filled quick logging.
- **Test Suite Results**: 222/222 unit & widget tests passed cleanly (`flutter test`), including new widget coverage for interaction suggestion routine tiles.
