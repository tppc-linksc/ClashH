import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { ClashClient, ClashClientState, RpcMethod } from 'proxy_core';

/**
 * 确保 UI 能访问 mihomo 内核。
 * 这里只启动 VPN 扩展进程并加载配置，不调用 StartClash，因此不会创建 TUN。
 */
export async function ensureCoreProfile(context: common.UIAbilityContext, profileUid: string): Promise<ClashClient> {
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
  await client.request(RpcMethod.Load, [profileUid], 15000);
  return client;
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
