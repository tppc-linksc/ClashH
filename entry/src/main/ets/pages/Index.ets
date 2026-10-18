// Index：使用 HarmonyOS 6.1 原生 HdsTabs 沉浸材质底部胶囊。

import { DividerMode, HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { isPhoneBreakpoint } from '../common/breakpoint/BreakPointSystem2D';
import { HomePage } from './HomePage';
import { ProxyPage } from './ProxyPage';
import { ConfigurationPage } from './ConfigurationPage';
import { MorePage } from './MorePage';

@Entry
@Component
struct Index {
  @StorageLink('currentWidthBreakpoint') widthBp: number = 1;
  @State currentIndex: number = 0;

  /** 使用系统 Symbol，选中态与文字共享品牌色。 */
  @Builder
  TabBuilder(index: number, icon: Resource, label: string) {
    Column({ space: 1 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([this.currentIndex === index ? $r('app.color.brand') : $r('app.color.text_tertiary')])
      Text(label)
        .fontSize(10)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? $r('app.color.brand') : $r('app.color.text_secondary'))
    }
    .width(84)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Transparent)
    .onClick(() => { this.currentIndex = index; })
    .accessibilityText(label)
    .accessibilityDescription(`切换到${label}页面`)
  }

  build() {
    HdsTabs({
      barPosition: BarPosition.End,
      index: this.currentIndex
    }) {
      TabContent() { HomePage({ active: this.currentIndex === 0 }) }
        .backgroundColor($r('app.color.background'))
        .tabBar(this.TabBuilder(0, $r('sys.symbol.house_fill'), '首页'))
      TabContent() { ProxyPage({ active: this.currentIndex === 1 }) }
        .backgroundColor($r('app.color.background'))
        .tabBar(this.TabBuilder(1, $r('sys.symbol.wifi_router_fill'), '代理'))
      TabContent() { ConfigurationPage({ active: this.currentIndex === 2 }) }
        .backgroundColor($r('app.color.background'))
        .tabBar(this.TabBuilder(2, $r('sys.symbol.doc_text_fill'), '配置'))
      TabContent() { MorePage() }
        .backgroundColor($r('app.color.background'))
        .tabBar(this.TabBuilder(3, $r('sys.symbol.square_grid_2x2'), '工具'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .vertical(false)
    .barMode(BarMode.Fixed)
    .barHeight(52)
    .barOverlap(true)
    .divider({ mode: DividerMode.NONE })
    .scrollable(false)
    .animationDuration(220)
    .barFloatingStyle({
      barWidth: { smallWidth: 300, mediumWidth: 360, largeWidth: 424 },
      barSideMargin: 16,
      // HdsTabs 已会自动避让系统底部手势区。手机端再保留 24vp
      // 会变成双重间距，因此只留一个较紧凑的光学边距。
      // xs / sm / 阔直板手机均使用紧凑底边距；600vp 起按大屏处理。
      barBottomMargin: isPhoneBreakpoint(this.widthBp) ? 8 : 24,
      gradientMask: { maskColor: Color.Transparent, maskHeight: 88 },
      adaptToHandedness: false,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        // EXQUISITE 在手机模拟器上会产生胶囊底部的矩形采样块；
        // 真机保留精致材质，模拟器使用系统中性材质。
        materialLevel: deviceInfo.productModel.toLowerCase().includes('emulator')
          ? hdsMaterial.MaterialLevel.GENTLE
          : hdsMaterial.MaterialLevel.EXQUISITE
      },
      thermoCtrl: true,
      barOpacity: 0.80
    })
    .onChange((index: number) => { this.currentIndex = index; })
  }
}
