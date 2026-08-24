// proxy_core 模块对外导出
export { ClashClient, ClashClientState } from './src/main/ets/core/ClashClient';
export { RpcMethod, RpcRequest, RpcResult, RPC_EOF } from './src/main/ets/core/RpcProtocol';
export { SocketProxyService } from './src/main/ets/core/SocketProxyService';
export { ClashVpnService, DEFAULT_TUN_IP, DEFAULT_DNS, DEFAULT_MTU } from './src/main/ets/core/ClashVpnService';

// 数据模型
export { Proxy, ProxyType, ProxyGroup, DelayHistory, isProxyGroup } from './src/main/ets/models/Proxy';
export { ConnectionInfo, ConnectionMetaData } from './src/main/ets/models/Connection';
export { Profile, ProfileType, SubscriptionInfo } from './src/main/ets/models/Profile';
export { ClashConfig, TunConfig, DnsConfig, ProxyMode, TunStack } from './src/main/ets/models/ClashConfig';
export { TrafficInfo, LogInfo, LogLevel, IpInfo } from './src/main/ets/models/Common';
export { AppState } from './src/main/ets/state/AppState';
