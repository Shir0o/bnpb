2025-02-18 - Optimized Image Memory in PeopleCard
Learning: Large images loaded from network or disk into small widgets consume memory proportional to their original size, not display size.
Action: Use `ResizeImage(provider, width: (displaySize * pixelRatio).toInt())` to decode images at their display resolution. This is especially critical in `ListView`s where many images are loaded.

2025-02-18 - Eliminated IntrinsicHeight in Timeline
Learning: `IntrinsicHeight` forces a speculative layout pass, which is expensive in `ListView`s.
Action: Replace it with `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` and `CustomPaint` to draw height-dependent decorations. The `CustomPaint` will naturally stretch to match the row's height (determined by other children) without a second pass.

2025-02-18 - Optimized Eager Instantiation in ExpansionTiles
Learning: Passing a pre-built list of widgets to a collapsed expansion tile causes unnecessary instantiation and build overhead on every parent rebuild.
Action: Use a builder pattern (itemCount/itemBuilder) to lazily generate children only when the tile is expanded.
