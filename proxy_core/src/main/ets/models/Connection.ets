// 连接数据模型
// 与 mihomo HTTP API（/connections）返回结构一致

/** 连接元数据 */
export interface ConnectionMetaData {
  /** 网络类型 tcp/udp */
  network: string;
  /** 连接类型（HTTP/HTTPS 等） */
  type: string;
  /** 源 IP */
  sourceIP: string;
  /** 目标 IP */
  destinationIP: string;
  /** 源端口 */
  sourcePort: string;
  /** 目标端口 */
  destinationPort: string;
  /** 入站名称 */
  inboundName: string;
  /** 入站用户 */
  inboundUser: string;
  /** 主机名（域名） */
  host: string;
  /** DNS 模式 */
  dnsMode: string;
  /** 进程名 */
  process: string;
  /** 进程路径 */
  processPath: string;
  /** 特殊代理 */
  specialProxy: string;
  /** 远端目标 */
  remoteDestination: string;
  /** 嗅探出的主机名 */
  sniffHost: string;
}

/** 单条连接 */
export interface ConnectionInfo {
  /** 连接 id */
  id: string;
  /** 元数据 */
  metadata: ConnectionMetaData;
  /** 上行字节数 */
  upload: number;
  /** 下行字节数 */
  download: number;
  /** 建立时间（RFC3339） */
  start: string;
  /** 链路（节点链） */
  chains: string[];
  /** 规则类型 */
  rule: string;
  /** 规则匹配值 */
  rulePayload: string;
  /** UI 计算：瞬时上行速率 */
  curUpload?: number;
  /** UI 计算：瞬时下行速率 */
  curDownload?: number;
}

/** /connections 响应 */
export interface ConnectionsResponse {
  /** 总下行字节 */
  downloadTotal: number;
  /** 总上行字节 */
  uploadTotal: number;
  /** 连接列表 */
  connections: ConnectionInfo[];
}
