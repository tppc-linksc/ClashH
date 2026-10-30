// ProxyViewModel：代理页数据模型
// 负责获取代理组、切换节点、延迟测试

import { ClashClient, RpcMethod, ProxyGroup, Proxy, isProxyGroup } from 'proxy_core';
import { common } from '@kit.AbilityKit';
import { ProfileRepository, ProfileStoreData } from '../service/ProfileRepository';
import { ensureCoreProfile } from '../service/CoreSession';
import { saveRuntimeMode } from '../service/RuntimeSettings';

/** /proxies 响应结构 */
interface ProxiesResponse {
  proxies?: Record<string, Proxy>;
  mode?: string;
}

/** 延迟测试响应（内核返回 {"name":..,"value":..}，value 为毫秒） */
interface DelayResponse {
  name?: string;
  value?: number;
  delay?: number;
}

// 内核单节点测速内部上限是 30s（HTTP 客户端超时），客户端必须比它宽，
// 否则会先超时并误报“超时”，而内核其实稍后才出结果。
const SINGLE_TEST_TIMEOUT_MS = 35000;
// 内核批量测速按 8 个一批串行执行，一轮最坏 30s+。
const BATCH_TEST_BASE_MS = 40000;
const BATCH_TEST_ROUND_MS = 32000;
const BATCH_TEST_SIZE = 8;
// 测速期间轮询内核 history 的间隔，让结果边测边显示。
const POLL_INTERVAL_MS = 1200;

export class ProxyViewModel {
  private client: ClashClient;
  private repository: ProfileRepository | null = null;
  private profileUid: string = '';
  private context: common.Context | null = null;

  /** 代理组列表 */
  groups: ProxyGroup[] = [];
  /** 全部代理（含节点） */
  proxies: Record<string, Proxy> = {};
  /**
   * 本次会话最近一次测速结果（毫秒，-1 表示超时）。
   * 内核 /proxies 的 history 由测速协程异步写入，测速刚结束时可能还查不到；
   * 这里直接用 RPC 返回值兜底，保证 loading 一结束就能看到数字。
   */
  delays: Record<string, number> = {};
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

  /** 测速期间的 history 轮询定时器（-1 表示未启动）。 */
  private polling: number = -1;
  private pollBusy: boolean = false;

  constructor() {
    this.client = ClashClient.getInstance();
  }

  /** 刷新代理列表；silent=true 时已有旧数据，不进 loading，后台静默更新。 */
  async refresh(context: common.UIAbilityContext, silent: boolean = false): Promise<void> {
    this.context = context;
    this.loading = !silent;
    this.error = silent ? this.error : '';
    this.notify();
    try {
      this.repository = new ProfileRepository(context);
      const store: ProfileStoreData = await this.repository.list();
      this.hasProfile = store.current.length > 0;
      // 换配置后旧节点的测速结果不再有参考价值，一并清掉。
      if (store.current !== this.profileUid) {
        this.delays = {};
      }
      this.profileUid = store.current;
      if (!this.hasProfile) {
        this.groups = [];
        this.proxies = {};
        return;
      }
      this.client = await ensureCoreProfile(context, store.current);
      await this.queryGroups();
    } catch (e) {
      this.error = (e as Error).message;
      console.error('[ProxyViewModel] 刷新失败:', this.error);
      // 静默刷新失败时保留旧列表，避免把用户正在看的页面清成空态。
      if (!silent) {
        this.groups = [];
        this.proxies = {};
      }
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
      // 持久化，避免重启后回到配置文件里的模式。
      if (this.context) {
        await saveRuntimeMode(this.context, mode);
      } else {
        console.warn('[ProxyViewModel] context 未就绪，模式切换未持久化，重启后将回到旧模式');
      }
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
    let delay = -1;
    try {
      const raw = await this.client.request(RpcMethod.HealthCheck, [name], SINGLE_TEST_TIMEOUT_MS);
      delay = this.readDelay(raw);
    } catch (e) {
      // 这里必须是 -1：测速失败要显示“超时”，不能停在旧值或占位符。
      console.warn('[ProxyViewModel] 测速失败: ' + (e as Error).message);
      delay = -1;
    }
    this.delays[name] = delay;
    this.testing.delete(name);
    // 先落地结果与 loading 状态，再去对齐内核 history。
    // 之前是「等 history 查完才通知」，而 history 由内核测速协程写入，
    // 查得太早会拿到空数据，界面就永远停在 “--”。
    this.notify();
    try {
      await this.queryGroups();
    } catch (error) {
      console.warn('[ProxyViewModel] 测速后刷新失败: ' + (error as Error).message);
    }
    this.notify();
    return delay;
  }

  /** 批量测速（组内全部节点） */
  testingGroup: string = '';

  async testGroup(group: ProxyGroup): Promise<void> {
    // 进入测速状态，界面把按钮换成转圈；重复点击被忽略。
    if (this.testingGroup.length > 0) return;
    this.testingGroup = group.name;
    this.notify();
    const names = group.all;
    const rounds = Math.ceil(names.length / BATCH_TEST_SIZE);
    const timeout = Math.max(BATCH_TEST_BASE_MS, rounds * BATCH_TEST_ROUND_MS + 8000);
    // 整组可能要几十秒，期间轮询 history，节点测完一个就显示一个。
    this.startPolling();
    try {
      const raw = await this.client.request(RpcMethod.HealthCheckBatch, [JSON.stringify(names)], timeout);
      this.applyBatchDelays(names, raw);
    } catch (e) {
      console.warn('[ProxyViewModel] 批量测速失败: ' + (e as Error).message);
    }
    this.stopPolling();
    this.testingGroup = '';
    this.notify();
    try {
      await this.queryGroups();
    } catch (error) {
      console.warn('[ProxyViewModel] 批量测速后刷新失败: ' + (error as Error).message);
    }
    this.notify();
  }

  /** 解析单个测速响应，非正数统一按超时（-1）处理。 */
  private readDelay(raw: string): number {
    try {
      return this.delayOf(JSON.parse(raw) as DelayResponse);
    } catch (error) {
      console.warn('[ProxyViewModel] 解析测速结果失败: ' + (error as Error).message);
      return -1;
    }
  }

  private delayOf(data: DelayResponse): number {
    // 旧内核字段为 delay，ClashBox 为 value，两者都兼容。
    const value = typeof data.value === 'number' ? data.value
      : (typeof data.delay === 'number' ? data.delay : 0);
    return value > 0 ? value : -1;
  }

  /** 测速期间轮询内核 history，让结果边测边显示。 */
  private startPolling(): void {
    this.stopPolling();
    this.polling = setInterval(() => {
      this.pollOnce();
    }, POLL_INTERVAL_MS);
  }

  /** 页面离开或测速结束时停止轮询，避免后台空转。 */
  stopPolling(): void {
    if (this.polling !== -1) {
      clearInterval(this.polling);
      this.polling = -1;
      this.pollBusy = false;
    }
  }

  private async pollOnce(): Promise<void> {
    if (this.pollBusy) {
      return;
    }
    this.pollBusy = true;
    try {
      await this.queryGroups();
      this.notify();
    } catch (error) {
      // 轮询失败不打扰用户，下一轮会重试。
      console.warn('[ProxyViewModel] 测速轮询失败: ' + (error as Error).message);
    } finally {
      this.pollBusy = false;
    }
  }

  /** 批量测速按 group.all 的顺序回填结果。 */
  private applyBatchDelays(names: string[], raw: string): void {
    try {
      const list = JSON.parse(raw) as DelayResponse[];
      if (!Array.isArray(list)) {
        return;
      }
      const size = Math.min(names.length, list.length);
      for (let i = 0; i < size; i++) {
        this.delays[names[i]] = this.delayOf(list[i]);
      }
    } catch (error) {
      console.warn('[ProxyViewModel] 解析批量测速结果失败: ' + (error as Error).message);
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
