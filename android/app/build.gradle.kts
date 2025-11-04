import java.util.Properties
import java.io.FileInputStream

val keystoreProps = Properties()
val propsFile = rootProject.file("key.properties")
val hasKeystore = if (propsFile.exists()) {
    keystoreProps.load(FileInputStream(propsFile))
    true
} else {
    println("⚠ key.properties not found at ${propsFile.absolutePath}. " +
            "Release signing will fall back to debug / unsigned.")
    false
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flex_facility_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.flexfacility.app"
        minSdk = maxOf(28, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = 10
        versionName = "1.0.9"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions { jvmTarget = "11" }

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                val path = keystoreProps["storeFile"] as String
                storeFile = file(path)
                storePassword = keystoreProps["storePassword"] as String
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (hasKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
