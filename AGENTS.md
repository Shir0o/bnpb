# Repository Guidelines

## Overview
This repository contains a Flutter application for managing contact information, including creation, grouping, export, and restoration of entries. The app uses Material 3 theming with Google Fonts support and persists data locally with Sqflite. These guidelines apply to the entire repository unless a nested `AGENTS.md` overrides them.

## Project Structure
- `lib/main.dart`: App entry point, Material 3 theme configuration, and navigation shell.
- `lib/screens/`: UI screens such as the home page, add-contact flow, and detail views.
- `lib/models/`: Dart data models (for example, contact records and history entries).
- `lib/db/`: Local persistence helpers built on top of Sqflite and JSON-encoded history data.
- `lib/repositories/`: Aggregated data accessors that wrap the database helper for analytics and preferences.
- Platform directories (`android`, `ios`, `web`, etc.) contain generated Flutter boilerplate and should not be edited unless the task explicitly targets them.

## Coding Conventions
- Follow the `flutter_lints` ruleset enabled in `analysis_options.yaml`. Run `flutter analyze` after code changes to ensure lint compliance.
- Prefer descriptive names and add short Dart doc comments (`///`) for public classes, methods, and any helper whose behavior is non-trivial.
- Keep widget build methods declarative and side-effect free. Place asynchronous or data-mutating logic in callbacks, lifecycle methods (`initState`, `dispose`), or dedicated helpers.
- When updating persistence logic, ensure `Contact.history` remains JSON-serializable (encode before saving, decode after fetching) to stay compatible with existing Sqflite schema.
- Maintain UI consistency with Material 3 patterns: use `NavigationBar`, `AppBar`, `Scaffold`, and theming tokens already configured in `main.dart`.

## Testing & Tooling
- Run `flutter analyze` to catch static analysis issues.
- Execute widget/unit tests with `flutter test` when applicable.
- For data import/export flows, add regression coverage or manual testing notes when practical (e.g., round-tripping JSON files).

## Pull Requests & Documentation
- Update relevant documentation or inline comments when adding new features or modifying existing behavior (particularly around data persistence and state management).
- Keep commits focused, with clear messages summarizing the functional change.
