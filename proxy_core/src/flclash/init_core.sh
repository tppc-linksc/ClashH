#!/bin/bash
# ===========================================================================
# 初始化 mihomo OHOS 内核源码（flclash/core）
#
# ClashH 的 Go 内核基于 mihomo 的 OHOS 支持分支：
#   https://github.com/xfz347/Clash.Meta（ohos 分支，ClashBox 维护）
#
# 用法：
#   ./init_core.sh          # 克隆 ohos 分支到 ./core
#   ./init_core.sh local    # 软链接到本地 mihomo 源码（开发调试）
# ===========================================================================

set -e

MODE="${1:-clone}"

if [ -d "core" ] && [ -f "core/go.mod" ]; then
  echo "==> core 已存在，跳过"
  exit 0
fi

if [ "$MODE" = "local" ]; then
  # 链接到仓库内的 mihomo 源码（Alpha 分支，API 可能不完全一致）
  echo "==> 软链接到 ../../../mihomo（Alpha 分支）"
  ln -sfn ../../../mihomo core
else
  # 克隆 ClashBox 维护的 OHOS 分支（推荐）
  echo "==> 克隆 mihomo OHOS 分支..."
  git clone --depth 1 -b ohos https://github.com/xfz347/Clash.Meta.git core
  echo "==> 完成"
fi
