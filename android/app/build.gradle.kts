import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.juxia.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.juxia.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 3
        versionName = "1.0.5"
    }

    val releasePropsFile = rootProject.file("keystore.properties")
    val releaseProps = Properties()
    if (releasePropsFile.exists()) {
        releasePropsFile.inputStream().use { releaseProps.load(it) }
    }
    signingConfigs {
        if (releasePropsFile.exists()) {
            create("release") {
                storeFile = rootProject.file(
                    releaseProps.getProperty("storeFile") ?: ".signing/juxia-release.jks"
                )
                storePassword = releaseProps.getProperty("storePassword")
                keyAlias = releaseProps.getProperty("keyAlias")
                keyPassword = releaseProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            // 备份格式字段名必须保留：SJ4 与鸿蒙版互通依赖这些名字不被混淆
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures { compose = true }
    testOptions {
        unitTests.all {
            it.systemProperty(
                "java.io.tmpdir",
                layout.buildDirectory.get().asFile.absolutePath
            )
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.10.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.navigation:navigation-compose:2.8.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    // 数据库加密（D2-A，2026-11-16）：SQLCipher 4.5.x 捆绑 SQLite 3.44，
    // FTS5 + trigram  intact；同时取代 requery 承担"新版 SQLite"角色
    implementation("net.zetetic:sqlcipher-android:4.5.6")
    // SQLCipher 的 SQLiteDatabase 实现依赖 SupportSQLiteDatabase，显式补 compile classpath。
    implementation("androidx.sqlite:sqlite:2.4.0")
    // 经典皮卡片毛玻璃：backdropBlur 的 Compose 等价（dev.chrisbanes.haze）
    implementation("dev.chrisbanes.haze:haze:1.5.4")
    testImplementation("junit:junit:4.13.2")
}
