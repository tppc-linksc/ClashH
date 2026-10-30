# ClashH

> 鸿蒙原生 Clash 客户端 —— 基于 [mihomo](https://github.com/MetaCubeX/mihomo) 内核，
> UI 参考 [clash-verge-rev](https://github.com/clash-verge-rev/clash-verge-rev) 与 [ClashBox](https://github.com/xiaobaigroup/ClashBox)。

## 项目简介

ClashH 是为 **HarmonyOS NEXT（6.1.0+ / API 23+）** 打造的原生代理客户端：

- **纯鸿蒙原生**：ArkTS + ArkUI 3.0 声明式 UI，Stage 模型
- **mihomo 内核**：Go 交叉编译为 `libflclash.so`，经 NAPI 嵌入应用进程
- **系统 VPN**：`VpnExtensionAbility` 创建虚拟网卡（TUN），流量接管
- **多端适配**：优先适配 400–599vp 阔直板手机（Pura X View），兼顾普通手机、平板与 2in1
- **完整 UI**：深浅色主题、中英文国际化、平板/手机自适应导航
- **国内分流**：规则模式下自动补齐 CN 直连规则（设置中可关闭），首页可快捷切换规则/全局/直连，并在重启后保持选择

设备优先级与真机验收见 [docs/device-priority.md](docs/device-priority.md)。

### 当前使用状态

已在作者自用鸿蒙手机上持续使用一段时间：扫码导入配置、建立 VPN 连接及连接后的基础使用均可正常进行，主流程相对稳定。细节功能和更多设备、网络场景尚未系统测试。

## 技术架构

```
+------------------------------------------------------------+
| entry（UI 模块，ArkTS）                                      |
|  Index -> HomePage / ProxyPage / ConfigurationPage / MorePage |
|       ^                                        |             |
|       | LocalSocket (RPC)                     | NAPI        |
+-------|----------------------------------------|-------------+
| proxy_core（原生核心，HAR）                     |             |
|  ClashClient <-> SocketProxyService <-> Go flclash 内核      |
|                    |                     |                  |
|             ClashVpnAbility        libflclash.so (mihomo)   |
|             (VpnExtensionAbility)   TUN fd 交给 sing_tun    |
+------------------------------------------------------------+
```

### 两条通信链路

1. **UI -> VPN 服务**：LocalSocket（Unix domain socket），RPC 协议（见 `RpcProtocol.ets`）
2. **VPN 服务 -> 内核**：NAPI 直调 `libflclash.so`（`initClash`/`startTun`/`getProxies`...）

## 目录结构

```
ClashH/
├── AppScope/                 # 应用级配置（图标/名称/签名）
├── entry/                    # UI 主模块（HAP）
│   └── src/main/ets/
│       ├── entryability/     # EntryAbility + ClashVpnAbility（VPN 后台）
│       ├── pages/            # Index/Home/Proxy/Configuration/More
│       ├── viewmodel/        # 页面数据模型
│       └── common/           # 断点系统（平板/手机自适应）
├── proxy_core/               # 原生核心模块（HAR）
│   ├── src/main/cpp/types/   # Go NAPI 的 ArkTS 类型声明
│   ├── src/main/ets/         # RPC 协议 / ClashClient / VPN 服务
│   ├── src/flclash/          # Go 内核源码（mihomo 封装）
│   └── libs/arm64-v8a/       # libflclash.so 产物
├── mihomo/                   # mihomo 参考源码（Alpha 分支）
├── repo/                     # clash-verge-rev 参考源码
├── references/ClashBox/      # ClashBox 参考源码
├── docs/                     # 架构/API/构建文档
└── scripts/                  # 构建与工具脚本
```

## 构建指南

### 前置条件

1. **DevEco Studio**（HarmonyOS NEXT 6.1.0+ SDK，API 23）
2. **go-ohos 工具链**：[OpenHarmony SIG Go](https://gitee.com/openharmony-sig/ohos_golang_go)
3. **mihomo OHOS 分支**：`proxy_core/src/flclash/init_core.sh` 自动克隆

### 编译内核（生成 libflclash.so）

```bash
cd proxy_core/src/flclash
./init_core.sh local # 链接仓库内 mihomo 源码（已初始化时可跳过）
./build.sh          # 交叉编译 arm64（MatePad / 手机）
```

### 构建应用

用 DevEco Studio 打开项目根目录，同步后构建即可。

## 开发路线

- [x] 项目骨架（Stage 模型 + 四层架构）
- [x] Go 直接导出的 NAPI 接口
- [x] RPC 协议与 IPC（LocalSocket）
- [x] 数据模型（Proxy/Connection/Profile/Config）
- [x] UI 框架（断点自适应 + 深浅色 + 中英文）
- [x] 内核编译脚本（go-ohos / openharmony-arm64）
- [x] TUN 真机基础验证（扫码导入、连接及基础使用正常）
- [ ] 细节功能与更多设备、网络场景的系统测试
- [x] 订阅导入/更新流程
- [x] 连接列表 / 日志实时流
- [ ] 上架与签名

## 更新记录

每次发布的改动、原因与涉及文件见 [CHANGELOG.md](CHANGELOG.md)。
最近一次（2026-10-30）修复了代理页 Dock 遮挡、配置改名不刷新、订阅 DNS 兼容、分享链接 `allowInsecure` 丢失与测速结果不刷新等问题。

## 参考项目

| 项目 | 说明 | 许可证 |
| --- | --- | --- |
| [mihomo](https://github.com/MetaCubeX/mihomo) | Clash Meta 内核（Go） | GPL-3.0 |
| [clash-verge-rev](https://github.com/clash-verge-rev/clash-verge-rev) | 桌面客户端 UI 参考 | GPL-3.0 |
| [ClashBox](https://github.com/xiaobaigroup/ClashBox) | 鸿蒙原生 mihomo 客户端（架构参考） | GPL-3.0 |

> 本项目仅作学习研究用途。
