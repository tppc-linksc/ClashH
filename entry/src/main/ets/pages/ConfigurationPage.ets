// ConfigurationPage：配置页
// 功能：订阅列表、扫码/链接/文件导入、新建、启用/更新/删除

import { ClashClient, Profile, ProfileType } from 'proxy_core';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { picker } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { ProfileRepository, ProfileStoreData } from '../service/ProfileRepository';
import { isHttpSubscription, normalizeProfileInput } from '../service/ProfileInput';
import { isShareLinkPayload } from '../service/ShareLinkParser';
import { ensureCoreProfile } from '../service/CoreSession';
import { isWidePhoneBreakpoint } from '../common/breakpoint/BreakPointSystem2D';


@Component
export struct ConfigurationPage {
  @StorageLink('currentWidthBreakpoint') widthBp: number = 1;
  @Prop @Watch('onActiveChanged') active: boolean = false;
  private client: ClashClient = ClashClient.getInstance();
  private pathStack: NavPathStack = new NavPathStack();
  @State profiles: Profile[] = [];
  @State currentUid: string = '';
  @State urlInput: string = '';
  @State showImport: boolean = false;
  @State loading: boolean = false;
  @State editingUid: string = '';
  @State editingName: string = '';
  @State editingUrl: string = '';
  @State editingDesc: string = '';
  @State savingMetadata: boolean = false;
  private repository: ProfileRepository | null = null;

  aboutToAppear(): void {
    this.refresh();
  }

  onActiveChanged(): void {
    if (this.active) {
      this.refresh();
    }
  }

  async refresh(): Promise<void> {
    try {
      const data: ProfileStoreData = await this.getRepository().list();
      this.profiles = data.profiles;
      this.currentUid = data.current;
    } catch (e) {
      console.error('[ConfigurationPage] 读取配置失败: ' + (e as Error).message);
    }
  }

  /** 解析扫描结果：兼容订阅地址与 ss/vmess/vless/trojan/hysteria/tuic 分享链接 */
  parseScanResult(rawValue: string): string {
    return normalizeProfileInput(rawValue);
  }

  /** 扫码导入（调用 @kit.ScanKit） */
  async scanQR(): Promise<void> {
    try {
      if (!canIUse('SystemCapability.Multimedia.Scan.Core')) {
        this.toast('当前设备不支持系统扫码服务');
        return;
      }
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: true,
        enableAlbum: true
      };
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const permissionResult = await abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(ctx, ['ohos.permission.CAMERA']);
      if (permissionResult.authResults[0] !== 0) {
        this.toast('需要相机权限才能扫码');
        return;
      }
      if (canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) {
        const result = await scanBarcode.startScanForResult(ctx, options);
        const url = this.parseScanResult(result.originalValue);
        if (url) {
          this.urlInput = url;
          this.showImport = true;
          this.toast('已识别，点击“导入”完成添加');
        } else {
          this.toast('未识别到有效的订阅或节点链接');
        }
      } else {
        this.toast('当前设备不支持系统扫码服务');
      }
    } catch (e) {
      const err = e as BusinessError;
      this.toast('扫码失败: ' + err.message);
    }
  }

  /** 从链接导入：HTTP(S) 走订阅下载，节点分享链接在本地转成 Clash 配置 */
  async importFromUrl(): Promise<void> {
    const value = normalizeProfileInput(this.urlInput);
    if (!value) {
      this.toast('请输入或扫码获取链接');
      return;
    }
    const subscription = isHttpSubscription(value);
    if (!subscription && !isShareLinkPayload(value)) {
      this.toast('无法识别：请填写订阅地址或节点分享链接');
      return;
    }
    this.loading = true;
    try {
      const repository = this.getRepository();
      const profile = subscription
        ? await repository.importFromUrl(value)
        : await repository.importFromShareLinks(value);
      await this.activateProfile(profile.uid, '已导入并启用: ' + profile.name);
      this.urlInput = '';
      this.showImport = false;
      await this.refresh();
    } catch (e) {
      this.toast('导入失败: ' + (e as Error).message);
    } finally {
      this.loading = false;
    }
  }

  async importFromFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const result = await documentPicker.select({ maxSelectNumber: 1 });
      if (result.length > 0) {
        const profile = await this.getRepository().importFromFile(result[0]);
        await this.activateProfile(profile.uid, '已导入并启用: ' + profile.name);
        await this.refresh();
      }
    } catch (e) {
      console.error('[ConfigurationPage] 文件导入失败:', (e as Error).message);
      this.toast('文件导入失败: ' + (e as Error).message);
    }
  }

  async useProfile(uid: string): Promise<void> {
    await this.activateProfile(uid, '已启用');
  }

  private async activateProfile(uid: string, successMessage: string): Promise<void> {
    try {
      await this.getRepository().setCurrent(uid);
      this.currentUid = uid;
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.client = await ensureCoreProfile(context, uid, true);
      this.toast(successMessage);
    } catch (e) {
      // current 已写入时仍然保留选择，代理页会提供明确的重试入口。
      console.error('[ConfigurationPage] 配置加载失败:', (e as Error).message);
      this.toast('配置已保存，但加载失败: ' + (e as Error).message);
    }
  }

  async updateProfile(profile: Profile): Promise<void> {
    try {
      await this.getRepository().update(profile);
      if (profile.uid === this.currentUid) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        this.client = await ensureCoreProfile(context, profile.uid, true);
      }
      this.toast('已更新');
      await this.refresh();
    } catch (e) {
      console.error('[ConfigurationPage] 更新失败:', (e as Error).message);
      this.toast('更新失败: ' + (e as Error).message);
    }
  }

  async deleteProfile(profile: Profile): Promise<void> {
    const confirmed = await this.confirm('删除 ' + profile.name + '?');
    if (!confirmed) return;
    try {
      await this.getRepository().delete(profile);
      await this.refresh();
      this.toast('已删除');
    } catch (error) {
      this.toast('删除失败: ' + (error as Error).message);
    }
  }

  openProfile(profile: Profile): void {
    // 列表项的 p 是渲染时捕获的旧对象，改名后可能仍是旧值；
    // 一律以 this.profiles 里的最新数据为准，避免详情页回填旧名称。
    const latest = this.profiles.find((item: Profile) => item.uid === profile.uid) ?? profile;
    this.editingUid = latest.uid;
    this.editingName = latest.name;
    this.editingUrl = latest.url ?? '';
    this.editingDesc = latest.desc ?? '';
    this.pathStack.pushPathByName('profile-detail', null);
  }

  editingProfile(): Profile | undefined {
    return this.profiles.find((profile: Profile) => profile.uid === this.editingUid);
  }

  async saveProfileMetadata(): Promise<void> {
    if (this.savingMetadata) return;
    this.savingMetadata = true;
    try {
      await this.getRepository().updateMetadata(
        this.editingUid, this.editingName, this.editingUrl, this.editingDesc);
      await this.refresh();
      this.toast('配置详情已保存');
      this.pathStack.pop();
    } catch (error) {
      this.toast('保存失败: ' + (error as Error).message);
    } finally {
      this.savingMetadata = false;
    }
  }

  async deleteEditingProfile(): Promise<void> {
    const profile = this.editingProfile();
    if (!profile) return;
    const confirmed = await this.confirm('删除 ' + profile.name + '?');
    if (!confirmed) return;
    try {
      await this.getRepository().delete(profile);
      await this.refresh();
      this.pathStack.pop();
      this.toast('已删除');
    } catch (error) {
      this.toast('删除失败: ' + (error as Error).message);
    }
  }

  confirm(message: string): Promise<boolean> {
    return new Promise((resolve) => {
      try {
        this.getUIContext().getPromptAction().showDialog({
          title: message,
          buttons: [
            { text: '取消', color: '#666666' },
            { text: '确定', color: '#E84026' }
          ]
        }).then((res) => resolve(res.index === 1))
          .catch(() => resolve(false));
      } catch (error) {
        resolve(false);
      }
    });
  }

  private getRepository(): ProfileRepository {
    if (!this.repository) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.repository = new ProfileRepository(context);
    }
    return this.repository;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      console.warn('[ConfigurationPage] 显示提示失败: ' + (error as Error).message);
    }
  }

  profileTypeText(profile: Profile): string {
    return profile.type === ProfileType.Remote ? '远程订阅' : '本地配置';
  }

  updatedText(profile: Profile): string {
    if (!profile.updated) return '未知';
    const date = new Date(profile.updated);
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hour = String(date.getHours()).padStart(2, '0');
    const minute = String(date.getMinutes()).padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day} ${hour}:${minute}`;
  }

  build() {
    Navigation(this.pathStack) {
      this.ProfileRoot()
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .navDestination(this.ProfileDestination)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private ProfileRoot() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Text($r('app.string.tab_config'))
          .fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('添加')
          .height(30).fontSize(13).type(ButtonType.Capsule)
          .onClick(() => { this.showImport = !this.showImport; })
      }
      .padding({ left: isWidePhoneBreakpoint(this.widthBp) ? 16 : 12,
        right: isWidePhoneBreakpoint(this.widthBp) ? 16 : 12 })
      .width('100%').alignItems(VerticalAlign.Center).height(48)

      if (this.showImport) {
        Column({ space: 8 }) {
          // URL 输入 + 扫码 + 导入
          Row({ space: 8 }) {
            TextInput({ placeholder: '订阅地址或节点分享链接', text: this.urlInput })
              .layoutWeight(1).height(36).fontSize(13)
              .onChange((v: string) => { this.urlInput = v; })
            Button('扫码')
              .height(36).width(72).fontSize(13).type(ButtonType.Capsule)
              .onClick(() => this.scanQR())
            Button('导入')
              .height(36).fontSize(13).type(ButtonType.Capsule)
              .enabled(!this.loading)
              .onClick(() => this.importFromUrl())
          }
          // 文件导入
          Button('从文件导入')
            .height(36).fontSize(13).type(ButtonType.Capsule)
            .backgroundColor($r('app.color.button_container_background'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => this.importFromFile())
        }
        .padding({ left: isWidePhoneBreakpoint(this.widthBp) ? 16 : 12,
          right: isWidePhoneBreakpoint(this.widthBp) ? 16 : 12,
          top: 12, bottom: 12 })
        .width('100%')
      }

      if (this.profiles.length === 0) {
        Column() {
          Text($r('app.string.config_empty')).fontSize(13).fontColor($r('app.color.text_tertiary'))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.profiles, (p: Profile) => {
            ListItem() {
              this.ProfileCard(p)
            }
          // key 必须带上会被修改的字段：只写 uid 时，改名后 key 不变，
          // ForEach 会复用旧节点，列表和详情页都会停留在旧名称。
          }, (p: Profile) => `${p.uid}:${p.name}:${p.desc ?? ''}:${p.url ?? ''}:${p.updated}`)
        }
        .padding({ left: isWidePhoneBreakpoint(this.widthBp) ? 16 : 12,
          right: isWidePhoneBreakpoint(this.widthBp) ? 16 : 12,
          top: 12, bottom: 104 })
        .constraintSize({ maxWidth: 720 })
        .layoutWeight(1).scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.background'))
  }

  @Builder
  private ProfileDestination(name: string) {
    if (name === 'profile-detail') {
      NavDestination() {
        Scroll() {
          Column({ space: 12 }) {
            Column({ space: 8 }) {
              Text('名称')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              TextInput({ placeholder: '配置名称', text: this.editingName })
                .height(42)
                .fontSize(14)
                .onChange((value: string) => { this.editingName = value; })
            }
            .padding(14)
            .width('100%')
            .backgroundColor($r('app.color.container_background'))
            .borderRadius(14)

            if (this.editingProfile()?.type === ProfileType.Remote) {
              Column({ space: 8 }) {
                Text('订阅地址')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                TextInput({ placeholder: 'https://…', text: this.editingUrl })
                  .height(42)
                  .fontSize(13)
                  .type(InputType.Normal)
                  .onChange((value: string) => { this.editingUrl = value; })
                Text('修改地址后，可在配置列表点击“更新”重新下载订阅。')
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
              }
              .padding(14)
              .width('100%')
              .backgroundColor($r('app.color.container_background'))
              .borderRadius(14)
            }

            Column({ space: 8 }) {
              Text('备注')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              TextArea({ placeholder: '可选', text: this.editingDesc })
                .height(88)
                .fontSize(13)
                .onChange((value: string) => { this.editingDesc = value; })
            }
            .padding(14)
            .width('100%')
            .backgroundColor($r('app.color.container_background'))
            .borderRadius(14)

            Column() {
              this.DetailRow('类型', this.editingProfile() ? this.profileTypeText(this.editingProfile() as Profile) : '--')
              this.DetailRow('文件', this.editingProfile()?.file ?? '--')
              this.DetailRow('更新时间', this.editingProfile() ? this.updatedText(this.editingProfile() as Profile) : '--')
            }
            .width('100%')
            .backgroundColor($r('app.color.container_background'))
            .borderRadius(14)
            .clip(true)

            Button(this.savingMetadata ? '保存中…' : '保存修改')
              .height(42)
              .width('100%')
              .type(ButtonType.Capsule)
              .enabled(!this.savingMetadata)
              .onClick(() => this.saveProfileMetadata())

            Button('删除配置')
              .height(42)
              .width('100%')
              .type(ButtonType.Capsule)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.error'))
              .onClick(() => this.deleteEditingProfile())
          }
          .padding({ left: 12, right: 12, top: 12, bottom: 112 })
          .width('100%')
          .constraintSize({ maxWidth: 720 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
      .title('配置详情')
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
  }

  @Builder
  private DetailRow(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
      Text(value)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(48)
    .padding({ left: 14, right: 14 })
    .width('100%')
  }

  @Builder
  ProfileCard(p: Profile) {
    Row({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph(p.type === ProfileType.Remote ? $r('sys.symbol.link') : $r('sys.symbol.doc_text'))
          .fontSize(21)
          .fontColor([$r('app.color.brand')])
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(p.name).fontSize(14).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (p.uid === this.currentUid) {
              Text('当前').fontSize(10).fontColor(Color.White).padding({ left: 6, right: 6, top: 2, bottom: 2 }).backgroundColor($r('app.color.brand')).borderRadius(8)
            }
          }
          Text(p.desc || this.profileTypeText(p) + ' · ' + this.updatedText(p))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }
      .layoutWeight(1)
      .onClick(() => this.openProfile(p))
      Button('更新').height(26).fontSize(11).type(ButtonType.Capsule)
        .backgroundColor($r('app.color.button_container_background'))
        .fontColor($r('app.color.text_primary'))
        .enabled(p.type === ProfileType.Remote)
        .onClick(() => this.updateProfile(p))
      if (p.uid !== this.currentUid) {
        Button('启用').height(26).fontSize(11).type(ButtonType.Capsule).onClick(() => this.useProfile(p.uid))
      }
      Button('删除').height(26).fontSize(11).type(ButtonType.Capsule)
        .backgroundColor($r('app.color.button_container_background'))
        .fontColor($r('app.color.error'))
        .onClick(() => this.deleteProfile(p))
    }.padding(12).width('100%').backgroundColor($r('app.color.container_background')).borderRadius(14)
  }
}
