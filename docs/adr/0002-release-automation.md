# ADR 0002: Android Release Automation Pipeline

- Status: Accepted
- Date: 2026-09-07
- Mirrors: [`Shir0o/attd` ADR 0001](https://github.com/Shir0o/attd/blob/main/docs/adr/0001-release-automation.md), [`Shir0o/bible-read` ADR 0001](https://github.com/Shir0o/bible-read/blob/main/docs/adr/0001-release-automation.md)

## Context

Releases for BNPB were previously conducted manually: version codes were tracked via `pubspec.yaml` (e.g. `1.1.0+2`), release notes were maintained manually in `RELEASE.md`, builds were assembled by developers, and submissions to the Google Play Console were executed by hand.

The sibling repositories `attd` and `bible-read` have adopted a shared, automated continuous delivery pattern for Android releases. Aligning BNPB with this established architecture reduces maintenance overhead, ensures consistent release tagging, and guarantees that every production/internal artifact can be traced directly to an auditable commit and release tag.

## Decision

We adopt the standardized release pipeline consisting of four core components:

1. **Release Please** (`googleapis/release-please-action`):
   Acts as the single source of truth for semantic versioning, changelog generation, git tag creation, and GitHub Release drafting. It analyzes conventional-commit PR titles merged to `main`.
2. **Fastlane Supply**:
   Automates Play Console uploading for the generated Android App Bundle (`.aab`) to the **internal testing** track.
3. **Play App Signing**:
   CI signs builds using an upload key stored in encrypted GitHub secrets (`ANDROID_KEYSTORE_BASE64`, `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD`). Google Play verifies the upload key and re-signs binaries for end-user distribution.
4. **Internal-Track-First Delivery (Draft Status)**:
   Automated uploads land on the internal testing track with `release_status: "draft"`. This ensures no untested build is prematurely broadcast to testers, while production promotion remains an explicit maintainer action within Google Play Console.

### Key Details & Customizations for BNPB

- **Changelog file**: Configured to write directly to `RELEASE.md` (via `"changelog-path": "RELEASE.md"` in `release-please-config.json`), preserving BNPB's historical documentation standard.
- **Version code calculation**: Derived deterministically at build time from the git tag (`major * 10000 + minor * 100 + patch`, e.g., `v1.2.0` -> `10200`). This completely supersedes the legacy `+buildNumber` suffix in `pubspec.yaml`.
- **No Google Services dependency**: Unlike Firebase-backed apps, BNPB does not require a `GOOGLE_SERVICES_JSON` secret because it does not use Google Services Gradle plugin for local-first encrypted storage.
- **PR Title Linting**: Enforced via `pr-title-lint.yml` to ensure squash-merged pull requests provide a valid conventional commit signal.

## Consequences

### Positive
- One-click release workflow triggered upon merging the automated Release Please PR.
- Unified release process and tooling across all companion applications (`bnpb`, `bible-read`, `attd`).
- Deterministic, conflict-free `versionCode` progression.
- Fastlane automates Play Console metadata, release notes (extracted from `RELEASE.md`), and upload handling.

### Negative
- Requires provisioning and maintaining six GitHub secrets (`RELEASE_PLEASE_TOKEN`, `ANDROID_KEYSTORE_BASE64`, `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD`, `PLAY_SUPPLY_JSON_KEY`).
- Conventional commit discipline on PR titles is required (`pr-title-lint` blocks non-conforming titles).

### Reversibility
- **Easy**: Fastlane configuration, Release Please configuration, and GitHub workflows can be modified or removed at any time.
- **Medium**: Tags and GitHub releases created by Release Please can be deleted if necessary.
- **Hard**: Upload key registration in Play App Signing cannot be changed without initiating an upload key reset ticket in Google Play Console.
