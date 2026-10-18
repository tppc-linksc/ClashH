// EntryAbility：应用入口
// 负责初始化断点系统、全局状态，并加载主界面
import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { breakpointSystem } from '../common/breakpoint/BreakPointSystem';
import { isOwnVpnActive } from '../service/VpnNetworkStatus';
import { AppState } from 'proxy_core';

const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;
  private vpnNetConnection?: connection.NetConnection;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate');
    // 初始化全局应用状态
    AppState.init(this.context.filesDir);
    AppStorage.setOrCreate<number>('ClashH.foregroundEpoch', Date.now());
    AppStorage.setOrCreate<boolean>('ClashH.appForeground', true);
    AppStorage.setOrCreate<number>('ClashH.networkLossEpoch', 0);
    this.startVpnNetworkObserver();
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'onDestroy');
    this.vpnNetConnection?.unregister((error: BusinessError) => {
      if (error) {
        hilog.warn(0x0000, TAG, '注销 VPN 网络监听失败: %{public}s', error.message);
      }
    });
    this.vpnNetConnection = undefined;
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'onWindowStageCreate');
    try {
      this.mainWindow = windowStage.getMainWindowSync();
      this.updateSystemBarAppearance(this.context.config.colorMode);
    } catch (error) {
      hilog.warn(0x0000, TAG, '获取主窗口失败: %{public}s', JSON.stringify(error));
    }
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
    this.mainWindow = undefined;
  }

  onConfigurationUpdate(config: Configuration): void {
    this.updateSystemBarAppearance(config.colorMode);
  }

  onForeground(): void {
    hilog.info(0x0000, TAG, 'onForeground');
    AppStorage.setOrCreate<boolean>('ClashH.appForeground', true);
    AppStorage.setOrCreate<number>('ClashH.foregroundEpoch', Date.now());
  }

  onBackground(): void {
    hilog.info(0x0000, TAG, 'onBackground');
    AppStorage.setOrCreate<boolean>('ClashH.appForeground', false);
  }

  private startVpnNetworkObserver(): void {
    try {
      const observer = connection.createNetConnection({
        netCapabilities: { bearerTypes: [connection.NetBearType.BEARER_VPN] }
      });
      observer.on('netLost', () => {
        isOwnVpnActive().then((active: boolean | null) => {
          if (active === false) {
            AppStorage.setOrCreate<number>('ClashH.networkLossEpoch', Date.now());
          }
        });
      });
      observer.register((error: BusinessError) => {
        if (error) {
          hilog.warn(0x0000, TAG, '注册 VPN 网络监听失败: %{public}s', error.message);
        }
      });
      this.vpnNetConnection = observer;
    } catch (error) {
      hilog.warn(0x0000, TAG, '启动 VPN 网络监听失败: %{public}s', (error as Error).message);
    }
  }

  /**
   * 保留系统状态信息，同时让状态栏、页面和底部手势区使用同一套主题背景。
   * 不启用全屏布局，避免标题、Dock 与挖孔/手势安全区发生重叠。
   */
  private updateSystemBarAppearance(colorMode?: ConfigurationConstant.ColorMode): void {
    if (!this.mainWindow) {
      return;
    }
    const isDark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const backgroundColor = isDark ? '#FF000000' : '#FFF1F3F5';
    const contentColor = isDark ? '#FFFFFFFF' : '#FF1A1A1A';
    this.mainWindow.setWindowSystemBarProperties({
      statusBarColor: backgroundColor,
      statusBarContentColor: contentColor,
      isStatusBarLightIcon: isDark,
      navigationBarColor: backgroundColor,
      navigationBarContentColor: contentColor,
      isNavigationBarLightIcon: isDark,
      enableStatusBarAnimation: false,
      enableNavigationBarAnimation: false
    }).catch((error: object) => {
      hilog.warn(0x0000, TAG, '更新系统栏样式失败: %{public}s', JSON.stringify(error));
    });
  }
}
