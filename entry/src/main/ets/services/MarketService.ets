import { KLine } from '../models/KLine';
import { MarketRuleConfig, ScenarioData, ScenarioMeta, StockSpec } from '../models/Scenario';
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
  /** 多标的：当前选中的股票（null = 单标的模式用 data.timeline） */
  private currentStock: StockSpec | null = null;

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
    this.currentStock = data.stocks === undefined || data.stocks.length === 0 ? null : data.stocks[0];
  }

  /** 多标的清单（单标的模式返回空） */
  get stocks(): StockSpec[] {
    if (this.data === null || this.data.stocks === undefined) {
      return [];
    }
    return this.data.stocks;
  }

  /** 当前选中股票（单标的模式返回 null） */
  get activeStock(): StockSpec | null {
    return this.currentStock;
  }

  /** 切换选中股票，游标不重置：所有股票共用同一条时间线推进节奏 */
  selectStock(id: string): void {
    if (this.data === null || this.data.stocks === undefined) {
      return;
    }
    for (const s of this.data.stocks) {
      if (s.id === id) {
        this.currentStock = s;
        return;
      }
    }
  }

  /** 当前时间轴（多标的取选中股票的） */
  private timeline(): KLine[] {
    if (this.data === null) {
      return [];
    }
    if (this.currentStock !== null && this.data.stocks !== undefined) {
      return this.currentStock.timeline;
    }
    return this.data.timeline;
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
    const tl: KLine[] = this.timeline();
    if (tl.length === 0 || this.cursor >= tl.length) {
      return null;
    }
    return tl[this.cursor];
  }

  get totalDays(): number {
    return this.timeline().length;
  }

  get dayIndex(): number {
    return this.cursor;
  }

  /** 指定股票在指定下标的K线（多标的估值用；越界返回 null） */
  barAt(stockId: string, idx: number): KLine | null {
    if (this.data === null) {
      return null;
    }
    if (this.data.stocks !== undefined) {
      for (const s of this.data.stocks) {
        if (s.id === stockId) {
          if (idx < 0 || idx >= s.timeline.length) {
            return s.timeline[s.timeline.length - 1] ?? null;
          }
          return s.timeline[idx];
        }
      }
      return null;
    }
    if (idx < 0 || idx >= this.data.timeline.length) {
      return null;
    }
    return this.data.timeline[idx];
  }

  get finished(): boolean {
    const tl: KLine[] = this.timeline();
    if (tl.length === 0) {
      return false;
    }
    return this.cursor >= tl.length - 1;
  }

  /** 当日涨跌幅（相对前一交易日，按当前股票） */
  dayChangeRatio(): number {
    const tl: KLine[] = this.timeline();
    if (tl.length === 0 || this.cursor === 0) {
      return 0;
    }
    const prev: number = tl[this.cursor - 1].price;
    const cur: number = tl[this.cursor].price;
    if (prev === 0) {
      return 0;
    }
    return (cur - prev) / prev;
  }

  /** 当前日期触发的历史事件（多标的取选中股票的） */
  eventsToday(): ScenarioEvent[] {
    if (this.data === null) {
      return [];
    }
    const tl: KLine[] = this.timeline();
    if (tl.length === 0 || this.cursor >= tl.length) {
      return [];
    }
    const date: string = tl[this.cursor].date;
    const source: ScenarioEvent[] = this.currentStock !== null ? this.currentStock.events : this.data.events;
    const hits: ScenarioEvent[] = [];
    for (const e of source) {
      if (e.date === date) {
        hits.push(e);
      }
    }
    return hits;
  }

  /** 推进一个交易日，返回当天所有股票触发的事件（多标的时合并展示） */
  advance(): ScenarioEvent[] {
    if (this.data === null) {
      return [];
    }
    const maxLen: number = this.maxStockDays();
    if (this.cursor < maxLen - 1) {
      this.cursor += 1;
    }
    // 多标的：返回所有股票当天的事件（事件标题后自动带股票名）
    if (this.data.stocks !== undefined && this.data.stocks.length > 0) {
      const hits: ScenarioEvent[] = [];
      const date: string = this.timeline()[Math.min(this.cursor, this.timeline().length - 1)].date;
      for (const s of this.data.stocks) {
        for (const e of s.events) {
          if (e.date === date) {
            hits.push(e);
          }
        }
      }
      return hits;
    }
    return this.eventsToday();
  }

  /** 全部股票里最长的时间轴（多标的推进到最长的结束） */
  maxStockDays(): number {
    if (this.data === null) {
      return 0;
    }
    if (this.data.stocks === undefined || this.data.stocks.length === 0) {
      return this.data.timeline.length;
    }
    let max: number = 0;
    for (const s of this.data.stocks) {
      if (s.timeline.length > max) {
        max = s.timeline.length;
      }
    }
    return max;
  }

  /** 回到剧本开头 */
  restart(): void {
    this.cursor = 0;
  }

  /** 将时间轴游标移到指定位置（恢复快照用） */
  setCursor(n: number): void {
    const max: number = this.maxStockDays() - 1;
    let v: number = n;
    if (v < 0) {
      v = 0;
    }
    if (v > max) {
      v = max;
    }
    this.cursor = v;
  }

  /** 已走过的收盘价序列（恢复曲线用；多标的用最长序列，画图时用当前股票的） */
  historyPrices(): number[] {
    const out: number[] = [];
    const tl: KLine[] = this.timeline();
    for (let i = 0; i <= this.cursor && i < tl.length; i++) {
      out.push(tl[i].price);
    }
    return out;
  }

  /** 已走过的日期序列（复盘页做买卖点定位用） */
  historyDates(): string[] {
    const out: string[] = [];
    const tl: KLine[] = this.timeline();
    for (let i = 0; i <= this.cursor && i < tl.length; i++) {
      out.push(tl[i].date);
    }
    return out;
  }

  /** 已走过的所有历史事件（恢复事件列表用；多标的合并，带股票名） */
  eventsPassed(): ScenarioEvent[] {
    const out: ScenarioEvent[] = [];
    if (this.data === null) {
      return out;
    }
    const limit: number = Math.min(this.cursor, this.maxStockDays() - 1);
    if (this.data.stocks !== undefined && this.data.stocks.length > 0) {
      const passedDates: Set<string> = new Set<string>();
      for (const s of this.data.stocks) {
        for (let i = 0; i <= limit && i < s.timeline.length; i++) {
          passedDates.add(s.timeline[i].date);
        }
      }
      for (const s of this.data.stocks) {
        for (const e of s.events) {
          if (passedDates.has(e.date)) {
            out.push(e);
          }
        }
      }
    } else {
      const passedDates: Set<string> = new Set<string>();
      for (let i = 0; i <= limit && i < this.data.timeline.length; i++) {
        passedDates.add(this.data.timeline[i].date);
      }
      for (const e of this.data.events) {
        if (passedDates.has(e.date)) {
          out.push(e);
        }
      }
    }
    return out;
  }
}