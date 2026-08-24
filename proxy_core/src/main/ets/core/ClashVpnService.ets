// ClashVpnService：VPN 服务抽象
// 负责创建 VpnConnection、获取 TUN fd、保护隧道 socket
// 使用官方 @ohos.net.vpnExtension / @ohos.net.connection 类型

import { socket, vpnExtension } from '@kit.NetworkKit';
import { connection } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { RpcResult } from './RpcProtocol';

/** 默认 VPN 参数（与 Go 内核 state 保持一致） */
export const DEFAULT_TUN_IP = '172.19.0.1';
export const DEFAULT_DNS = '172.19.0.2';
export const DEFAULT_MTU = 1400;

/**
 * VPN 服务抽象基类
 * 子类实现 onRemoteMessageRequest 处理 RPC 请求
 */
export abstract class ClashVpnService {
  /** 应用上下文（VpnExtensionAbility 的 context） */
  context: common.Context;
  /** VPN 连接实例 */
  vpnConnection: vpnExtension.VpnConnection | undefined;
  /** 文本解码器 */
  protected decoder: util.TextDecoder;

  protected constructor(context: common.Context) {
    this.context = context;
    this.decoder = util.TextDecoder.create('utf-8');
  }

  /** 初始化（子类实现） */
  abstract init(): Promise<void>;

  /** 处理远端 RPC 消息（子类实现） */
  abstract onRemoteMessageRequest(client: socket.LocalSocketConnection,
    message: socket.LocalSocketMessageInfo): Promise<void>;

  /** 向客户端发送响应 */
  async sendClient(client: socket.LocalSocketConnection, result: RpcResult): Promise<void> {
    try {
      await client.send({ data: JSON.stringify(result) + 'EOF', encoding: 'utf-8' });
    } catch (error) {
      console.error('[ClashVpnService] 发送 RPC 响应失败: ' + (error as Error).message);
    }
  }

  /**
   * 创建 VPN 连接并获取 TUN fd
   * @returns TUN 文件描述符，失败返回 -1
   */
  async getTunFd(): Promise<number> {
    let tunFd = -1;
    try {
      this.vpnConnection = vpnExtension.createVpnConnection(this.context as common.VpnExtensionContext);
      const config: vpnExtension.VpnConfig = this.buildVpnConfig();
      tunFd = await this.vpnConnection.create(config);
      console.info('[ClashVpnService] 获取 TUN fd:', tunFd);
      return tunFd;
    } catch (e) {
      console.error('[ClashVpnService] 创建 VPN 失败:', (e as Error).message);
      try {
        await this.vpnConnection?.destroy();
      } catch (destroyError) {
        console.warn('[ClashVpnService] 清理失败的 VPN 连接异常: ' + (destroyError as Error).message);
      }
      this.vpnConnection = undefined;
      return -1;
    }
  }

  /** 保护隧道 socket（防止流量回环） */
  async protect(fd: number): Promise<void> {
    if (!this.vpnConnection) {
      throw new Error('[ClashVpnService] VpnConnection 未初始化，无法保护 fd=' + fd);
    }
    try {
      await this.vpnConnection.protect(fd);
    } catch (error) {
      throw new Error('[ClashVpnService] 保护 socket 失败: ' + (error as Error).message);
    }
  }

  /**
   * 将当前进程后续创建的出站连接绑定到物理网络，避免再次进入 TUN 形成回环。
   * protectProcessNet 从 API 22 起提供，本项目 minSdk 为 API 23。
   */
  async protectProcess(): Promise<void> {
    if (!this.vpnConnection) {
      throw new Error('[ClashVpnService] VpnConnection 未初始化，无法保护进程网络');
    }
    try {
      await this.vpnConnection.protectProcessNet();
    } catch (error) {
      throw new Error('[ClashVpnService] 保护进程网络失败: ' + (error as Error).message);
    }
  }

  /** 停止 VPN */
  async stopVpn(): Promise<void> {
    try {
      await this.vpnConnection?.destroy();
    } catch (error) {
      console.warn('[ClashVpnService] 销毁 VPN 连接失败: ' + (error as Error).message);
    }
    this.vpnConnection = undefined;
  }

  /**
   * 构建 VPN 配置（子类可覆盖）
   * 使用官方 VpnConfig：addresses 为 LinkAddress 数组
   */
  protected buildVpnConfig(): vpnExtension.VpnConfig {
    const netAddr: connection.NetAddress = { address: DEFAULT_TUN_IP };
    const linkAddr: connection.LinkAddress = { address: netAddr, prefixLength: 30 };
    const defaultAddress: connection.NetAddress = { address: '0.0.0.0' };
    const defaultRoute: connection.RouteInfo = {
      interface: '',
      destination: { address: defaultAddress, prefixLength: 0 },
      gateway: defaultAddress,
      hasGateway: false,
      isDefaultRoute: true
    };
    return {
      addresses: [linkAddr],
      dnsAddresses: [DEFAULT_DNS],
      routes: [defaultRoute],
      mtu: DEFAULT_MTU,
      isIPv4Accepted: true,
      isIPv6Accepted: false
    } as vpnExtension.VpnConfig;
  }
}
