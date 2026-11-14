import { KLine } from '../models/KLine';
import { MarketRuleConfig, StockSpec } from '../models/Scenario';
import { ScenarioEvent } from '../models/ScenarioEvent';

/** 虚构股票名池（避免影射真实公司） */
const NAMES: string[] = ['星辰科技', '北湖酒业', '远山医药', '青禾能源', '南风物流', '拾光传媒', '白鹿电池', '流云半导体'];

/** 行业前缀池：用于生成不同的代码 */
const CODE_PREFIX: string[] = ['SH60', 'SZ00', 'SH68', 'SZ30'];

const EVENT_TITLES: string[] = ['业绩超预期', '突发利空', '机构席位集中买入', '大股东减持', '行业政策利好', '财报被质疑'];
const EVENT_DESCS: string[] = [
  '季报净利润同比大幅超出预期，资金开始抢筹，股价放量上行。',
  '供应链传出不利消息，盘中出现集中抛售，短时间跌幅明显。',
  '龙虎榜显示机构席位连续三日净买入，市场情绪被点燃。',
  '大股东公告拟减持不超过 3% 股份，市场情绪转弱。',
  '行业迎来政策支持，板块集体走强，个股跟随上涨。',
  '财报关键数据被质疑，股价盘中剧烈震荡，多空分歧加大。'
];

/** 单只股票的生成状态（随机游走参数） */
export interface LiveStockState {
  price: number;
  drift: number;
  vol: number;
  segLeft: number;
}

/** 活市场存档结构 */
export interface LiveSave {
  rules: MarketRuleConfig;
  dateISO: string;
  dayCount: number;
  stocks: LiveStockSave[];
}

export interface LiveStockSave {
  id: string;
  code: string;
  name: string;
  timeline: KLine[];
  events: ScenarioEvent[];
  state: LiveStockState;
}

/**
 * 活的随机市场：
 * 与"预生成固定剧本"不同，这里每天实时生成下一根K线，
 * 永不落幕，直到用户主动结束。可序列化以便存档续玩。
 */
export class LiveRandomMarket {
  stocks: StockSpec[] = [];
  rules: MarketRuleConfig = { priceLimit: 0, tPlus: 1, feeRate: 0.0008, shortSell: false };
  dayCount: number = 0;
  private currentDate: Date = new Date(2026, 0, 5);
  private states: LiveStockState[] = [];

  /** 初始化 n 只股票（3~5 只） */
  init(n: number): void {
    const pool: string[] = NAMES.slice();
    // 全市场规则统一
    const priceLimit: number = Math.random() < 0.5 ? 0.1 : 0;
    this.rules = {
      priceLimit: priceLimit,
      tPlus: Math.random() < 0.7 ? 1 : 0,
      feeRate: 0.0005 + Math.random() * 0.001,
      shortSell: priceLimit === 0
    };
    for (let i = 0; i < n; i++) {
      const ni: number = Math.floor(Math.random() * pool.length);
      const name: string = pool.splice(ni, 1)[0];
      const code: string = `${CODE_PREFIX[Math.floor(Math.random() * CODE_PREFIX.length)]}${1000 + Math.floor(Math.random() * 8999)}`;
      const sp: StockSpec = {
        id: `rnd-stock-${i}`,
        code: code,
        name: name,
        timeline: [],
        events: []
      };
      this.stocks.push(sp);
      this.states.push({
        price: 15 + Math.random() * 85,
        drift: (Math.random() - 0.45) * 0.006,
        vol: 0.02 + Math.random() * 0.02,
        segLeft: 40 + Math.floor(Math.random() * 50)
      });
    }
  }

  /** 推进一个交易日：生成每只股票的新价格，随机触发消息 */
  nextDay(): ScenarioEvent[] {
    // 跳过周末
    do {
      this.currentDate.setDate(this.currentDate.getDate() + 1);
    } while (this.currentDate.getDay() === 0 || this.currentDate.getDay() === 6);
    this.dayCount += 1;
    const date: string = this.fmt(this.currentDate);
    const events: ScenarioEvent[] = [];
    for (let i = 0; i < this.states.length; i++) {
      const st: LiveStockState = this.states[i];
      if (st.segLeft <= 0) {
        // 切换趋势段：牛市 / 震荡 / 熊市
        st.drift = (Math.random() - 0.45) * 0.008;
        st.segLeft = 40 + Math.floor(Math.random() * 60);
      }
      st.segLeft -= 1;
      const ret: number = st.drift + (Math.random() - 0.5) * 2 * st.vol * (0.5 + Math.random());
      st.price = st.price * (1 + ret);
      if (st.price < 1) {
        st.price = 1;
      }
      if (st.price > 500) {
        st.price = 500;
      }
      const sp: StockSpec = this.stocks[i];
      const kline: KLine = { date: date, price: Math.round(st.price * 100) / 100, note: '' };
      sp.timeline.push(kline);
      // 突发消息：每天每只约 5% 概率
      if (Math.random() < 0.05) {
        const ei: number = Math.floor(Math.random() * EVENT_TITLES.length);
        const e: ScenarioEvent = {
          date: date,
          title: EVENT_TITLES[ei],
          desc: EVENT_DESCS[ei],
          cardId: `live-${i}-${sp.events.length}`
        };
        sp.events.push(e);
        // 展示用副本带股票名
        events.push({ date: e.date, title: `[${sp.name}] ${e.title}`, desc: e.desc, cardId: e.cardId });
      }
    }
    return events;
  }

  /** 序列化（存档用） */
  serialize(): LiveSave {
    const out: LiveStockSave[] = [];
    for (let i = 0; i < this.stocks.length; i++) {
      const sp: StockSpec = this.stocks[i];
      out.push({
        id: sp.id,
        code: sp.code,
        name: sp.name,
        timeline: sp.timeline,
        events: sp.events,
        state: this.states[i]
      });
    }
    return {
      rules: this.rules,
      dateISO: this.currentDate.toISOString(),
      dayCount: this.dayCount,
      stocks: out
    };
  }

  /** 从存档恢复 */
  static restore(save: LiveSave): LiveRandomMarket {
    const m: LiveRandomMarket = new LiveRandomMarket();
    m.rules = save.rules;
    m.currentDate = new Date(save.dateISO);
    m.dayCount = save.dayCount;
    m.stocks = [];
    m.states = [];
    for (const s of save.stocks) {
      m.stocks.push({ id: s.id, code: s.code, name: s.name, timeline: s.timeline, events: s.events });
      m.states.push(s.state);
    }
    return m;
  }

  private fmt(d: Date): string {
    const y: string = `${d.getFullYear()}`;
    const m: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const mm: string = m < 10 ? `0${m}` : `${m}`;
    const dd: string = day < 10 ? `0${day}` : `${day}`;
    return `${y}-${mm}-${dd}`;
  }
}

/**
 * 随机行情服务（门面）：
 * 随机盘现在是"活市场"——每天实时生成下一根K线，永不落幕
 */
export class RandomScenarioService {

  /** 生成一局全新的活市场（3~5 只股票） */
  generateLive(): LiveRandomMarket {
    const count: number = 3 + Math.floor(Math.random() * 3);
    const m: LiveRandomMarket = new LiveRandomMarket();
    m.init(count);
    return m;
  }
}