// EntryAbility：应用入口
// 负责初始化断点系统、全局状态，并加载主界面
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { breakpointSystem } from '../common/breakpoint/BreakPointSystem';
import { AppState } from 'proxy_core';

const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate');
    // 初始化全局应用状态
    AppState.init(this.context.filesDir);
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, '加载首页失败: %{public}s', JSON.stringify(err));
        return;
      }
      // UIContext 就绪后使用实例级 MediaQuery（全局接口自 API 18 起已弃用）。
      breakpointSystem.start(windowStage.getMainWindowSync().getUIContext());
      hilog.info(0x0000, TAG, '首页加载成功');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'onWindowStageDestroy');
    breakpointSystem.stop();
  }

  onForeground(): void {
    hilog.info(0x0000, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, TAG, 'onBackground');
  }
}
