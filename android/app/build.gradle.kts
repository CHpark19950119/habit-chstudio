plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.firebase.appdistribution")
}

android {
    namespace = "com.cheonhong.cheonhong_studio"
    compileSdk = flutter.compileSdkVersion
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
        applicationId = "com.cheonhong.cheonhong_studio"
        minSdk = 26  // Health Connect 요구사항 (2026-04-19, 갤럭시 a15 는 33+)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = file("release-keystore.jks")
            storePassword = "cheonhong2026"
            keyAlias = "cheonhong"
            keyPassword = "cheonhong2026"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            firebaseAppDistribution {
                artifactType = "APK"
                groups = "testers"
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // AppNotificationListener에서 직접 사용 (Tuya wake + screen ON)
    implementation("com.google.firebase:firebase-firestore-ktx:25.1.2")
}

flutter {
    source = "../.."
}