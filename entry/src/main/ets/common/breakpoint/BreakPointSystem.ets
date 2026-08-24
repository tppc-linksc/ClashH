// 断点监听器：通过媒体查询监听窗口尺寸变化，通知所有订阅者
import { MediaQuery, UIContext, mediaquery } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WidthBreakpoint, HeightBreakpoint } from './BreakPointSystem2D';

const TAG = 'BreakpointSystem';

/** 断点条目：断点名 + 起始尺寸（vp） */
interface BreakpointItem {
  /** 断点名 */
  name: WidthBreakpoint | HeightBreakpoint;
  /** 起始尺寸 */
  size: number;
}

// 宽度断点（vp）
const WIDTH_BP: BreakpointItem[] = [
  { name: 'xs', size: 0 },
  { name: 'sm', size: 320 },
  { name: 'md', size: 600 },
  { name: 'lg', size: 840 },
  { name: 'xl', size: 1000 },
];

// 高度断点（vp）
const HEIGHT_BP: BreakpointItem[] = [
  { name: 'hsm', size: 0 },
  { name: 'hmd', size: 600 },
  { name: 'hlg', size: 900 },
];

/**
 * 断点系统单例
 * 在 EntryAbility 中 start()，页面通过 @StorageLink 读取 currentWidthBreakpoint / currentHeightBreakpoint
 */
export class BreakpointSystem {
  private static instance: BreakpointSystem | null = null;

  // 媒体查询监听器
  private widthListeners: mediaquery.MediaQueryListener[] = [];
  private heightListeners: mediaquery.MediaQueryListener[] = [];
  private mediaQuery: MediaQuery | null = null;

  // 当前断点（写入 AppStorage，供全局 @StorageLink 使用）
  private widthBp: number = 1; // 默认 sm
  private heightBp: number = 1; // 默认 hmd

  private constructor() {}

  static getInstance(): BreakpointSystem {
    if (!BreakpointSystem.instance) {
      BreakpointSystem.instance = new BreakpointSystem();
    }
    return BreakpointSystem.instance;
  }

  /** 启动监听（幂等） */
  start(context: UIContext): void {
    if (this.widthListeners.length > 0) return;
    this.mediaQuery = context.getMediaQuery();
    this.registerWidth();
    this.registerHeight();
  }

  /** 停止监听 */
  stop(): void {
    this.widthListeners.forEach((l: mediaquery.MediaQueryListener) => l.off('change'));
    this.heightListeners.forEach((l: mediaquery.MediaQueryListener) => l.off('change'));
    this.widthListeners = [];
    this.heightListeners = [];
    this.mediaQuery = null;
  }

  private registerWidth(): void {
    WIDTH_BP.forEach((bp: BreakpointItem, index: number) => {
      const isLast = index === WIDTH_BP.length - 1;
      const condition = isLast
        ? `(${bp.size}vp<=width)`
        : `(${bp.size}vp<=width<${WIDTH_BP[index + 1].size}vp)`;
      const listener = this.mediaQuery!.matchMediaSync(condition);
      if (listener.matches) {
        this.widthBp = index;
        AppStorage.setOrCreate<number>('currentWidthBreakpoint', this.widthBp);
      }
      listener.on('change', (result: mediaquery.MediaQueryResult) => {
        if (result.matches) {
          this.widthBp = index;
          AppStorage.setOrCreate<number>('currentWidthBreakpoint', this.widthBp);
          hilog.info(0x1000, TAG, '宽度断点: %{public}s', bp.name);
        }
      });
      this.widthListeners.push(listener);
    });
  }

  private registerHeight(): void {
    HEIGHT_BP.forEach((bp: BreakpointItem, index: number) => {
      const isLast = index === HEIGHT_BP.length - 1;
      const condition = isLast
        ? `(${bp.size}vp<=height)`
        : `(${bp.size}vp<=height<${HEIGHT_BP[index + 1].size}vp)`;
      const listener = this.mediaQuery!.matchMediaSync(condition);
      if (listener.matches) {
        this.heightBp = index;
        AppStorage.setOrCreate<number>('currentHeightBreakpoint', this.heightBp);
      }
      listener.on('change', (result: mediaquery.MediaQueryResult) => {
        if (result.matches) {
          this.heightBp = index;
          AppStorage.setOrCreate<number>('currentHeightBreakpoint', this.heightBp);
          hilog.info(0x1000, TAG, '高度断点: %{public}s', bp.name);
        }
      });
      this.heightListeners.push(listener);
    });
  }
}

// 全局导出单例
export const breakpointSystem = BreakpointSystem.getInstance();
