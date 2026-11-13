import { AppConfig } from '../config/AppConfig';
import { Result } from '../core/Result';
import { Account } from '../models/Account';
import { MarketRuleConfig } from '../models/Scenario';
import { TradeRecord } from '../models/TradeRecord';

/** 单只股票的持仓（多标的模式） */
interface Position {
  shares: number;
  cost: number;
  /** T+1：当日买入股数 */
  todayBought: number;
}

/** 账户快照（持久化 / 恢复用） */
export interface AccountSnapshot {
  cash: number;
  shares: number;
  cost: number;
  loanPrincipal: number;
  leveragePrincipal: number;
  loanInterest: number;
  feeTotal: number;
  /** 交易流水（旧存档可能缺失） */
  records?: TradeRecord[];
  /** 净值峰值（旧存档可能缺失） */
  peak?: number;
  /** 最大回撤（旧存档可能缺失） */
  maxDrawdown?: number;
  /** 多标的：每只股票的持仓（旧存档缺失） */
  positions?: Record<string, Position>;
}

/** 涨跌停判定容差：达到限制的 95% 视为封板 */
const LIMIT_TOLERANCE: number = 0.95;

/**
 * 交易服务（门面）：校验 + 记账
 * 按剧本规则生效：
 * - feeRate：买卖双边收取手续费
 * - tPlus：T+1 时当日买入不可卖出
 * - priceLimit：涨停买不进、跌停卖不出
 * - shortSell：允许先卖后买（负持仓）
 * 持仓成本统一记"总成本"，空头成本为负数，卖出/买入平仓时按均价结转
 */
export class TradingService {
  private account: Account = new Account();
  private rules: MarketRuleConfig = { priceLimit: 0, tPlus: 0, feeRate: 0, shortSell: false };
  /** 单标的模式的当日买入股数（T+1 用） */
  private todayBought: number = 0;
  private lastDate: string = '';
  private feeTotalValue: number = 0;
  /** 贷款本金（普通借款） */
  private loanPrincipal: number = 0;
  /** 杠杆融资本本 */
  private leveragePrincipal: number = 0;
  /** 累计未还利息 */
  private loanInterest: number = 0;
  /** 交易流水 */
  private records: TradeRecord[] = [];
  /** 净值峰值（计算最大回撤） */
  private peakNetValue: number = 0;
  /** 最大回撤（0~1） */
  private maxDrawdownValue: number = 0;
  /** 本局用过的最高杠杆倍数（成就判定用） */
  private maxLeverageValue: number = 1;
  /** 本局累计借款金额（成就判定用） */
  private totalBorrowedValue: number = 0;
  /** 多标的：按股票 id 独立持仓；空 = 单标的模式 */
  private positions: Map<string, Position> | null = null;

  /** 多标的模式：启用按股票独立记账 */
  enableMultiStock(ids: string[]): void {
    this.positions = new Map<string, Position>();
    for (const id of ids) {
      this.positions.set(id, { shares: 0, cost: 0, todayBought: 0 });
    }
  }

  /** 当前股票的持仓（单标的模式返回主账户） */
  private pos(stockId: string | null): Position {
    if (this.positions !== null && stockId !== null) {
      const p: Position | undefined = this.positions.get(stockId);
      if (p !== undefined) {
        return p;
      }
    }
    // 单标的：借用主账户的仓位（用包装对象避免改 Account）
    if (this.singlePos === null) {
      this.singlePos = { shares: this.account.shares, cost: this.account.cost, todayBought: this.todayBought };
    }
    return this.singlePos;
  }

  private singlePos: Position | null = null;

  /** 把孥位写回主账户（单标的模式专用） */
  private syncSingle(): void {
    if (this.positions === null && this.singlePos !== null) {
      this.account.shares = this.singlePos.shares;
      this.account.cost = this.singlePos.cost;
      this.todayBought = this.singlePos.todayBought;
    }
  }

  /** 切换剧本规则并重置账户 */
  setRules(rules: MarketRuleConfig): void {
    this.rules = rules;
    this.reset();
  }

  /** 行情推进到新交易日：重置 T+1 计数，并对贷款计息（复利） */
  newDay(date: string): void {
    if (date !== this.lastDate) {
      this.lastDate = date;
      this.todayBought = 0;
      if (this.singlePos !== null) {
        this.singlePos.todayBought = 0;
      }
      if (this.positions !== null) {
        for (const id of this.positions.keys()) {
          const p: Position = this.positions.get(id) as Position;
          p.todayBought = 0;
        }
      }
      const principalAndInterest: number = this.loanPrincipal + this.leveragePrincipal + this.loanInterest;
      if (principalAndInterest > 0) {
        this.loanInterest += principalAndInterest * AppConfig.DAILY_LOAN_RATE;
      }
    }
  }

  /** 借入资金（计入债务，现金立即到账） */
  borrow(amount: number): Result<Account> {
    if (amount <= 0) {
      return Result.fail<Account>('借款金额必须大于 0');
    }
    if (amount > this.loanAvailable) {
      return Result.fail<Account>(`超出可借额度（剩余 ${Math.round(this.loanAvailable)}）`);
    }
    this.account.cash += amount;
    this.loanPrincipal += amount;
    this.totalBorrowedValue += amount;
    return Result.success(this.account);
  }

  /** 还款：现金扣减，先冲抵杠杆融资，再冲抵普通借款，最后冲利息 */
  repay(amount: number): Result<Account> {
    if (amount <= 0) {
      return Result.fail<Account>('还款金额必须大于 0');
    }
    if (this.debt <= 0) {
      return Result.fail<Account>('当前没有贷款');
    }
    if (amount > this.account.cash) {
      return Result.fail<Account>('现金不足，无法还款');
    }
    const actual: number = Math.min(amount, this.debt);
    this.account.cash -= actual;
    let remain: number = actual;
    const payLev: number = Math.min(remain, this.leveragePrincipal);
    this.leveragePrincipal -= payLev;
    remain -= payLev;
    const payLoan: number = Math.min(remain, this.loanPrincipal);
    this.loanPrincipal -= payLoan;
    remain -= payLoan;
    this.loanInterest -= remain;
    if (this.loanInterest < 0) {
      this.loanInterest = 0;
    }
    return Result.success(this.account);
  }

  /**
   * 买入：涨停封板不可买
   * leverage > 1 时按保证金交易，不足部分自动融资（计入负债）
   * stockId：多标的模式指定目标股票，单标的传 null
   */
  buy(price: number, qty: number, dayRatio: number, leverage: number = 1, stockId: string | null = null): Result<Account> {
    if (price <= 0) {
      return Result.fail<Account>('行情未就绪');
    }
    if (qty <= 0) {
      return Result.fail<Account>('数量必须大于 0');
    }
    if (this.rules.priceLimit > 0 && dayRatio >= this.rules.priceLimit * LIMIT_TOLERANCE) {
      return Result.fail<Account>('涨停封板，买不进');
    }
    const amount: number = price * qty;
    const fee: number = amount * this.rules.feeRate;

    if (leverage <= 1) {
      if (this.account.cash < amount + fee) {
        return Result.fail<Account>('现金不足（含手续费）');
      }
    } else {
      // 杠杆：按倍数强制配资，自有资金只承担保证金（最高 50 倍）
      const lev: number = Math.min(leverage, AppConfig.MAX_LEVERAGE);
      if (lev > this.maxLeverageValue) {
        this.maxLeverageValue = lev;
      }
      const margin: number = amount / lev;
      if (this.account.cash < margin + fee) {
        return Result.fail<Account>(`保证金不足，需 ${Math.round(margin + fee)}`);
      }
      const borrowAmt: number = amount - margin;
      if (this.debt + borrowAmt > AppConfig.MAX_DEBT) {
        return Result.fail<Account>('融资金额超出总债务上限');
      }
      this.account.cash += borrowAmt;
      this.leveragePrincipal += borrowAmt;
    }

    const p: Position = this.pos(stockId);
    // 若当前是空头，先按均价平空，剩余部分转为多头
    const closeQty: number = Math.min(qty, Math.max(0, -p.shares));
    const openQty: number = qty - closeQty;
    const shortAvg: number = p.shares === 0 ? 0 : p.cost / p.shares;
    if (closeQty > 0) {
      p.cost += shortAvg * closeQty;
    }
    if (openQty > 0) {
      p.cost += price * openQty;
    }
    this.account.cash -= amount + fee;
    p.shares += qty;
    if (p.shares === 0) {
      p.cost = 0;
    }

    // T+1：只有开多方向计入今日买入
    if (this.rules.tPlus === 1 && openQty > 0) {
      p.todayBought += openQty;
    }
    this.feeTotalValue += fee;
    // 平空部分已实现盈亏
    const realized: number = closeQty > 0 ? (shortAvg - price) * closeQty : 0;
    this.records.push({
      date: this.lastDate,
      side: '买',
      price: price,
      qty: qty,
      fee: fee,
      amount: amount,
      realized: realized
    });
    this.syncSingle();
    return Result.success(this.account);
  }

  /** 卖出：跌停封板不可卖，持仓/T+1/做空规则校验 */
  sell(price: number, qty: number, dayRatio: number, stockId: string | null = null): Result<Account> {
    if (price <= 0) {
      return Result.fail<Account>('行情未就绪');
    }
    if (qty <= 0) {
      return Result.fail<Account>('数量必须大于 0');
    }
    if (this.rules.priceLimit > 0 && dayRatio <= -this.rules.priceLimit * LIMIT_TOLERANCE) {
      return Result.fail<Account>('跌停封板，卖不出');
    }

    const p: Position = this.pos(stockId);
    if (!this.rules.shortSell) {
      // 不可做空：只能卖已有持仓，且 T+1 下当日买入部分冻结
      let sellable: number = p.shares;
      if (this.rules.tPlus === 1) {
        sellable = sellable - p.todayBought;
      }
      if (qty > Math.max(0, sellable)) {
        if (this.rules.tPlus === 1 && p.todayBought > 0 && p.shares >= qty) {
          return Result.fail<Account>('T+1：今日买入的仓位不可卖出');
        }
        return Result.fail<Account>('持仓不足');
      }
    }

    const amount: number = price * qty;
    const fee: number = amount * this.rules.feeRate;
    // 多头部分按均价结转成本，超出部分转为空头按卖出价记成本
    const closeQty: number = Math.min(qty, Math.max(0, p.shares));
    const openQty: number = qty - closeQty;
    // 新开空头的敞口上限：做空市值 ≤ 净资产 × 最大杠杆（多标的按选中股票的现价折算）
    if (openQty > 0) {
      const cap: number = this.netAsset(price) * AppConfig.MAX_LEVERAGE;
      if (openQty * price > cap) {
        return Result.fail<Account>(`做空规模超出净资产 ${AppConfig.MAX_LEVERAGE} 倍上限`);
      }
    }
    const longAvg: number = p.shares === 0 ? 0 : p.cost / p.shares;
    if (closeQty > 0) {
      p.cost -= longAvg * closeQty;
    }
    if (openQty > 0) {
      p.cost -= price * openQty;
    }
    this.account.cash += amount - fee;
    p.shares -= qty;
    if (p.shares === 0) {
      p.cost = 0;
    }
    this.feeTotalValue += fee;
    // 平多部分已实现盈亏（相对持仓均价）
    const realized: number = closeQty > 0 ? (price - longAvg) * closeQty : 0;
    this.records.push({
      date: this.lastDate,
      side: '卖',
      price: price,
      qty: qty,
      fee: fee,
      amount: amount,
      realized: realized
    });
    this.syncSingle();
    return Result.success(this.account);
  }

  get cash(): number {
    return this.account.cash;
  }

  /** 选中股票的持仓股数（多标的传 stockId） */
  shares(stockId: string | null = null): number {
    return this.pos(stockId).shares;
  }

  /** 选中股票的持仓均价（空头时为卖出均价） */
  avgCost(stockId: string | null = null): number {
    const p: Position = this.pos(stockId);
    if (p.shares === 0) {
      return 0;
    }
    return p.cost / p.shares;
  }

  /** 选中股票的浮动盈亏 */
  pnl(price: number, stockId: string | null = null): number {
    const p: Position = this.pos(stockId);
    const avg: number = p.shares === 0 ? 0 : p.cost / p.shares;
    return (price - avg) * p.shares;
  }

  /** 选中股票的可卖数量（受 T+1 限制） */
  sellableShares(stockId: string | null = null): number {
    const p: Position = this.pos(stockId);
    let s: number = p.shares;
    if (this.rules.tPlus === 1) {
      s = s - p.todayBought;
    }
    return Math.max(0, s);
  }

  /** 当前现金最多可买股数（按整手 100 股，含手续费；leverage 为杠杆倍数） */
  maxBuyable(price: number, leverage: number = 1): number {
    if (price <= 0) {
      return 0;
    }
    let lev: number = leverage;
    if (lev < 1) {
      lev = 1;
    }
    if (lev > AppConfig.MAX_LEVERAGE) {
      lev = AppConfig.MAX_LEVERAGE;
    }
    const budget: number = this.account.cash * lev;
    const perShare: number = price * (1 + this.rules.feeRate);
    const qty: number = Math.floor(budget / perShare / 100) * 100;
    return qty > 0 ? qty : 0;
  }

  /** 累计手续费 */
  get feeTotal(): number {
    return this.feeTotalValue;
  }

  /** 交易流水 */
  get tradeRecords(): TradeRecord[] {
    return this.records;
  }

  /** 成交笔数 */
  get tradeCount(): number {
    return this.records.length;
  }

  /** 买入成交笔数 */
  get buyCount(): number {
    let n: number = 0;
    for (const r of this.records) {
      if (r.side === '买') {
        n += 1;
      }
    }
    return n;
  }

  /** 卖出成交笔数 */
  get sellCount(): number {
    let n: number = 0;
    for (const r of this.records) {
      if (r.side === '卖') {
        n += 1;
      }
    }
    return n;
  }

  /** 本局用过的最高杠杆倍数 */
  get maxLeverageUsed(): number {
    return this.maxLeverageValue;
  }

  /** 本局累计借款金额 */
  get totalBorrowed(): number {
    return this.totalBorrowedValue;
  }

  /** 胜率：盈利的卖出笔数 / 总卖出笔数 */
  get winRate(): number {
    let sells: number = 0;
    let wins: number = 0;
    for (const r of this.records) {
      if (r.side === '卖') {
        sells += 1;
        if (r.realized > 0) {
          wins += 1;
        }
      }
    }
    if (sells === 0) {
      return 0;
    }
    return wins / sells;
  }

  /** 实时更新净值峰值与最大回撤（每个交易日调用） */
  updateNetTracking(price: number): void {
    const net: number = this.netAsset(price);
    if (this.peakNetValue === 0 || net > this.peakNetValue) {
      this.peakNetValue = net;
    }
    if (this.peakNetValue > 0) {
      const dd: number = (this.peakNetValue - net) / this.peakNetValue;
      if (dd > this.maxDrawdownValue) {
        this.maxDrawdownValue = dd;
      }
    }
  }

  /** 最大回撤（0~1） */
  get maxDrawdown(): number {
    return this.maxDrawdownValue;
  }

  /** 净值峰值 */
  get peakNet(): number {
    return this.peakNetValue;
  }

  /** 恢复流水与回撤统计（继续上一局用） */
  restoreStats(list: TradeRecord[], peak: number, dd: number): void {
    this.records = list;
    this.peakNetValue = peak;
    this.maxDrawdownValue = dd;
  }

  /** 当前债务总额（本金 + 利息，含杠杆融资） */
  get debt(): number {
    return this.loanPrincipal + this.leveragePrincipal + this.loanInterest;
  }

  /** 未还本金（普通借款 + 杠杆融资） */
  get debtPrincipal(): number {
    return this.loanPrincipal + this.leveragePrincipal;
  }

  /** 杠杆融资本金 */
  get leverageDebt(): number {
    return this.leveragePrincipal;
  }

  /** 累计利息 */
  get debtInterest(): number {
    return this.loanInterest;
  }

  /** 每个交易日将新增的利息（按当前本息合计估算） */
  get dailyInterest(): number {
    return this.debt * AppConfig.DAILY_LOAN_RATE;
  }

  /** 剩余可借额度 */
  get loanAvailable(): number {
    const left: number = AppConfig.MAX_LOAN - this.loanPrincipal;
    return left > 0 ? left : 0;
  }

  /** 净资产 = 现金 + 持仓市值 - 债务（多标的：传每只股票的「股数×现价」数组） */
  netAsset(price: number, stockId: string | null = null): number {
    let marketValue: number = 0;
    if (this.positions !== null) {
      // 多标的：调用方先 setValuationPrices 或直接传入各股票行情
      for (const id of this.positions.keys()) {
        const p: Position = this.positions.get(id) as Position;
        const px: number | undefined = this.valuationPrices.get(id);
        marketValue += p.shares * (px === undefined ? price : px);
      }
    } else {
      marketValue = this.pos(null).shares * price;
    }
    return this.account.cash + marketValue - this.debt;
  }

  /** 多标的：更新每只股票的估值价（每个交易日推进时调用） */
  setValuationPrices(prices: Record<string, number>): void {
    this.valuationPrices = new Map<string, number>();
    const keys: string[] = Object.keys(prices);
    for (const k of keys) {
      this.valuationPrices.set(k, prices[k]);
    }
  }

  private valuationPrices: Map<string, number> = new Map<string, number>();

  /** 估值用：某股票当前价（多标的未设置时返回 fallback） */
  valuationPriceOf(stockId: string, fallback: number): number {
    const px: number | undefined = this.valuationPrices.get(stockId);
    return px === undefined ? fallback : px;
  }

  /** 是否已爆仓（净资产 <= 0） */
  bankrupt(price: number): boolean {
    return this.netAsset(price) <= 0;
  }

  /** 重开剧本时重置账户 */
  reset(): void {
    this.account = new Account();
    this.todayBought = 0;
    this.lastDate = '';
    this.feeTotalValue = 0;
    this.loanPrincipal = 0;
    this.leveragePrincipal = 0;
    this.loanInterest = 0;
    this.records = [];
    this.peakNetValue = 0;
    this.maxDrawdownValue = 0;
    this.maxLeverageValue = 1;
    this.totalBorrowedValue = 0;
    this.positions = null;
    this.singlePos = null;
    this.valuationPrices = new Map<string, number>();
  }

  /** 导出账户快照（持久化用） */
  snapshot(): AccountSnapshot {
    const snap: AccountSnapshot = {
      cash: this.account.cash,
      shares: this.pos(null).shares,
      cost: this.pos(null).cost,
      loanPrincipal: this.loanPrincipal,
      leveragePrincipal: this.leveragePrincipal,
      loanInterest: this.loanInterest,
      feeTotal: this.feeTotalValue,
      records: this.records,
      peak: this.peakNetValue,
      maxDrawdown: this.maxDrawdownValue
    };
    if (this.positions !== null) {
      const map: Record<string, Position> = {};
      for (const id of this.positions.keys()) {
        const p: Position = this.positions.get(id) as Position;
        map[id] = { shares: p.shares, cost: p.cost, todayBought: 0 };
      }
      snap.positions = map;
    }
    return snap;
  }

  /** 从快照恢复账户（继续上一局用，兼容不含流水字段的旧存档） */
  restore(s: AccountSnapshot): void {
    this.reset();
    this.account.cash = s.cash;
    this.loanPrincipal = s.loanPrincipal;
    this.leveragePrincipal = s.leveragePrincipal === undefined ? 0 : s.leveragePrincipal;
    this.loanInterest = s.loanInterest;
    this.feeTotalValue = s.feeTotal;
    this.records = s.records === undefined ? [] : s.records;
    this.peakNetValue = s.peak === undefined ? 0 : s.peak;
    this.maxDrawdownValue = s.maxDrawdown === undefined ? 0 : s.maxDrawdown;
    if (s.positions !== undefined) {
      const ids: string[] = Object.keys(s.positions);
      this.positions = new Map<string, Position>();
      for (const id of ids) {
        const p = s.positions[id];
        this.positions.set(id, { shares: p.shares, cost: p.cost, todayBought: 0 });
      }
    } else {
      // 单标的旧存档：恢复到主仓位
      this.singlePos = { shares: s.shares, cost: s.cost, todayBought: 0 };
      this.syncSingle();
    }
    this.lastDate = '';
  }
}