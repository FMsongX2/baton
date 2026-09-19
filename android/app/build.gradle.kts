plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hajung.baton"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hajung.baton"
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
        // AdMob 앱 ID. APK 매니페스트에 그대로 노출되는 값이라 비밀이 아님.
        // 실제 ID는 빌드 때 -P admobAppId=... 로 넣고, 없거나 비면 공식 테스트 ID를 씀.
        // profile은 debug를 복제해 만들어지므로 buildTypes가 아니라 여기 둬야 비지 않음
        val admobAppId = (project.findProperty("admobAppId") as String?)?.takeIf { it.isNotBlank() }
            ?: "ca-app-pub-3940256099942544~3347511713"
        // SDK의 init provider가 광고 사용 여부와 무관하게 앱 시작 때 이 형식을 검사하고 틀리면 죽음
        require(Regex("^ca-app-pub-[0-9]{16}~[0-9]{10}$").matches(admobAppId)) {
            "admobAppId 형식이 틀림(ca-app-pub-숫자16~숫자10): $admobAppId"
        }
        manifestPlaceholders["admobAppId"] = admobAppId
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
