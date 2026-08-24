// RequestsPage：展示内核记录的最近连接请求。

import { ClashClient, ClashClientState, ConnectionInfo, RpcMethod } from 'proxy_core';

@Component
export struct RequestsPage {
  @State items: ConnectionInfo[] = [];
  private client: ClashClient = ClashClient.getInstance();

  aboutToAppear(): void {
    this.refresh();
  }

  async refresh(): Promise<void> {
    if (this.client.getState() !== ClashClientState.Connected) {
      this.items = [];
      return;
    }
    try {
      const raw = await this.client.request(RpcMethod.GetRequestList);
      this.items = JSON.parse(raw) as ConnectionInfo[];
    } catch (error) {
      console.error('[RequestsPage] 获取请求记录失败: ' + (error as Error).message);
    }
  }

  async clear(): Promise<void> {
    if (this.client.getState() !== ClashClientState.Connected) {
      return;
    }
    try {
      await this.client.request(RpcMethod.ClearRequestList);
      this.items = [];
    } catch (error) {
      this.toast('清空失败: ' + (error as Error).message);
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      console.warn('[RequestsPage] 显示提示失败: ' + (error as Error).message);
    }
  }

  host(item: ConnectionInfo): string {
    return item.metadata.host || item.metadata.sniffHost || item.metadata.destinationIP || '--';
  }

  chain(item: ConnectionInfo): string {
    return item.chains.length > 0 ? item.chains.join(' → ') : 'DIRECT';
  }

  startTime(item: ConnectionInfo): string {
    return item.start.length >= 19 ? item.start.substring(11, 19) : item.start;
  }

  networkColor(network: string): ResourceColor {
    return network.toLowerCase() === 'tcp' ? $r('app.color.success') : $r('app.color.warning');
  }

  build() {
    NavDestination() {
      Column() {
        if (this.items.length === 0) {
          Column() {
            Text(this.client.getState() === ClashClientState.Connected ? '暂无请求记录' : '内核未连接')
              .fontSize(14).fontColor($r('app.color.text_tertiary'))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding({ bottom: 100 })
        } else {
          List({ space: 4 }) {
            ForEach(this.items, (item: ConnectionInfo) => {
              ListItem() {
                Column({ space: 4 }) {
                  Row() {
                    Text(item.metadata.network.toUpperCase()).fontSize(11)
                      .fontColor(this.networkColor(item.metadata.network)).fontWeight(FontWeight.Bold).width(48)
                    Text(item.rule || 'MATCH').fontSize(11).fontColor($r('app.color.text_tertiary')).layoutWeight(1)
                    Text(this.chain(item)).fontSize(11).fontColor($r('app.color.brand')).maxLines(1)
                    Text(this.startTime(item)).fontSize(11).fontColor($r('app.color.text_tertiary')).margin({ left: 8 })
                  }.width('100%')
                  Text(this.host(item)).fontSize(12).fontColor($r('app.color.text_primary')).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.padding(10).width('100%').backgroundColor($r('app.color.container_background')).borderRadius(8)
              }
            }, (item: ConnectionInfo) => item.id)
          }.padding({ left: 12, right: 12, top: 12, bottom: 112 }).layoutWeight(1).scrollBar(BarState.Off)
        }
      }
      .width('100%').height('100%')
      .constraintSize({ maxWidth: 960 })
    }
    .title('请求记录')
    .menus([{ value: '清空', icon: $r('sys.symbol.trash'), action: () => { this.clear(); } }])
    .width('100%').height('100%').backgroundColor($r('app.color.background'))
  }
}
