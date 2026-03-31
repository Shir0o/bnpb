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

## Sync Architecture
The system is designed for multi-device sync:
- Each record has a globally unique `syncId`.
- `updatedAt` tracks the last modification time in UTC.
- `deletedAt` allows tracking of deleted records across devices without losing the history needed for conflict resolution.
