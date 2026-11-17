import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "org.openbbs.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 22 要这个，不开的话 Gradle 直接报
        // 「Dependency ':flutter_local_notifications' requires core library desugaring」。
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // 包名决定老用户能不能覆盖升级，不能让新包各走各的。
        // 1.3.1 起全部用户都在 com.kalutoex.shijianxian，默认就用它；
        // 1.2.x / 1.3.0 那批旧包 com.kalutoex.tieba 已废弃，只留构建能力。
        applicationId =
            (project.findProperty("appId") as String?) ?: "com.kalutoex.shijianxian"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // 只出 32 位包时用：插件自带的 .so 会按依赖把 64 位目录也带进来，
    // 那些目录里没有 libapp.so / libflutter.so，64 位设备误装会直接崩。
    // 用 -PonlyArm32 打，versionCode 仍是 pubspec 里的，不会像 split-per-abi 那样被加 1000。
    packaging {
        jniLibs {
            // 插件自带的 .so 会把三种 ABI 目录都建出来，里面多数只有一个 libdartjni.so。
            // 打 64 位包时留着 x86_64、armeabi-v7a 那两份纯属白占，装机也用不到；
            // 打 32 位包（-PonlyArm32）则反过来只留 armeabi-v7a。
            if (project.hasProperty("onlyArm32")) {
                excludes += setOf("lib/arm64-v8a/**", "lib/x86_64/**", "lib/x86/**")
            } else {
                excludes += setOf("lib/x86/**", "lib/x86_64/**", "lib/armeabi-v7a/**")
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
    // 本地通知插件要求；版本跟插件 android/build.gradle 里写的一致。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
