#!/bin/bash
# ===========================================================================
# flclash 交叉编译脚本
# 将 mihomo 内核（Go）交叉编译为 HarmonyOS 可加载的动态库 libflclash.so
#
# 前置条件：
#   1. DevEco Studio 自带的 OHOS NDK（含 sysroot 与 clang 工具链）
#      OHOS_NATIVE_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native
#   2. OpenHarmony SIG Go 工具链（go-ohos，当前仅支持 arm64）
#   3. mihomo OHOS 分支源码（git submodule）
#
# 用法：
#   ./build.sh                # 编译 arm64（默认，MatePad / 手机）
# ===========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MIHOMO_DIR="$SCRIPT_DIR/../../../mihomo"

# ---- 参数 -------
ARCH="${1:-arm64}"           # arm64 | x86_64
if [ "$ARCH" = "arm64" ]; then
  TARGET="aarch64"
  OUTDIR="arm64-v8a"
else
  TARGET="x86_64"
  OUTDIR="x86_64"
fi

# ---- 工具链路径（按需修改） ----
OHOS_NATIVE_HOME="${OHOS_NATIVE_HOME:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
GO_OHOS="${GO_OHOS:-go-ohos}"

TOOLCHAIN="$OHOS_NATIVE_HOME/llvm"
OUTPUT="$SCRIPT_DIR/../../libs/$OUTDIR/libflclash.so"
CORE_VERSION="${CORE_VERSION:-$(git -C "$MIHOMO_DIR" describe --tags --always --dirty 2>/dev/null || echo development)}"

if [ ! -x "$GO_OHOS" ] && ! command -v "$GO_OHOS" >/dev/null 2>&1; then
  echo "错误：未找到 go-ohos。请设置 GO_OHOS=/path/to/go-ohos/bin/go" >&2
  exit 1
fi
if [ ! -x "$TOOLCHAIN/bin/clang" ]; then
  echo "错误：未找到 OHOS NDK clang：$TOOLCHAIN/bin/clang" >&2
  exit 1
fi
if [ "$ARCH" != "arm64" ]; then
  echo "错误：当前 OpenHarmony SIG Go 1.22 工具链仅支持 openharmony/arm64" >&2
  exit 1
fi

# ---- 编译环境 ----
export CC="$TOOLCHAIN/bin/clang"
export CXX="$TOOLCHAIN/bin/clang++"
export CGO_AR="$TOOLCHAIN/bin/llvm-ar"
export GOOS="openharmony"
export GOARCH="$ARCH"
export CGO_ENABLED="1"
export CGO_CFLAGS="-Wno-error --target=$TARGET-linux-ohos --sysroot=$OHOS_NATIVE_HOME/sysroot"
export CGO_LDFLAGS="--sysroot=$OHOS_NATIVE_HOME/sysroot --target=$TARGET-linux-ohos"

echo "==> 编译 libflclash.so ($ARCH)"
mkdir -p "$(dirname "$OUTPUT")"
cd "$SCRIPT_DIR"
# -tags ohos：启用应用侧鸿蒙适配；当前 TUN 使用 system 栈，不依赖 gvisor。
"$GO_OHOS" build -trimpath -buildmode c-shared \
  -tags "ohos" \
  -ldflags "-s -w -X main.Version=$CORE_VERSION" \
  -o "$OUTPUT" .

echo "==> 完成: proxy_core/libs/$OUTDIR/libflclash.so"
