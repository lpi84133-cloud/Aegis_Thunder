import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// google-services plugin is optional here: we only apply it when the
// google-services.json file has actually been dropped into the project.
// This keeps release/debug builds green while Firebase credentials are
// pending — the AlertRelay code catches the runtime init failure.
val googleServicesFile = file("google-services.json")
if (googleServicesFile.exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Load release signing config from android/key.properties (never in git).
val signingProps = Properties()
val signingPropsFile = rootProject.file("key.properties")
val hasSigningConfig = signingPropsFile.exists()
if (hasSigningConfig) {
    signingProps.load(FileInputStream(signingPropsFile))
}

android {
    namespace = "com.aegisthund.aegisthunder"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.aegisthund.aegisthunder"
        minSdk = 30
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasSigningConfig) {
        signingConfigs {
            create("release") {
                storeFile = file(signingProps["storeFile"] as String)
                storePassword = signingProps["storePassword"] as String
                keyAlias = signingProps["keyAlias"] as String
                keyPassword = signingProps["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = if (hasSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
