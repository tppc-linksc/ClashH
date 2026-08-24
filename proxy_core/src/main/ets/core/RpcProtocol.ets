// RPC 协议：UI 模块 <-> VpnAbility（LocalSocket）<-> Go 内核（Unix Socket）
//
// 两条链路：
//   UI (entry)  --LocalSocket-->  VpnAbility (proxy_core)  --LocalSocket-->  Go flclash
//   客户端（ClashClient）                服务端（SocketProxyService）        内核

/** RPC 方法枚举（与 Go 侧 ClashRpcType 一致） */
export enum RpcMethod {
  /** 查询实时流量 */
  QueryTrafficNow = 0,
  /** 查询隧道状态 */
  QueryTunnelState = 1,
  /** 查询总流量 */
  QueryTrafficTotal = 2,
  /** 查询代理组 */
  QueryProxyGroup = 3,
  /** 查询节点供应商 */
  QueryProviders = 4,
  /** 切换代理节点 */
  ChangeProxy = 5,
  /** 健康检查（单节点） */
  HealthCheck = 6,
  /** 更新供应商 */
  UpdateProvider = 7,
  /** 上传供应商 */
  UploadProvider = 8,
  /** 查询连接 */
  QueryConnections = 9,
  /** 关闭连接 */
  CloseConnection = 10,
  /** 清空连接 */
  ClearConnections = 11,
  /** 加载配置 */
  Load = 12,
  /** 启动内核 */
  StartClash = 13,
  /** 停止内核 */
  StopClash = 14,
  /** 校验配置 */
  ValidConfig = 15,
  /** 重置 */
  Reset = 16,
  /** 查询国家代码 */
  GetCountryCode = 17,
  /** 更新 Geo 数据 */
  UpdateGeoData = 18,
  /** 注册消息回调 */
  RegisterOnMessage = 19,
  /** 查询请求列表 */
  GetRequestList = 20,
  /** 清空请求列表 */
  ClearRequestList = 21,
  /** 设置日志监听 */
  SetLogObserver = 22,
  /** 停止日志监听 */
  StopLogObserver = 23,
  /** 查询 VPN 选项 */
  VpnOptions = 24,
  /** 设置状态 */
  SetOptionState = 25,
  /** 查询 VPN 运行时间 */
  GetVpnRunTime = 26,
  /** VPN 配置初始化完成 */
  VpnConfigInited = 27,
  /** 设置网络接口 */
  SetNetInterfaces = 28,
  /** 下载配置 */
  DownloadConfig = 29,
  /** 设置系统 DNS */
  SetSystemDns = 30,
  /** 全部健康检查 */
  HealthCheckAll = 31,
  /** 批量健康检查 */
  HealthCheckBatch = 32,
  /** 查询版本 */
  GetVersion = 33,
  /** 查询内存 */
  GetMemory = 34
}

/** RPC 请求 */
export interface RpcRequest {
  /** 请求序列号（用于匹配响应） */
  key: number;
  /** 方法 */
  method: RpcMethod;
  /** 参数 */
  params: (string | number | boolean)[];
}

/** RPC 响应 */
export interface RpcResult {
  /** 请求序列号 */
  key: number;
  /** 方法 */
  method: RpcMethod;
  /** 结果（JSON 字符串） */
  result?: string;
  /** 错误信息 */
  error?: string;
}

/** 消息分隔符（服务端与 Go 内核的协议约定） */
export const RPC_EOF = 'EOF';
