// ClashVpnAbility：系统 VPN 扩展与 mihomo 内核的宿主进程。

import { VpnExtensionAbility, socket } from '@kit.NetworkKit';
import { Want, common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { parseYaml } from '../utils/YamlParser';
import {
  AppState,
  SocketProxyService,
  ClashVpnService,
  RpcMethod,
  RpcRequest,
  RpcResult,
  RPC_EOF
} from 'proxy_core';
import {
  initClash,
  startTun,
  stopTun,
  startListener,
  stopListener,
  setFdMap,
  validateConfig,
  updateConfig,
  getTraffic,
  getTotalTraffic,
  resetTraffic,
  getProxies,
  changeProxy,
  asyncTestDelay,
  getConnections,
  closeConnections,
  closeConnection,
  getExternalProviders,
  getVpnOptions,
  getMemory,
  getRequestList,
  clearRequestList,
  updateDns,
  startLog,
  stopLog
} from 'libflclash.so';

const TAG = 'ClashVpnAbility';
const DEFAULT_TEST_URL = 'http://www.gstatic.com/generate_204';

interface ChangeProxyRequest {
  'group-name': string;
  'proxy-name': string;
}

interface DelayRequest {
  'proxy-name': string;
  timeout: number;
  'test-url': string;
}

interface TunnelStateResponse {
  running: boolean;
}

interface RuntimeResponse {
  milliseconds: number;
}

interface OptionState {
  mode?: string;
  mixedPort?: number;
  dns?: string;
}

interface ConfigExtendedParams {
  'is-patch': boolean;
  'is-compatible': boolean;
  'selected-map': Record<string, string>;
  'override-dns': boolean;
  'test-url': string;
}

interface UpdateConfigRequest {
  'profile-id': string;
  config: Record<string, Object | undefined>;
  params: ConfigExtendedParams;
}

interface GeoXUrls {
  mmdb: string;
  asn: string;
  geoip: string;
  geosite: string;
}

interface GeoResource {
  fileName: string;
}

interface ProfileSelectionEntry {
  uid: string;
  proxySelected?: Record<string, string>;
}

interface ProfileSelectionStore {
  profiles: ProfileSelectionEntry[];
}

export default class ClashVpnAbility extends VpnExtensionAbility {
  private proxyService: SocketProxyService | null = null;

  async onCreate(want: Want): Promise<void> {
    console.info(TAG, 'onCreate 启动 VPN 服务');
    try {
      AppState.init(this.context.filesDir);
      const vpnService = new ClashVpnServiceImpl(this.context);
      this.proxyService = new SocketProxyService(this.context, vpnService);
      await this.proxyService.startService();
      console.info(TAG, 'VPN 服务启动成功');
    } catch (error) {
      console.error(TAG, 'VPN 服务启动失败: ' + (error as Error).message);
    }
  }

  async onDestroy(): Promise<void> {
    console.info(TAG, 'onDestroy 停止 VPN 服务');
    try {
      if (this.proxyService) {
        await this.proxyService.destroy();
      }
    } catch (error) {
      console.error(TAG, 'VPN 服务销毁失败: ' + (error as Error).message);
    } finally {
      this.proxyService = null;
    }
  }
}

/** 在 VPN 扩展进程内直接分发 RPC 到 Go NAPI，避免重复的第二层 Unix Socket。 */
class ClashVpnServiceImpl extends ClashVpnService {
  private buffers: Map<number, string> = new Map();
  private coreInitialized: boolean = false;
  private running: boolean = false;
  private startedAt: number = 0;
  private optionState: OptionState = {};
  private loadedProfileId: string = '';

  constructor(context: common.Context) {
    super(context);
  }

  async init(): Promise<void> {
    if (this.coreInitialized) {
      return;
    }
    await this.ensureGeoResources();
    this.coreInitialized = initClash(this.context.filesDir);
    if (!this.coreInitialized) {
      throw new Error('mihomo 内核初始化失败');
    }
    AppState.setCoreVersion('mihomo · ClashBox core');
    console.info(TAG, 'mihomo 内核初始化成功');
  }

  /**
   * 将随 HAP 打包的 Geo 数据复制到 mihomo homeDir。
   * 按文件大小判断版本，既支持首次离线启动，也避免每次启动重复复制约 42 MB 数据。
   */
  private async ensureGeoResources(): Promise<void> {
    const resources: GeoResource[] = [
      { fileName: 'geoip.metadb' },
      { fileName: 'GeoIP.dat' },
      { fileName: 'GeoSite.dat' },
      { fileName: 'ASN.mmdb' }
    ];
    for (const resource of resources) {
      const sourcePath = `${this.context.resourceDir}/${resource.fileName}`;
      const targetPath = `${this.context.filesDir}/${resource.fileName}`;
      try {
        const sourceStat = await fileIo.stat(sourcePath);
        let needsCopy = true;
        try {
          const targetStat = await fileIo.stat(targetPath);
          needsCopy = targetStat.size !== sourceStat.size;
        } catch (error) {
          needsCopy = true;
        }
        if (needsCopy) {
          await fileIo.copyFile(sourcePath, targetPath);
        }
      } catch (error) {
        throw new Error('初始化 ' + resource.fileName + ' 失败: ' + (error as Error).message);
      }
    }
  }

  async onRemoteMessageRequest(client: socket.LocalSocketConnection,
    message: socket.LocalSocketMessageInfo): Promise<void> {
    const chunk = this.decoder.decodeToString(new Uint8Array(message.message));
    let buffer = (this.buffers.get(client.clientId) ?? '') + chunk;
    let separator = buffer.indexOf(RPC_EOF);
    while (separator >= 0) {
      const raw = buffer.substring(0, separator);
      buffer = buffer.substring(separator + RPC_EOF.length);
      if (raw.length > 0) {
        await this.handleRawRequest(client, raw);
      }
      separator = buffer.indexOf(RPC_EOF);
    }
    this.buffers.set(client.clientId, buffer);
  }

  override async stopVpn(): Promise<void> {
    stopLog();
    if (this.running) {
      stopTun();
      stopListener();
      this.running = false;
      this.startedAt = 0;
      AppState.setCoreRunning(false);
    }
    await super.stopVpn();
  }

  private async handleRawRequest(client: socket.LocalSocketConnection, raw: string): Promise<void> {
    let request: RpcRequest;
    try {
      request = JSON.parse(raw) as RpcRequest;
    } catch (error) {
      await this.sendClient(client, {
        key: 0,
        method: RpcMethod.QueryTunnelState,
        error: 'RPC 请求格式错误: ' + (error as Error).message
      });
      return;
    }

    const result: RpcResult = { key: request.key, method: request.method };
    try {
      result.result = await this.dispatch(client, request);
    } catch (error) {
      result.error = (error as Error).message;
      console.error(TAG, 'RPC ' + RpcMethod[request.method] + ' 失败: ' + result.error);
    }
    await this.sendClient(client, result);
  }

  private async dispatch(client: socket.LocalSocketConnection, request: RpcRequest): Promise<string> {
    switch (request.method) {
      case RpcMethod.QueryTrafficNow:
        return getTraffic();
      case RpcMethod.QueryTunnelState:
        return JSON.stringify({ running: this.running } as TunnelStateResponse);
      case RpcMethod.QueryTrafficTotal:
        return getTotalTraffic();
      case RpcMethod.QueryProxyGroup:
        return getProxies();
      case RpcMethod.QueryProviders:
        return getExternalProviders();
      case RpcMethod.ChangeProxy:
        const changeResult: string = await changeProxy(JSON.stringify({
          'group-name': this.stringParam(request, 0, '代理组'),
          'proxy-name': this.stringParam(request, 1, '代理节点')
        } as ChangeProxyRequest)) as string;
        // ClashBox 内核成功时返回空字符串，失败时返回错误文本。
        // 不转成 RPC 错误的话，UI 会误以为已切换。
        if (changeResult.length > 0) {
          throw new Error(changeResult);
        }
        return '{"status":"ok"}';
      case RpcMethod.HealthCheck:
        return this.testDelay(this.stringParam(request, 0, '代理节点'));
      case RpcMethod.HealthCheckBatch:
        return this.testDelayBatch(request);
      case RpcMethod.QueryConnections:
        return getConnections();
      case RpcMethod.CloseConnection:
        closeConnection(this.stringParam(request, 0, '连接 ID'));
        return '{"status":"ok"}';
      case RpcMethod.ClearConnections:
        closeConnections();
        return '{"status":"ok"}';
      case RpcMethod.Load:
        return this.loadProfile(this.stringParam(request, 0, '配置 ID'));
      case RpcMethod.StartClash:
        return this.startCore();
      case RpcMethod.StopClash:
        await this.stopVpn();
        return '{"status":"ok"}';
      case RpcMethod.ValidConfig:
        return validateConfig(this.stringParam(request, 0, '配置内容'));
      case RpcMethod.Reset:
        resetTraffic();
        return '{"status":"ok"}';
      case RpcMethod.SetLogObserver:
        this.observeLogs(client);
        return '{"status":"ok"}';
      case RpcMethod.StopLogObserver:
        stopLog();
        return '{"status":"ok"}';
      case RpcMethod.VpnOptions:
        return getVpnOptions();
      case RpcMethod.SetOptionState:
        const optionState = this.stringParam(request, 0, 'VPN 设置');
        const options = JSON.parse(optionState) as OptionState;
        this.optionState = {
          mode: options.mode ?? this.optionState.mode,
          mixedPort: options.mixedPort ?? this.optionState.mixedPort,
          dns: options.dns ?? this.optionState.dns
        };
        const shouldReload = this.coreInitialized && this.loadedProfileId.length > 0 &&
          (options.mode !== undefined || options.mixedPort !== undefined);
        if (shouldReload) {
          await this.loadProfile(this.loadedProfileId);
        } else if (this.coreInitialized && options.dns) {
          await updateDns(options.dns);
        }
        return '{"status":"ok"}';
      case RpcMethod.GetVpnRunTime:
        return JSON.stringify({
          milliseconds: this.running ? Date.now() - this.startedAt : 0
        } as RuntimeResponse);
      case RpcMethod.VpnConfigInited:
      case RpcMethod.RegisterOnMessage:
        return '{"status":"ok"}';
      case RpcMethod.SetSystemDns:
        await updateDns(this.stringParam(request, 0, 'DNS'));
        return '{"status":"ok"}';
      case RpcMethod.GetVersion:
        return '{"version":"mihomo · ClashBox core"}';
      case RpcMethod.GetMemory:
        return await getMemory();
      case RpcMethod.GetRequestList:
        return getRequestList();
      case RpcMethod.ClearRequestList:
        clearRequestList();
        return '{"status":"ok"}';
      default:
        throw new Error('暂不支持的 RPC 方法: ' + request.method);
    }
  }

  private async startCore(): Promise<string> {
    await this.init();
    if (this.running) {
      return '{"status":"ok","running":true}';
    }
    const tunFd = await this.getTunFd();
    if (tunFd < 0) {
      throw new Error('无法创建系统 VPN 虚拟网卡');
    }
    try {
      await this.protectProcess();
      startListener();
      startTun(tunFd, (id: number, fd: number) => {
        this.protect(fd).then(() => {
          setFdMap(id);
        }).catch((error: Error) => {
          console.error(TAG, '保护内核出站 socket 失败: id=' + id + ', ' + error.message);
        });
      });
      this.running = true;
      this.startedAt = Date.now();
      AppState.setCoreRunning(true);
      return '{"status":"ok","running":true}';
    } catch (error) {
      await super.stopVpn();
      throw new Error((error as Error).message);
    }
  }

  /** 将仓库中的 YAML 转成 ClashBox 内核接受的 RawConfig，并立即应用。 */
  private async loadProfile(profileId: string): Promise<string> {
    await this.init();
    const profilePath = `${this.context.filesDir}/profiles/${profileId}.yaml`;
    let yamlContent = '';
    try {
      yamlContent = await fileIo.readText(profilePath);
    } catch (error) {
      throw new Error('读取配置文件失败: ' + (error as Error).message);
    }
    if (yamlContent.trim().length === 0) {
      throw new Error('配置文件内容为空');
    }

    let rawConfig: Record<string, Object | undefined>;
    try {
      rawConfig = parseYaml(yamlContent);
    } catch (error) {
      throw new Error('YAML 解析失败: ' + (error as Error).message);
    }
    if (!rawConfig || typeof rawConfig !== 'object') {
      throw new Error('配置不是有效的 Clash/Mihomo YAML');
    }
    // 参考内核并不导出 setState，运行参数应在加载配置时合并，
    // 避免 VPN 扩展因引用不存在的 NAPI 函数而整个加载失败。
    if (this.optionState.mode) {
      rawConfig['mode'] = this.optionState.mode;
    }
    if (this.optionState.mixedPort && this.optionState.mixedPort >= 1024 && this.optionState.mixedPort <= 65535) {
      rawConfig['mixed-port'] = this.optionState.mixedPort;
    }
    // 订阅通常不携带 geox-url；ClashBox 的配置覆盖逻辑会把默认值覆盖为空，
    // 随后 GEOIP/GEOSITE 规则会尝试从空 URL 下载资源并导致整份配置加载失败。
    if (!rawConfig['geox-url']) {
      const geoXUrls: GeoXUrls = {
        'mmdb': 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb',
        'asn': 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb',
        'geoip': 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat',
        'geosite': 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat'
      };
      rawConfig['geox-url'] = geoXUrls;
    }

    const selectedMap: Record<string, string> = await this.loadSelectedMap(profileId);
    const params: ConfigExtendedParams = {
      'is-patch': false,
      'is-compatible': true,
      'selected-map': selectedMap,
      'override-dns': false,
      'test-url': DEFAULT_TEST_URL
    };
    const updateRequest: UpdateConfigRequest = {
      'profile-id': profileId,
      config: rawConfig,
      params
    };
    const encodedRequest: string = JSON.stringify(updateRequest);
    const result: string = await updateConfig(encodedRequest);
    if (result.length > 0) {
      throw new Error('配置加载失败: ' + result);
    }
    if (this.optionState.dns) {
      await updateDns(this.optionState.dns);
    }
    this.loadedProfileId = profileId;
    return '{"status":"ok"}';
  }

  private async loadSelectedMap(profileId: string): Promise<Record<string, string>> {
    try {
      const content = await fileIo.readText(`${this.context.filesDir}/profiles/index.json`);
      const store = JSON.parse(content) as ProfileSelectionStore;
      const profile = store.profiles.find((item: ProfileSelectionEntry) => item.uid === profileId);
      return profile?.proxySelected ?? {};
    } catch (error) {
      console.warn(TAG, '读取节点选择失败，将使用配置默认值: ' + (error as Error).message);
      return {};
    }
  }

  private async testDelay(proxyName: string): Promise<string> {
    return asyncTestDelay(JSON.stringify({
      'proxy-name': proxyName,
      timeout: 5000,
      'test-url': DEFAULT_TEST_URL
    } as DelayRequest));
  }

  private async testDelayBatch(request: RpcRequest): Promise<string> {
    const encoded = this.stringParam(request, 0, '代理节点列表');
    const names = JSON.parse(encoded) as string[];
    const delays: string[] = await Promise.all(names.map(async (name: string) => this.testDelay(name)));
    return '[' + delays.join(',') + ']';
  }

  private observeLogs(client: socket.LocalSocketConnection): void {
    startLog((_message: string, value: string) => {
      this.sendClient(client, {
        key: 0,
        method: RpcMethod.SetLogObserver,
        result: value
      }).catch((error: Error) => {
        console.error(TAG, '推送日志失败: ' + error.message);
      });
    });
  }

  private stringParam(request: RpcRequest, index: number, name: string): string {
    const value = request.params[index];
    if (typeof value !== 'string' || value.length === 0) {
      throw new Error(name + '不能为空');
    }
    return value;
  }

}
