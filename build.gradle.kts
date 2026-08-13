plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.0.21"
    id("maven-publish")
}

// JNI 产物目录：由 build-jni.sh 生成（先跑脚本，再跑 Gradle）。
// 放在 build/generated 下，避免与 Kotlin 增量编译缓存目录（build/kotlin）重叠。
// 仓库本身不包含任何源码/二进制，全部在构建时从 EasyTier 官方 tag 拉取。
val jniLibsDir = file(System.getenv("JNI_LIBS_DIR") ?: layout.buildDirectory.dir("generated/jni").get().asFile)
val jniKotlinDir = file(System.getenv("JNI_KOTLIN_DIR") ?: layout.buildDirectory.dir("generated/kotlin").get().asFile)

// 版本号与 EasyTier 官方版本一致（workflow 通过 -PjniVersion 传入）
val jniVersion: String = (project.findProperty("jniVersion") as String?)
    ?: System.getenv("JNI_VERSION")
    ?: "0.0.0"

android {
    namespace = "com.easytier.jni"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
    }

    sourceSets {
        getByName("main") {
            // Kotlin 包装类（EasyTierJNI.kt）与 4 个 ABI 的 .so，均由 build-jni.sh 放入 build/ 下
            kotlin.srcDir(jniKotlinDir)
            jniLibs.srcDir(jniLibsDir)
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                // Android 原生库必须用 AAR 打包，AGP 才会把 jni/<abi>/*.so 打进 APK；
                // 普通 jar 里的 .so 不会进入 APK。Gradle 依赖写法与 jar 完全一致。
                from(components["release"])
                groupId = "com.easytier"
                artifactId = "easytier-android-jni"
                version = jniVersion
            }
        }
        repositories {
            maven {
                // 默认发布到本地 build/maven-repo；CI 中通过 -PmavenRepoDir 指向 maven 仓库 checkout 目录
                val repoDir = providers.gradleProperty("mavenRepoDir").orNull
                url = uri(repoDir ?: layout.buildDirectory.dir("maven-repo").get().asFile)
            }
        }
    }
}
