// HomeViewModel：首页数据模型
// 通过 ClashClient（RPC）与内核通信，轮询流量、节点状态

import { ClashClient, ClashClientState, RpcMethod } from 'proxy_core';
import { common } from '@kit.AbilityKit';
import { ProfileRepository, ProfileStoreData } from '../service/ProfileRepository';

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

  /** 状态监听回调 */
  onStateChange: ((state: HomeState) => void) | null = null;

  constructor() {
    this.client = ClashClient.getInstance();
  }

  /** 启动轮询 */
  start(context: common.Context): void {
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
    const currentProfile = await this.currentProfileName();
    if (this.client.getState() !== ClashClientState.Connected) {
      this.emit({
        connected: false, connecting: false,
        up: 0, down: 0, upTotal: 0, downTotal: 0,
        currentNode: '', currentProfile, version: ''
      });
      return;
    }
    try {
      const trafficRaw = await this.client.request(RpcMethod.QueryTrafficNow);
      const totalRaw = await this.client.request(RpcMethod.QueryTrafficTotal);
      const tunnelRaw = await this.client.request(RpcMethod.QueryTunnelState);
      const versionRaw = await this.client.request(RpcMethod.GetVersion);
      const proxiesRaw = await this.client.request(RpcMethod.QueryProxyGroup);
      const traffic = JSON.parse(trafficRaw) as TrafficResponse;
      const total = JSON.parse(totalRaw) as TrafficResponse;
      const tunnel = JSON.parse(tunnelRaw) as TunnelResponse;
      const version = JSON.parse(versionRaw) as VersionResponse;
      const proxies = JSON.parse(proxiesRaw) as ProxiesResponse;
      const currentNode = this.findCurrentNode(proxies);
      this.emit({
        connected: tunnel.running,
        connecting: false,
        up: traffic.up,
        down: traffic.down,
        upTotal: total.up,
        downTotal: total.down,
        currentNode,
        currentProfile,
        version: version.version
      });
    } catch (e) {
      console.error('[HomeViewModel] 刷新流量失败:', (e as Error).message);
    }
  }

  private emit(state: HomeState): void {
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
    const store: ProfileStoreData = await this.repository.list();
    const profile = store.profiles.find(item => item.uid === store.current);
    return profile?.name ?? '';
  }
}
