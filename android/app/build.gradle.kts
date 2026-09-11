import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties, which is deliberately not
// in version control — it names a keystore and holds its passwords. Create it
// from key.properties.example once, and every release build after that is
// signed with the upload key Play expects.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.wordbattle.word_battle"
    // flutter_secure_storage 11.0.0 requires API 37; flutter.compileSdkVersion
    // is still 36 for this Flutter SDK.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Also registered as the package of the Android OAuth client in Google
        // Cloud Console — changing it means re-registering there.
        applicationId = "com.wordbattle.word_battle"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Play rejects a bundle signed with the debug key, and Google
            // Sign-In is bound to the certificate's SHA-1 — so a debug-signed
            // "release" cannot even log in. Without key.properties the build
            // still runs for local testing, but it is not publishable, and
            // saying so here beats finding out at upload time.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// An app bundle is the artifact Play is given, and Play rejects one signed with
// the debug key — as does Google Sign-In, which is bound to the certificate's
// SHA-1. Building one without a real key produces a file that looks finished
// and cannot be used, and the failure otherwise surfaces at upload time: a
// Gradle warning here does not survive the Flutter tool's output filter.
//
// `flutter build apk --release` is left alone, so a debug-signed release APK is
// still available for local testing.
gradle.taskGraph.whenReady {
    // Matched by exact name: AGP's own graph is full of internal tasks called
    // things like `bundleReleaseResources`, and a substring match on "bundle"
    // catches those too — which failed `flutter build apk --release` as well.
    if (!hasReleaseKeystore && allTasks.any { it.name == "bundleRelease" }) {
        throw GradleException(
            "\n\n  android/key.properties yo'q — release app bundle imzolab bo'lmaydi.\n" +
                "  Debug kalit bilan imzolangan .aab ni Google Play qabul qilmaydi va\n" +
                "  Google Sign-In ham ishlamaydi.\n\n" +
                "  Tuzatish:  cp android/key.properties.example android/key.properties\n" +
                "             (keyin keystore yo'li va parollarni to'ldiring)\n\n" +
                "  Lokal sinov uchun:  flutter build apk --release\n"
        )
    }
}

flutter {
    source = "../.."
}
