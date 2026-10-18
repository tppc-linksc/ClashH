// LogsPage：订阅 Go 内核日志并在页面生命周期内展示。

import { ClashClient, ClashClientState, RpcMethod, RpcResult } from 'proxy_core';

type LogLevel = 'debug' | 'info' | 'warning' | 'error';

interface LogItem {
  level: LogLevel;
  time: string;
  payload: string;
}

/** 内核日志字段：实际 .so 推 logLevel/payload/time，旧实现推 type/payload，这里做兼容。 */
interface CoreLogMessage {
  type?: string;
  logLevel?: string;
  payload?: string;
  time?: number | string;
}

@Component
export struct LogsPage {
  @State level: string = 'info';
  @State items: LogItem[] = [];

  private client: ClashClient = ClashClient.getInstance();
  private messageHandler: (result: RpcResult) => void = (result: RpcResult) => this.onCoreMessage(result);
  levels: string[] = ['debug', 'info', 'warning', 'error'];

  aboutToAppear(): void {
    this.client.onMessage(this.messageHandler);
    if (this.client.getState() === ClashClientState.Connected) {
      this.client.request(RpcMethod.SetLogObserver).catch((error: Error) => {
        console.error('[LogsPage] 开启日志监听失败: ' + error.message);
      });
    }
  }

  aboutToDisappear(): void {
    this.client.offMessage(this.messageHandler);
    if (this.client.getState() === ClashClientState.Connected) {
      this.client.request(RpcMethod.StopLogObserver).catch((error: Error) => {
        console.error('[LogsPage] 停止日志监听失败: ' + error.message);
      });
    }
  }

  colorForLevel(level: string): ResourceColor {
    if (level === 'error') return $r('app.color.error');
    if (level === 'warning') return $r('app.color.warning');
    if (level === 'debug') return $r('app.color.text_tertiary');
    return $r('app.color.text_primary');
  }

  filteredItems(): LogItem[] {
    const threshold = this.levelIndex(this.level);
    return this.items.filter((item: LogItem) => this.levelIndex(item.level) >= threshold);
  }

  private onCoreMessage(result: RpcResult): void {
    if (result.method !== RpcMethod.SetLogObserver || !result.result) {
      return;
    }
    try {
      const message = JSON.parse(result.result) as CoreLogMessage;
      const levelText: string = message.logLevel ?? message.type ?? 'info';
      const item: LogItem = {
        level: this.normalizeLevel(levelText),
        time: this.messageTime(message.time),
        payload: message.payload ?? ''
      };
      const updated = this.items.concat(item);
      this.items = updated.length > 500 ? updated.slice(updated.length - 500) : updated;
    } catch (error) {
      console.error('[LogsPage] 日志格式错误: ' + (error as Error).message);
    }
  }

  private normalizeLevel(level: string): LogLevel {
    const normalized = level.toLowerCase();
    if (normalized === 'error' || normalized === 'fatal') return 'error';
    if (normalized === 'warning' || normalized === 'warn') return 'warning';
    if (normalized === 'debug' || normalized === 'trace') return 'debug';
    return 'info';
  }

  private levelIndex(level: string): number {
    if (level === 'debug') return 0;
    if (level === 'info') return 1;
    if (level === 'warning') return 2;
    return 3;
  }

  /** 内核 time 为 Unix 秒；兼容 RFC3339 字符串，缺失时用本地时间。 */
  private messageTime(value: number | string | undefined): string {
    if (typeof value === 'number' && value > 0) {
      const date = new Date(value * 1000);
      return `${this.twoDigits(date.getHours())}:${this.twoDigits(date.getMinutes())}:${this.twoDigits(date.getSeconds())}`;
    }
    if (typeof value === 'string' && value.length >= 19) {
      return value.substring(11, 19);
    }
    return this.currentTime();
  }

  private currentTime(): string {
    const date = new Date();
    return `${this.twoDigits(date.getHours())}:${this.twoDigits(date.getMinutes())}:${this.twoDigits(date.getSeconds())}`;
  }

  private twoDigits(value: number): string {
    return value < 10 ? `0${value}` : String(value);
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 8 }) {
          ForEach(this.levels, (lv: string) => {
            Text(lv.toUpperCase())
              .fontSize(12)
              .fontColor(this.level === lv ? Color.White : $r('app.color.text_secondary'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.level === lv ? $r('app.color.brand') : $r('app.color.container_background'))
              .borderRadius(14)
              .onClick(() => { this.level = lv; })
          })
        }.padding({ left: 12, right: 12, bottom: 8 }).width('100%')

        if (this.filteredItems().length === 0) {
          Column() {
            Text(this.client.getState() === ClashClientState.Connected ? '暂无日志' : '内核未连接')
              .fontSize(14).fontColor($r('app.color.text_tertiary'))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding({ bottom: 100 })
        } else {
          List({ space: 4 }) {
            ForEach(this.filteredItems(), (item: LogItem, index: number) => {
              ListItem() {
                Row({ space: 8 }) {
                  Text(item.level.toUpperCase()).fontSize(10).fontColor(this.colorForLevel(item.level)).width(56)
                  Text(item.time).fontSize(11).fontColor($r('app.color.text_tertiary')).width(64)
                  Text(item.payload).fontSize(12).layoutWeight(1).fontColor(this.colorForLevel(item.level))
                }.padding({ left: 12, right: 12, top: 6, bottom: 6 }).width('100%')
              }
            }, (item: LogItem, index: number) => `${item.time}-${index}`)
          }.layoutWeight(1).padding({ bottom: 112 }).scrollBar(BarState.Off)
        }
      }
      .width('100%').height('100%')
      .constraintSize({ maxWidth: 960 })
    }
    .title('日志')
    .menus([{ value: '清空', icon: $r('sys.symbol.trash'), action: () => { this.items = []; } }])
    .width('100%').height('100%').backgroundColor($r('app.color.background'))
  }
}
