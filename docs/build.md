# 构建指南

## 环境要求

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| DevEco Studio | 6.0+ | 含 HarmonyOS NEXT 6.1.0 SDK（API 23） |
| Node.js | 18+ | DevEco 内置或独立安装 |
| Go | 1.20+ | 用于自举 go-ohos（go-ohos 需独立安装） |
| go-ohos | OpenHarmony SIG Go 1.22 | 编译 `openharmony/arm64` 目标 |

## 第一步：初始化内核源码

```bash
cd proxy_core/src/flclash
./init_core.sh local   # 链接到仓库内 mihomo 源码（仓库已初始化时会自动跳过）
```

## 第二步：交叉编译内核

通过环境变量指定工具链路径：

```bash
OHOS_NATIVE_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native
GO_OHOS=/path/to/go-ohos/bin/go
```

然后执行：

```bash
./build.sh            # arm64（MatePad / 手机）
```

产物：`proxy_core/libs/arm64-v8a/libflclash.so`

## 第三步：DevEco Studio 构建

1. 用 DevEco Studio 打开项目根目录
2. File -> Sync and Refresh Project
3. Build -> Build Hap(s)/APP(s)

### 签名配置

仓库不跟踪本机签名配置：`build-profile.json5` 已被 `.gitignore` 忽略，模板见根目录 `build-profile.example.json5`。
首次打开项目时，复制模板为 `build-profile.json5`，再在 DevEco Studio 中配置签名
（File -> Project Structure -> Signing Configs，可自动生成或导入本地证书）。
签名证书、口令等材料不要提交到仓库。

## 常见问题

### Q: 没有 go-ohos 能否构建？

不能。标准 Go 的 `linux/arm64` 虽然可以生成 `.so`，但不会按 OpenHarmony 的 NAPI 初始化时序导出 ArkTS 接口；必须使用 OpenHarmony SIG 的 go-ohos 工具链。

### Q: 本机没有鸿蒙 NDK 头文件，Go 编译报错？

`napi/native_api.h not found` 是正常的 —— 需要 DevEco Studio 的 OHOS NDK 环境。
纯逻辑检查可运行 `go build ./...`（排除 ohos/cgo tag）。

### Q: 运行时报 `No such file or directory`？

确认 `proxy_core/libs/arm64-v8a/libflclash.so` 存在，并重新执行无缓存 HAP 构建。
