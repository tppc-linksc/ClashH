import { connection } from '@kit.NetworkKit';
import { DEFAULT_TUN_IP } from 'proxy_core';

/**
 * 查询系统实际登记的本应用 VPN 网卡。RPC 的 running 标志只代表内核曾启动过，
 * 系统撤销 TUN 后可能仍为 true，不能单独作为首页的“已连接”依据。
 * null 表示系统查询失败，不等同于已断开。
 */
export async function isOwnVpnActive(): Promise<boolean | null> {
  try {
    const nets: connection.NetHandle[] = await connection.getAllNets();
    for (const net of nets) {
      const capabilities = await connection.getNetCapabilities(net);
      if (!capabilities.bearerTypes.includes(connection.NetBearType.BEARER_VPN)) {
        continue;
      }
      const properties = await connection.getConnectionProperties(net);
      if (properties.linkAddresses.some(address => address.address.address === DEFAULT_TUN_IP)) {
        return true;
      }
    }
    return false;
  } catch (error) {
    console.warn('[VpnNetworkStatus] 查询系统 VPN 状态失败: ' + (error as Error).message);
    return null;
  }
}
