# BNPB Companion MVP Scope

The MVP targets field directors and ministry coordinators who need a lightweight tool for tracking relationships, prayer needs, and follow-up commitments. The release plan is divided into incremental milestones that deliver observable value while de-risking critical integrations.

## Milestone Overview

| Milestone | Target Outcomes | Acceptance Criteria |
| --- | --- | --- |
| **M0 – Foundation & Data Layer** | Establish project scaffolding, persistence, and seed data for exploration. | - Sqflite schema creates contacts, interactions, prayer requests, and notification preference tables on first launch.<br>- Demo data loads when the database is empty so the analytics screen can render sample insights.<br>- App boots on Android, iOS, and web using the shared Flutter entry point. |
| **M1 – Contact Management** | Enable core contact CRUD flows and relationship tagging. | - Users can add, edit, and archive contacts with name, relationship type, and notes.<br>- Relationship graph view surfaces primary relationship tags for each saved contact.<br>- Export sheet produces CSV/JSON files with active contacts and their latest interaction summary. |
| **M2 – Prayer & Interaction Tracking** | Capture ongoing ministry context for each contact. | - Interaction log allows logging of meetings with duration, notes, and optional follow-up date.<br>- Prayer requests can be marked answered and appear on the contact detail timeline.<br>- Timeline view merges interactions and prayer updates in chronological order. |
| **M3 – Reminders & Notifications** | Keep commitments on track through scheduled prompts. | - Notification settings page exposes per-channel frequency (follow-up, prayer, review).<br>- Reminder coordinator re-evaluates schedules whenever contacts or interactions change.<br>- Users can snooze or mark reminders done from the delivered notification. |
| **M4 – Analytics Dashboard (MVP Complete)** | Provide strategic insight into engagement patterns. | - Analytics page displays summary metrics, top contacts, category breakdown, timeline chart, and gap warnings.<br>- Date range selector refreshes metrics without app restart.<br>- Exported analytics snapshot (PDF/CSV) matches on-screen totals for the selected range. |

## Backlog Mapping

1. **Project Setup & Architecture** (M0)
   - Define layered folder structure (`lib/repositories`, `lib/services`, `lib/widgets`, etc.).
   - Document platform choice via ADR. Acceptance: repo tree matches documented layers and passes CI checks.
2. **Contact CRUD Workflow** (M1)
   - Implement add/edit forms with validation and local persistence.
   - Display contact list with search and filters.
   - Acceptance: Creating a contact surfaces it immediately in list and detail pages, stored in Sqflite.
3. **Relationship Explorer** (M1)
   - Visualize relationships through existing explorer page.
   - Acceptance: Graph view updates when relationships are added/removed from a contact.
4. **Interaction Logging** (M2)
   - Capture meeting notes, duration, and follow-up suggestions.
   - Acceptance: Logging an interaction updates contact timeline and increments analytics counters.
5. **Prayer Request Tracking** (M2)
   - Allow marking requests answered and sorting by urgency.
   - Acceptance: Completed requests no longer appear in active list but remain in history.
6. **Reminder Scheduling** (M3)
   - Sync reminder service with notification preferences.
   - Acceptance: Adjusting notification cadence updates scheduled jobs within one minute.
7. **Notification Settings UI** (M3)
   - Provide user controls for reminder intensity and quiet hours.
   - Acceptance: Changes persist across app restarts and reflect in scheduled reminders.
8. **Analytics Summary** (M4)
   - Aggregate data across contacts to highlight trends.
   - Acceptance: Dashboard cards render accurate totals over selectable date ranges.
9. **Data Export & Sharing** (M4)
   - Offer CSV/PDF/JSON export of contact and analytics data.
   - Acceptance: Export file downloads/shares successfully on mobile and desktop targets.

## Out of Scope for MVP

- Real-time synchronization across multiple devices.
- Multi-user authentication or shared workspaces.
- Full localization beyond English (strings prepared for localization but not translated).
- Automated integration with external CRMs or church management systems.

Clarifying these constraints keeps the MVP focused on high-value ministry workflows while allowing subsequent releases to tackle collaboration and integrations.
