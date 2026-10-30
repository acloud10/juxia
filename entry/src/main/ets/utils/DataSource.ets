// 句栖 · 轻量 LazyForEach 数据源
export class ArrayDataSource<T> implements IDataSource {
  private data: T[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.data.length;
  }

  getData(index: number): T {
    return this.data[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i: number = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }

  setData(arr: T[]): void {
    this.data = arr;
    this.listeners.forEach((l: DataChangeListener) => {
      l.onDataReloaded();
    });
  }

  notifyChange(index: number): void {
    if (index < 0 || index >= this.data.length) return;
    this.listeners.forEach((l: DataChangeListener) => {
      l.onDataChange(index);
    });
  }

  notifyAll(): void {
    for (let i = 0; i < this.data.length; i++) {
      this.listeners.forEach((l: DataChangeListener) => {
        l.onDataChange(i);
      });
    }
  }
}


