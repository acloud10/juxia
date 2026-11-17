// 句栖 · 显式刷新总线
// Store 的数据不是 ArkUI 可观察对象；隐藏 Tab 的 @Monitor 不保证触发。
// 这里让 Store.bump() 直接通知已挂载页面 reload，避免只能重启应用。
export class RefreshBus {
  private static listeners: Array<() => void> = [];

  static register(fn: () => void): void {
    if (RefreshBus.listeners.indexOf(fn) < 0) {
      RefreshBus.listeners.push(fn);
    }
  }

  static unregister(fn: () => void): void {
    const i: number = RefreshBus.listeners.indexOf(fn);
    if (i >= 0) {
      RefreshBus.listeners.splice(i, 1);
    }
  }

  static emit(): void {
    const copy: Array<() => void> = RefreshBus.listeners.slice();
    copy.forEach((fn: () => void) => {
      try {
        fn();
      } catch (e) {
        console.error('juxia refresh listener fail', String(e));
      }
    });
  }
}
