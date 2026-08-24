// AppState：全局应用状态
// 通过 AppStorage 与 UI 共享，AppStorage 键名以 ClashH 开头避免冲突

/** 内核类型 */
export enum ClashCore {
  /** mihomo 内核 */
  Mihomo = 'mihomo'
}

/** 应用运行状态 */
export enum AppFlowingState {
  /** 未运行 */
  Stopped = 'stopped',
  /** 运行中 */
  Running = 'running',
  /** 错误 */
  Error = 'error'
}

/**
 * 全局应用状态管理
 * 通过 AppStorage 键值与 UI 的 @StorageLink 联动
 */
export class AppState {
  /** 应用数据目录 */
  static homeDir: string = '';
  /** 当前配置 id */
  static currentProfileId: string = '';
  /** 当前配置名 */
  static currentProfileName: string = '';

  /** 初始化应用状态 */
  static init(homeDir: string): void {
    AppState.homeDir = homeDir;
    AppStorage.setOrCreate<string>('ClashH.homeDir', homeDir);
    AppStorage.setOrCreate<boolean>('ClashH.coreRunning', false);
    AppStorage.setOrCreate<string>('ClashH.coreVersion', '');
    AppStorage.setOrCreate<string>('ClashH.currentProfileName', '');
    AppStorage.setOrCreate<number>('ClashH.trafficUp', 0);
    AppStorage.setOrCreate<number>('ClashH.trafficDown', 0);
  }

  /** 设置内核运行状态 */
  static setCoreRunning(running: boolean): void {
    AppStorage.setOrCreate<boolean>('ClashH.coreRunning', running);
  }

  /** 设置内核版本 */
  static setCoreVersion(version: string): void {
    AppStorage.setOrCreate<string>('ClashH.coreVersion', version);
  }

  /** 设置当前配置 */
  static setCurrentProfile(name: string): void {
    AppState.currentProfileName = name;
    AppStorage.setOrCreate<string>('ClashH.currentProfileName', name);
  }

  /** 更新流量（供定时器调用） */
  static updateTraffic(up: number, down: number): void {
    AppStorage.setOrCreate<number>('ClashH.trafficUp', up);
    AppStorage.setOrCreate<number>('ClashH.trafficDown', down);
  }
}
