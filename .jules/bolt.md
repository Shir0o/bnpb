2025-02-18 - Optimized Image Memory in PeopleCard
Learning: Large images loaded from network or disk into small widgets consume memory proportional to their original size, not display size.
Action: Use `ResizeImage(provider, width: (displaySize * pixelRatio).toInt())` to decode images at their display resolution. This is especially critical in `ListView`s where many images are loaded.
