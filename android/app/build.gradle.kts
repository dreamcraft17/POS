plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.epluse.eepos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.epluse.eepos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // -------- Release signing from gradle.properties (Option B) --------
    signingConfigs {
        create("release") {
            fun readSecret(name: String): String? {
                val fromGradle = project.findProperty(name)?.toString()?.trim()
                if (!fromGradle.isNullOrEmpty()) return fromGradle

                val fromEnv = System.getenv(name)?.trim()
                if (!fromEnv.isNullOrEmpty()) return fromEnv

                return null
            }

            val releaseStoreFile = readSecret("RELEASE_STORE_FILE")
            val releaseStorePassword = readSecret("RELEASE_STORE_PASSWORD")
            val releaseKeyAlias = readSecret("RELEASE_KEY_ALIAS")
            val releaseKeyPassword = readSecret("RELEASE_KEY_PASSWORD")

            // Only configure when all props are present (helps on CI/PRs)
            val hasAll =
                !releaseStoreFile.isNullOrBlank() &&
                !releaseStorePassword.isNullOrBlank() &&
                !releaseKeyAlias.isNullOrBlank() &&
                !releaseKeyPassword.isNullOrBlank()

            if (hasAll) {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            } else {
                // Optional: uncomment to fail fast if missing
                // throw GradleException("Missing release signing properties in gradle.properties")
                println("Warning: Release signing secrets are missing; release build may be unsigned.")
            }
        }
    }

    buildTypes {
        getByName("release") {
            // Use the REAL release signing (not debug)
            signingConfig = signingConfigs.getByName("release")

            // Safe defaults for Flutter; enable later if you add proper rules
            isMinifyEnabled = false
            isShrinkResources = false
            // If you enable minify/shrink later, add proguard files:
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        getByName("debug") {
            // leave default debug signing
        }
    }
}

flutter {
    source = "../.."
}
