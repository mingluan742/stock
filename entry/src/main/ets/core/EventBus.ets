/**
 * 事件总线（观察者模式）
 * 用于"非状态类"的跨模块通知：成交、剧本事件、成就解锁……
 * 状态联动仍交给 @Observed / AppStorage，两者分工不重叠
 */
export class EventBus {
  private static handlers: Map<string, Array<(payload: string) => void>> =
    new Map<string, Array<(payload: string) => void>>();

  /** 订阅事件 */
  static on(event: string, handler: (payload: string) => void): void {
    let list = EventBus.handlers.get(event);
    if (list === undefined) {
      list = [];
      EventBus.handlers.set(event, list);
    }
    list.push(handler);
  }

  /** 取消订阅（页面 aboutToDisappear 时调用，防内存泄漏） */
  static off(event: string, handler: (payload: string) => void): void {
    const list = EventBus.handlers.get(event);
    if (list === undefined) {
      return;
    }
    const idx = list.indexOf(handler);
    if (idx >= 0) {
      list.splice(idx, 1);
    }
  }

  /** 发布事件 */
  static emit(event: string, payload: string = ''): void {
    const list = EventBus.handlers.get(event);
    if (list === undefined) {
      return;
    }
    for (const h of list) {
      h(payload);
    }
  }
}