plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tride.tride_driver"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.tride.driver"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["usesCleartextTraffic"] = "false"
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationId = "com.tride.driver.dev"
            resValue("string", "app_name", "TRide Driver DEV")
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        create("stg") {
            dimension = "environment"
            applicationId = "com.tride.driver.staging"
            resValue("string", "app_name", "TRide Driver STG")
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        create("prod") {
            dimension = "environment"
            applicationId = "com.tride.driver"
            resValue("string", "app_name", "TRide Driver")
            manifestPlaceholders["usesCleartextTraffic"] = "false"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
