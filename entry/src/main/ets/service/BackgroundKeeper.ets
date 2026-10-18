// BackgroundKeeper：VPN 运行期间申请数据传输长时任务。
// 手机不支持 taskKeeping；申请该类型会使整次长时任务请求失败。

import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = '[BackgroundKeeper]';

/** 与 module.json5 的 backgroundModes 对应。 */
const BACKGROUND_MODES: string[] = ['dataTransfer'];

class BackgroundKeeper {
  private active: boolean = false;
  private pending: boolean = false;

  /** VPN 已连接时调用。重复调用安全。 */
  async start(context: common.Context): Promise<void> {
    if (this.active || this.pending) {
      return;
    }
    this.pending = true;
    try {
      const agent: WantAgent = await wantAgent.getWantAgent({
        wants: [{
          bundleName: context.applicationInfo.name,
          abilityName: 'EntryAbility'
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      await backgroundTaskManager.startBackgroundRunning(context, BACKGROUND_MODES, agent);
      this.active = true;
      console.info(TAG, '长时任务已启动');
    } catch (error) {
      const err = error as BusinessError;
      // 申请失败不应阻断连接流程，但后台运行可能不稳定。
      console.error(TAG, `长时任务启动失败 code=${err.code} msg=${err.message}`);
    } finally {
      this.pending = false;
    }
  }

  /** VPN 断开时调用。 */
  async stop(context: common.Context): Promise<void> {
    if (!this.active) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      console.info(TAG, '长时任务已停止');
    } catch (error) {
      const err = error as BusinessError;
      console.warn(TAG, `长时任务停止失败 code=${err.code} msg=${err.message}`);
    } finally {
      this.active = false;
    }
  }

  isActive(): boolean {
    return this.active;
  }
}

export const backgroundKeeper = new BackgroundKeeper();
