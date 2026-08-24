// AboutPage：关于

@Component
export struct AboutPage {
  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 8 }) {
          Column({ space: 8 }) {
            Image($r('app.media.box_cat_round')).width(72).height(72).borderRadius(36)
            Text('ClashH').fontSize(22).fontWeight(FontWeight.Bold)
            Text('v0.1.0').fontSize(13).fontColor($r('app.color.text_tertiary'))
          }.padding({ top: 24, bottom: 16 }).width('100%')
          this.InfoItem('项目', 'ClashH')
          this.InfoItem('内核', 'mihomo')
          this.InfoItem('技术栈', 'ArkTS / HarmonyOS / NAPI')
          this.InfoItem('开源', 'GPL-3.0')
          this.InfoItem('作者', 'ClashH Team')
          Text('仅供学习研究使用，请勿用于非法用途。')
            .fontSize(12).fontColor($r('app.color.text_tertiary'))
            .padding({ top: 12, left: 12, right: 12 })
        }.padding({ left: 12, right: 12, top: 12, bottom: 112 })
          .width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').constraintSize({ maxWidth: 720 }).scrollBar(BarState.Off)
    }
    .title('关于')
    .width('100%').height('100%').backgroundColor($r('app.color.background'))
  }

  @Builder
  InfoItem(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor($r('app.color.text_tertiary')).width(72)
      Text(value).fontSize(13).fontColor($r('app.color.text_primary')).layoutWeight(1)
    }.padding(12).width('100%').backgroundColor($r('app.color.container_background')).borderRadius(8)
  }
}
