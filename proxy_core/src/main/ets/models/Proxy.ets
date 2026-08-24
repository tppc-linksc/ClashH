// 代理节点 / 代理组数据模型
// 与 mihomo HTTP API（/proxies）返回结构一致

/** 代理类型（mihomo 支持的全部类型） */
export enum ProxyType {
  Direct = 'Direct',
  Reject = 'Reject',
  RejectDrop = 'RejectDrop',
  Compatible = 'Compatible',
  Pass = 'Pass',
  Dns = 'Dns',
  Shadowsocks = 'Shadowsocks',
  ShadowsocksR = 'ShadowsocksR',
  Snell = 'Snell',
  Socks5 = 'Socks5',
  Http = 'Http',
  Vmess = 'Vmess',
  Vless = 'Vless',
  Trojan = 'Trojan',
  Hysteria = 'Hysteria',
  Hysteria2 = 'Hysteria2',
  WireGuard = 'WireGuard',
  Tuic = 'Tuic',
  Ssh = 'Ssh',
  Mieru = 'Mieru',
  Masque = 'Masque',
  AnyTLS = 'AnyTLS',
  Relay = 'Relay',
  Sudoku = 'Sudoku',
  TrustTunnel = 'TrustTunnel',
  OpenVPN = 'OpenVPN',
  Tailscale = 'Tailscale',
  GostRelay = 'GostRelay',
  Selector = 'Selector',
  Fallback = 'Fallback',
  URLTest = 'URLTest',
  LoadBalance = 'LoadBalance',
  // 未知类型（mihomo 用 { Unknown: string } 表示）
  Unknown = 'Unknown'
}

/** 延迟历史样本 */
export interface DelayHistory {
  /** unix 毫秒 */
  time: number;
  /** 延迟毫秒数，-1 表示超时 */
  delay: number;
}

/** 代理节点或代理组（mihomo /proxies 条目） */
export interface Proxy {
  /** 名称 */
  name: string;
  /** 类型 */
  type: string;
  /** 是否存活 */
  alive: boolean;
  /** 是否支持 UDP */
  udp: boolean;
  /** UDP over TCP */
  uot: boolean;
  /** XUDP */
  xudp: boolean;
  /** TCP Fast Open */
  tfo: boolean;
  /** Multipath TCP */
  mptcp: boolean;
  /** Stream Multiplex */
  smux: boolean;
  /** 接口名 */
  interface: string;
  /** 拨号代理 */
  dialerProxy: string;
  /** 路由标记 */
  routingMark: number;
  /** 所属 provider 名 */
  providerName: string;
  /** 延迟历史 */
  history: DelayHistory[];
  /** 代理组：子成员列表 */
  all?: string[];
  /** 代理组：当前选中 */
  now?: string;
  /** 代理组：固定节点 */
  fixed?: string;
  /** 是否隐藏 */
  hidden?: boolean;
  /** 图标 */
  icon?: string;
  /** 测速 URL */
  testUrl?: string;
  /** 预期状态码 */
  expectedStatus?: string;
  /** 节点 id */
  id?: string;
  /** 协议附加字段 */
  extra: Record<string, string>;
}

/** 代理组（Selector/URLTest/Fallback/LoadBalance/Relay） */
export interface ProxyGroup extends Proxy {
  type: string;
  all: string[];
  now?: string;
  hidden?: boolean;
}

/** 判断是否为代理组 */
export function isProxyGroup(type: string): boolean {
  return type === ProxyType.Selector || type === ProxyType.URLTest ||
    type === ProxyType.Fallback || type === ProxyType.LoadBalance ||
    type === ProxyType.Relay;
}

/** /proxies 响应 */
export interface ProxiesResponse {
  proxies: Record<string, Proxy>;
}
