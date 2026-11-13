import { KLine } from '../models/KLine';
import { MarketRuleConfig, ScenarioData, StockSpec } from '../models/Scenario';
import { ScenarioEvent } from '../models/ScenarioEvent';

/** 虚构股票名池（避免影射真实公司） */
const NAMES: string[] = ['星辰科技', '北湖酒业', '远山医药', '青禾能源', '南风物流', '拾光传媒', '白鹿电池', '流云半导体'];

/** 行业后缀池：用于起不同的代码 */
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

/**
 * 随机行情生成器：
 * 多标的模式：一次生成 3~5 只虚构股票，各自独立随机游走，
 * 突发消息挂到具体股票上；也保留单股票生成（供旧流程使用）。
 */
export class RandomScenarioService {

  /** 生成一局全新的多股票随机剧本 */
  generateMulti(): ScenarioData {
    const count: number = 3 + Math.floor(Math.random() * 3); // 3~5 只
    const days: number = 120 + Math.floor(Math.random() * 150); // 120~270 天
    // 全市场规则统一（同一交易所规则）
    const priceLimit: number = Math.random() < 0.5 ? 0.1 : 0;
    const rules: MarketRuleConfig = {
      priceLimit: priceLimit,
      tPlus: Math.random() < 0.7 ? 1 : 0,
      feeRate: 0.0005 + Math.random() * 0.001,
      shortSell: priceLimit === 0
    };

    // 用后缀区分选股：随机抽 count 个不同的名字
    const pool: string[] = NAMES.slice();
    const stocks: StockSpec[] = [];
    for (let i = 0; i < count; i++) {
      const ni: number = Math.floor(Math.random() * pool.length);
      const name: string = pool.splice(ni, 1)[0];
      // 波动率 2~4%（随机盘比历史更活跃一些）
      const timeline: KLine[] = this.walk(days, 0.02 + Math.random() * 0.02);
      // 每只 1~2 条突发消息
      const events: ScenarioEvent[] = this.randomEvents(1 + Math.floor(Math.random() * 2), timeline, i);
      stocks.push({
        id: `rnd-stock-${i}`,
        code: `${CODE_PREFIX[Math.floor(Math.random() * CODE_PREFIX.length)]}${(1000 + Math.floor(Math.random() * 8999))}`,
        name: name,
        timeline: timeline,
        events: events
      });
    }

    // 主时间轴取第一只，保证向后兼容的单标的逻辑还能用
    return {
      meta: {
        id: `random-${Date.now()}`,
        name: stocks[0].name,
        era: '虚拟市场 · 随机生成',
        benchmark: '模拟个股 · 多标的',
        intro: `一局同时交易 ${count} 只随机生成的股票。每只走势独立，突发消息只影响个股——观察板块轮动，练习分散仓位。`
      },
      rules: rules,
      timeline: stocks[0].timeline,
      events: stocks[0].events,
      stocks: stocks
    };
  }

  /** 用第一只股票的时间轴生成（向后兼容旧调用） */
  generate(): ScenarioData {
    return this.generateMulti();
  }

  /** 生成一段几何随机游走（分段牛熊） */
  private walk(days: number, vol: number): KLine[] {
    let price: number = 15 + Math.random() * 85;
    let drift: number = (Math.random() - 0.45) * 0.006;
    let segLeft: number = 40 + Math.floor(Math.random() * 50);
    const timeline: KLine[] = [];
    const d: Date = new Date(2026, 0, 5);

    while (timeline.length < days) {
      d.setDate(d.getDate() + 1);
      const wd: number = d.getDay();
      if (wd === 0 || wd === 6) {
        continue;
      }
      if (segLeft <= 0) {
        drift = (Math.random() - 0.45) * 0.008;
        segLeft = 40 + Math.floor(Math.random() * 60);
      }
      segLeft -= 1;
      const ret: number = drift + (Math.random() - 0.5) * 2 * vol * (0.5 + Math.random());
      price = price * (1 + ret);
      if (price < 1) {
        price = 1;
      }
      if (price > 500) {
        price = 500;
      }
      timeline.push({
        date: this.fmt(d),
        price: Math.round(price * 100) / 100,
        note: ''
      });
    }
    return timeline;
  }

  /** 随机消息事件，cardId 带股票序号 */
  private randomEvents(cnt: number, timeline: KLine[], stockIdx: number): ScenarioEvent[] {
    const events: ScenarioEvent[] = [];
    const used: number[] = [];
    for (let k = 0; k < cnt; k++) {
      let idx: number = 10 + Math.floor(Math.random() * (timeline.length - 15));
      while (used.indexOf(idx) >= 0) {
        idx += 1;
        if (idx >= timeline.length) {
          idx = 10;
        }
      }
      used.push(idx);
      const ei: number = Math.floor(Math.random() * EVENT_TITLES.length);
      events.push({
        date: timeline[idx].date,
        title: EVENT_TITLES[ei],
        desc: EVENT_DESCS[ei],
        cardId: `rnd-${stockIdx}-${k}`
      });
    }
    events.sort((a: ScenarioEvent, b: ScenarioEvent) => a.date < b.date ? -1 : 1);
    return events;
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