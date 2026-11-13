import { AppConfig } from '../config/AppConfig';
import { AchievementContext, AchievementDef, AchievementItem } from '../models/Achievement';

/** 跨局累计统计 */
export interface AchievementStats {
  /** 完成的对局数 */
  rounds: number;
  /** 累计成交笔数 */
  trades: number;
  /** 累计爆仓次数 */
  bankruptcies: number;
}

/** 持久化结构 */
interface AchievementSave {
  ids: string[];
  stats: AchievementStats;
}

/** 成就静态清单（顺序即展示顺序） */
const ACHIEVEMENTS: AchievementDef[] = [
  {
    id: 'first-buy', name: '第一次出手', icon: '✦', tier: 0,
    desc: '完成第一笔买入'
  },
  {
    id: 'first-sell', name: '落袋为安', icon: '✓', tier: 0,
    desc: '完成第一笔卖出'
  },
  {
    id: 'short-seller', name: '逆向思维', icon: '↓', tier: 1,
    desc: '第一次做空，在下跌中持仓'
  },
  {
    id: 'debtor', name: '负债经营', icon: '¥', tier: 0,
    desc: '累计借款达到 100 万'
  },
  {
    id: 'lev-20', name: '刀口舔血', icon: '⚡', tier: 1,
    desc: '使用 20 倍及以上杠杆'
  },
  {
    id: 'lev-50', name: '五十倍狂热', icon: '☄', tier: 2,
    desc: '把杠杆推到 50 倍的极限'
  },
  {
    id: 'bankrupt', name: '归零体验', icon: '✕', tier: 1,
    desc: '经历一次爆仓'
  },
  {
    id: 'survivor', name: '穿越周期', icon: '◈', tier: 0,
    desc: '完整走完一个剧本且没有爆仓'
  },
  {
    id: 'zero-trade', name: '空仓到底', icon: '○', tier: 1,
    desc: '一局零交易走完全程'
  },
  {
    id: 'trader-20', name: '短线刺客', icon: '≡', tier: 1,
    desc: '单局成交达到 20 笔'
  },
  {
    id: 'win-70', name: '手感不错', icon: '▲', tier: 1,
    desc: '卖出 5 笔以上且胜率不低于 70%'
  },
  {
    id: 'rich', name: '第一个百万', icon: '★', tier: 2,
    desc: '净资产达到 150 万'
  },
  {
    id: 'loss-half', name: '学费交足', icon: '▼', tier: 0,
    desc: '单局亏损超过 50%'
  },
  {
    id: 'drawdown', name: '回撤控制', icon: '◇', tier: 1,
    desc: '成交 5 笔以上、走完全程且最大回撤不超过 5%'
  },
  {
    id: 'veteran', name: '老练的旁观者', icon: '♛', tier: 2,
    desc: '累计完成 5 局'
  }
];

/**
 * 成就服务：
 * - 静态清单 + 动态解锁状态
 * - 解锁状态与跨局统计持久化在 AppStorage（PersistentStorage 绑定）
 * - 判定输入是一局的实时快照（AchievementContext），不改动业务服务
 */
export class AchievementService {
  static readonly KEY: string = 'stock_achievements';

  private unlockedIds: string[] = [];
  /** 本局新解锁（用于结算页展示） */
  private sessionIds: string[] = [];
  private stats: AchievementStats = { rounds: 0, trades: 0, bankruptcies: 0 };
  private loaded: boolean = false;

  /** 从 AppStorage 读取（首次访问时调用） */
  load(): void {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const raw: string | undefined = AppStorage.get<string>(AchievementService.KEY);
      if (raw === undefined || raw === '') {
        return;
      }
      const data = JSON.parse(raw) as AchievementSave;
      this.unlockedIds = data.ids === undefined ? [] : data.ids;
      if (data.stats !== undefined) {
        this.stats = data.stats;
      }
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] 成就读取失败: ${e.message}`);
    }
  }

  private persist(): void {
    try {
      const data: AchievementSave = { ids: this.unlockedIds, stats: this.stats };
      AppStorage.setOrCreate<string>(AchievementService.KEY, JSON.stringify(data));
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] 成就写入失败: ${e.message}`);
    }
  }

  /** 开始新一局：清空"本局新解锁" */
  startSession(): void {
    this.load();
    this.sessionIds = [];
  }

  /** 是否已解锁 */
  has(id: string): boolean {
    return this.unlockedIds.indexOf(id) >= 0;
  }

  /** 已解锁数量 */
  get unlockedCount(): number {
    this.load();
    return this.unlockedIds.length;
  }

  /** 成就总数 */
  get totalCount(): number {
    return ACHIEVEMENTS.length;
  }

  /** 全部成就（带解锁状态） */
  list(): AchievementItem[] {
    this.load();
    const out: AchievementItem[] = [];
    for (const d of ACHIEVEMENTS) {
      out.push({
        id: d.id,
        name: d.name,
        desc: d.desc,
        icon: d.icon,
        tier: d.tier,
        unlocked: this.has(d.id)
      });
    }
    return out;
  }

  /** 本局新解锁的成就 */
  sessionUnlocked(): AchievementItem[] {
    const out: AchievementItem[] = [];
    for (const id of this.sessionIds) {
      for (const d of ACHIEVEMENTS) {
        if (d.id === id) {
          out.push({ id: d.id, name: d.name, desc: d.desc, icon: d.icon, tier: d.tier, unlocked: true });
        }
      }
    }
    return out;
  }

  /** 判定并解锁，返回本次新解锁的成就 */
  check(ctx: AchievementContext): AchievementDef[] {
    this.load();
    const gained: AchievementDef[] = [];
    for (const d of ACHIEVEMENTS) {
      if (this.has(d.id)) {
        continue;
      }
      if (this.evaluate(d.id, ctx)) {
        this.unlockedIds.push(d.id);
        this.sessionIds.push(d.id);
        gained.push(d);
      }
    }
    if (gained.length > 0) {
      this.persist();
    }
    return gained;
  }

  /** 一局结束：累计统计并再判定一次（如"完成 5 局"） */
  finishRound(ctx: AchievementContext): AchievementDef[] {
    this.load();
    this.stats.rounds += 1;
    this.stats.trades += ctx.tradeCount;
    if (ctx.bankrupt) {
      this.stats.bankruptcies += 1;
    }
    this.persist();
    return this.check(ctx);
  }

  /** 跨局累计 */
  get statsSnapshot(): AchievementStats {
    this.load();
    return this.stats;
  }

  private evaluate(id: string, c: AchievementContext): boolean {
    const init: number = AppConfig.INIT_CASH;
    if (id === 'first-buy') {
      return c.buyCount >= 1;
    }
    if (id === 'first-sell') {
      return c.sellCount >= 1;
    }
    if (id === 'short-seller') {
      return c.shares < 0;
    }
    if (id === 'debtor') {
      return c.totalBorrowed >= 1000000;
    }
    if (id === 'lev-20') {
      return c.maxLeverage >= 20;
    }
    if (id === 'lev-50') {
      return c.maxLeverage >= 50;
    }
    if (id === 'bankrupt') {
      return c.bankrupt;
    }
    if (id === 'survivor') {
      return c.finished && !c.bankrupt;
    }
    if (id === 'zero-trade') {
      return c.finished && c.tradeCount === 0;
    }
    if (id === 'trader-20') {
      return c.tradeCount >= 20;
    }
    if (id === 'win-70') {
      return c.sellCount >= 5 && c.winRate >= 0.7;
    }
    if (id === 'rich') {
      return c.netAsset >= init * 1.5;
    }
    if (id === 'loss-half') {
      return c.netAsset <= init * 0.5;
    }
    if (id === 'drawdown') {
      return c.finished && c.tradeCount >= 5 && c.maxDrawdown <= 0.05;
    }
    if (id === 'veteran') {
      return this.stats.rounds >= 5;
    }
    return false;
  }
}