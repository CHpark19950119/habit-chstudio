# Firebase Firestore — TypeToken generic 보호
-keep class com.google.firebase.firestore.** { *; }
-keep class com.google.firebase.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# gRPC — Firestore 연결용
-keep class io.grpc.** { *; }
-dontwarn io.grpc.**

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
