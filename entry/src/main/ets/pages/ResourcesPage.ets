// ResourcesPage：展示内核实际存在的 Geo 数据文件，不伪造更新时间。

import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

@Component
export struct ResourcesPage {
  @State geoIp: string = '未安装';
  @State geoSite: string = '未安装';
  @State mmdb: string = '未安装';
  @State asn: string = '未安装';

  aboutToAppear(): void {
    this.refreshStatus();
  }

  async refreshStatus(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // ClashVpnAbility.ensureGeoResources 会把资源复制到 filesDir 根目录。
    const homeDir = context.filesDir;
    this.geoIp = await this.fileStatus(`${homeDir}/GeoIP.dat`);
    this.geoSite = await this.fileStatus(`${homeDir}/GeoSite.dat`);
    this.mmdb = await this.fileStatus(`${homeDir}/geoip.metadb`);
    this.asn = await this.fileStatus(`${homeDir}/ASN.mmdb`);
  }

  async fileStatus(path: string): Promise<string> {
    try {
      if (!(await fileIo.access(path))) return '未安装';
      const stat = await fileIo.stat(path);
      const date = new Date(stat.mtime * 1000);
      return `${this.formatSize(stat.size)} · ${date.toLocaleDateString()}`;
    } catch (error) {
      return '读取失败';
    }
  }

  formatSize(bytes: number): string {
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  }

  build() {
    NavDestination() {
      List({ space: 8 }) {
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.network_acceleration')).fontSize(24).fontColor([$r('app.color.brand')])
              Column({ space: 2 }) {
                Text('GeoIP').fontSize(15).fontWeight(FontWeight.Medium)
                Text('IP 地理位置数据库').fontSize(12).fontColor($r('app.color.text_tertiary'))
                Text(this.geoIp).fontSize(11).fontColor($r('app.color.text_tertiary'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
              Text('由内核管理').fontSize(11).fontColor($r('app.color.text_tertiary'))
            }.padding(14).width('100%').backgroundColor($r('app.color.container_background')).borderRadius(10)
          }
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.doc_text_badge_magnifyingglass')).fontSize(24).fontColor([$r('app.color.brand')])
              Column({ space: 2 }) {
                Text('GeoSite').fontSize(15).fontWeight(FontWeight.Medium)
                Text('域名分类数据库').fontSize(12).fontColor($r('app.color.text_tertiary'))
                Text(this.geoSite).fontSize(11).fontColor($r('app.color.text_tertiary'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
              Text('由内核管理').fontSize(11).fontColor($r('app.color.text_tertiary'))
            }.padding(14).width('100%').backgroundColor($r('app.color.container_background')).borderRadius(10)
          }
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.archivebox_fill')).fontSize(24).fontColor([$r('app.color.brand')])
              Column({ space: 2 }) {
                Text('MMDB').fontSize(15).fontWeight(FontWeight.Medium)
                Text('IP 库 mmdb 格式').fontSize(12).fontColor($r('app.color.text_tertiary'))
                Text(this.mmdb).fontSize(11).fontColor($r('app.color.text_tertiary'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
              Text('由内核管理').fontSize(11).fontColor($r('app.color.text_tertiary'))
            }.padding(14).width('100%').backgroundColor($r('app.color.container_background')).borderRadius(10)
          }
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.globe_and_keyboard')).fontSize(24).fontColor([$r('app.color.brand')])
              Column({ space: 2 }) {
                Text('ASN').fontSize(15).fontWeight(FontWeight.Medium)
                Text('自治系统号数据库').fontSize(12).fontColor($r('app.color.text_tertiary'))
                Text(this.asn).fontSize(11).fontColor($r('app.color.text_tertiary'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
              Text('由内核管理').fontSize(11).fontColor($r('app.color.text_tertiary'))
            }.padding(14).width('100%').backgroundColor($r('app.color.container_background')).borderRadius(10)
          }
      }.padding({ left: 12, right: 12, top: 12, bottom: 112 }).width('100%')
        .constraintSize({ maxWidth: 840 }).scrollBar(BarState.Off)
    }
    .title('资源')
    .width('100%').height('100%').backgroundColor($r('app.color.background'))
  }
}
