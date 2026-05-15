# MediaPipe (used by flutter_gemma) loads framework + tasks classes by
# reflection from JNI and references generated proto classes that R8
# can't see at compile time. Keep all three packages; other parts of
# MediaPipe (e.g. `solutions.*`, `glutil.*`) can still be optimized.
-keep class com.google.mediapipe.proto.** { *; }
-keep class com.google.mediapipe.framework.** { *; }
-keep class com.google.mediapipe.tasks.** { *; }
-dontwarn com.google.mediapipe.**

# Protobuf-generated classes use reflection.
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**
