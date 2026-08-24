// HomePage：首页（仪表盘）
// 布局：问候 -> 连接控制 -> 流量 -> 当前节点

import { HomeViewModel, HomeState } from '../viewmodel/HomeViewModel';
import { BreakpointFunction2D } from '../common/breakpoint/BreakPointSystem2D';
import { vpnExtension } from '@kit.NetworkKit';
import { Want, common } from '@kit.AbilityKit';
import { ClashClient, ClashClientState, RpcMethod } from 'proxy_core';
import { ProfileRepository, ProfileStoreData } from '../service/ProfileRepository';
import { loadRuntimeSettings, RuntimeCoreSettings } from '../service/RuntimeSettings';

// 首页内容宽度：窄屏满宽，宽屏居中限宽
const PageWidth = BreakpointFunction2D<string>({
  ['xs']: { ['hsm']: '100%', ['hmd']: '100%', ['hlg']: '100%' },
  ['sm']: { ['hsm']: '100%', ['hmd']: '100%', ['hlg']: '100%' },
  ['md']: { ['hsm']: '100%', ['hmd']: '100%', ['hlg']: '100%' },
  ['lg']: { ['hsm']: '720vp', ['hmd']: '720vp', ['hlg']: '720vp' },
  ['xl']: { ['hsm']: '840vp', ['hmd']: '840vp', ['hlg']: '840vp' },
});

@Component
export struct HomePage {
  @StorageLink('currentWidthBreakpoint') widthBp: number = 1;
  @StorageLink('currentHeightBreakpoint') heightBp: number = 1;
  @Prop @Watch('onActiveChanged') active: boolean = true;

  private vm: HomeViewModel = new HomeViewModel();
  @State state: HomeState = {
    connected: false, connecting: false,
    up: 0, down: 0, upTotal: 0, downTotal: 0,
    currentNode: '', currentProfile: '', version: ''
  };

  aboutToAppear(): void {
    this.vm.onStateChange = (s: HomeState) => { this.state = s; };
    if (this.active) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.vm.start(context);
    }
  }

  onActiveChanged(): void {
    if (this.active) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.vm.start(context);
    } else {
      this.vm.stop();
    }
  }

  aboutToDisappear(): void {
    this.vm.stop();
  }

  async onToggleConnect(): Promise<void> {
    if (this.state.connected) {
      await this.stopVpn();
    } else {
      await this.startVpn();
    }
  }

  private async startVpn(): Promise<void> {
    this.updateConnecting(true);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const client = ClashClient.getInstance();
    const want = this.createVpnWant(context, true);
    try {
      const store: ProfileStoreData = await new ProfileRepository(context).list();
      if (store.current.length === 0) {
        throw new Error('请先导入并选择一个配置');
      }
      await vpnExtension.startVpnExtensionAbility(want);
      await this.connectCore(client, context);
      const runtimeSettings: RuntimeCoreSettings = await loadRuntimeSettings(context);
      await client.request(RpcMethod.SetOptionState, [JSON.stringify(runtimeSettings)]);
      await client.request(RpcMethod.Load, [store.current], 15000);
      await client.request(RpcMethod.StartClash, [], 15000);
      await this.vm.refreshNow();
    } catch (e) {
      await client.disconnect();
      try {
        await vpnExtension.stopVpnExtensionAbility(this.createVpnWant(context, false));
      } catch (stopError) {
        console.warn('[HomePage] 启动失败后的清理未完成: ' + (stopError as Error).message);
      }
      this.toast('启动失败: ' + (e as Error).message);
    } finally {
      this.updateConnecting(false);
    }
  }

  private async stopVpn(): Promise<void> {
    this.updateConnecting(true);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const client = ClashClient.getInstance();
    try {
      if (client.getState() === ClashClientState.Connected) {
        await client.request(RpcMethod.StopClash, [], 10000);
      }
    } catch (e) {
      this.toast('停止内核失败: ' + (e as Error).message);
    } finally {
      await client.disconnect();
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
    for (let attempt = 0; attempt < 20; attempt++) {
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
      version: this.state.version
    };
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

        // 实时流量卡片
        Column({ space: 10 }) {
          Row() {
            Text($r('app.string.home_traffic'))
              .fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
            Row() {
              Text($r('app.string.home_total'))
                .fontSize(11).fontColor($r('app.color.text_tertiary'))
              Text(': ' + this.formatBytes(this.state.upTotal + this.state.downTotal))
                .fontSize(11).fontColor($r('app.color.text_tertiary'))
            }
          }.width('100%')
          Row() {
            Column({ space: 4 }) {
              Text(this.formatSpeed(this.state.up))
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.speed_up_icon'))
              Text($r('app.string.home_upload'))
                .fontSize(11).fontColor($r('app.color.text_tertiary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Column({ space: 4 }) {
              Text(this.formatSpeed(this.state.down))
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.speed_down_icon'))
              Text($r('app.string.home_download'))
                .fontSize(11).fontColor($r('app.color.text_tertiary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%')
        }
        .padding(16).width('100%').backgroundColor($r('app.color.container_background')).borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        // 当前节点
        Row() {
          Text($r('app.string.home_current_node'))
            .fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
          Text(this.state.currentNode || '--')
            .fontSize(13).fontColor($r('app.color.text_secondary'))
        }
        .padding(16).width('100%').backgroundColor($r('app.color.container_background')).borderRadius(16)
        .alignItems(VerticalAlign.Center)

        // 版本信息
        Text('mihomo ' + (this.state.version || '--'))
          .fontSize(11).fontColor($r('app.color.text_tertiary')).width('100%').textAlign(TextAlign.Center)
      }
      .padding(16).width('100%')
    }
    .width('100%').height('100%').backgroundColor($r('app.color.background'))
    .align(Alignment.Top).scrollBar(BarState.Off)
  }
}
