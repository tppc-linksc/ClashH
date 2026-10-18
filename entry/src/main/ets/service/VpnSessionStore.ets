import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

export interface VpnSessionIntent {
  desired: boolean;
  profileId: string;
}

const DEFAULT_INTENT: VpnSessionIntent = { desired: false, profileId: '' };

/** 用户的连接意图持久化在应用文件目录，供 UI 与 VPN 扩展进程共同读取。 */
export class VpnSessionStore {
  private path: string;

  constructor(context: common.Context) {
    this.path = `${context.filesDir}/vpn_session.json`;
  }

  async read(): Promise<VpnSessionIntent> {
    try {
      const value = JSON.parse(await fileIo.readText(this.path)) as VpnSessionIntent;
      if (typeof value.desired === 'boolean' && typeof value.profileId === 'string') {
        return value;
      }
    } catch (error) {
      // 首次启动没有文件；损坏的状态不能触发自动连接。
    }
    return DEFAULT_INTENT;
  }

  async write(intent: VpnSessionIntent): Promise<void> {
    const tempPath = `${this.path}.tmp`;
    let file: fileIo.File | undefined;
    try {
      file = await fileIo.open(tempPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, JSON.stringify(intent));
      await fileIo.close(file);
      file = undefined;
      await fileIo.rename(tempPath, this.path);
    } finally {
      if (file) {
        await fileIo.close(file);
      }
    }
  }
}
