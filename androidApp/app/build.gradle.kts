import java.util.zip.ZipFile

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

tasks.register("verifyDebugApkRuntime") {
    dependsOn("assembleDebug")
    doLast {
        val apk = layout.buildDirectory.file("outputs/apk/debug/app-debug.apk").get().asFile
        require(apk.isFile && apk.length() > 10_000_000L) {
            "Debug APK missing or unexpectedly small: ${apk.absolutePath}"
        }
        ZipFile(apk).use { zip ->
            val engine = zip.getEntry("lib/arm64-v8a/liblitertlm_jni.so")
            require(engine != null && engine.size > 10_000_000L) {
                "APK does not contain the arm64 LiteRT-LM native engine"
            }
            require(zip.getEntry("AndroidManifest.xml") != null) {
                "APK does not contain AndroidManifest.xml"
            }
        }
        println("Verified APK contains the bundled arm64 LiteRT-LM engine: ${apk.length()} bytes")
    }
}

android {
    namespace = "com.mingkong.photoaccessibility"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.mingkong.photoaccessibility"
        minSdk = 26
        targetSdk = 35
        versionCode = 8
        versionName = "0.8.0-test"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    packaging {
        jniLibs.useLegacyPackaging = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.9.0")
    implementation("androidx.recyclerview:recyclerview:1.4.0")
    implementation("androidx.exifinterface:exifinterface:1.4.1")
    implementation("androidx.documentfile:documentfile:1.1.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.15.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}
