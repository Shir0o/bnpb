💡 **What:** Redesigned the "Follow-up suggestions" card on the Home page (`lib/screens/home_page.dart`) with priority badges (`CRITICAL`, `HIGH`, `MEDIUM`, `LOW`), Crisp Utility design system styling, and a direct `+ Log` button on each suggestion row.

🎯 **Why:** Previously, tapping a follow-up recommendation on the Home page only navigated to the Contact Details page. Users had to leave the Home screen to record a quick meeting or check-in. Adding a direct `+ Log` button launches `LogInteractionSheet` directly from the Home screen and refreshes recommendations upon saving, streamlining daily workflow.

📊 **Measured Improvement:**
- **One-tap interaction logging**: Reduced steps to log a follow-up interaction from 3 taps (nav -> details -> log) down to 1 tap directly from the Home screen.
- **Visual Hierarchy**: Priority tags (`CRITICAL`, `HIGH`, `MEDIUM`, `LOW`) provide instant visual cues for urgent follow-ups.
- **Test Suite Results**: 219/219 unit & widget tests passed cleanly, including new widget coverage for card layout and logger sheet invocation.
