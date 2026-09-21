plugins {
    id("com.android.application")
    id("kotlin-android")
    // Reads google-services.json and generates the resources Firebase and
    // Google Sign-In look up at runtime (including default_web_client_id).
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "it.davideorsini.rubbish_manager"
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Required by flutter_local_notifications, which uses java.time APIs
        // that predate the app's minSdk.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "it.davideorsini.rubbish_manager"
        // Firebase Auth requires API 23 or newer. Kept explicit rather than
        // following flutter.minSdkVersion, which is 24 and would drop Android
        // 6 for no reason of ours.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: replace with a real signing config before publishing.
            // Debug keys keep `flutter run --release` working in the meantime.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
