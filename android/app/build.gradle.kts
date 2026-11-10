import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Ключ подписи лежит в android/key.properties и в git не попадает.
// Пока файл не заполнен, debug-сборки работают, а release падает
// с понятным сообщением вместо тихой подписи debug-ключом.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val keystorePassword = keystoreProperties.getProperty("storePassword").orEmpty()
val keystoreAlias = keystoreProperties.getProperty("keyAlias").orEmpty()
val signingReady = keystorePropertiesFile.exists() &&
    keystorePassword.isNotBlank() && keystorePassword != "CHANGE_ME" &&
    keystoreAlias.isNotBlank() && keystoreAlias != "CHANGE_ME"
val buildingRelease = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

android {
    namespace = "com.example.vguit_app"
    // flutter_local_notifications 23 и androidx.core 1.19 требуют API 37.
    // Flutter 3.47 по умолчанию собирает под 36, поэтому задаём явно.
    compileSdk = 37
    ndkVersion = "30.0.16248370"

    compileOptions {
        // Нужно для flutter_local_notifications (java.time в старых Android).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.vguit_app"
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
    }

    signingConfigs {
        if (signingReady) {
            create("release") {
                storeFile = rootProject.file(
                    keystoreProperties.getProperty("storeFile") ?: "../vguit-release.jks",
                )
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (signingReady) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                if (buildingRelease) {
                    throw GradleException(
                        "Не настроена подпись релиза: заполните android/key.properties " +
                            "(storeFile, storePassword, keyAlias, keyPassword). " +
                            "Без постоянного ключа автообновление не сможет " +
                            "установить новую версию поверх старой.",
                    )
                }
                // Для отладочных сборок достаточно debug-ключа.
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
