// ConnectionsPage：连接管理

import { ClashClient, ClashClientState, ConnectionInfo, RpcMethod } from 'proxy_core';

interface ConnectionsResponse {
  connections: ConnectionInfo[];
}

@Component
export struct ConnectionsPage {
  @State items: ConnectionInfo[] = [];
  private client: ClashClient = ClashClient.getInstance();
  private timer: number = -1;

  aboutToAppear(): void {
    this.refresh();
    this.timer = setInterval(() => this.refresh(), 1000);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  async refresh(): Promise<void> {
    if (this.client.getState() !== ClashClientState.Connected) {
      this.items = [];
      return;
    }
    try {
      const raw = await this.client.request(RpcMethod.QueryConnections);
      const response = JSON.parse(raw) as ConnectionsResponse;
      this.items = response.connections ?? [];
    } catch (error) {
      console.error('[ConnectionsPage] 刷新失败: ' + (error as Error).message);
    }
  }

  async closeAll(): Promise<void> {
    if (this.client.getState() !== ClashClientState.Connected) {
      this.toast('内核未连接');
      return;
    }
    try {
      await this.client.request(RpcMethod.ClearConnections);
      await this.refresh();
    } catch (error) {
      this.toast('关闭失败: ' + (error as Error).message);
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      console.warn('[ConnectionsPage] 显示提示失败: ' + (error as Error).message);
    }
  }

  host(item: ConnectionInfo): string {
    return item.metadata.host || item.metadata.sniffHost || item.metadata.destinationIP || '--';
  }

  startTime(item: ConnectionInfo): string {
    return item.start.length >= 19 ? item.start.substring(11, 19) : item.start;
  }

  formatBytes(b: number): string {
    if (b < 1024) return `${b} B`;
    if (b < 1024 * 1024) return `${(b / 1024).toFixed(1)} KB`;
    return `${(b / 1024 / 1024).toFixed(1)} MB`;
  }

  build() {
    NavDestination() {
      Column() {
        if (this.items.length === 0) {
          Column() {
            Text('暂无活跃连接').fontSize(14).fontColor($r('app.color.text_tertiary'))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding({ bottom: 100 })
        } else {
          List({ space: 8 }) {
            ForEach(this.items, (item: ConnectionInfo) => {
              ListItem() {
                Column({ space: 6 }) {
                  Row() {
                    Text(this.host(item)).fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
                    Text(item.metadata.network.toUpperCase()).fontSize(11).fontColor($r('app.color.text_secondary'))
                  }.width('100%')
                  Text(item.chains.join(' → ') + (item.rule ? ` · ${item.rule}` : '')).fontSize(11).fontColor($r('app.color.text_tertiary'))
                  Row() {
                    Text('↑' + this.formatBytes(item.upload)).fontSize(11).fontColor($r('app.color.speed_up_icon'))
                    Text(' ↓' + this.formatBytes(item.download)).fontSize(11).fontColor($r('app.color.speed_down_icon')).margin({ left: 8 })
                    Blank()
                    Text(this.startTime(item)).fontSize(11).fontColor($r('app.color.text_tertiary'))
                  }.width('100%')
                }.padding(12).width('100%').backgroundColor($r('app.color.container_background')).borderRadius(10)
              }
            }, (item: ConnectionInfo) => item.id)
          }.padding({ left: 12, right: 12, top: 12, bottom: 112 }).width('100%')
            .constraintSize({ maxWidth: 960 }).layoutWeight(1).scrollBar(BarState.Off)
        }
      }.width('100%').height('100%').alignItems(HorizontalAlign.Center)
    }
    .title('连接')
    .menus([{ value: '清空', icon: $r('sys.symbol.trash'), action: () => { this.closeAll(); } }])
    .width('100%').height('100%').backgroundColor($r('app.color.background'))
  }
}
