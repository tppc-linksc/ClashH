// ProxyPage：代理页
// 功能：模式切换（规则/全局/直连）、代理组列表、节点选择、延迟测试、搜索

import { ProxyViewModel } from '../viewmodel/ProxyViewModel';
import { ProxyGroup, Proxy } from 'proxy_core';
import { common } from '@kit.AbilityKit';
import { isWidePhoneBreakpoint } from '../common/breakpoint/BreakPointSystem2D';

// 延迟着色阈值（ms）：移动网络下跨境节点普遍在 200-600ms，阈值放宽避免满屏红色。
const DELAY_GOOD_MS = 280;
const DELAY_FAIR_MS = 660;

// Index 里的 HdsTabs 开了 barOverlap，TabContent 会延伸到悬浮 Dock 之下。
// 列表底部必须让出 Dock 高度（barHeight 52）+ 底部边距（手机 8）+ 材质渐变余量，
// 否则滚动到底部时最后几个节点被 Dock 遮住。与配置页列表的 104 保持一致。
const DOCK_BOTTOM_INSET = 104;

@Component
export struct ProxyPage {
  @StorageLink('currentWidthBreakpoint') widthBp: number = 1;
  @StorageLink('currentHeightBreakpoint') heightBp: number = 1;
  @Prop @Watch('onActiveChanged') active: boolean = false;

  private vm: ProxyViewModel = new ProxyViewModel();
  @State loading: boolean = false;
  @State error: string = '';
  @State hasProfile: boolean = false;
  @State groups: ProxyGroup[] = [];
  @State proxies: Record<string, Proxy> = {};
  /** 本次会话最近一次测速结果，测速结束时立即生效，不等内核 history。 */
  @State delays: Record<string, number> = {};
  @State mode: string = 'rule';
  @State keyword: string = '';
  @State testingNames: string[] = [];
  @State testingGroup: string = '';
  @State expandedNames: string[] = [];

  /** 模式选项 */
  private modes: string[] = ['rule', 'global', 'direct'];

  aboutToAppear(): void {
    this.vm.onChange = () => {
      this.syncViewState();
    };
    if (this.active) {
      this.refresh();
    }
  }

  onActiveChanged(): void {
    if (this.active) {
      this.refresh();
    } else {
      // 离开代理页就停止测速轮询，回来时由 refresh 重新对齐。
      this.vm.stopPolling();
    }
  }

  aboutToDisappear(): void {
    this.vm.stopPolling();
  }

  private refresh(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 已有代理列表时静默刷新：切回本页不闪 loading，后台更新数据。
    this.vm.refresh(context, this.vm.groups.length > 0);
  }

  private syncViewState(): void {
    this.loading = this.vm.loading;
    this.error = this.vm.error;
    this.hasProfile = this.vm.hasProfile;
    this.groups = Array.from(this.vm.groups);
    this.proxies = this.vm.proxies;
    // 必须拷贝成新对象：@State 只有引用变化才会触发重建。
    this.delays = this.copyDelays(this.vm.delays);
    this.mode = this.vm.mode;
    this.keyword = this.vm.keyword;
    this.testingNames = Array.from(this.vm.testing);
    this.testingGroup = this.vm.testingGroup;
    this.expandedNames = Array.from(this.vm.expanded);
  }

  private filteredGroups(): ProxyGroup[] {
    const keyword = this.keyword.trim().toLowerCase();
    if (keyword.length === 0) return this.groups;
    return this.groups.filter((group: ProxyGroup) => {
      if (group.name.toLowerCase().includes(keyword)) return true;
      return group.all.some((name: string) => name.toLowerCase().includes(keyword));
    });
  }

  private async selectProxy(groupName: string, proxyName: string): Promise<void> {
    try {
      await this.vm.selectProxy(groupName, proxyName);
      this.toast('已选择：' + proxyName);
    } catch (error) {
      this.toast('切换失败：' + (error as Error).message);
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      console.warn('[ProxyPage] 显示提示失败: ' + (error as Error).message);
    }
  }

  /** 延迟显示文本：优先用最近一次测速结果，其次回落到内核 history。 */
  delayText(name: string): string {
    const delay = this.delayValue(name);
    if (delay === undefined) return '--';
    return delay <= 0 ? '超时' : delay + 'ms';
  }

  /** 取节点延迟：本地测速结果优先，内核 history 作为冷启动时的来源。 */
  private delayValue(name: string): number | undefined {
    const local = this.delays[name];
    if (typeof local === 'number') {
      return local;
    }
    const p = this.proxies[name];
    if (!p || !p.history || p.history.length === 0) {
      return undefined;
    }
    return p.history[p.history.length - 1].delay;
  }

  private copyDelays(source: Record<string, number>): Record<string, number> {
    const copy: Record<string, number> = {};
    const keys = Object.keys(source);
    for (let i = 0; i < keys.length; i++) {
      copy[keys[i]] = source[keys[i]];
    }
    return copy;
  }

  /** 节点图标（按类型） */
  nodeIcon(type: string): string {
    const map: Record<string, string> = {
      'Shadowsocks': '🛰️',
      'Vmess': '🔮',
      'Vless': '💠',
      'Trojan': '🐴',
      'Hysteria': '🌀',
      'Hysteria2': '🌀',
      'Tuic': '⚡',
      'WireGuard': '🔒',
      'Direct': '🌐',
      'Reject': '🚫'
    };
    return map[type] ?? '📡';
  }

  build() {
    Column({ space: 0 }) {
      // 顶栏：模式切换 + 搜索
      if (isWidePhoneBreakpoint(this.widthBp)) {
        Row({ space: 10 }) {
          this.ModeSelector()
          this.SearchField()
        }.padding(12).width('100%').alignItems(VerticalAlign.Center)
      } else {
        Column({ space: 8 }) {
          this.ModeSelector()
          this.SearchField()
        }.padding(12).width('100%')
      }

      // 代理组列表
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(28).height(28)
          Text('正在加载配置与节点…')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.filteredGroups().length === 0) {
        Column() {
          SymbolGlyph(this.hasProfile ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.doc_text'))
            .fontSize(28)
            .fontColor([$r('app.color.text_tertiary')])
          Text(this.emptyMessage())
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 8 })
          if (this.hasProfile && this.error.length > 0) {
            Button('重新加载')
              .height(32)
              .fontSize(12)
              .type(ButtonType.Capsule)
              .margin({ top: 12 })
              .onClick(() => this.refresh())
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.filteredGroups(), (group: ProxyGroup) => {
              this.GroupCard(group)
            }, (g: ProxyGroup) => `${g.name}:${g.now ?? ''}`)
          }
          .padding({ left: 12, right: 12, top: 12, bottom: DOCK_BOTTOM_INSET })
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private ModeSelector() {
    Row({ space: isWidePhoneBreakpoint(this.widthBp) ? 4 : 8 }) {
      ForEach(this.modes, (mode: string) => {
        Text(this.modeLabel(mode))
          .fontSize(13)
          .fontColor(this.mode === mode ? Color.White : $r('app.color.text_secondary'))
          .padding({ left: isWidePhoneBreakpoint(this.widthBp) ? 11 : 14,
            right: isWidePhoneBreakpoint(this.widthBp) ? 11 : 14,
            top: 6, bottom: 6 })
          .backgroundColor(this.mode === mode ? $r('app.color.brand') : $r('app.color.button_container_background'))
          .borderRadius(16)
          .onClick(() => { this.vm.setMode(mode); })
      })
    }
  }

  @Builder
  private SearchField() {
    TextInput({ placeholder: $r('app.string.proxy_search'), text: this.keyword })
      .width(isWidePhoneBreakpoint(this.widthBp) ? undefined : '100%')
      .layoutWeight(isWidePhoneBreakpoint(this.widthBp) ? 1 : 0)
      .height(36)
      .fontSize(13)
      .onChange((v: string) => {
        this.vm.keyword = v;
        this.keyword = v;
      })
  }

  emptyMessage(): string {
    if (!this.hasProfile) return '请先在配置页导入并选择配置';
    if (this.error.length > 0) return '配置加载失败：' + this.error;
    return '当前配置中没有代理组';
  }

  /** 模式文案 */
  modeLabel(mode: string): string {
    if (mode === 'rule') return this.getStr('app.string.proxy_mode_rule');
    if (mode === 'global') return this.getStr('app.string.proxy_mode_global');
    return this.getStr('app.string.proxy_mode_direct');
  }

  getStr(key: string): string {
    try {
      return (this.getUIContext().getHostContext() as common.UIAbilityContext)
        .resourceManager.getStringByNameSync(key.split('.').pop() as string);
    } catch (error) {
      console.warn('[ProxyPage] 读取文案失败: ' + (error as Error).message);
      return key;
    }
  }

  /** 代理组卡片 */
  @Builder
  GroupCard(group: ProxyGroup) {
    Column({ space: 0 }) {
      // 组头（点击展开/收起）
      Row() {
        Text(group.icon ?? '📁')
          .fontSize(16)
        Text(group.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 8 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 当前选中
        Text(group.now ?? '--')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ right: 8 })
          .maxLines(1)
        // 测速按钮：批量测速进行中时显示转圈
        if (this.testingGroup === group.name) {
          Row({ space: 5 }) {
            LoadingProgress().width(14).height(14)
              .color($r('app.color.text_primary'))
            Text($r('app.string.proxy_latency_testing'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .height(26)
          .padding({ left: 10, right: 10 })
          .borderRadius(13)
          .backgroundColor($r('app.color.button_container_background'))
        } else {
          Button($r('app.string.proxy_latency_test'))
            .height(26)
            .fontSize(11)
            .type(ButtonType.Capsule)
            .backgroundColor($r('app.color.button_container_background'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => { this.vm.testGroup(group); })
        }
        // 展开箭头
        Text(this.expandedNames.includes(group.name) ? '▾' : '▸')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: 6 })
      }
      .width('100%')
      .padding(12)
      .onClick(() => this.vm.toggleGroup(group.name))

      // 成员列表
      if (this.expandedNames.includes(group.name)) {
        ForEach(group.all, (name: string) => {
          this.NodeRow(group, name)
        }, (n: string) => n)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.container_background'))
    .borderRadius(14)
    .clip(true)
    .alignItems(HorizontalAlign.Start)
  }

  /** 节点行 */
  @Builder
  NodeRow(group: ProxyGroup, name: string) {
    // 节点数据（ArkUI @Builder 内不支持局部 const，直接取用）
    // 是否选中
    Row({ space: 8 }) {
      Text(this.nodeIcon((this.proxies[name] as Proxy)?.type ?? ''))
        .fontSize(14)
      Text(name)
        .fontSize(13)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor((group.now === name) ? $r('app.color.brand') : $r('app.color.text_primary'))
      if (this.testingNames.includes(name)) {
        LoadingProgress().width(14).height(14)
      } else {
        Text(this.delayText(name))
          .fontSize(11)
          .fontColor(this.delayColor(name))
          .onClick(() => { this.vm.testDelay(name); })
      }
      if (group.now === name) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(15)
          .fontColor([$r('app.color.brand')])
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .backgroundColor((group.now === name) ? $r('app.color.selected_background') : Color.Transparent)
    .onClick(() => { this.selectProxy(group.name, name); })
  }

  /** 延迟颜色：绿/黄/红。阈值见 DELAY_GOOD_MS / DELAY_FAIR_MS。 */
  delayColor(name: string): ResourceColor {
    const delay = this.delayValue(name);
    if (delay === undefined) return $r('app.color.text_tertiary');
    // 0 同样是失败（内核失败样本写入 delay=0），与负值一并归入错误色。
    if (delay <= 0) return $r('app.color.error');
    if (delay <= DELAY_GOOD_MS) return $r('app.color.success');
    if (delay <= DELAY_FAIR_MS) return $r('app.color.warning');
    return $r('app.color.error');
  }
}
