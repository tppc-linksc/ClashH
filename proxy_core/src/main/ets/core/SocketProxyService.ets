// SocketProxyService：VpnAbility 内的 RPC 服务端
// 职责：
//   1. 创建 LocalSocketServer 监听 UI 客户端的连接
//   2. 将 UI 的 RPC 请求转发给 Go 内核（flclash，通过 NAPI 或 Unix socket）
//   3. 把内核返回结果回传给 UI

import { socket } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ClashVpnService } from './ClashVpnService';

/**
 * RPC 服务端（运行在 VpnAbility 进程中）
 * UI 通过 LocalSocket 连接本服务，本服务再调用 Go 内核
 */
export class SocketProxyService {
  /** LocalSocket 服务端 */
  private server: socket.LocalSocketServer;
  /** 客户端连接池 */
  private clientPool: Map<number, socket.LocalSocketConnection> = new Map();
  /** VPN 服务（负责 TUN fd 与内核启动） */
  private vpnService: ClashVpnService;
  /** 上下文 */
  private context: common.Context;
  /** socket 文件路径 */
  private socketPath: string = '';
  /** 文本解码器（ArrayBuffer -> string） */
  private decoder: util.TextDecoder;

  constructor(context: common.Context, vpnService: ClashVpnService) {
    this.context = context;
    this.vpnService = vpnService;
    this.server = socket.constructLocalSocketServerInstance();
    this.socketPath = `${context.filesDir}/ClashH.sock`;
    this.decoder = util.TextDecoder.create('utf-8');
  }

  /**
   * 启动服务
   * 1. 清理残留 socket 文件（上次异常退出可能遗留）
   * 2. 启动 LocalSocket 监听
   */
  async startService(): Promise<void> {
    try {
      await this.cleanup();
      await this.vpnService.init();
      await this.server.listen({ address: this.socketPath });
      this.server.on('connect', (client: socket.LocalSocketConnection) => {
        console.info('[SocketProxyService] 客户端已连接: ' + client.clientId);
        this.clientPool.set(client.clientId, client);
        client.on('message', (value: socket.LocalSocketMessageInfo) => {
          this.vpnService.onRemoteMessageRequest(client, value).catch((error: Error) => {
            console.error('[SocketProxyService] 请求处理失败:', error.message);
          });
        });
        client.on('close', () => {
          console.info('[SocketProxyService] 客户端已关闭: ' + client.clientId);
          client.off('message');
          client.off('close');
          this.clientPool.delete(client.clientId);
        });
      });
      console.info('[SocketProxyService] 监听启动: ' + this.socketPath);
    } catch (e) {
      console.error('[SocketProxyService] 启动失败:', (e as Error).message);
      await this.cleanup();
      throw new Error('[SocketProxyService] 启动失败: ' + (e as Error).message);
    }
  }

  /** 停止服务并清理 */
  async destroy(): Promise<void> {
    const closeTasks: Promise<void>[] = [];
    this.clientPool.forEach((client: socket.LocalSocketConnection) => {
      client.off('message');
      client.off('close');
      closeTasks.push(client.close().catch((error: Error) => {
        console.warn('[SocketProxyService] 关闭客户端连接失败: ' + error.message);
      }));
    });
    await Promise.all(closeTasks);
    this.clientPool.clear();
    this.server.off('connect');
    await this.vpnService.stopVpn();
    await this.cleanup();
  }

  /** 清理 socket 文件与 VPN */
  private async cleanup(): Promise<void> {
    try {
      if (await fileIo.access(this.socketPath)) {
        await fileIo.unlink(this.socketPath);
      }
    } catch (e) {
      console.warn('[SocketProxyService] 清理失败:', (e as Error).message);
    }
  }
}
