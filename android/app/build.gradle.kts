import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 读取签名配置（android/key.properties，已在 .gitignore 中忽略）
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.shiwuji.shiwuji"
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
        applicationId = "com.shiwuji.shiwuji"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 应用名称占位符（debug 构建在 buildTypes 中覆盖为「拾物记Debug」）
        manifestPlaceholders["appLabel"] = "拾物记"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // 正式签名：仅当 android/key.properties 存在时使用；
            // 缺失时（如临时测试机）回退 debug 签名，保证 release 测试包可打包
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            // ⚠️ 临时：小体积测试包，独立包名 com.shiwuji.shiwuji.test
            //    （与正式包 com.shiwuji.shiwuji、调试包 .debug 三者共存）
            // 发布正式版前必须删除下面这一行！
            applicationIdSuffix = ".test"
        }
        debug {
            // 独立包名（com.shiwuji.shiwuji.debug）：可与正式包同时安装，数据完全隔离。
            // 应用名称保持「拾物记」（包名有 debug 后缀即可区分）
            applicationIdSuffix = ".debug"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
