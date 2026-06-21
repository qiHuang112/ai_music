import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystoreProperties = Properties()
val releaseKeystoreFile = rootProject.file("key.properties")
if (releaseKeystoreFile.exists()) {
    releaseKeystoreProperties.load(FileInputStream(releaseKeystoreFile))
}

fun releaseSigningValue(name: String): String? {
    val fileValue = releaseKeystoreProperties.getProperty(name)?.trim()
    if (!fileValue.isNullOrEmpty()) {
        return fileValue
    }
    return providers.environmentVariable("AI_MUSIC_${name.uppercase()}").orNull?.trim()
        ?.takeIf { it.isNotEmpty() }
}

val releaseStoreFile = releaseSigningValue("storeFile")
val releaseKeyAlias = releaseSigningValue("keyAlias")
val releaseKeyPassword = releaseSigningValue("keyPassword")
val releaseStorePassword = releaseSigningValue("storePassword")
val releaseSigningConfigured = listOf(
    releaseStoreFile,
    releaseKeyAlias,
    releaseKeyPassword,
    releaseStorePassword,
).all { !it.isNullOrEmpty() }

android {
    namespace = "com.qi.ai.music"
    compileSdk = 36
    buildToolsVersion = "35.0.0"
    ndkVersion = "27.0.11718014"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.qi.ai.music"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                val storeFilePath = releaseStoreFile!!
                storeFile = if (file(storeFilePath).isAbsolute) {
                    file(storeFilePath)
                } else {
                    rootProject.file(storeFilePath)
                }
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storePassword = releaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

tasks.configureEach {
    if (name.contains("Release")) {
        doFirst {
            if (!releaseSigningConfigured) {
                throw GradleException(
                    "Release signing is not configured. Create android/key.properties " +
                        "from key.properties.example or set AI_MUSIC_STOREFILE, " +
                        "AI_MUSIC_KEYALIAS, AI_MUSIC_KEYPASSWORD, and " +
                        "AI_MUSIC_STOREPASSWORD."
                )
            }
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
