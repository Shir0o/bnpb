## Summary

Adds a deterministic, on-device recurring-log pattern engine and wires it into the
Ready-to-log card.

### What changed

- Detects per-Contact routines from Interaction history using normalized
  `summary` plus `medium`.
- Infers weekday-mask and fixed-interval cadences with a 90-day lookback and a
  45-day retirement rule.
- Add a day-level due/overdue model and a confirm-before-suggest flow.
- Infer a session span from recent matching logs, with explicit user overrides.
- Add canonical Bible metadata for all 66 books, sequential chapter advancement,
  and cross-book sessions such as `Psa. 150; Prov. 1`.
- Keep the LLM limited to parsing free-form scripture references from the
  latest note.
- Show non-scripture routines without requiring a scripture pill.
- Add Settings > Routines for confirming, editing cadence and span, snoozing,
  and stopping routines.
- Persist confirmations and overrides locally in `SharedPreferences`.
- Surface non-scripture and scripture routines through the existing
  Ready-to-log card with overdue/confidence/payload ranking.

### Privacy

Recurring patterns are inferred locally from Interaction history. That history
is not sent to the AI model. The LLM is only given the latest note or
Interaction when it must parse a free-form scripture reference. AI remains
opt-in and off by default.

### Verification

- `flutter analyze` is clean.
- Full `flutter test` suite passes: 312/312.
- Added tests for detection, cadence, span inference, cross-book progression,
  canon boundaries, preferences, Home confirmation flow, non-scripture
  routines, and the Settings routines page.

### Docs

- Updated `CONTEXT.md`.
- Added ADR 0003 for deterministic on-device pattern detection.
- Linked the ADR from `README.md`.
- Clarified the AI/privacy policy.
