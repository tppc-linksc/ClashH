import { parse } from 'yaml';

/**
 * 将第三方 yaml 包返回的动态 JavaScript 值收口成 ArkTS 可使用的明确类型。
 * 保持这个兼容边界在 .ts 文件中，业务侧 .ets 不传播 any。
 */
export function parseYaml(source: string): Record<string, Object | undefined> {
  return parse(source) as Record<string, Object | undefined>;
}
