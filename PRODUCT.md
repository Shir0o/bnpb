# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users
Ministry leaders, mentors, and relational caretakers who maintain intentional personal relationships, spiritual care, prayer requests, and interaction histories. On desktop, users engage in deep relational review, focused prayer diary journaling, interaction staging queue triage, bulk contact management, and analytics review, while mobile serves as the rapid on-the-go capture companion.

## Product Purpose
BNPB is an offline-first, privacy-respecting personal relationship companion and local-first CRM. It helps users intentionally nurture relationships, track interactions, sustain active prayer lists, and maintain relational context without compromising personal confidentiality or relying on unencrypted cloud servers. Success means zero data leaks, effortless recall of relational history, and intentional follow-through on commitments and prayers.

## Positioning
An encrypted, local-first relationship companion with optional on-device AI that guarantees sensitive personal, ministry, and prayer notes never leak to external cloud servers or surveillance architectures. Unlike commercial CRMs or cloud note tools, BNPB pairs strict AES-256 local database encryption with private, user-controlled peer sync (encrypted Google Drive & CISA Tracker) and local on-device inference (Gemma via MediaPipe/LiteRT).

## Operating Context
- Desktops (macOS currently, Windows/Linux in roadmap) for deep work sessions: review of imported Simple Time Tracker interaction records via the staging queue, multi-column prayer journaling, contact timeline auditing, and analytics exploration.
- Mobile devices (Android/iOS) for quick logging, immediate follow-up notes, and timely notification reminders.
- Synchronized via encrypted Google Drive backups and authenticated CISA Tracker integration.
- Keyboard-driven workflows, multi-pane navigation, and custom desktop window chrome on desktop form factors.

## Capabilities and Constraints
- **Platform Architecture**: Single Flutter codebase adapting across mobile (Material 3 navigation) and desktop (dedicated desktop shell with persistent sidebar, custom window chrome, and multi-pane views).
- **Security & Encryption**: SQLCipher SQLite database with AES-256 encryption; keys secured in platform KeyStore / Keychain; optional passcode and biometric app lock.
- **Data Synchronization**: Idempotent synchronization through encrypted Google Drive files and CISA Tracker API; deterministic fingerprinting for deduplication and candidate interaction staging.
- **On-Device & Cloud AI**: Local on-device inference (Gemma / LiteRT) off by default and privacy-contained; optional user-configured cloud LLM providers (Gemini, Claude, Hugging Face) using user-supplied API keys.
- **Data Portability**: Full manual exports/imports in CSV, PDF, JSON, and encrypted AES archives with user passphrase; "Securely purge all data" capability.
- **Terminology**: Strict domain naming conventions (Contact, Interaction, Prayer Request, Recurring log pattern, Candidate Interaction, Import Staging Queue) as recorded in CONTEXT.md.

## Brand Commitments
- **Name**: BNPB ("Local-first CRM").
- **Design Language**: Incumbent "Crisp Utility" design token system — high contrast, calm emerald primary greens, clean structural dividers, frosted surfaces, and specialized dark cards for AI search/ask modules.
- **Tone & Voice**: Respectful, discreet, utilitarian, and privacy-first; no gamified pressure, no dark patterns, and no uninvited telemetry.

## Evidence on Hand
- Full incumbent Flutter codebase: `lib/` (including desktop views in `lib/screens/macos/`).
- Stitch desktop visual specifications and mockups: `stitch_assets/main_window_shell.html`, `stitch_assets/main_window_shell.png`, `stitch_settings.html`, `stitch_assets/prayer_diary/`.
- Domain specifications and ADRs: `CONTEXT.md`, `docs/adr/0001-platform.md` through `0007-multi-provider-ai-and-dynamic-model-catalog.md`.
- Comprehensive test suite and design token verification tests: `test/macos_design_token_usage_test.dart`, `test/design_token_usage_test.dart`.

## Product Principles
1. **Privacy & Offline First**: All relational and prayer data belongs exclusively to the user on their physical hardware; cloud sync is strictly encrypted, user-initiated or user-controlled, and on-device processing is the default expectation.
2. **Form-Factor Ergonomics**: Mobile prioritizes fast capture and glanceable reminders; desktop prioritizes deep reflection, multi-column triage, batch interaction auditing, and focused journaling.
3. **Deterministic Integrity**: Relational patterns, deduplication fingerprints, and import queues operate on clear, deterministic rules rather than opaque heuristics.
4. **Zero Vendor Lock-in**: All contact histories, notes, and prayer records are fully exportable in open and encrypted formats with lossless schema fidelity.

## Accessibility & Inclusion
- Adherence to WCAG 2.2 contrast requirements across both light and dark themes using semantic `ColorScheme` roles.
- Scalable dynamic typography via `fontSizeNotifier` and accessible touch/click targets across both mouse/pointer and touch surfaces.
- Full keyboard navigation and system shortcut support for desktop environments.
