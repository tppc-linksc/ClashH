// ProxyViewModel：代理页数据模型
// 负责获取代理组、切换节点、延迟测试

import { ClashClient, RpcMethod, ProxyGroup, Proxy, isProxyGroup } from 'proxy_core';
import { common } from '@kit.AbilityKit';
import { ProfileRepository, ProfileStoreData } from '../service/ProfileRepository';
import { ensureCoreProfile } from '../service/CoreSession';

/** /proxies 响应结构 */
interface ProxiesResponse {
  proxies?: Record<string, Proxy>;
  mode?: string;
}

/** 延迟测试响应 */
interface DelayResponse {
  delay: number;
}

export class ProxyViewModel {
  private client: ClashClient;
  private repository: ProfileRepository | null = null;
  private profileUid: string = '';

  /** 代理组列表 */
  groups: ProxyGroup[] = [];
  /** 全部代理（含节点） */
  proxies: Record<string, Proxy> = {};
  /** 当前模式 */
  mode: string = 'rule';
  /** 搜索关键字 */
  keyword: string = '';
  /** 测速中的节点 */
  testing: Set<string> = new Set();
  /** 展开的组 */
  expanded: Set<string> = new Set();
  /** 页面加载状态与可展示错误。 */
  loading: boolean = false;
  error: string = '';
  hasProfile: boolean = false;

  /** 数据变化回调 */
  onChange: (() => void) | null = null;

  constructor() {
    this.client = ClashClient.getInstance();
  }

  /** 刷新代理列表 */
  async refresh(context: common.UIAbilityContext): Promise<void> {
    this.loading = true;
    this.error = '';
    this.notify();
    try {
      this.repository = new ProfileRepository(context);
      const store: ProfileStoreData = await this.repository.list();
      this.hasProfile = store.current.length > 0;
      this.profileUid = store.current;
      if (!this.hasProfile) {
        this.groups = [];
        this.proxies = {};
        return;
      }
      this.client = await ensureCoreProfile(context, store.current);
      await this.queryGroups();
    } catch (e) {
      this.groups = [];
      this.proxies = {};
      this.error = (e as Error).message;
      console.error('[ProxyViewModel] 刷新失败:', this.error);
    } finally {
      this.loading = false;
      this.notify();
    }
  }

  /** 切换 mihomo 运行模式。 */
  async setMode(mode: string): Promise<void> {
    try {
      await this.client.request(RpcMethod.SetOptionState, [JSON.stringify({ mode })]);
      this.mode = mode;
      this.notify();
    } catch (error) {
      console.error('[ProxyViewModel] 模式切换失败:', (error as Error).message);
    }
  }

  /** 切换节点 */
  async selectProxy(groupName: string, proxyName: string): Promise<void> {
    try {
      await this.client.request(RpcMethod.ChangeProxy,
        [groupName, proxyName]);
      if (this.repository && this.profileUid.length > 0) {
        await this.repository.setProxySelection(this.profileUid, groupName, proxyName);
      }
      await this.queryGroups();
      this.notify();
    } catch (e) {
      console.error('[ProxyViewModel] 切换失败:', (e as Error).message);
      throw new Error((e as Error).message);
    }
  }

  /** 单节点延迟测试 */
  async testDelay(name: string): Promise<number> {
    this.testing.add(name);
    this.notify();
    try {
      const raw = await this.client.request(RpcMethod.HealthCheck, [name]);
      const data = JSON.parse(raw) as DelayResponse;
      return data.delay;
    } catch (e) {
      console.error('[ProxyViewModel] 测速失败:', (e as Error).message);
      return -1;
    } finally {
      this.testing.delete(name);
      try {
        await this.queryGroups();
      } catch (error) {
        console.warn('[ProxyViewModel] 测速后刷新失败:', (error as Error).message);
      }
      this.notify();
    }
  }

  /** 批量测速（组内全部节点） */
  async testGroup(group: ProxyGroup): Promise<void> {
    try {
      await this.client.request(RpcMethod.HealthCheckBatch, [JSON.stringify(group.all)]);
      await this.queryGroups();
      this.notify();
    } catch (e) {
      console.error('[ProxyViewModel] 批量测速失败:', (e as Error).message);
    }
  }

  /** 过滤后的代理组 */
  filteredGroups(): ProxyGroup[] {
    if (!this.keyword.trim()) return this.groups;
    const kw = this.keyword.trim().toLowerCase();
    return this.groups.filter(g => {
      // 组名或成员名包含关键字
      if (g.name.toLowerCase().includes(kw)) return true;
      return g.all.some(n => n.toLowerCase().includes(kw));
    });
  }

  /** 展开/收起组 */
  toggleGroup(name: string): void {
    if (this.expanded.has(name)) {
      this.expanded.delete(name);
    } else {
      this.expanded.add(name);
    }
    this.notify();
  }

  private notify(): void {
    this.onChange?.();
  }

  private async queryGroups(): Promise<void> {
    const raw = await this.client.request(RpcMethod.QueryProxyGroup);
    const data = JSON.parse(raw) as ProxiesResponse;
    // ClashBox 的 NAPI 直接返回代理映射；mihomo HTTP API 则包在 proxies 字段中。
    // 同时兼容两种结构，避免配置已经加载却被界面误判为空。
    const proxyMap = data.proxies ?? data as Record<string, Proxy>;
    this.proxies = proxyMap;
    this.mode = data.mode ?? this.mode;
    this.groups = Object.values(proxyMap)
      .filter((proxy: Proxy) => isProxyGroup(proxy.type))
      .map((proxy: Proxy) => proxy as ProxyGroup);
  }
}
