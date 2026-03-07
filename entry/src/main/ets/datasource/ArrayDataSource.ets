export class ArrayDataSource<T> implements IDataSource {
  private listeners: DataChangeListener[] = []
  private dataArray: T[] = []

  constructor(data: T[] = []) {
    this.dataArray = data.slice()
  }

  totalCount(): number {
    return this.dataArray.length
  }

  getData(index: number): T {
    return this.dataArray[index]
  }

  getAllData(): T[] {
    return this.dataArray.slice()
  }

  setData(data: T[]): void {
    this.dataArray = data.slice()
    this.notifyDataReload()
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener)
    if (index >= 0) {
      this.listeners.splice(index, 1)
    }
  }

  private notifyDataReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}
