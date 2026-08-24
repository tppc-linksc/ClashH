// libflclash.so 的 ArkTS 类型声明
// 对应 flclash/main_cgo.go 通过 ohos-napi 直接注册的 NAPI 函数

/** 初始化内核 */
export const initClash: (homeDir: string) => boolean;

/** 启动 TUN 隧道 */
export const startTun: (fd: number, callback: (id: number, fd: number) => void) => void;

/** 启动/停止 mihomo 监听器 */
export const startListener: () => void;
export const stopListener: () => void;

/** 通知 Go 侧指定出站 fd 已由系统 VPN 保护 */
export const setFdMap: (id: number) => void;

/** 停止 TUN 隧道 */
export const stopTun: () => void;

/** 强制回收 Go 侧内存 */
export const forceGc: () => void;

/** 获取 VPN 选项 JSON */
export const getVpnOptions: () => string;

/** 获取 Go 内存占用 JSON */
export const getMemory: () => Promise<string>;

/** 获取内核记录的最近连接请求 */
export const getRequestList: () => string;

/** 清空请求记录 */
export const clearRequestList: () => void;

/** 校验配置，返回结果 JSON */
export const validateConfig: (params: string) => Promise<string>;

/** 更新配置，返回结果 JSON */
export const updateConfig: (params: string) => Promise<string>;

/** 获取代理列表 JSON */
export const getProxies: () => string;

/** 获取实时流量 JSON */
export const getTraffic: () => string;

/** 获取总流量 JSON */
export const getTotalTraffic: () => string;

/** 重置流量统计 */
export const resetTraffic: () => void;

/** 切换代理节点，返回结果 JSON */
export const changeProxy: (params: string) => Promise<string>;

/** 延迟测试，返回结果 JSON */
export const asyncTestDelay: (params: string) => Promise<string>;

/** 获取连接列表 JSON */
export const getConnections: () => string;

/** 关闭全部连接 */
export const closeConnections: () => boolean;

/** 关闭指定连接 */
export const closeConnection: (connectionId: string) => boolean;

/** 获取外部供应商列表 JSON */
export const getExternalProviders: () => string;

/** 更新系统 DNS */
export const updateDns: (dnsList: string) => Promise<void>;

/** 注册日志回调，收到 (message, value) */
export const startLog: (callback: (message: string, value: string) => void) => void;

/** 停止日志回调 */
export const stopLog: () => void;

/** 启动 Unix socket IPC 服务 */
export const startIpc: (path: string) => void;
