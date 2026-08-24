# ClashH API 文档

## 1. NAPI 接口（libflclash.so）

Go 内核经 NAPI 暴露给 ArkTS 的接口（`proxy_core/src/main/cpp/types/libflclash/Index.d.ts`）：

| 函数 | 参数 | 返回 | 说明 |
| --- | --- | --- | --- |
| `initClash` | homeDir, version | number | 初始化内核（0 成功） |
| `startTun` | fd | number | 启动 TUN 隧道 |
| `stopTun` | - | void | 停止 TUN |
| `forceGc` | - | void | 强制 GC |
| `getVpnOptions` | - | string | VPN 配置 JSON |
| `validateConfig` | params | string | 校验配置 |
| `updateConfig` | params | string | 更新配置 |
| `getProxies` | - | string | 代理列表 JSON |
| `getTraffic` | - | string | 实时流量 JSON |
| `getTotalTraffic` | - | string | 总流量 JSON |
| `resetTraffic` | - | void | 重置流量 |
| `changeProxy` | params | string | 切换节点 |
| `asyncTestDelay` | params | string | 延迟测试 |
| `getConnections` | - | string | 连接列表 JSON |
| `closeConnections` | - | void | 关闭全部连接 |
| `closeConnection` | id | void | 关闭指定连接 |
| `getExternalProviders` | - | string | 供应商列表 |
| `startLog` | callback | void | 注册日志回调 |
| `stopLog` | - | void | 停止日志 |
| `startIpc` | path | void | 启动 IPC 服务 |

## 2. RPC 协议（UI <-> VPN 服务）

### 传输

- LocalSocket（Unix domain socket），路径：`{filesDir}/ClashH.sock`
- 消息：JSON + `EOF` 分隔符

### 请求

```json
{ "key": 1, "method": 5, "params": ["Group1", "Node1"] }
```

### 响应

```json
{ "key": 1, "method": 5, "result": "{\"status\":\"ok\"}", "error": "" }
```

### 方法枚举（RpcMethod / ClashRpcType）

| 值 | 方法 | 参数 | 说明 |
| --- | --- | --- | --- |
| 0 | QueryTrafficNow | - | 实时流量 |
| 1 | QueryTunnelState | - | 隧道状态 |
| 2 | QueryTrafficTotal | - | 总流量 |
| 3 | QueryProxyGroup | - | 代理列表 |
| 4 | QueryProviders | - | 供应商 |
| 5 | ChangeProxy | [group, proxy] | 切换节点 |
| 6 | HealthCheck | [name] | 单节点测速 |
| 7 | UpdateProvider | [name] | 更新供应商 |
| 8 | UploadProvider | [name, data] | 上传供应商 |
| 9 | QueryConnections | - | 连接列表 |
| 10 | CloseConnection | [id] | 关闭连接 |
| 11 | ClearConnections | - | 清空连接 |
| 12 | Load | [profileId] | 加载配置 |
| 13 | StartClash | - | 启动内核 |
| 14 | StopClash | - | 停止内核 |
| 15 | ValidConfig | [yaml] | 校验配置 |
| 16 | Reset | - | 重置 |
| 17 | GetCountryCode | [ip] | 国家代码 |
| 18 | UpdateGeoData | [type, name] | 更新 Geo |
| 19 | RegisterOnMessage | - | 消息订阅 |
| 20 | GetRequestList | - | 请求记录 |
| 21 | ClearRequestList | - | 清空记录 |
| 22 | SetLogObserver | - | 日志订阅 |
| 23 | StopLogObserver | - | 停止日志 |
| 24 | VpnOptions | - | VPN 选项 |
| 25 | SetOptionState | [json] | 设置状态 |
| 26 | GetVpnRunTime | - | VPN 运行时间 |
| 27 | VpnConfigInited | - | VPN 就绪 |
| 28 | SetNetInterfaces | [json] | 网络接口 |
| 29 | DownloadConfig | [url, ua] | 下载配置 |
| 30 | SetSystemDns | [dns] | 系统 DNS |
| 31 | HealthCheckAll | - | 全部测速 |
| 32 | HealthCheckBatch | [names] | 批量测速 |
| 33 | GetVersion | - | 内核版本 |
| 34 | GetMemory | - | 内存占用 |

## 3. 数据模型

详见 `docs/api/types.md`（完整 TS 模型定义）。

## 4. VPN 生命周期

```
用户点击连接
  -> HomePage.startVpn()
  -> vpnExtension.startVpnExtensionAbility(want)
  -> 系统拉起 ClashVpnAbility
  -> onCreate: 启动 SocketProxyService（RPC 服务端）
  -> UI 的 ClashClient 连接 LocalSocket
  -> 用户授权后 createVpnConnection -> TUN fd
  -> startTun(fd) -> sing_tun 接管流量
```
