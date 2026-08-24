// MorePage：工具页及其内部子导航。Dock 由最外层 Index 统一持有。

import { ConnectionsPage } from './ConnectionsPage';
import { LogsPage } from './LogsPage';
import { RequestsPage } from './RequestsPage';
import { ResourcesPage } from './ResourcesPage';
import { SettingsPage } from './SettingsPage';
import { AboutPage } from './AboutPage';

/** 工具子页路由名。 */
type ToolRoute = 'connections' | 'logs' | 'requests' | 'resources' | 'settings' | 'about';

/** 入口项 */
interface MoreItem {
  icon: Resource;
  title: string;
  route: ToolRoute;
}

interface MoreGroup {
  title: string;
  items: MoreItem[];
}

@Component
export struct MorePage {
  private pathStack: NavPathStack = new NavPathStack();

  private groups: MoreGroup[] = [
    {
      title: '运行状态',
      items: [
        { icon: $r('sys.symbol.connection'), title: '连接', route: 'connections' },
        { icon: $r('sys.symbol.doc_text'), title: '日志', route: 'logs' },
        { icon: $r('sys.symbol.paperplane_fill'), title: '请求记录', route: 'requests' },
        { icon: $r('sys.symbol.archivebox_fill'), title: '资源', route: 'resources' },
      ]
    },
    {
      title: '应用',
      items: [
        { icon: $r('sys.symbol.gearshape_fill'), title: '设置', route: 'settings' },
        { icon: $r('sys.symbol.info_circle_fill'), title: '关于', route: 'about' },
      ]
    }
  ];

  build() {
    Navigation(this.pathStack) {
      this.ToolRoot()
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .navDestination(this.ToolDestination)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private ToolRoot() {
    Column() {
      Row() {
        Text('工具').fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1)
      }.padding(12).width('100%').height(48).alignItems(VerticalAlign.Center)

      List({ space: 8 }) {
        ForEach(this.groups, (group: MoreGroup) => {
          ListItem() {
            Column({ space: 8 }) {
              Text(group.title)
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .padding({ left: 4 })
              Column() {
                ForEach(group.items, (item: MoreItem) => {
                  this.EntryRow(item)
                }, (item: MoreItem) => item.title)
              }
              .width('100%')
              .backgroundColor($r('app.color.container_background'))
              .borderRadius(16)
              .clip(true)
            }
          }
        }, (group: MoreGroup) => group.title)
      }
      .padding({ left: 12, right: 12, bottom: 100 })
      .width('100%')
      .constraintSize({ maxWidth: 840 })
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private ToolDestination(name: string) {
    if (name === 'connections') {
      ConnectionsPage()
    } else if (name === 'logs') {
      LogsPage()
    } else if (name === 'requests') {
      RequestsPage()
    } else if (name === 'resources') {
      ResourcesPage()
    } else if (name === 'settings') {
      SettingsPage()
    } else if (name === 'about') {
      AboutPage()
    }
  }

  @Builder
  private EntryRow(item: MoreItem) {
    Row({ space: 12 }) {
      SymbolGlyph(item.icon).fontSize(21).fontColor([$r('app.color.brand')])
      Text(item.title).fontSize(15).layoutWeight(1).fontColor($r('app.color.text_primary'))
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([$r('app.color.text_tertiary')])
    }
    .padding(14)
    .width('100%')
    .onClick(() => {
      this.pathStack.pushPathByName(item.route, null);
    })
  }
}
