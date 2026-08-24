// Clash 运行时配置模型
// 与 mihomo HTTP API（/configs）返回结构一致

/** 代理模式 */
export enum ProxyMode {
  /** 规则模式 */
  Rule = 'rule',
  /** 全局模式 */
  Global = 'global',
  /** 直连模式 */
  Direct = 'direct'
}

/** TUN 协议栈 */
export enum TunStack {
  /** 系统栈（默认） */
  System = 'system',
  /** gvisor 用户态栈 */
  Gvisor = 'gvisor',
  /** mixed */
  Mixed = 'mixed'
}

/** DNS 增强模式 */
export enum DnsEnhancedMode {
  FakeIp = 'fake-ip',
  RedirHost = 'redir-host'
}

/** TUN 配置 */
export interface TunConfig {
  /** 是否启用 */
  enable: boolean;
  /** 网卡名 */
  device: string;
  /** 协议栈 */
  stack: TunStack;
  /** 自动路由 */
  autoRoute: boolean;
  /** DNS 劫持地址 */
  dnsHijack: string[];
  /** MTU */
  mtu: number;
  /** 严格路由 */
  strictRoute: boolean;
}

/** DNS 配置 */
export interface DnsConfig {
  /** 是否启用 */
  enable: boolean;
  /** 监听地址 */
  listen: string;
  /** 增强模式 */
  enhancedMode: DnsEnhancedMode;
  /** fake-ip 网段 */
  fakeIpRange: string;
  /** 名字服务器 */
  nameserver: string[];
  /** 回退服务器 */
  fallback: string[];
  /** 默认服务器 */
  defaultNameserver: string[];
}

/** Clash 运行时配置 */
export interface ClashConfig {
  /** HTTP 端口 */
  port: number;
  /** SOCKS 端口 */
  socksPort: number;
  /** 混合端口 */
  mixedPort: number;
  /** 允许局域网 */
  allowLan: boolean;
  /** 代理模式 */
  mode: ProxyMode;
  /** IPv6 */
  ipv6: boolean;
  /** 日志级别 */
  logLevel: string;
  /** TUN 配置 */
  tun: TunConfig;
  /** DNS 配置 */
  dns: DnsConfig;
}

/** 隧道状态 */
export interface TunnelState {
  /** 隧道是否运行 */
  running: boolean;
  /** 隧道地址 */
  address?: string;
  /** 启动时间 */
  startedAt?: string;
}
