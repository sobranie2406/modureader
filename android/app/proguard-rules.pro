# ONNX JNI looks up Java classes and constructors by their original names.
# Keeping only native methods is insufficient: TensorInfo and the result
# constructors are called FROM native code and must survive R8 unchanged.
# https://onnxruntime.ai/docs/build/android.html#note-proguard-rules-for-r8-minimization-android-app-builds-to-work
-keep class ai.onnxruntime.** { *; }
