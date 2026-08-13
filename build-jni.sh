#!/usr/bin/env bash
set -euo pipefail

# easytier-jni 构建脚本
# 从 EasyTier 官方 tag（如 v2.6.4）拉取源码，构建 libeasytier_android_jni.so（默认 4 个 ABI），
# 并取出同一 tag 的 Kotlin 包装类 EasyTierJNI.kt，供 Gradle 打包成 AAR。
# 仓库本身不含 EasyTier 源码，所有源文件都在构建时从官方仓库拉取。
#
# 用法:
#   ./build-jni.sh v2.6.4
#   ABIS="arm64-v8a x86_64" ./build-jni.sh v2.6.4
#
# 前置要求: Rust 1.95 (rustup)、protoc、Android NDK、cargo-ndk（脚本自动安装）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG="${1:-}"
ABIS="${ABIS:-arm64-v8a armeabi-v7a x86 x86_64}"
EASYTIER_SRC="$SCRIPT_DIR/build/easytier-src"
OUT_LIBS="$SCRIPT_DIR/build/generated/jni"
OUT_KOTLIN="$SCRIPT_DIR/build/generated/kotlin"

if [ -z "$TAG" ]; then
    echo "用法: $0 <EasyTier tag>，例如: $0 v2.6.4" >&2
    exit 1
fi

# EasyTier 存在未使用导入/死代码等警告。若环境注入 RUSTFLAGS=-D warnings
# （部分 CI 工具链默认行为）会导致编译失败，这里仅移除该开关。
RUSTFLAGS="${RUSTFLAGS:-}"
export RUSTFLAGS="${RUSTFLAGS//-D warnings/}"

declare -A TARGET_MAP
TARGET_MAP["arm64-v8a"]="aarch64-linux-android"
TARGET_MAP["armeabi-v7a"]="armv7-linux-androideabi"
TARGET_MAP["x86"]="i686-linux-android"
TARGET_MAP["x86_64"]="x86_64-linux-android"

fail() {
    echo "错误: $*" >&2
    exit 1
}

command -v rustc >/dev/null 2>&1 || fail "未找到 rustc，请先安装 Rust"
command -v cargo >/dev/null 2>&1 || fail "未找到 cargo"
command -v protoc >/dev/null 2>&1 || fail "未找到 protoc（easytier-proto 构建需要）"
command -v git >/dev/null 2>&1 || fail "未找到 git"

if ! cargo ndk --version >/dev/null 2>&1; then
    echo "==> 安装 cargo-ndk..."
    cargo install cargo-ndk
fi

EASYTIER_DIR="$EASYTIER_SRC/$TAG"
mkdir -p "$EASYTIER_DIR"
if [ ! -d "$EASYTIER_DIR/.git" ]; then
    echo "==> 克隆 EasyTier $TAG -> $EASYTIER_DIR"
    git clone --depth 1 --branch "$TAG" https://github.com/EasyTier/EasyTier.git "$EASYTIER_DIR"
fi

JNI_DIR="$EASYTIER_DIR/easytier-contrib/easytier-android-jni"
KOTLIN_FILE="$JNI_DIR/kotlin/com/easytier/jni/EasyTierJNI.kt"
[ -d "$JNI_DIR" ] || fail "easytier-android-jni 不存在: $JNI_DIR（请确认 tag $TAG 包含该模块）"
[ -f "$KOTLIN_FILE" ] || fail "Kotlin 包装类不存在: $KOTLIN_FILE"

patch_file="$SCRIPT_DIR/patches/easytier-jni-self-contained.patch"
if [ -f "$patch_file" ] \
    && grep -q 'unsafe extern "C"' "$JNI_DIR/src/lib.rs" \
    && ! grep -q 'easytier-ffi' "$JNI_DIR/Cargo.toml"; then
    echo "==> 应用 JNI 自包含补丁（旧版 EasyTier 的 JNI 壳没有静态链接 easytier-ffi）"
    git -C "$EASYTIER_DIR" apply --whitespace=nowarn "$patch_file"
fi

for abi in $ABIS; do
    rust_target="${TARGET_MAP[$abi]:-}"
    [ -n "$rust_target" ] || fail "未知 ABI: $abi（支持: arm64-v8a armeabi-v7a x86 x86_64）"

    rustup target list --installed | grep -q "$rust_target" || rustup target add "$rust_target"

    echo "==> 构建 $abi ($rust_target)"
    (cd "$JNI_DIR" && cargo ndk -t "$abi" build --release)

    OUT_DIR="$OUT_LIBS/$abi"
    mkdir -p "$OUT_DIR"
    cp "$EASYTIER_DIR/target/$rust_target/release/libeasytier_android_jni.so" "$OUT_DIR/"
    echo "==> 已复制到 $OUT_DIR/（libeasytier_android_jni.so，自包含 easytier-ffi）"
done

mkdir -p "$OUT_KOTLIN/com/easytier/jni"
cp "$KOTLIN_FILE" "$OUT_KOTLIN/com/easytier/jni/EasyTierJNI.kt"
echo "==> Kotlin 包装类已复制到 $OUT_KOTLIN/"

echo "==> 完成。运行 ./gradlew publish -PjniVersion=${TAG#v} 打包并发布"
