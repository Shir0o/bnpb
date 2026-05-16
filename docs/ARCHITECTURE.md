# Architecture Documentation

## Overview
BNPB is a Flutter-based personal relationship manager designed with an offline-first, security-centric approach. It uses a layered architecture to separate concerns and ensure maintainability.

## System Layers

### 1. Presentation Layer (`lib/screens/`, `lib/widgets/`)
- **UI Framework**: Flutter with Material 3.
- **State Management**: Built-in Flutter patterns (StatefulWidgets, ValueNotifiers, etc.) or provider-based state depending on complexity.
- **Principles**: Widgets are declarative and side-effect free in their `build` methods.

### 2. Business Logic & Orchestration (`lib/services/`)
- Coordinates complex operations that span multiple domains (e.g., Export service, Sync coordination, Notification scheduling).
- Handles platform-specific integrations via plugins.

### 3. Data Access Layer (`lib/repositories/`)
- Provides a clean API for the presentation layer.
- Aggregates data from the database and applies higher-level logic (e.g., analytics calculations, preference management).

### 4. Persistence Layer (`lib/db/`)
- **Engine**: Sqflite with SQLCipher for transparent database encryption.
- **Security**: Database keys are generated on-device and managed by `SecurityService` using platform-native secure storage (Keychain/Keystore).
- **Schema Management**: Managed via `DBHelper`. Supports migrations and schema versioning.
- **Sync Support**: Implements a "Soft Delete" pattern using `updatedAt` and `deletedAt` timestamps, and unique `syncId` (UUID) for records.

### 5. Domain Models (`lib/models/`)
- Pure Dart objects representing entities like `Contact`, `Interaction`, `Relationship`, and `PrayerRequest`.
- Includes serialization logic (`toMap`, `fromMap`) for persistence and exports.

## Data Flow
1. **User Input**: User interacts with a widget (e.g., `AddContactPage`).
2. **Action**: Widget calls a method in a repository or service.
3. **Processing**: The repository/service performs validation or logic and calls the `DBHelper`.
4. **Persistence**: `DBHelper` executes SQL commands against the encrypted database.
5. **Feedback**: The UI updates based on the result (often via a `FutureBuilder` or state refresh).

## Security Model
- **At-Rest Encryption**: All user data is stored in an AES-encrypted SQLite database.
- **Gating**: Biometric (FaceID/Fingerprint) and passcode authentication protect the app entry point.
- **Privacy**: No user data is sent to external servers unless the user explicitly initiates an export or sync.

## AI Layer (`lib/services/ai/`)
AI features (AutoTag, FollowUpSuggestion, InteractionSummary, OutreachDraft,
PrayerClustering, Ask semantic search) are gated, opt-in, and currently
**on-device only**. Inference uses `flutter_gemma` against a locally
downloaded Gemma model; embeddings use a separate local Gecko 110M model.

- **Abstraction.** Every AI service depends on the `LocalLlmService`
  interface (`local_llm_service.dart`) rather than the `flutter_gemma`
  package directly. The production implementation is
  `FlutterGemmaLlmService`; tests inject fakes. This seam exists
  specifically so the backend can be swapped without rippling through
  the seven services that consume it.
- **Warm session + streaming.** `FlutterGemmaLlmService` keeps a long-lived
  `InferenceModelSession` keyed by a `systemPrefix` string. Services that
  send the same system-prompt prefix on every call (AutoTag, in particular)
  get KV-cache reuse: the prefix is encoded once and reused on every
  subsequent call until the prefix string changes. Streaming is exposed
  via the `LocalLlmServiceStreaming` extension so partial results can be
  rendered as tokens arrive. Backend selection (`PreferredBackend.gpu`,
  falling back to CPU) is configured in `load()`.
- **Privacy posture.** By default inference is local; prompts and outputs
  are never transmitted. A previous always-on integration that sent
  contact data to Google's Gemini API was removed (see commit `2a613ba`)
  because the disclosure was not comfortable in a pastoral context.
- **Opt-in cloud backend.** A second backend, `GeminiApiLlmService`
  (`gemini_api_llm_service.dart`), routes the same `LocalLlmService`
  interface to Google's Gemini API. It is **off by default** and gated by
  two separate explicit user actions: a Settings toggle that shows a
  disclosure dialog explaining what data leaves the device, and the user
  pasting their own Google AI Studio API key (BYOK; stored in the
  platform secure key store via `SecurityService`). `AiServices`
  swaps the active backend based on the user's preference; the five
  consumer services see no change because they only depend on the
  abstract interface. Network failures on the cloud backend surface as
  visible errors — there is intentionally no silent fallback to the
  local model, since switching backends without the user's knowledge
  would defeat the consent the cloud opt-in is built on.

## Sync Architecture
The system is designed for multi-device sync:
- Each record has a globally unique `syncId`.
- `updatedAt` tracks the last modification time in UTC.
- `deletedAt` allows tracking of deleted records across devices without losing the history needed for conflict resolution.
