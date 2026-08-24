import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME = 'clashh_settings';

export interface RuntimeCoreSettings {
  mixedPort: number;
  dns: string;
}

export async function loadRuntimeSettings(context: common.Context): Promise<RuntimeCoreSettings> {
  try {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    const port = Number(store.get('mixedPort', 7890));
    return {
      mixedPort: port >= 1024 && port <= 65535 ? port : 7890,
      dns: String(store.get('dns', '')).trim()
    };
  } catch (error) {
    console.warn('[RuntimeSettings] 读取设置失败: ' + (error as Error).message);
    return { mixedPort: 7890, dns: '' };
  }
}
