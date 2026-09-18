# Configurable contact name markers and review triage

Contact association from Simple Time Tracker comments is a configurable, deterministic name-marker system (default `w/` and `with `) with a whole-comment fallback scan, rather than an LLM. Staged records with no associated Contact are kept but default to unselected, and the staging queue is grouped for manual triage.

- Status: accepted
- Date: 2026-09-18

## Context

ADR-0004 introduced the Import Staging Queue that parses CSV records tagged `Contact` and maps them to BNPB Contacts. On first import the queue can hold thousands of records, many with comments that do not follow the original `w/` / `with ` shape, so the deterministic matcher returned no Contact for them. AI-based parsing was considered and rejected (cost, privacy exposure of many notes at once, and off-by-default AI gate that would leave the matcher broken when AI is disabled).

## Decision

- Contact association is **deterministic** and driven by a user-configured list of **Name markers** (default `w/, with `).
- Matching is **marker-respected first**: if a marker is present, only text after it is scanned for a contact name.
- When **no marker** is present, the **whole comment** is scanned as a fallback, but it requires a **stronger name signature** (full name, first+last, or nickname). A bare first name is accepted only directly after a marker.
- Records with **no matched Contact** are kept in the queue but **default to unselected**, so relational data is not silently dropped while noise is reduced.
- The staging queue is **grouped for manual triage** and sorted newest-first.
- No LLM is used for parsing or suggestion.

## Consequences

Deterministic, offline, and predictable: the matcher never leaves the device and behaves identically regardless of AI settings. Users whose comments follow a different marker can reconfigure it in settings. The fallback scan trades some precision for recall and may occasionally under-associate (a real name that is neither a full match nor after a marker), which the unselected-by-default policy absorbs without wrong imports.