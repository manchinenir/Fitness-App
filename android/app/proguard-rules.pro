# --- Flutter / plugins ---
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# --- WebView & JS bridges ---
-keep class * extends android.webkit.WebViewClient { *; }
-keep class * extends android.webkit.WebChromeClient { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class androidx.webkit.** { *; }
-dontwarn androidx.webkit.**

# --- Square (if using native SDK or classes referenced by their web libs) ---
-keep class com.squareup.** { *; }
-dontwarn com.squareup.**
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okio.** { *; }
-dontwarn okio.**

# --- Google Pay (if used) ---
-keep class com.google.android.gms.wallet.** { *; }
-dontwarn com.google.android.gms.**

# --- Firebase (quiet R8 warnings) ---
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
