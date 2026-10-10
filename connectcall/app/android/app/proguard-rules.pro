# WebRTC (used by LiveKit) is called through JNI; keep its classes in release builds.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-keep class com.cloudwebrtc.webrtc.** { *; }
