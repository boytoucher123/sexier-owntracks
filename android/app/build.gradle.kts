import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google Maps is optional. Put MAPS_API_KEY=... in android/local.properties
// (never committed) or export it in the environment before building.
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val mapsApiKey: String =
    (localProps.getProperty("MAPS_API_KEY") ?: System.getenv("MAPS_API_KEY") ?: "").trim()

android {
    namespace = "app.flock.flock"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.flock.flock"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["mapsApiKey"] = mapsApiKey
    }

    // Release signing. Every update must be signed with the same key or
    // phones will refuse to install it over the old version. Provide the key
    // through environment variables (CI) or android/key.properties (local).
    val keyProps = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    fun signingValue(name: String): String? =
        System.getenv(name)?.takeIf { it.isNotBlank() } ?: keyProps.getProperty(name)
    val keystorePath = signingValue("ANDROID_KEYSTORE_PATH")

    signingConfigs {
        if (keystorePath != null && file(keystorePath).exists()) {
            create("release") {
                storeFile = file(keystorePath)
                // Alias defaults to "flock" and the key password to the
                // keystore password, so CI only needs two secrets.
                val storePass = signingValue("ANDROID_KEYSTORE_PASSWORD")
                storePassword = storePass
                keyAlias = signingValue("ANDROID_KEY_ALIAS") ?: "flock"
                keyPassword = signingValue("ANDROID_KEY_PASSWORD") ?: storePass
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key so local release builds still work.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
