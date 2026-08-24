# ClashH 架构设计

> 版本：v0.1（2026-08）

## 1. 总体架构

ClashH 采用四层架构，参照 ClashBox 的成熟方案：

```
┌─────────────────────────────────────────────────────────┐
│ ① entry（UI 模块 HAP）                                    │
│    ArkTS + ArkUI 3.0，Navigation/Tabs 自适应              │
│    HomePage / ProxyPage / ConfigurationPage / MorePage   │
└──────────────┬──────────────────────────────────────────┘
               │ LocalSocket（Unix Domain Socket，RPC）
┌──────────────▼──────────────────────────────────────────┐
│ ② proxy_core（原生核心 HAR）                              │
│    ClashClient（RPC 客户端）                              │
│    SocketProxyService（RPC 服务端）                       │
│    ClashVpnService（VPN 抽象）                            │
└──────────────┬──────────────────────────────────────────┘
               │ NAPI（进程内直调）
┌──────────────▼──────────────────────────────────────────┐
│ ③ libflclash.so（Go 交叉编译产物）                        │
│    mihomo 内核封装：initClash/startTun/updateConfig/...   │
└──────────────┬──────────────────────────────────────────┘
               │ TUN fd
┌──────────────▼──────────────────────────────────────────┐
│ ④ 系统 VPN（VpnExtensionAbility）                         │
│    vpnExtension.createVpnConnection -> 虚拟网卡 fd        │
└─────────────────────────────────────────────────────────┘
```

## 2. 为什么用 NAPI + 进程内内核

HarmonyOS NEXT 沙箱**禁止普通应用 fork/exec 自带 ELF 二进制**，
因此 mihomo 必须以动态库形式嵌入应用进程：

1. 使用 go-ohos（OpenHarmony SIG Go 移植版）交叉编译
2. `GOOS=openharmony GOARCH=arm64 CGO_ENABLED=1 -buildmode c-shared`
3. 产出 `libflclash.so`，放入 `proxy_core/libs/arm64-v8a/`
4. 通过 ohos-napi 由 Go 动态库直接导出 NAPI 给 ArkTS

## 3. TUN 数据通路

```
用户点击连接
  -> vpnExtension.startVpnExtensionAbility(want)
  -> 系统拉起 ClashVpnAbility（VpnExtensionAbility）
  -> vpnConnection.create(VpnConfig) -> 返回 TUN fd
  -> startTun(fd)（NAPI 调用 Go）
  -> sing_tun.New({FileDescriptor: fd, AutoRoute: false})
  -> 流量经 TUN fd 进入 mihomo 隧道
```

关键点：`AutoRoute: false` —— 路由由鸿蒙系统 VPN 框架管理，
内核只负责收发 TUN fd 上的 IP 包，避免与系统路由冲突。

## 4. RPC 协议

UI 与 VPN 服务通过 LocalSocket 通信，协议见 `RpcProtocol.ets`：

- 请求：`{key, method, params[]}`（JSON + `EOF` 分隔）
- 响应：`{key, method, result, error}`
- key=0 表示服务端主动推送（日志、事件）

方法枚举（RpcMethod）与 Go 侧 `ClashRpcType` 一一对应。

## 5. 断点系统（屏幕适配）

二维断点（宽度 × 高度）：

| 宽度断点 | 范围 | 典型设备 |
| --- | --- | --- |
| xs | <320vp | 小屏手机 |
| sm | 320~600vp | MatePad mini 竖屏（480vp） |
| md | 600~840vp | 手机横屏 / 小平板 |
| lg | 840~1000vp | 平板竖屏 |
| xl | >=1000vp | MatePad 12.2 横屏（~1100vp） |

- 窄屏（xs/sm）：底部 Tab 栏
- 宽屏（lg/xl）：左侧 Tab 栏
- 内容宽度：窄屏 100%，宽屏限宽居中（720/840vp）

## 6. 文件结构约定

- 单文件不超过 1000 行（gold file 红线）
- 中文注释，中英文双语资源（`zh_CN` / `en_US`）
- 深浅色主题：`base/element/color.json`（浅色）+ `dark/element/color.json`（深色）
