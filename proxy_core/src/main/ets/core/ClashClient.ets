// ClashClient：UI 侧 RPC 客户端
// 通过 LocalSocket（Unix domain socket）连接 VpnAbility 中的 SocketProxyService，
// 服务端再把请求转发给 Go 内核（flclash），实现 UI 与内核的解耦。
//
// 说明：API 23 中 LocalSocket 由 socket.constructLocalSocketInstance() 创建

import { socket } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { RpcMethod, RpcRequest, RpcResult, RPC_EOF } from './RpcProtocol';
import { util } from '@kit.ArkTS';

interface PendingRequest {
  resolve: (value: string) => void;
  reject: (reason: Error) => void;
  timer: number;
}

/** 客户端与服务端连接状态 */
export enum ClashClientState {
  /** 未连接 */
  Disconnected = 'disconnected',
  /** 连接中 */
  Connecting = 'connecting',
  /** 已连接 */
  Connected = 'connected'
}

/**
 * UI 侧 RPC 客户端（单例）
 */
export class ClashClient {
  private static instance: ClashClient | null = null;

  private client: socket.LocalSocket | null = null;
  private socketPath: string = '';
  private requestSeq: number = 0;
  private pendingRequests: Map<number, PendingRequest> = new Map();
  private buffer: string = '';
  private messageCallbacks: ((result: RpcResult) => void)[] = [];
  private stateCallbacks: ((state: ClashClientState) => void)[] = [];

  private state: ClashClientState = ClashClientState.Disconnected;
  private connectingPromise: Promise<void> | null = null;
  private decoder: util.TextDecoder;

  private constructor() {
    this.decoder = util.TextDecoder.create('utf-8');
  }

  /** 获取单例 */
  static getInstance(): ClashClient {
    if (!ClashClient.instance) {
      ClashClient.instance = new ClashClient();
    }
    return ClashClient.instance;
  }

  /** 当前连接状态 */
  getState(): ClashClientState {
    return this.state;
  }

  /**
   * 连接服务端
   * @param context 上下文（用于获取沙箱路径）
   * @param socketName socket 文件名
   */
  async connect(context: common.Context, socketName: string = 'ClashH.sock'): Promise<void> {
    if (this.state === ClashClientState.Connected) return;
    if (this.connectingPromise) {
      return this.connectingPromise;
    }
    this.connectingPromise = this.openConnection(context, socketName);
    try {
      await this.connectingPromise;
    } finally {
      this.connectingPromise = null;
    }
  }

  private async openConnection(context: common.Context, socketName: string): Promise<void> {
    this.setState(ClashClientState.Connecting);

    this.socketPath = `${context.filesDir}/${socketName}`;
    try {
      this.client = socket.constructLocalSocketInstance();
      await this.client.connect({ address: { address: this.socketPath }, timeout: 3000 });
      this.client.on('message', (info: socket.LocalSocketMessageInfo) => {
        this.handleMessage(info);
      });
      this.client.on('close', () => {
        this.handleClose();
      });
      this.setState(ClashClientState.Connected);
      console.info('[ClashClient] 已连接: ' + this.socketPath);
    } catch (e) {
      const failedClient = this.client;
      this.client = null;
      if (failedClient) {
        failedClient.off('message');
        failedClient.off('close');
        try {
          await failedClient.close();
        } catch (closeError) {
          console.warn('[ClashClient] 清理失败连接异常: ' + (closeError as Error).message);
        }
      }
      console.error('[ClashClient] 连接失败:', (e as Error).message);
      this.setState(ClashClientState.Disconnected);
      throw new Error((e as Error).message);
    }
  }

  /** 断开连接 */
  async disconnect(): Promise<void> {
    if (this.client) {
      const closingClient = this.client;
      this.client = null;
      closingClient.off('message');
      closingClient.off('close');
      try {
        await closingClient.close();
      } catch (error) {
        console.warn('[ClashClient] 关闭连接失败: ' + (error as Error).message);
      }
    }
    this.buffer = '';
    this.rejectPendingRequests('连接已断开');
    this.setState(ClashClientState.Disconnected);
  }

  /**
   * 发送 RPC 请求并等待响应
   * @param method 方法
   * @param params 参数
   * @returns 响应 JSON 字符串
   */
  request(method: RpcMethod, params: (string | number | boolean)[] = [], timeoutMs: number = 5000): Promise<string> {
    return new Promise((resolve, reject) => {
      if (this.state !== ClashClientState.Connected || !this.client) {
        reject(new Error('[ClashClient] 未连接'));
        return;
      }
      const key = ++this.requestSeq;
      const req: RpcRequest = { key, method, params };
      const timer = setTimeout(() => {
        this.pendingRequests.delete(key);
        reject(new Error(`[ClashClient] 请求超时: ${RpcMethod[method]}`));
      }, timeoutMs);
      this.pendingRequests.set(key, { resolve, reject, timer });
      this.client.send({
        data: JSON.stringify(req) + RPC_EOF,
        encoding: 'utf-8'
      }).catch((e: Error) => {
        const pending = this.pendingRequests.get(key);
        if (pending) {
          clearTimeout(pending.timer);
          this.pendingRequests.delete(key);
        }
        reject(e);
      });
    });
  }

  /** 注册消息回调（服务端推送的消息） */
  onMessage(cb: (result: RpcResult) => void): void {
    if (!this.messageCallbacks.includes(cb)) {
      this.messageCallbacks.push(cb);
    }
  }

  /** 注销消息回调，避免页面反复进入后重复接收。 */
  offMessage(cb: (result: RpcResult) => void): void {
    this.messageCallbacks = this.messageCallbacks.filter((item) => item !== cb);
  }

  /** 注册状态变化回调 */
  onStateChange(cb: (state: ClashClientState) => void): void {
    if (!this.stateCallbacks.includes(cb)) {
      this.stateCallbacks.push(cb);
    }
  }

  /** 注销状态回调。 */
  offStateChange(cb: (state: ClashClientState) => void): void {
    this.stateCallbacks = this.stateCallbacks.filter((item) => item !== cb);
  }

  private setState(state: ClashClientState): void {
    this.state = state;
    this.stateCallbacks.forEach(cb => cb(state));
  }

  /** 处理收到的消息（ArrayBuffer -> string -> 按 EOF 分隔） */
  private handleMessage(info: socket.LocalSocketMessageInfo): void {
    const msg = this.decoder.decodeToString(new Uint8Array(info.message));
    this.buffer += msg;
    let idx = this.buffer.indexOf(RPC_EOF);
    while (idx >= 0) {
      const raw = this.buffer.substring(0, idx);
      this.buffer = this.buffer.substring(idx + RPC_EOF.length);
      try {
        this.dispatch(JSON.parse(raw) as RpcResult);
      } catch (e) {
        console.error('[ClashClient] 解析消息失败:', (e as Error).message);
      }
      idx = this.buffer.indexOf(RPC_EOF);
    }
  }

  /** 分发消息：key=0 推送给消息回调，否则匹配请求 */
  private dispatch(result: RpcResult): void {
    if (result.key === 0) {
      this.messageCallbacks.forEach(cb => cb(result));
      return;
    }
    const pending = this.pendingRequests.get(result.key);
    if (pending) {
      clearTimeout(pending.timer);
      this.pendingRequests.delete(result.key);
      if (result.error) {
        pending.reject(new Error(result.error));
      } else {
        pending.resolve(result.result ?? '');
      }
    }
  }

  /** 连接关闭：所有未完成请求失败 */
  private handleClose(): void {
    this.client = null;
    // 丢弃半包，避免重连后旧数据与新响应拼在一起。
    this.buffer = '';
    this.rejectPendingRequests('连接已关闭');
    this.setState(ClashClientState.Disconnected);
  }

  private rejectPendingRequests(message: string): void {
    this.pendingRequests.forEach((pending: PendingRequest) => {
      clearTimeout(pending.timer);
      pending.reject(new Error(message));
    });
    this.pendingRequests.clear();
  }
}
