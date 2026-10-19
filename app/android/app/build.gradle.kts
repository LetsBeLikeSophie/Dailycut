import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 2026-10-19: 출시용 업로드 키. 출시 빌드(tools/build_release.sh)만 UPLOAD_SIGN=true로 이 키를 쓰고,
// 테스트로 나눠 주는 APK는 예전처럼 디버그 키(이미 깔린 앱을 덮어 설치할 수 있게). key.properties·키스토어는 git 밖.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val useUploadKey = System.getenv("ORG_GRADLE_PROJECT_UPLOAD_SIGN") == "true" && keyProps.getProperty("storeFile") != null

android {
    namespace = "com.dailycut.dailycut"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dailycut.dailycut"
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
        // 애드몹 앱 ID: gradle.properties(ADMOB_APP_ID)가 없으면 구글 공식 테스트 앱 ID(개발용 — 광고 수익 없음)
        manifestPlaceholders["admobAppId"] = (project.findProperty("ADMOB_APP_ID") as String?) ?: "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        if (useUploadKey) {
            create("upload") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (useUploadKey) "upload" else "debug")
            // 코드 축소(R8)가 광고 SDK 쪽 WorkManager/Room 클래스를 지워 앱이 안 켜지던 문제 때문에 보존 규칙을 둠(2026-10-18)
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    // 홈 화면 위젯의 갱신·재시도 일정(광고 SDK가 이미 끌고 오는 같은 라이브러리 — 위젯 코드가 직접 쓰므로 명시)
    implementation("androidx.work:work-runtime:2.10.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
