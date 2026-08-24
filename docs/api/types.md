# 数据模型 (ArkTS 复刻)

> 参考 clash-verge-rev 的 `src/types/` 与 mihomo HTTP API 返回结构。

## Proxy / ProxyGroup

```typescript
interface IProxyNode {
  name: string;             // 节点名称
  type: ProxyType;          // ss / ssr / vmess / vless / trojan / hysteria / hysteria2 / tuic / wireguard / direct / reject
  udp: boolean;             // 是否支持 UDP
  xudp: boolean;            // XUDP (Reality/VLESS)
  tfo: boolean;             // TCP Fast Open
  mptcp: boolean;           // Multipath TCP
  smux: boolean;            // Stream Multiplex
  history: DelayHistory[];  // 历史延迟样本
}

interface IProxyGroup extends IProxyNode {
  type: 'Selector' | 'URLTest' | 'Fallback' | 'LoadBalance' | 'Relay';
  all: string[];            // 子节点 / 子组 名字
  now?: string;             // 当前选中的子
  hidden?: boolean;
  icon?: string;            // emoji icon
}

interface IProxiesMap {
  proxies: Record<string, IProxyGroup | IProxyNode>;
}

type ProxyType =
  | 'Direct' | 'Reject' | 'Selector' | 'URLTest' | 'Fallback'
  | 'LoadBalance' | 'Relay' | 'Shadowsocks' | 'ShadowsocksR'
  | 'Vmess' | 'Vless' | 'Trojan' | 'Hysteria' | 'Hysteria2'
  | 'Tuic' | 'WireGuard';

interface DelayHistory {
  time: number;             // unix ms
  delay: number;            // ms, -1 = timeout
}
```

## Connection

```typescript
interface IConnection {
  id: string;               // clash internal id
  metadata: {
    network: 'tcp' | 'udp';
    type: 'HTTP' | 'HTTPS' | string;
    host: string;
    sourceIP: string;
    sourcePort: string;
    destinationIP?: string;
    destinationPort?: string;
    sniffingHost?: string;   // SNI / Host
  };
  rulePayload?: string;
  chains: string[];         // 链路节点
  upload: number;           // bytes
  download: number;
  start: string;            // RFC3339
}
```

## Traffic

```typescript
interface ITraffic {
  up: number;               // bytes/s
  down: number;
}
```

## Rule

```typescript
interface IRule {
  type: string;             // Domain, DomainSuffix, DomainKeyword, GEOIP, ... 完整列表见 mihomo 文档
  payload: string;          // 匹配值
  proxy: string;            // 目标 proxy
  size?: number;            // 命中计数
}
```

## Log

```typescript
interface ILog {
  level: 'debug' | 'info' | 'warning' | 'error' | 'silent';
  type: string;             // 模块分类
  payload: string;          // 消息内容
  time: string;             // RFC3339
}
```

## Memory

```typescript
interface IMemory {
  inuse: number;            // 占用 MB
  oslimit?: number;         // 系统限制 MB
}
```

## Profile (订阅)

```typescript
interface IProfile {
  id: string;
  name: string;
  url?: string;             // 远端订阅 URL
  file?: string;            // 本地文件路径（相对于 home）
  remote?: boolean;         // 是否远端
  updated?: number;         // 上次更新时间
  userinfo?: {
    upload: number; download: number; total: number; expire: number;
  };
}
```

## App Settings

```typescript
interface IVerge {
  appTheme: 'light' | 'dark' | 'system';
  language: 'zh-CN' | 'en-US' | 'auto';
  startTunOnBoot: boolean;
  systemProxyEnabled: boolean;
  dnsBypass: boolean;
  trafficGraphIntervalMs: number;
  logLevel: 'debug' | 'info' | 'warning' | 'error' | 'silent';
}
```

## Clash Core Status

```typescript
interface ICoreState {
  running: boolean;
  version?: string;
  startedAt?: string;       // RFC3339
  homeDir: string;
  externalController?: string;
}
```
