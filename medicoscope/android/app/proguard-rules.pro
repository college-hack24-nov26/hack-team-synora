# Keep TensorFlow Lite (incl. the GPU delegate classes R8 was stripping) so the
# on-device heart/eye/skin models load. Fixes the missing
# org.tensorflow.lite.gpu.GpuDelegateFactory$Options R8 error.
-keep class org.tensorflow.** { *; }
-keep interface org.tensorflow.** { *; }
-dontwarn org.tensorflow.**
-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.lite.gpu.**

# tflite_flutter plugin
-keep class org.tensorflow.lite.** { *; }

# Play Core (referenced by Flutter's deferred-components stubs) - not used here.
-dontwarn com.google.android.play.core.**
