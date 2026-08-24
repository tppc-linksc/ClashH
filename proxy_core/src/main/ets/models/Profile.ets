// 订阅配置（Profile）数据模型

/** 配置类型 */
export enum ProfileType {
  /** 本地配置 */
  Local = 'local',
  /** 远端订阅 */
  Remote = 'remote',
  /** 合并配置 */
  Merge = 'merge',
  /** 脚本配置 */
  Script = 'script'
}

/** 订阅用户信息（流量套餐） */
export interface SubscriptionInfo {
  /** 已用上传字节 */
  upload: number;
  /** 已用下载字节 */
  download: number;
  /** 总流量字节 */
  total: number;
  /** 到期时间戳（秒） */
  expire: number;
}

/** 配置条目 */
export interface Profile {
  /** 唯一 id */
  uid: string;
  /** 类型 */
  type: ProfileType;
  /** 名称 */
  name: string;
  /** 描述 */
  desc?: string;
  /** 文件名 */
  file?: string;
  /** 订阅 URL */
  url?: string;
  /** 更新时间戳 */
  updated?: number;
  /** 用户信息 */
  extra?: SubscriptionInfo;
  /** 每个可选代理组当前选中的节点，用于重载配置后恢复。 */
  proxySelected?: Record<string, string>;
}
