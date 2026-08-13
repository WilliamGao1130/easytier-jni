# easytier-android-jni

EasyTier Android JNI 库的独立构建仓库。**仓库内不包含任何源文件与二进制**
（只有构建逻辑），每次构建都从 EasyTier 官方仓库拉取对应版本的源码、原生库与
Kotlin 包装类，打包成 AAR 后发布到 Maven 仓库。

## 产物与版本

- 坐标：`com.easytier:easytier-android-jni:<版本号>`
- 版本号 = EasyTier 官方 release 版本号（如 `2.6.4`，对应官方 tag `v2.6.4`）
- 产物类型：**AAR**（Android 原生库必须用 AAR，AGP 才会把 `jni/<abi>/*.so`
  打进 APK；普通 jar 内的 `.so` 不会进入 APK，Gradle 依赖写法与 jar 相同）
- 架构：`arm64-v8a`、`armeabi-v7a`、`x86`、`x86_64`
- 每个 ABI 含 **一个 .so**：`libeasytier_android_jni.so`（JNI 壳，已将
  `easytier-ffi` 静态链接进去）。旧版 v2.6.4 的 JNI 壳原本用裸
  `extern "C"` 声明 FFI 符号，导致运行时 `cannot locate symbol`；本仓库会在
  构建时自动应用自包含补丁，把 FFI 作为 Rust 依赖静态链接进同一个 JNI 库。

## 工作流程

1. 每天北京时间 00:00（GitHub Actions cron 为 UTC，已用 `0 16 * * *` 折算）
   自动检测 EasyTier 官方最新 release；
2. 若该版本尚未发布到 Maven 仓库，则并行构建：`build-jni` 任务按
   matrix 拆成 4 个 job（每个 runner 构建一个 ABI 的 JNI 壳），
   总耗时约等于单个 ABI 的编译时间；
3. `publish` 任务收集 4 个 `.so`（4 ABI × 1），取出同一 tag 的 `EasyTierJNI.kt`，
   Gradle 打包 AAR 并 `maven-publish`；
4. 提交到 [WilliamGao1130/maven](https://github.com/WilliamGao1130/maven)
   的 `main` 分支根目录（标准 Maven 目录结构），由 GitHub Pages 对外提供；
5. 手动触发：仓库 Actions → `Build & Publish easytier-android-jni` → `Run workflow`，
   可指定版本号，留空则构建最新官方 release。

## 一次性配置

1. 在 GitHub 创建空仓库 `WilliamGao1130/maven`（可先推入本仓库旁的 `maven/`
   目录内容），并打开 Settings → Pages → Deploy from a branch → `main` / `/`。
2. 在 `easytier-android-jni` 仓库 Settings → Secrets and variables → Actions 中添加
   **1 个** Secret：

   | 名称 | 说明 |
   |---|---|
   | `MAVEN_REPO_TOKEN` | 有权限向 `WilliamGao1130/maven` 写入的 PAT（classic `repo` 权限，或 fine-grained：仅 maven 仓库 `Contents: Read and write`） |

   > `GITHUB_TOKEN` 由 GitHub 自动注入，无需配置。

## 本地构建

```bash
./build-jni.sh v2.6.4
./gradlew publish -PjniVersion=2.6.4 -PmavenRepoDir=build/maven-repo
```

前置要求：Rust 1.95（rustup）、protoc、Android NDK、Android SDK（compileSdk 35）。

## 在 Android 项目中使用（Gradle 引入依赖）

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        maven { url = uri("https://williamgao1130.github.io/maven") }
        google()
        mavenCentral()
    }
}

// app/build.gradle.kts
dependencies {
    implementation("com.easytier:easytier-android-jni:2.6.4")
}
```

## 注意事项

- 每日检测只针对**非预发布** release；pre-release 版本不会触发构建。
- AnTier 目前使用的 JNI API（`startConfigServerClient` / `callJsonRpc` /
  `listInstances` 等）只在 EasyTier `main` 分支存在，官方最新正式版 v2.6.4
  尚不包含。等包含这些 API 的下一个官方 release 发布后，本流水线会自动构建
  发布，届时 AnTier 即可切换为 Gradle 依赖（见下方 AnTier 迁移说明）。
