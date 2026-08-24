// 通用数据模型（流量/日志/IP 等）

/** 实时流量 */
export interface TrafficInfo {
  /** 上行字节/秒 */
  up: number;
  /** 下行字节/秒 */
  down: number;
}

/** 总流量 */
export interface TotalTrafficInfo {
  /** 总上行字节 */
  upTotal: number;
  /** 总下行字节 */
  downTotal: number;
}

/** 内存占用（MB） */
export interface MemoryInfo {
  /** 已用 */
  inuse: number;
  /** 系统限制 */
  oslimit?: number;
}

/** 日志级别 */
export enum LogLevel {
  Debug = 'debug',
  Info = 'info',
  Warning = 'warning',
  Error = 'error',
  Silent = 'silent'
}

/** 单条日志 */
export interface LogInfo {
  /** 级别 */
  level: LogLevel;
  /** 时间（RFC3339） */
  time: string;
  /** 模块 */
  type: string;
  /** 内容 */
  payload: string;
}

/** IP 信息 */
export interface IpInfo {
  /** IP 地址 */
  ip: string;
  /** 国家代码 */
  countryCode: string;
  /** 国家 */
  country: string;
  /** 城市 */
  city?: string;
}
