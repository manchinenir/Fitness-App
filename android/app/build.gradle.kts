buildscript {
    dependencies {
        classpath("com.google.gms:google-services:4.3.15") // ✅ this line
    }
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flex_facility_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

   defaultConfig {
        applicationId = "com.flexfacility.app"

        // ✅ Kotlin DSL: use property, not function
        // Prefer Flutter’s configured min/target if present. Many FlutterFire libs need 23+.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion // or set a number like 34

        versionCode = 1
        versionName = "1.0"
    }
  buildTypes {
        release {
            // Using debug signing so `flutter run --release` works until you add a release keystore
            signingConfig = signingConfigs.getByName("debug")
            // example if you enable shrinking later:
            // isMinifyEnabled = true
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )
        }
    }
}
flutter {
    source = "../.."
}
