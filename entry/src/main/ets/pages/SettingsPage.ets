// SettingsPage：设置页，使用原生 Navigation 栈式标题栏。

import { ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { ComponentContent, promptAction } from '@kit.ArkUI';
import { ClashClient, ClashClientState, RpcMethod } from 'proxy_core';

/** 设置项模型 */
interface SettingItem {
  icon: Resource;
  title: string;
  value: string;
  action: 'language' | 'theme' | 'dns' | 'port' | 'domestic' | 'about';
}

interface SettingsEditorArgs {
  title: string;
  description: string;
  placeholder: string;
  value: string;
  numeric: boolean;
  onChange: (value: string) => void;
  onCancel: () => void;
  onSave: () => void;
}

/** 使用独立 ComponentContent 构建弹窗，避免成员 Builder 脱离组件上下文。 */
@Builder
function SettingsEditorDialog(args: SettingsEditorArgs) {
  Column({ space: 18 }) {
    Text(args.title)
      .width('100%').textAlign(TextAlign.Center)
      .fontSize(20).fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
    Text(args.description)
      .width('100%').fontSize(13).fontColor($r('app.color.text_secondary'))
    TextInput({ placeholder: args.placeholder, text: args.value })
      .type(args.numeric ? InputType.Number : InputType.Normal)
      .height(48).fontSize(args.numeric ? 18 : 15).padding(12).borderRadius(12)
      .backgroundColor($r('app.color.background'))
      .onChange((value: string) => args.onChange(value))
    Row({ space: 12 }) {
      Button('取消').type(ButtonType.Capsule).layoutWeight(1)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.background'))
        .onClick(() => args.onCancel())
      Button('保存').type(ButtonType.Capsule).layoutWeight(1)
        .fontColor(Color.White).backgroundColor($r('app.color.brand'))
        .onClick(() => args.onSave())
    }.width('100%')
  }
  .width(420)
  .padding(24)
  .borderRadius(24)
  .backgroundColor($r('app.color.container_background'))
}

const STORE_NAME = 'clashh_settings';
const KEY_LANGUAGE = 'language';
const KEY_THEME = 'theme';
const KEY_DNS = 'dns';
const KEY_PORT = 'mixedPort';
const KEY_DOMESTIC_DIRECT = 'domesticDirect';
const KEY_MODE = 'mode';

@Component
export struct SettingsPage {
  @State language: string = 'auto';
  @State theme: string = 'auto';
  @State customDns: string = '';
  @State mixedPort: string = '7890';
  @State domesticDirect: boolean = true;
  @State runtimeMode: string = '';
  @State dnsInput: string = '';
  @State portInput: string = '';

  private store: preferences.Preferences | null = null;
  private client: ClashClient = ClashClient.getInstance();
  private dnsDialogController: promptAction.DialogController = new promptAction.DialogController();
  private portDialogController: promptAction.DialogController = new promptAction.DialogController();
  private dnsDialogContent: ComponentContent<SettingsEditorArgs> | undefined = undefined;
  private portDialogContent: ComponentContent<SettingsEditorArgs> | undefined = undefined;

  async aboutToAppear(): Promise<void> {
    await this.loadSettings();
  }

  async loadSettings(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.store = await preferences.getPreferences(ctx, { name: STORE_NAME });
      this.language = String(await this.store.get(KEY_LANGUAGE, 'auto'));
      this.theme = String(await this.store.get(KEY_THEME, 'auto'));
      this.customDns = String(await this.store.get(KEY_DNS, ''));
      this.mixedPort = String(await this.store.get(KEY_PORT, '7890'));
      this.domesticDirect = Boolean(await this.store.get(KEY_DOMESTIC_DIRECT, true));
      this.runtimeMode = String(await this.store.get(KEY_MODE, '')).trim().toLowerCase();
      this.applyTheme(this.theme);
    } catch (e) {
      console.error('[Settings] 加载失败:', (e as Error).message);
    }
  }

  async saveKey(key: string, value: string | number | boolean): Promise<void> {
    if (!this.store) return;
    try {
      await this.store.put(key, value);
      await this.store.flush();
    } catch (e) {
      console.error('[Settings] 保存失败:', (e as Error).message);
    }
  }

  applyTheme(theme: string): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let mode: ConfigurationConstant.ColorMode;
      if (theme === 'dark') mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      else if (theme === 'light') mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      else mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      ctx.setColorMode(mode);
    } catch (e) {
      console.warn('[Settings] setColorMode 失败:', (e as Error).message);
    }
  }

  onItemClick(item: SettingItem): void {
    switch (item.action) {
      case 'language': this.pickLanguage(); break;
      case 'theme': this.pickTheme(); break;
      case 'dns': this.openDnsEditor(); break;
      case 'port': this.openPortEditor(); break;
      case 'domestic': this.toggleDomesticDirect(); break;
      case 'about': this.showAbout(); break;
    }
  }

  async pickLanguage(): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '选择语言',
        buttons: [
          { text: '跟随系统', color: $r('app.color.brand') },
          { text: '简体中文', color: $r('app.color.text_primary') },
          { text: 'English', color: $r('app.color.text_primary') },
        ]
      });
      const choices: string[] = ['auto', 'zh-CN', 'en-US'];
      this.language = choices[result.index] ?? 'auto';
      await this.saveKey(KEY_LANGUAGE, this.language);
      i18n.System.setAppPreferredLanguage(this.language === 'auto' ? 'default' : this.language);
      this.toast('已保存：' + this.languageLabel(this.language));
    } catch (error) {
      console.warn('[Settings] 切换语言失败: ' + (error as Error).message);
    }
  }

  async pickTheme(): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '选择外观',
        buttons: [
          { text: '跟随系统', color: $r('app.color.brand') },
          { text: '浅色', color: $r('app.color.text_primary') },
          { text: '深色', color: $r('app.color.text_primary') },
        ]
      });
      const choices: string[] = ['auto', 'light', 'dark'];
      this.theme = choices[result.index] ?? 'auto';
      await this.saveKey(KEY_THEME, this.theme);
      this.applyTheme(this.theme);
      this.toast('已切换：' + this.themeLabel(this.theme));
    } catch (error) {
      console.warn('[Settings] 切换外观失败: ' + (error as Error).message);
    }
  }

  openDnsEditor(): void {
    this.dnsInput = this.customDns;
    if (this.dnsDialogContent !== undefined) return;
    const content = new ComponentContent<SettingsEditorArgs>(
      this.getUIContext(),
      wrapBuilder(SettingsEditorDialog),
      {
        title: 'DNS 设置',
        description: 'DNS 服务器（多个用逗号分隔，留空使用默认）',
        placeholder: '如 1.1.1.1, 8.8.8.8',
        value: this.dnsInput,
        numeric: false,
        onChange: (value: string) => { this.dnsInput = value; },
        onCancel: () => this.cancelDns(),
        onSave: () => { this.saveDns(); }
      }
    );
    this.dnsDialogContent = content;
    this.getUIContext().getPromptAction().openCustomDialogWithController(
      content,
      this.dnsDialogController,
      {
        alignment: DialogAlignment.Center,
        isModal: true,
        autoCancel: true,
        showInSubWindow: false,
        onDidDisappear: () => this.finishDnsDialog()
      }
    ).catch((error: Error) => {
      if (this.dnsDialogContent === content) {
        content.dispose();
        this.dnsDialogContent = undefined;
      }
      console.error('[Settings] 打开 DNS 弹窗失败: ' + error.message);
      this.toast('无法打开 DNS 设置');
    });
  }

  async saveDns(): Promise<void> {
    this.customDns = this.dnsInput.trim();
    await this.saveKey(KEY_DNS, this.customDns);
    this.closeDnsDialog();
    await this.applyCoreSettings();
    this.toast(this.customDns === '' ? '已恢复默认 DNS' : 'DNS 已保存');
  }

  cancelDns(): void {
    this.closeDnsDialog();
  }

  openPortEditor(): void {
    this.portInput = this.mixedPort;
    if (this.portDialogContent !== undefined) return;
    const content = new ComponentContent<SettingsEditorArgs>(
      this.getUIContext(),
      wrapBuilder(SettingsEditorDialog),
      {
        title: '端口设置',
        description: '混合端口（HTTP/SOCKS5 代理端口，范围 1024-65535）',
        placeholder: '7890',
        value: this.portInput,
        numeric: true,
        onChange: (value: string) => { this.portInput = value; },
        onCancel: () => this.cancelPort(),
        onSave: () => { this.savePort(); }
      }
    );
    this.portDialogContent = content;
    this.getUIContext().getPromptAction().openCustomDialogWithController(
      content,
      this.portDialogController,
      {
        alignment: DialogAlignment.Center,
        isModal: true,
        autoCancel: true,
        showInSubWindow: false,
        onDidDisappear: () => this.finishPortDialog()
      }
    ).catch((error: Error) => {
      if (this.portDialogContent === content) {
        content.dispose();
        this.portDialogContent = undefined;
      }
      console.error('[Settings] 打开端口弹窗失败: ' + error.message);
      this.toast('无法打开端口设置');
    });
  }

  async savePort(): Promise<void> {
    const port = parseInt(this.portInput);
    if (isNaN(port) || port < 1024 || port > 65535) {
      this.toast('端口无效（需 1024-65535）');
      return;
    }
    this.mixedPort = String(port);
    await this.saveKey(KEY_PORT, port);
    this.closePortDialog();
    await this.applyCoreSettings();
    this.toast('端口已保存：' + this.mixedPort);
  }

  cancelPort(): void {
    this.closePortDialog();
  }

  private closeDnsDialog(): void {
    if (this.dnsDialogContent === undefined) return;
    try {
      this.dnsDialogController.close();
    } catch (error) {
      console.warn('[Settings] 关闭 DNS 弹窗失败: ' + (error as Error).message);
    }
  }

  private closePortDialog(): void {
    if (this.portDialogContent === undefined) return;
    try {
      this.portDialogController.close();
    } catch (error) {
      console.warn('[Settings] 关闭端口弹窗失败: ' + (error as Error).message);
    }
  }

  private finishDnsDialog(): void {
    if (this.dnsDialogContent !== undefined) {
      this.dnsDialogContent.dispose();
      this.dnsDialogContent = undefined;
    }
  }

  private finishPortDialog(): void {
    if (this.portDialogContent !== undefined) {
      this.portDialogContent.dispose();
      this.portDialogContent = undefined;
    }
  }

  showAbout(): void {
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: '关于 ClashH',
        message: 'ClashH v0.1.0\n基于 mihomo 内核\n仅供学习研究',
        buttons: [{ text: '关闭', color: $r('app.color.brand') }]
      }).catch((error: Error) => {
        console.warn('[Settings] 显示关于对话框失败: ' + error.message);
      });
    } catch (error) {
      console.warn('[Settings] 显示关于对话框失败: ' + (error as Error).message);
    }
  }

  /** 规则模式下开启/关闭国内直连；连接中通过 SetOptionState 重载配置。 */
  async toggleDomesticDirect(): Promise<void> {
    const previousValue = this.domesticDirect;
    this.domesticDirect = !this.domesticDirect;
    await this.saveKey(KEY_DOMESTIC_DIRECT, this.domesticDirect);
    const label = this.domesticDirect ? '已开启国内直连规则' : '已关闭国内直连规则';
    const inactiveMode = this.runtimeMode === 'global' || this.runtimeMode === 'direct';
    const modeHint = inactiveMode ? '；当前全局/直连模式下不生效' : '；仅规则模式生效';
    if (this.client.getState() !== ClashClientState.Connected) {
      this.toast(label + modeHint + '，连接后生效');
      return;
    }
    try {
      await this.client.request(RpcMethod.SetOptionState,
        [JSON.stringify({ domesticDirect: this.domesticDirect })], 30000);
      this.toast(label + modeHint);
    } catch (error) {
      this.domesticDirect = previousValue;
      await this.saveKey(KEY_DOMESTIC_DIRECT, previousValue);
      this.toast('应用失败: ' + (error as Error).message);
    }
  }

  private async applyCoreSettings(): Promise<void> {
    if (this.client.getState() !== ClashClientState.Connected) {
      return;
    }
    try {
      await this.client.request(RpcMethod.SetOptionState, [JSON.stringify({
        mixedPort: Number(this.mixedPort),
        dns: this.customDns
      })]);
    } catch (error) {
      this.toast('应用到内核失败: ' + (error as Error).message);
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      console.warn('[Settings] 显示提示失败: ' + (error as Error).message);
    }
  }

  languageLabel(lang: string): string {
    if (lang === 'zh-CN') return '简体中文';
    if (lang === 'en-US') return 'English';
    return '跟随系统';
  }

  themeLabel(theme: string): string {
    if (theme === 'light') return '浅色';
    if (theme === 'dark') return '深色';
    return '跟随系统';
  }

  domesticDirectValue(): string {
    if (this.runtimeMode === 'global' || this.runtimeMode === 'direct') {
      return '当前模式无效';
    }
    return '规则模式有效';
  }

  groups(): SettingItem[][] {
    return [
      [
        { icon: $r('sys.symbol.globe_and_keyboard'), title: '语言', value: this.languageLabel(this.language), action: 'language' },
        { icon: $r('sys.symbol.paintbrush_fill'), title: '外观', value: this.themeLabel(this.theme), action: 'theme' },
      ],
      [
        { icon: $r('sys.symbol.wifi_router_fill'), title: 'DNS 设置', value: this.customDns === '' ? '默认' : this.customDns, action: 'dns' },
        { icon: $r('sys.symbol.connection'), title: '端口设置', value: this.mixedPort, action: 'port' },
        { icon: $r('sys.symbol.network_acceleration'), title: '国内直连规则', value: this.domesticDirect ? this.domesticDirectValue() : '关闭', action: 'domestic' },
      ],
      [
        { icon: $r('sys.symbol.info_circle_fill'), title: '关于', value: 'v0.1.0', action: 'about' },
      ],
    ];
  }

  build() {
    NavDestination() {
      Column() {
        List({ space: 10 }) {
          ForEach(this.groups(), (group: SettingItem[]) => {
            ListItem() {
              Column({ space: 0 }) {
                ForEach(group, (item: SettingItem) => {
                  this.SettingRow(item)
                }, (item: SettingItem) => item.title)
              }
              .width('100%')
              .backgroundColor($r('app.color.container_background'))
              .borderRadius(12)
              .clip(true)
            }
          }, (group: SettingItem[], idx: number) => `group-${idx}`)
        }
        .padding({ left: 12, right: 12, top: 12, bottom: 112 })
        .width('100%')
        .constraintSize({ maxWidth: 840 })
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .title('设置')
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  SettingRow(item: SettingItem) {
    Row({ space: 12 }) {
      SymbolGlyph(item.icon).fontSize(21).fontColor([$r('app.color.brand')])
      Text(item.title).fontSize(15).layoutWeight(1).fontColor($r('app.color.text_primary'))
      Text(item.value).fontSize(13).fontColor($r('app.color.text_secondary'))
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([$r('app.color.text_tertiary')])
    }.padding(14).width('100%').onClick(() => this.onItemClick(item))
  }

}
