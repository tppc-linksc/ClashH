import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME = 'clashh_settings';

/** 从设置页持久化、在连接时下发给内核的运行参数。 */
export interface RuntimeCoreSettings {
  mixedPort: number;
  dns: string;
  /** rule / global / direct；空串表示沿用配置文件里的 mode。 */
  mode: string;
}

function normalizeMode(value: string): string {
  const mode = value.trim().toLowerCase();
  return mode === 'rule' || mode === 'global' || mode === 'direct' ? mode : '';
}

export async function loadRuntimeSettings(context: common.Context): Promise<RuntimeCoreSettings> {
  try {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    // Preferences.get 返回 Promise；必须 await，否则会得到 "[object Promise]"。
    const portValue = await store.get('mixedPort', 7890);
    const dnsValue = await store.get('dns', '');
    const modeValue = await store.get('mode', '');
    const port = Number(portValue);
    return {
      mixedPort: port >= 1024 && port <= 65535 ? port : 7890,
      dns: String(dnsValue).trim(),
      mode: normalizeMode(String(modeValue))
    };
  } catch (error) {
    console.warn('[RuntimeSettings] 读取设置失败: ' + (error as Error).message);
    return { mixedPort: 7890, dns: '', mode: '' };
  }
}

/** 持久化用户选择的代理模式，下次连接时自动应用。 */
export async function saveRuntimeMode(context: common.Context, mode: string): Promise<void> {
  const normalized = normalizeMode(mode);
  if (normalized.length === 0) {
    return;
  }
  const store = await preferences.getPreferences(context, { name: STORE_NAME });
  await store.put('mode', normalized);
  await store.flush();
}
