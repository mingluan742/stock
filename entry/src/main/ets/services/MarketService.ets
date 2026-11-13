import { KLine } from '../models/KLine';
import { MarketRuleConfig, ScenarioData, ScenarioMeta } from '../models/Scenario';
import { ScenarioEvent } from '../models/ScenarioEvent';
import { IMarketDataSource } from '../repository/IMarketDataSource';

/**
 * 行情服务：管理"当前剧本 + 时间轴游标"
 * 职责：加载剧本、读取当前价格、推进交易日、触发事件
 * 不关心 UI，不关心数据来自哪里（依赖 IMarketDataSource 接口）
 */
export class MarketService {
  private source: IMarketDataSource;
  private data: ScenarioData | null = null;
  private cursor: number = 0;

  constructor(source: IMarketDataSource) {
    this.source = source;
  }

  /** 剧本目录 */
  async listScenarios(): Promise<ScenarioMeta[]> {
    return await this.source.listScenarios();
  }

  /** 加载剧本，游标归零 */
  async load(id: string): Promise<void> {
    this.data = await this.source.loadScenario(id);
    this.cursor = 0;
  }

  /** 直接载入一份现成的剧本数据（随机模拟使用） */
  loadData(data: ScenarioData): void {
    this.data = data;
    this.cursor = 0;
  }

  /** 剧本包含的历史事件数量 */
  get eventCount(): number {
    if (this.data === null) {
      return 0;
    }
    return this.data.events.length;
  }

  get loaded(): boolean {
    return this.data !== null;
  }

  get meta(): ScenarioMeta | null {
    if (this.data === null) {
      return null;
    }
    return this.data.meta;
  }

  get rules(): MarketRuleConfig | null {
    if (this.data === null) {
      return null;
    }
    return this.data.rules;
  }

  get currentBar(): KLine | null {
    if (this.data === null) {
      return null;
    }
    return this.data.timeline[this.cursor];
  }

  get totalDays(): number {
    if (this.data === null) {
      return 0;
    }
    return this.data.timeline.length;
  }

  get dayIndex(): number {
    return this.cursor;
  }

  get finished(): boolean {
    if (this.data === null) {
      return false;
    }
    return this.cursor >= this.data.timeline.length - 1;
  }

  /** 当日涨跌幅（相对前一交易日） */
  dayChangeRatio(): number {
    if (this.data === null || this.cursor === 0) {
      return 0;
    }
    const prev: number = this.data.timeline[this.cursor - 1].price;
    const cur: number = this.data.timeline[this.cursor].price;
    if (prev === 0) {
      return 0;
    }
    return (cur - prev) / prev;
  }

  /** 当前日期触发的历史事件 */
  eventsToday(): ScenarioEvent[] {
    if (this.data === null) {
      return [];
    }
    const date: string = this.data.timeline[this.cursor].date;
    const hits: ScenarioEvent[] = [];
    for (const e of this.data.events) {
      if (e.date === date) {
        hits.push(e);
      }
    }
    return hits;
  }

  /** 推进一个交易日，返回当天触发的事件 */
  advance(): ScenarioEvent[] {
    if (this.data === null) {
      return [];
    }
    if (this.cursor < this.data.timeline.length - 1) {
      this.cursor += 1;
    }
    return this.eventsToday();
  }

  /** 回到剧本开头 */
  restart(): void {
    this.cursor = 0;
  }
}