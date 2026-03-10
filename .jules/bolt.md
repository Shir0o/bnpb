## 2025-02-18 - Optimized Image Memory in PeopleCard
**Learning:** Large images loaded from network or disk into small widgets consume memory proportional to their original size, not display size.
**Action:** Use `ResizeImage(provider, width: (displaySize * pixelRatio).toInt())` to decode images at their display resolution. This is especially critical in `ListView`s where many images are loaded.

## 2025-02-18 - Eliminated IntrinsicHeight in Timeline
**Learning:** `IntrinsicHeight` forces a speculative layout pass, which is expensive in `ListView`s.
**Action:** Replace it with `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` and `CustomPaint` to draw height-dependent decorations. The `CustomPaint` will naturally stretch to match the row's height (determined by other children) without a second pass.

## 2025-02-18 - Optimized Eager Instantiation in ExpansionTiles
**Learning:** Passing a pre-built list of widgets to a collapsed expansion tile causes unnecessary instantiation and build overhead on every parent rebuild.
**Action:** Use a builder pattern (itemCount/itemBuilder) to lazily generate children only when the tile is expanded.

## 2025-02-18 - Isolate InkWell Ripple Paints
**Learning:** Ripples on `InkWell` trigger a repaint of the nearest `Material` ancestor. If the `InkWell` wraps complex content (like images or text), that entire subtree is repainted on every frame of the splash animation.
**Action:** Wrap the child of `InkWell` in a `RepaintBoundary` to cache the complex content as a layer, allowing the ripple to composite over it cheaply.

## 2025-02-18 - Optimized Contact Parsing
**Learning:** Converting DB rows to Maps, then to Objects, then back to Maps for parent objects, and finally back to Objects is a massive waste of CPU and Memory.
**Action:** Modified `Contact.fromMap` to accept `List<Interaction>` (and other child lists) directly, bypassing the intermediate Map transformation in `DBHelper`.

## 2025-02-18 - Optimized Eager Instantiation in MacOSShell
**Learning:** IndexedStack instantiates and builds all of its children immediately on startup, which causes a spike in memory and initialization overhead.
**Action:** Replace IndexedStack with a PageView with NeverScrollableScrollPhysics and wrap children in AutomaticKeepAliveClientMixin to preserve state while deferring widget building until the tab is first visited.

## 2025-02-18 - Optimized String Interpolation in Contact
**Learning:** Instantiating throwaway collections (like Lists) and using `.where()` + `.join()` for simple string concatenation in frequently accessed getters (like `fullName`) causes significant memory allocation and execution overhead.
**Action:** Replace dynamically allocated lists and joins with direct boolean condition checks and string interpolation (`'$firstName ${lastName!}'`). In Dart, benchmarks show this structural fast-path approach can be ~5x faster.

## 2025-02-18 - Optimized DateFormat Instantiation
**Learning:** `intl`'s `DateFormat` parsing is an expensive operation. Instantiating it inside hot paths like Flutter `build` loops (e.g., inside chart axis label builders) or nested iterative data mapping algorithms (e.g., search indexers) creates unnecessary CPU bottlenecks and garbage collection churn.
**Action:** Cache `DateFormat` as a static class member, or class instance variable (e.g., `_dateFormatter = DateFormat.yMMMd()`) to reuse a single instance across method calls and widget rebuilds.
