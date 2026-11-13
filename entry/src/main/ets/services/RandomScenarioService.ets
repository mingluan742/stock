import { KLine } from '../models/KLine';
import { MarketRuleConfig, ScenarioData } from '../models/Scenario';
import { ScenarioEvent } from '../models/ScenarioEvent';

/** 虚构股票名池（避免影射真实公司） */
const NAMES: string[] = ['星辰科技', '北湖酒业', '远山医药', '青禾能源', '南风物流', '拾光传媒', '白鹿电池', '流云半导体'];

/**
 * 随机行情生成器：
 * 用几何随机游走生成走势，分段切换牛熊趋势，
 * 随机插入突发消息事件，规则也随机（是否涨跌停、T+0/T+1）
 */
export class RandomScenarioService {

  /** 生成一局全新的随机剧本 */
  generate(): ScenarioData {
    const days: number = 260 + Math.floor(Math.random() * 180);
    const vol: number = 0.012 + Math.random() * 0.018;
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
        // 切换趋势段：牛市 / 震荡 / 熊市
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

    // 随机突发消息 3~5 条
    const events: ScenarioEvent[] = [];
    const titles: string[] = ['业绩超预期', '突发利空', '机构席位集中买入', '大股东减持', '行业政策利好', '财报被质疑'];
    const descs: string[] = [
      '季报净利润同比大幅超出预期，资金开始抢筹，股价放量上行。',
      '供应链传出不利消息，盘中出现集中抛售，短时间跌幅明显。',
      '龙虎榜显示机构席位连续三日净买入，市场情绪被点燃。',
      '大股东公告拟减持不超过 3% 股份，市场情绪转弱。',
      '行业迎来政策支持，板块集体走强，个股跟随上涨。',
      '财报关键数据被质疑，股价盘中剧烈震荡，多空分歧加大。'
    ];
    const cnt: number = 3 + Math.floor(Math.random() * 3);
    const used: number[] = [];
    for (let k = 0; k < cnt; k++) {
      let idx: number = 20 + Math.floor(Math.random() * (days - 30));
      while (used.indexOf(idx) >= 0) {
        idx = idx + 1;
        if (idx >= days) {
          idx = 20;
        }
      }
      used.push(idx);
      events.push({
        date: timeline[idx].date,
        title: titles[Math.floor(Math.random() * titles.length)],
        desc: descs[Math.floor(Math.random() * descs.length)],
        cardId: `rnd-${k}`
      });
    }
    events.sort((a: ScenarioEvent, b: ScenarioEvent) => a.date < b.date ? -1 : 1);

    // 随机市场规则
    const priceLimit: number = Math.random() < 0.5 ? 0.1 : 0;
    const rules: MarketRuleConfig = {
      priceLimit: priceLimit,
      tPlus: Math.random() < 0.7 ? 1 : 0,
      feeRate: 0.0005 + Math.random() * 0.001,
      shortSell: priceLimit === 0
    };

    const name: string = NAMES[Math.floor(Math.random() * NAMES.length)];

    return {
      meta: {
        id: `random-${Date.now()}`,
        name: name,
        era: '虚拟市场 · 随机生成',
        benchmark: '模拟个股',
        intro: '这是一段算法即时生成的行情：走势、波动、突发消息都无法预测，没有历史答案可以对照。观察趋势、控制仓位，看看你的判断能否穿过未知的牛熊。'
      },
      rules: rules,
      timeline: timeline,
      events: events
    };
  }

  private fmt(d: Date): string {
    const y: number = d.getFullYear();
    const m: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const mm: string = m < 10 ? `0${m}` : `${m}`;
    const dd: string = day < 10 ? `0${day}` : `${day}`;
    return `${y}-${mm}-${dd}`;
  }
}