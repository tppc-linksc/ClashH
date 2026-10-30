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

## 7. 配置加载与 DNS 策略

配置加载链路（`ClashVpnAbility.loadProfile`）：

```
profiles/{uid}.yaml → parseYaml → 补默认值 → updateConfig(NAPI) → executor.ApplyConfig
```

补默认值的原则：**能影响连通性的字段不能盲信订阅**。

| 字段 | 策略 |
| --- | --- |
| `geox-url` / `geodata-loader` | 缺失时补齐，否则 GEOIP/GEOSITE 规则会触发资源下载或加载器为空 |
| `tun` | 每次都完整下发，内核会无条件覆盖这几个字段 |
| `dns` | 只有 `enable === true` 且 `nameserver` 非空才算可用，否则整段替换为内置 DNS |
| `sniffer` | 缺失时补默认值 |

DNS 判定为什么这么严：机场订阅常见两种坑，而节点 server 往往全是域名，DNS 一挂就是整页节点超时。

1. `dns.enable: false` —— 内核退回系统解析器，而 VPN 扩展进程里的系统解析不可靠，TUN 又把 53 端口劫持给被禁用的 DNS。
2. `dns.fallback` 指向境外 DoH —— 境外 IP 必然命中 `fallback-filter`，国内直连不可达时解析要等十几秒。

因此内置 DNS 固定使用 fake-ip + 国内 DoH，并显式配置 `proxy-server-nameserver`：节点域名必须走直连 DNS 解析，否则解析请求会绕回隧道自身形成环回。

分享链接（`ShareLinkParser`）另有一条独立约束：机场常用「借用域名做 SNI + 自签证书」，链接里的 `allowInsecure=1` 必须落成 `skip-cert-verify: true`，否则内核严格校验证书会让整组节点握手失败。

