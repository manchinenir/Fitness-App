

import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

// Load keystore props
val keystoreProps = Properties()
val propsFile = rootProject.file("key.properties")
if (!propsFile.exists()) {
    throw GradleException("key.properties not found at ${propsFile.absolutePath}")
}
keystoreProps.load(FileInputStream(propsFile))


plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "com.example.flex_facility_app"   // <- keep or set your package namespace
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.flexfacility.app"
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions { jvmTarget = "11" }

    signingConfigs {
        create("release") {
            val path = keystoreProps["storeFile"] as String
            storeFile = file(path)
            storePassword = keystoreProps["storePassword"] as String
            keyAlias = keystoreProps["keyAlias"] as String
            keyPassword = keystoreProps["keyPassword"] as String
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")   // ← critical
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
