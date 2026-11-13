import { AppConfig } from '../config/AppConfig';
import { Result } from '../core/Result';
import { Account } from '../models/Account';
import { MarketRuleConfig } from '../models/Scenario';
import { TradeRecord } from '../models/TradeRecord';

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
  /** 当日买入股数（T+1 用） */
  private todayBought: number = 0;
  private lastDate: string = '';
  private feeTotalValue: number = 0;
  /** 贷款本金（普通借款） */
  private loanPrincipal: number = 0;
  /** 杠杆融资本金 */
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
   */
  buy(price: number, qty: number, dayRatio: number, leverage: number = 1): Result<Account> {
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

    // 若当前是空头，先按均价平空，剩余部分转为多头
    const closeQty: number = Math.min(qty, Math.max(0, -this.account.shares));
    const openQty: number = qty - closeQty;
    const shortAvg: number = this.avgCost;
    if (closeQty > 0) {
      this.account.cost += shortAvg * closeQty;
    }
    if (openQty > 0) {
      this.account.cost += price * openQty;
    }
    this.account.cash -= amount + fee;
    this.account.shares += qty;
    if (this.account.shares === 0) {
      this.account.cost = 0;
    }

    // T+1：只有开多方向计入今日买入
    if (this.rules.tPlus === 1 && openQty > 0) {
      this.todayBought += openQty;
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
    return Result.success(this.account);
  }

  /** 卖出：跌停封板不可卖，持仓/T+1/做空规则校验 */
  sell(price: number, qty: number, dayRatio: number): Result<Account> {
    if (price <= 0) {
      return Result.fail<Account>('行情未就绪');
    }
    if (qty <= 0) {
      return Result.fail<Account>('数量必须大于 0');
    }
    if (this.rules.priceLimit > 0 && dayRatio <= -this.rules.priceLimit * LIMIT_TOLERANCE) {
      return Result.fail<Account>('跌停封板，卖不出');
    }

    if (!this.rules.shortSell) {
      // 不可做空：只能卖已有持仓，且 T+1 下当日买入部分冻结
      let sellable: number = this.account.shares;
      if (this.rules.tPlus === 1) {
        sellable = sellable - this.todayBought;
      }
      if (qty > Math.max(0, sellable)) {
        if (this.rules.tPlus === 1 && this.todayBought > 0 && this.account.shares >= qty) {
          return Result.fail<Account>('T+1：今日买入的仓位不可卖出');
        }
        return Result.fail<Account>('持仓不足');
      }
    }

    const amount: number = price * qty;
    const fee: number = amount * this.rules.feeRate;
    // 多头部分按均价结转成本，超出部分转为空头按卖出价记成本
    const closeQty: number = Math.min(qty, Math.max(0, this.account.shares));
    const openQty: number = qty - closeQty;
    // 新开空头的敏口上限：做空市值 ≤ 净资产 × 最大杠杆
    if (openQty > 0) {
      const cap: number = this.netAsset(price) * AppConfig.MAX_LEVERAGE;
      if (openQty * price > cap) {
        return Result.fail<Account>(`做空规模超出净资产 ${AppConfig.MAX_LEVERAGE} 倍上限`);
      }
    }
    const longAvg: number = this.avgCost;
    if (closeQty > 0) {
      this.account.cost -= longAvg * closeQty;
    }
    if (openQty > 0) {
      this.account.cost -= price * openQty;
    }
    this.account.cash += amount - fee;
    this.account.shares -= qty;
    if (this.account.shares === 0) {
      this.account.cost = 0;
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
    return Result.success(this.account);
  }

  get cash(): number {
    return this.account.cash;
  }

  get shares(): number {
    return this.account.shares;
  }

  /** 持仓均价（空头时为卖出均价） */
  get avgCost(): number {
    if (this.account.shares === 0) {
      return 0;
    }
    return this.account.cost / this.account.shares;
  }

  /** 浮动盈亏：多头赚差价，空头价格下跌时盈利 */
  pnl(price: number): number {
    return (price - this.avgCost) * this.account.shares;
  }

  /** 可卖数量（受 T+1 限制） */
  get sellableShares(): number {
    let s: number = this.account.shares;
    if (this.rules.tPlus === 1) {
      s = s - this.todayBought;
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

  /** 净资产 = 现金 + 持仓市值 - 债务（空头持仓市值为负） */
  netAsset(price: number): number {
    return this.account.cash + this.account.shares * price - this.debt;
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
  }

  /** 导出账户快照（持久化用） */
  snapshot(): AccountSnapshot {
    return {
      cash: this.account.cash,
      shares: this.account.shares,
      cost: this.account.cost,
      loanPrincipal: this.loanPrincipal,
      leveragePrincipal: this.leveragePrincipal,
      loanInterest: this.loanInterest,
      feeTotal: this.feeTotalValue,
      records: this.records,
      peak: this.peakNetValue,
      maxDrawdown: this.maxDrawdownValue
    };
  }

  /** 从快照恢复账户（继续上一局用，兼容不含流水字段的旧存档） */
  restore(s: AccountSnapshot): void {
    this.account.cash = s.cash;
    this.account.shares = s.shares;
    this.account.cost = s.cost;
    this.loanPrincipal = s.loanPrincipal;
    this.leveragePrincipal = s.leveragePrincipal === undefined ? 0 : s.leveragePrincipal;
    this.loanInterest = s.loanInterest;
    this.feeTotalValue = s.feeTotal;
    this.records = s.records === undefined ? [] : s.records;
    this.peakNetValue = s.peak === undefined ? 0 : s.peak;
    this.maxDrawdownValue = s.maxDrawdown === undefined ? 0 : s.maxDrawdown;
    this.todayBought = 0;
    this.lastDate = '';
  }
}