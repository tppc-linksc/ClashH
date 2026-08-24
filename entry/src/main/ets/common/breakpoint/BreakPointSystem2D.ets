// 二维断点系统（宽度 × 高度）
// 用于同时适配手机（MatePad mini 竖屏 ≈ 480vp）与平板（MatePad 12.2 横屏 ≈ 1100vp）
//
// 宽度断点: xs(<320) sm(<600) md(<840) lg(<1000) xl(>=1000)
// 高度断点: hsm(<600) hmd(<900) hlg(>=900)

export type WidthBreakpoint = 'xs' | 'sm' | 'md' | 'lg' | 'xl';
export type HeightBreakpoint = 'hsm' | 'hmd' | 'hlg';

// 宽度断点顺序（用于矩阵索引）
export const WIDTH_BP_ORDER: WidthBreakpoint[] = ['xs', 'sm', 'md', 'lg', 'xl'];
export const HEIGHT_BP_ORDER: HeightBreakpoint[] = ['hsm', 'hmd', 'hlg'];

// 断点配置类型：按宽度与高度组合取值
export type BreakpointConfig<T> = Record<WidthBreakpoint, Record<HeightBreakpoint, T>>;

/**
 * 二维断点取值器
 * 用法：const size = BreakpointType2D({...}).getValue(widthBp, heightBp)
 */
export class BreakpointType2D<T> {
  private config: BreakpointConfig<T>;

  constructor(config: BreakpointConfig<T>) {
    this.config = config;
  }

  getValue(widthBp: number, heightBp: number): T {
    const wIdx = Math.min(Math.max(widthBp, 0), WIDTH_BP_ORDER.length - 1);
    const hIdx = Math.min(Math.max(heightBp, 0), HEIGHT_BP_ORDER.length - 1);
    return this.config[WIDTH_BP_ORDER[wIdx]][HEIGHT_BP_ORDER[hIdx]];
  }
}

/**
 * 函数式二维断点（返回直接可调用的函数）
 */
export function BreakpointFunction2D<T>(config: BreakpointConfig<T>): (w: number, h: number) => T {
  const getter = new BreakpointType2D<T>(config);
  return (w: number, h: number): T => getter.getValue(w, h);
}
