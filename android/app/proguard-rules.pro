# MediaPipe (used by flutter_gemma) references generated proto classes that
# R8 can't see at compile time. Keep them and silence the warnings.
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Protobuf-generated classes use reflection.
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**
