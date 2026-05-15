# MediaPipe (used by flutter_gemma) references generated proto classes that
# R8 can't see at compile time. Keep only the proto package — the rest of
# MediaPipe can be optimized/stripped normally.
-keep class com.google.mediapipe.proto.** { *; }
-dontwarn com.google.mediapipe.**

# Protobuf-generated classes use reflection.
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**
