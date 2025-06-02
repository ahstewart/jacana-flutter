# Keep TensorFlow Lite GPU delegate classes
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.** { *; }
-keep class com.google.android.** { *; }
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options