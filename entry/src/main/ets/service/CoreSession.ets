import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { ClashClient, ClashClientState, RpcMethod } from 'proxy_core';

/** QueryTunnelState 的响应结构，与 ClashVpnAbility 保持一致。 */
interface TunnelState {
  running: boolean;
  profileId?: string;
}

/**
 * 确保 UI 能访问 mihomo 内核。
 * 这里只启动 VPN 扩展进程并加载配置，不调用 StartClash，因此不会创建 TUN。
 *
 * 内核已经应用过同一份配置时默认跳过 Load：运行中重载会独占内核锁，
 * 期间所有 RPC 都会排队，代理页切进来就会等到超时（"请求超时: Load"）。
 * 配置内容变了（切换/更新订阅）时由调用方传 forceReload。
 */
export async function ensureCoreProfile(context: common.UIAbilityContext, profileUid: string,
  forceReload: boolean = false): Promise<ClashClient> {
  if (profileUid.length === 0) {
    throw new Error('请先导入并选择一个配置');
  }
  const client = ClashClient.getInstance();
  if (client.getState() !== ClashClientState.Connected) {
    const want: Want = {
      bundleName: context.applicationInfo.name,
      abilityName: 'ClashVpnAbility',
      parameters: { requestId: Date.now(), previewOnly: true }
    };
    await vpnExtension.startVpnExtensionAbility(want);
    await connectCore(client, context);
  }
  if (!forceReload && await isProfileLoaded(client, profileUid)) {
    return client;
  }
  await client.request(RpcMethod.Load, [profileUid], 30000);
  return client;
}

/** 查询内核当前已应用的配置。查询失败时按“未加载”处理，让调用方照常 Load。 */
async function isProfileLoaded(client: ClashClient, profileUid: string): Promise<boolean> {
  try {
    const raw = await client.request(RpcMethod.QueryTunnelState, [], 5000);
    const state = JSON.parse(raw) as TunnelState;
    return state.profileId === profileUid;
  } catch (error) {
    console.warn('[CoreSession] 查询内核状态失败，按未加载处理: ' + (error as Error).message);
    return false;
  }
}

async function connectCore(client: ClashClient, context: common.UIAbilityContext): Promise<void> {
  let lastMessage = '内核服务尚未就绪';
  for (let attempt = 0; attempt < 20; attempt++) {
    try {
      await client.connect(context);
      return;
    } catch (error) {
      lastMessage = (error as Error).message;
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 150));
    }
  }
  throw new Error(lastMessage);
}
