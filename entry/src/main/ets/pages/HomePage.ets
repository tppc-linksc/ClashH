// HomePage：首页（仪表盘）
// 布局：问候 -> 连接控制 -> 流量 -> 当前节点

import { HomeViewModel, HomeState } from '../viewmodel/HomeViewModel';
import { BreakpointFunction2D, isWidePhoneBreakpoint } from '../common/breakpoint/BreakPointSystem2D';
import { vpnExtension } from '@kit.NetworkKit';
import { Want, common } from '@kit.AbilityKit';
import { ClashClient, ClashClientState, RpcMethod } from 'proxy_core';
import { ProfileRepository, ProfileStoreData } from '../service/ProfileRepository';
import { loadRuntimeSettings, RuntimeCoreSettings, saveRuntimeMode } from '../service/RuntimeSettings';
import { backgroundKeeper } from '../service/BackgroundKeeper';
import { VpnSessionStore } from '../service/VpnSessionStore';

// 首页内容宽度：窄屏满宽，宽屏居中限宽
const PageWidth = BreakpointFunction2D<string>({
  ['xs']: { ['hsm']: '100%', ['hmd']: '100%', ['hlg']: '100%' },
  ['sm']: { ['hsm']: '100%', ['hmd']: '100%', ['hlg']: '100%' },
  ['wide']: { ['hsm']: '100%', ['hmd']: '100%', ['hlg']: '100%' },
  ['md']: { ['hsm']: '100%', ['hmd']: '100%', ['hlg']: '100%' },
  ['lg']: { ['hsm']: '720vp', ['hmd']: '720vp', ['hlg']: '720vp' },
  ['xl']: { ['hsm']: '840vp', ['hmd']: '840vp', ['hlg']: '840vp' },
});

@Component
export struct HomePage {
  @StorageLink('currentWidthBreakpoint') widthBp: number = 1;
  @StorageLink('currentHeightBreakpoint') heightBp: number = 1;
  @StorageLink('ClashH.foregroundEpoch') @Watch('onForegroundEpoch') foregroundEpoch: number = 0;
  @StorageLink('ClashH.appForeground') @Watch('onAppForegroundChanged') appForeground: boolean = true;
  @StorageLink('ClashH.networkLossEpoch') @Watch('onNetworkLoss') networkLossEpoch: number = 0;
  @Prop @Watch('onActiveChanged') active: boolean = true;

  private vm: HomeViewModel = new HomeViewModel();
  private recovering: boolean = false;
  private lastRecoveryAttempt: number = 0;
  @State state: HomeState = {
    connected: false, connecting: false,
    up: 0, down: 0, upTotal: 0, downTotal: 0,
    currentNode: '', currentProfile: '', version: '', mode: 'rule'
  };

  aboutToAppear(): void {
    this.vm.onStateChange = (s: HomeState) => {
      this.state = {
        connected: s.connected, connecting: this.state.connecting,
        up: s.up, down: s.down, upTotal: s.upTotal, downTotal: s.downTotal,
        currentNode: s.currentNode, currentProfile: s.currentProfile, version: s.version,
        mode: s.mode.length > 0 ? s.mode : this.state.mode
      };
    };
    this.loadSavedMode();
    if (this.active && this.appForeground) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.vm.start(context);
    }
    if (this.appForeground) {
      this.recoverIfNeeded();
    }
  }

  /** 读取上次选择的代理模式；连接后内核返回的模式会覆盖它。 */
  private async loadSavedMode(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const settings: RuntimeCoreSettings = await loadRuntimeSettings(context);
      if (settings.mode.length > 0) {
        this.updateMode(settings.mode);
      }
    } catch (error) {
      console.warn('[HomePage] 读取代理模式失败: ' + (error as Error).message);
    }
  }

  onActiveChanged(): void {
    if (this.active && this.appForeground) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.vm.start(context);
      this.recoverIfNeeded();
    } else {
      this.vm.stop();
    }
  }

  aboutToDisappear(): void {
    this.vm.stop();
  }

  onForegroundEpoch(): void {
    if (this.appForeground) {
      this.recoverIfNeeded();
    }
  }

  onAppForegroundChanged(): void {
    if (this.appForeground) {
      if (this.active) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        this.vm.start(context);
      }
      this.recoverIfNeeded();
    } else {
      this.vm.stop();
    }
  }

  onNetworkLoss(): void {
    this.recoverIfNeeded();
  }

  /** 回到 App 后先核对系统 VPN，再依据上次用户意图自动恢复。 */
  private async recoverIfNeeded(): Promise<void> {
    if (this.recovering || this.state.connecting) {
      return;
    }
    this.recovering = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.vm.refreshNow();
      if (this.state.connected) {
        await backgroundKeeper.start(context);
        return;
      }
      if (Date.now() - this.lastRecoveryAttempt < (this.appForeground ? 5000 : 30000)) {
        return;
      }
      const intent = await new VpnSessionStore(context).read();
      if (intent.desired && intent.profileId.length > 0) {
        this.lastRecoveryAttempt = Date.now();
        console.warn('[HomePage] VPN 已断开，尝试自动恢复');
        await this.startVpn(true);
      }
    } catch (error) {
      console.error('[HomePage] 自动恢复检查失败: ' + (error as Error).message);
    } finally {
      this.recovering = false;
    }
  }

  async onToggleConnect(): Promise<void> {
    if (this.recovering || this.state.connecting) {
      return;
    }
    if (this.state.connected) {
      await this.stopVpn();
    } else {
      await this.startVpn();
    }
  }

  private async startVpn(automatic: boolean = false): Promise<void> {
    this.updateConnecting(true);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const client = ClashClient.getInstance();
    const want = this.createVpnWant(context, true);
    try {
      const store: ProfileStoreData = await new ProfileRepository(context).list();
      if (store.current.length === 0) {
        throw new Error('请先导入并选择一个配置');
      }
      await new VpnSessionStore(context).write({ desired: true, profileId: store.current });
      await vpnExtension.startVpnExtensionAbility(want);
      await this.connectCore(client, context);
      const runtimeSettings: RuntimeCoreSettings = await loadRuntimeSettings(context);
      await client.request(RpcMethod.SetOptionState, [JSON.stringify(runtimeSettings)]);
      await client.request(RpcMethod.Load, [store.current], 15000);
      await client.request(RpcMethod.StartClash, [], 15000);
      // 官方长时任务仅接受 UIAbilityContext；用于保持应用后台运行，VPN 扩展由系统单独管理。
      await backgroundKeeper.start(context);
      await this.vm.refreshNow();
    } catch (e) {
      await client.disconnect();
      await backgroundKeeper.stop(context);
      try {
        await vpnExtension.stopVpnExtensionAbility(this.createVpnWant(context, false));
      } catch (stopError) {
        console.warn('[HomePage] 启动失败后的清理未完成: ' + (stopError as Error).message);
      }
      if (!automatic) {
        // 手动连接失败时撤销连接意图，避免回到前台后反复自动重连。
        try {
          await new VpnSessionStore(context).write({ desired: false, profileId: '' });
        } catch (sessionError) {
          console.warn('[HomePage] 回滚连接意图失败: ' + (sessionError as Error).message);
        }
        this.toast('启动失败: ' + (e as Error).message);
      } else {
        console.error('[HomePage] 自动恢复失败: ' + (e as Error).message);
      }
    } finally {
      this.updateConnecting(false);
    }
  }

  private async stopVpn(): Promise<void> {
    this.updateConnecting(true);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const client = ClashClient.getInstance();
    try {
      await new VpnSessionStore(context).write({ desired: false, profileId: '' });
    } catch (error) {
      this.toast('保存断开状态失败: ' + (error as Error).message);
      this.updateConnecting(false);
      return;
    }
    try {
      if (client.getState() === ClashClientState.Connected) {
        await client.request(RpcMethod.StopClash, [], 10000);
      }
    } catch (e) {
      this.toast('停止内核失败: ' + (e as Error).message);
    } finally {
      await client.disconnect();
      await backgroundKeeper.stop(context);
      try {
        await vpnExtension.stopVpnExtensionAbility(this.createVpnWant(context, false));
      } catch (error) {
        this.toast('停止 VPN 失败: ' + (error as Error).message);
      }
      this.updateConnecting(false);
      await this.vm.refreshNow();
    }
  }

  private createVpnWant(context: common.UIAbilityContext, includeRequestId: boolean): Want {
    if (includeRequestId) {
      return {
        bundleName: context.applicationInfo.name,
        abilityName: 'ClashVpnAbility',
        parameters: { requestId: Date.now() }
      };
    }
    return {
      bundleName: context.applicationInfo.name,
      abilityName: 'ClashVpnAbility'
    };
  }

  private async connectCore(client: ClashClient, context: common.UIAbilityContext): Promise<void> {
    let lastMessage = 'VPN 服务尚未就绪';
    for (let attempt = 0; attempt < 8; attempt++) {
      try {
        await client.connect(context);
        return;
      } catch (error) {
        lastMessage = (error as Error).message;
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 150));
      }
    }
    throw new Error(lastMessage);
  }

  private updateConnecting(connecting: boolean): void {
    this.state = {
      connected: this.state.connected,
      connecting,
      up: this.state.up,
      down: this.state.down,
      upTotal: this.state.upTotal,
      downTotal: this.state.downTotal,
      currentNode: this.state.currentNode,
      currentProfile: this.state.currentProfile,
      version: this.state.version,
      mode: this.state.mode
    };
  }

  private updateMode(mode: string): void {
    this.state = {
      connected: this.state.connected,
      connecting: this.state.connecting,
      up: this.state.up,
      down: this.state.down,
      upTotal: this.state.upTotal,
      downTotal: this.state.downTotal,
      currentNode: this.state.currentNode,
      currentProfile: this.state.currentProfile,
      version: this.state.version,
      mode
    };
  }

  /** 首页快捷切换 rule/global/direct；未连接时只持久化，连接后生效。 */
  private async onModeSelect(mode: string): Promise<void> {
    if (this.state.connecting || this.state.mode === mode) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const previous = this.state.mode;
    this.updateMode(mode);
    try {
      await saveRuntimeMode(context, mode);
    } catch (error) {
      console.warn('[HomePage] 保存代理模式失败: ' + (error as Error).message);
    }
    const client = ClashClient.getInstance();
    if (client.getState() !== ClashClientState.Connected) {
      this.toast('已设为' + this.modeName(mode) + '模式，连接后生效');
      return;
    }
    try {
      await client.request(RpcMethod.SetOptionState, [JSON.stringify({ mode })], 30000);
      this.toast('已切换为' + this.modeName(mode) + '模式');
      await this.vm.refreshNow();
    } catch (error) {
      this.updateMode(previous);
      this.toast('切换模式失败: ' + (error as Error).message);
    }
  }

  private modeName(mode: string): string {
    if (mode === 'global') return '全局';
    if (mode === 'direct') return '直连';
    return '规则';
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      console.warn('[HomePage] 显示提示失败: ' + (error as Error).message);
    }
  }

  formatSpeed(b: number): string {
    if (b < 1024) return b.toFixed(0) + ' B/s';
    if (b < 1024 * 1024) return (b / 1024).toFixed(1) + ' KB/s';
    if (b < 1024 * 1024 * 1024) return (b / 1024 / 1024).toFixed(1) + ' MB/s';
    return (b / 1024 / 1024 / 1024).toFixed(2) + ' GB/s';
  }

  formatBytes(b: number): string {
    if (b < 1024) return b.toFixed(0) + ' B';
    if (b < 1024 * 1024) return (b / 1024).toFixed(1) + ' KB';
    if (b < 1024 * 1024 * 1024) return (b / 1024 / 1024).toFixed(1) + ' MB';
    return (b / 1024 / 1024 / 1024).toFixed(2) + ' GB';
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // 顶栏问候 + 头像（单次）
        Row() {
          Column({ space: 4 }) {
            Text($r('app.string.home_greeting')).fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text(this.state.currentProfile || $r('app.string.home_no_profile')).fontSize(13).fontColor($r('app.color.text_tertiary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Image($r('app.media.box_cat_round')).width(44).height(44).borderRadius(22)
        }.width('100%').alignItems(VerticalAlign.Center)

        // 连接控制卡片（按钮 + 状态）
        Row() {
          Column({ space: 4 }) {
            Text(this.state.connected ? (this.state.currentNode || '已连接') :
              (this.state.currentProfile || $r('app.string.home_no_profile'))).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.state.connected ? '已连接' : '未连接').fontSize(11).fontColor($r('app.color.text_tertiary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
          Button(this.state.connected ? $r('app.string.home_disconnect') : $r('app.string.home_connect'))
            .type(ButtonType.Capsule).height(36).fontSize(14).fontWeight(FontWeight.Medium)
            .backgroundColor(this.state.connected ? $r('app.color.error') : $r('app.color.brand'))
            .fontColor(Color.White).padding({ left: 20, right: 20 })
            .enabled(!this.state.connecting)
            .onClick(() => this.onToggleConnect())
        }
        .padding(16).width('100%').borderRadius(16)
        .backgroundColor($r('app.color.container_background'))
        .alignItems(VerticalAlign.Center)

        // 代理模式快捷切换：规则 / 全局 / 直连
        this.ModeSwitch()

        // 阔直板手机优先使用横向信息带；普通手机保持更易读的纵向卡片。
        if (isWidePhoneBreakpoint(this.widthBp)) {
          Row({ space: 12 }) {
            this.TrafficCard()
            this.CurrentNodeCard(true)
          }.width('100%').alignItems(VerticalAlign.Center)
        } else {
          this.TrafficCard()
          this.CurrentNodeCard(false)
        }

        // 版本信息
        Text('mihomo ' + (this.state.version || '--'))
          .fontSize(11).fontColor($r('app.color.text_tertiary')).width('100%').textAlign(TextAlign.Center)
      }
      .padding(16)
      .width(PageWidth(this.widthBp, this.heightBp))
      .constraintSize({ maxWidth: 840 })
    }
    .width('100%').height('100%').backgroundColor($r('app.color.background'))
    .align(Alignment.Top).scrollBar(BarState.Off)
  }

  @Builder
  private ModeSwitch() {
    Row({ space: 8 }) {
      Text('代理模式')
        .fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
      this.ModeChip('rule', $r('app.string.proxy_mode_rule'))
      this.ModeChip('global', $r('app.string.proxy_mode_global'))
      this.ModeChip('direct', $r('app.string.proxy_mode_direct'))
    }
    .padding({ left: 16, right: 12, top: 10, bottom: 10 })
    .width('100%').borderRadius(16)
    .backgroundColor($r('app.color.container_background'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ModeChip(mode: string, label: Resource) {
    Text(label)
      .fontSize(12)
      .fontColor(this.state.mode === mode ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.state.mode === mode ? $r('app.color.brand') : $r('app.color.button_container_background'))
      .borderRadius(14)
      .onClick(() => { this.onModeSelect(mode); })
  }

  @Builder
  private TrafficCard() {
    Column({ space: 10 }) {
      Row({ space: 4 }) {
        Text($r('app.string.home_traffic'))
          .fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
        // 资源对象不能直接和字符串拼接（会变成 [object Object]），标题与数值分开渲染。
        Text($r('app.string.home_total'))
          .fontSize(11).fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
        Text(this.formatBytes(this.state.upTotal + this.state.downTotal))
          .fontSize(11).fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
      }.width('100%').alignItems(VerticalAlign.Center)
      Row() {
        Column({ space: 4 }) {
          Text(this.formatSpeed(this.state.up))
            .fontSize(isWidePhoneBreakpoint(this.widthBp) ? 17 : 20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.speed_up_icon'))
            .maxLines(1)
          Text($r('app.string.home_upload'))
            .fontSize(11).fontColor($r('app.color.text_tertiary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 4 }) {
          Text(this.formatSpeed(this.state.down))
            .fontSize(isWidePhoneBreakpoint(this.widthBp) ? 17 : 20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.speed_down_icon'))
            .maxLines(1)
          Text($r('app.string.home_download'))
            .fontSize(11).fontColor($r('app.color.text_tertiary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
    }
    .padding(16)
    .width(isWidePhoneBreakpoint(this.widthBp) ? undefined : '100%')
    .layoutWeight(isWidePhoneBreakpoint(this.widthBp) ? 3 : 0)
    .backgroundColor($r('app.color.container_background'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private CurrentNodeCard(compact: boolean) {
    if (compact) {
      Column({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.wifi_router_fill'))
          .fontSize(22).fontColor([$r('app.color.brand')])
        Text($r('app.string.home_current_node'))
          .fontSize(12).fontWeight(FontWeight.Medium)
        Text(this.state.currentNode || '--')
          .fontSize(12).fontColor($r('app.color.text_secondary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .padding(14)
      .layoutWeight(2)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.container_background'))
      .borderRadius(16)
    } else {
      Row() {
        Text($r('app.string.home_current_node'))
          .fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
        Text(this.state.currentNode || '--')
          .fontSize(13).fontColor($r('app.color.text_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .padding(16).width('100%')
      .backgroundColor($r('app.color.container_background')).borderRadius(16)
      .alignItems(VerticalAlign.Center)
    }
  }
}
