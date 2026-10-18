// HomeViewModel：首页数据模型
// 通过 ClashClient（RPC）与内核通信，轮询流量、节点状态

import { ClashClient, ClashClientState, RpcMethod } from 'proxy_core';
import { common } from '@kit.AbilityKit';
import { ProfileRepository, ProfileStoreData } from '../service/ProfileRepository';
import { isOwnVpnActive } from '../service/VpnNetworkStatus';

/** 首页状态 */
export interface HomeState {
  /** 是否已连接 */
  connected: boolean;
  /** 连接中 */
  connecting: boolean;
  /** 上行速率（B/s） */
  up: number;
  /** 下行速率（B/s） */
  down: number;
  /** 总上行（B） */
  upTotal: number;
  /** 总下行（B） */
  downTotal: number;
  /** 当前节点名 */
  currentNode: string;
  /** 当前配置名 */
  currentProfile: string;
  /** 内核版本 */
  version: string;
  /** 当前代理模式 rule / global / direct */
  mode: string;
}

/** 流量响应（RPC 返回 JSON 解析后） */
interface TrafficResponse {
  up: number;
  down: number;
}

/** 隧道状态响应 */
interface TunnelResponse {
  running: boolean;
}

interface VersionResponse {
  version: string;
}

interface ProxiesResponse {
  proxies?: Record<string, ProxyStatus>;
  mode?: string;
}

interface ProxyStatus {
  name: string;
  now?: string;
  all?: string[];
  type: string;
}

export class HomeViewModel {
  private client: ClashClient;
  private timer: number = -1;
  private repository: ProfileRepository | null = null;
  private context: common.Context | null = null;
  private refreshPromise: Promise<void> | null = null;
  private lastState: HomeState = {
    connected: false, connecting: false,
    up: 0, down: 0, upTotal: 0, downTotal: 0,
    currentNode: '', currentProfile: '', version: '', mode: ''
  };

  /** 状态监听回调 */
  onStateChange: ((state: HomeState) => void) | null = null;

  constructor() {
    this.client = ClashClient.getInstance();
  }

  /** 启动轮询 */
  start(context: common.Context): void {
    this.context = context;
    this.repository = new ProfileRepository(context);
    this.refreshTraffic();
    if (this.timer >= 0) return;
    this.timer = setInterval(() => {
      this.refreshTraffic();
    }, 1000);
  }

  /** 由连接按钮触发的立即刷新。 */
  async refreshNow(): Promise<void> {
    await this.refreshTraffic();
  }

  /** 停止轮询 */
  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  /** 刷新实时流量 */
  private async refreshTraffic(): Promise<void> {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }
    this.refreshPromise = this.performRefresh();
    try {
      await this.refreshPromise;
    } finally {
      this.refreshPromise = null;
    }
  }

  private async performRefresh(): Promise<void> {
    const currentProfile = await this.currentProfileName();
    // 以系统 VPN 网卡为准。LocalSocket 连着但系统 TUN 已消失时不能显示“已连接”。
    const systemVpnActive = await isOwnVpnActive();
    if (systemVpnActive === false) {
      this.emitDisconnected(currentProfile);
      return;
    }
    try {
      // App 冷启动时客户端单例是断开的，但 VPN 扩展可能仍在运行。
      if (this.client.getState() !== ClashClientState.Connected && this.context) {
        await this.client.connect(this.context);
      }
      const tunnelRaw = await this.client.request(RpcMethod.QueryTunnelState);
      const tunnel = JSON.parse(tunnelRaw) as TunnelResponse;
      if (!tunnel.running) {
        this.emitDisconnected(currentProfile);
        return;
      }
      // 系统网卡和内核都确认在运行，流量/节点 RPC 失败不能把 VPN 误报为断开。
      this.emit({
        connected: true, connecting: false,
        up: this.lastState.up, down: this.lastState.down,
        upTotal: this.lastState.upTotal, downTotal: this.lastState.downTotal,
        currentNode: this.lastState.currentNode, currentProfile,
        version: this.lastState.version, mode: this.lastState.mode
      });
    } catch (e) {
      console.error('[HomeViewModel] 核对 VPN 状态失败:', (e as Error).message);
      this.emitDisconnected(currentProfile);
      return;
    }
    try {
      const trafficRaw = await this.client.request(RpcMethod.QueryTrafficNow);
      const totalRaw = await this.client.request(RpcMethod.QueryTrafficTotal);
      const versionRaw = await this.client.request(RpcMethod.GetVersion);
      const proxiesRaw = await this.client.request(RpcMethod.QueryProxyGroup);
      const traffic = JSON.parse(trafficRaw) as TrafficResponse;
      const total = JSON.parse(totalRaw) as TrafficResponse;
      const version = JSON.parse(versionRaw) as VersionResponse;
      const proxies = JSON.parse(proxiesRaw) as ProxiesResponse;
      const currentNode = this.findCurrentNode(proxies);
      this.emit({
        connected: true,
        connecting: false,
        up: traffic.up,
        down: traffic.down,
        upTotal: total.up,
        downTotal: total.down,
        currentNode,
        currentProfile,
        version: version.version,
        mode: proxies.mode ?? this.lastState.mode
      });
    } catch (e) {
      console.warn('[HomeViewModel] 流量或节点信息暂不可用: ' + (e as Error).message);
    }
  }

  private emitDisconnected(currentProfile: string): void {
    this.emit({
      connected: false, connecting: false,
      up: 0, down: 0, upTotal: 0, downTotal: 0,
      currentNode: '', currentProfile, version: '', mode: this.lastState.mode
    });
  }

  private emit(state: HomeState): void {
    this.lastState = state;
    this.onStateChange?.(state);
  }

  private findCurrentNode(response: ProxiesResponse): string {
    const proxyMap = response.proxies ?? response as Record<string, ProxyStatus>;
    const groups = Object.values(proxyMap).filter((proxy: ProxyStatus) =>
      proxy.name !== 'GLOBAL' && proxy.now !== undefined);
    const referenced: Set<string> = new Set();
    groups.forEach((proxy: ProxyStatus) => {
      proxy.all?.forEach((name: string) => referenced.add(name));
    });
    const root = groups.find((proxy: ProxyStatus) => !referenced.has(proxy.name)) ?? groups[0];
    if (root?.now) {
      return this.resolveNode(proxyMap, root.now, new Set());
    }
    return proxyMap['GLOBAL']?.now ?? '';
  }

  private resolveNode(proxyMap: Record<string, ProxyStatus>, name: string, visited: Set<string>): string {
    if (visited.has(name)) {
      return name;
    }
    visited.add(name);
    const proxy = proxyMap[name];
    return proxy?.now ? this.resolveNode(proxyMap, proxy.now, visited) : name;
  }

  private async currentProfileName(): Promise<string> {
    if (!this.repository) {
      return '';
    }
    try {
      const store: ProfileStoreData = await this.repository.list();
      const profile = store.profiles.find(item => item.uid === store.current);
      return profile?.name ?? '';
    } catch (error) {
      console.warn('[HomeViewModel] 读取当前配置名失败: ' + (error as Error).message);
      return '';
    }
  }
}
