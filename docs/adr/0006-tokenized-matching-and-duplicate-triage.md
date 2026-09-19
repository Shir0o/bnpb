# Tokenized contact matching, duplicate detection, and on-demand AI triage

Amend ADR-0005 to tokenize contact names after markers, detect candidate collisions against hand-logged interactions, default commentless or duplicate records to unselected, and provide opt-in on-demand AI resolution for ambiguous records.

- Status: accepted
- Date: 2026-09-19

## Context

ADR-0005 established deterministic name markers and unselected-by-default for unmatched records. However, three gaps emerged in production:
1. Multi-contact records (e.g. `w/ vicente isai will`) and single-word comments (`peinado`) produced false associations or mis-attributed contacts due to un-tokenized substring matching.
2. Comments with no text (`""`) or records matching pre-existing hand-logged interactions could still be marked selected by default or create silent duplicates.
3. Completely unstructured or heavily colloquial comments remained unmatchable deterministically without manual user entry.

## Decision

1. **Tokenized name resolution**: Names following markers are split on standard delimiters (`,`, `&`, `+`, `and`, `y`, or whitespace) and evaluated per-token against contact aliases, nicknames, and full/first names with strict word boundaries.
2. **Commentless records unselected**: Records with empty comments default to `selected = false` in the staging queue.
3. **Collision / Duplicate detection**: Staged candidates are checked against existing database interactions within a temporal window ($\pm 60$ minutes). Potential collisions are flagged with a duplicate badge and default to `selected = false`.
4. **On-demand AI resolution**: When local or cloud AI is enabled by user preference, an opt-in "Resolve with AI" action (both batch and per-candidate) is made available in the staging queue for unmatched or ambiguous candidates, preserving offline determinism as the primary path.
5. **Unified Contact Multi-Select**: Replace disparate contact pickers with a rapid tokenized search-and-select component that auto-clears queries, preserves focus, and suggests regular participants and recent contacts.

## Consequences

Zero inadvertent bulk imports of empty or colliding records. Multi-person time logs parse accurately into multiple contact IDs without regex bleed. AI invocation remains strictly on-demand and user-consented, avoiding uncontrolled background token usage or privacy leakage.
