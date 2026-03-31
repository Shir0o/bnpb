# Contributing to BNPB

Thank you for your interest in contributing to BNPB! This document outlines the standards and workflows we use to maintain a high-quality, secure, and reliable codebase.

## Code of Conduct
By participating in this project, you agree to abide by our standards of professionalism and respect.

## Getting Started
1. Ensure you have the Flutter SDK installed (>= 3.0.0).
2. Clone the repository.
3. Run `flutter pub get` to install dependencies.
4. Run `flutter test` to ensure the base state is stable.

## Coding Conventions
- **Lints**: We follow the `flutter_lints` ruleset. Run `flutter analyze` frequently.
- **Formatting**: Use `dart format .` to keep code style consistent.
- **Documentation**: Use `///` Dart doc comments for all public classes, methods, and non-trivial helpers.
- **UI/UX**: Adhere to Material 3 patterns. Use `NavigationBar`, `AppBar`, and `Scaffold`. Ensure your plan includes a wireframe or mockup for UI changes.
- **Statelessness**: Keep `build` methods declarative and side-effect free. Move mutation and async logic to lifecycle methods or dedicated helpers.

## Test Driven Development (TDD)
> [!IMPORTANT]
> **TDD Mandate**: You MUST write unit or widget tests *before* writing any implementation code.

1. **Red**: Write a failing test for the new feature or bug fix.
2. **Green**: Implement the minimum code required to pass the test.
3. **Refactor**: Clean up the code while ensuring tests stay green.

### Regression Prevention
- Run **ALL** tests (`flutter test`) before and after any change.
- Never modify existing tests to pass new changes unless requirements have explicitly changed (and confirmed by the user).

## Security & Privacy
BNPB is offline-first and security-focused.
- Data is stored in an encrypted SQLCipher database.
- Encryption keys are managed via the platform's secure storage.
- Never log or commit sensitive user data.
- Ensure `Contact.history` remains JSON-serializable to maintain schema compatibility.

## Pull Request Process
1. Keep commits focused and descriptive.
2. Update relevant documentation (e.g., `README.md`, `ARCHITECTURE.md`) for any architectural changes.
3. Ensure `flutter analyze` and `flutter test` pass 100%.
