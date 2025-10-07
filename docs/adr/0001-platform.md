# ADR 0001: Adopt Flutter for Cross-Platform Delivery

## Status
Accepted

## Context
The BNPB companion app must reach ministry leaders on Android, iOS, desktop, and the web while remaining maintainable by a small team. The product roadmap prioritizes rapid iteration on contact management, reminders, and analytics with consistent theming and offline support. We evaluated several approaches:

- **Native (Kotlin/Swift + separate desktop/web stacks)** – Provides platform-specific UX but multiplies the effort to build and maintain features. Duplicate business logic and divergent release cycles would slow the MVP timeline and complicate QA.
- **React Native / Expo** – Strong web alignment and JavaScript ecosystem familiarity, yet bespoke native modules are often required for notification scheduling, background tasks, and secure storage. Our existing Dart domain models and Sqflite persistence would need to be rewritten.
- **Flutter** – Single codebase with first-class support for Android, iOS, web, and desktop. Material 3 widgets, theming, and high-quality rendering match the desired design system. Package ecosystem covers notifications, scheduling, and local storage. The team already prototypes features in Dart, easing onboarding.

## Decision
Adopt **Flutter** as the primary application framework. Flutter satisfies the multi-platform requirement, keeps the UI layer consistent across devices, and aligns with current team expertise and assets. It also integrates tightly with the Sqflite persistence approach already proven in prototypes.

## Consequences
- **Positive**
  - Unified code sharing across mobile, desktop, and web builds.
  - Strong tooling (hot reload, DevTools) accelerates feedback loops.
  - Mature widget library with Material 3 and adaptive layout support.
  - Dart language safety (null safety, strong typing) reduces runtime defects.
- **Negative**
  - Larger binary size than fully native counterparts.
  - Need to monitor plugin compatibility whenever targeting new OS versions.
  - Web performance depends on careful asset and bundle optimization.

## Core Dependencies
The MVP relies on the following Flutter ecosystem packages and SDK components:

| Layer | Dependency | Purpose |
| --- | --- | --- |
| Presentation | `flutter`, `flutter_localizations`, `google_fonts`, `fl_chart` | Material 3 UI, localization scaffolding, typography, and chart rendering. |
| Application | `intl`, `timezone` | Formatting dates/times and ensuring reminder calculations use canonical zones. |
| Data | `sqflite`, `path`, `path_provider`, `shared_preferences` | Local persistence, file system paths, and lightweight configuration storage. |
| Integration | `url_launcher`, `permission_handler`, `share_plus` | Launching external intents, managing runtime permissions, and exporting data. |
| Automation | `build_runner`, `json_serializable` (planned) | Code generation for models and serializers to keep data-layer maintenance lean. |

These choices keep the MVP focused on offline-first contact tracking while leaving room to add analytics and integration plugins as follow-up ADRs.
