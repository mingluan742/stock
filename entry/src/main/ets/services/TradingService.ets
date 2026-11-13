import { Result } from '../core/Result';
import { Account } from '../models/Account';

/**
 * 交易服务（门面）：买卖校验 + 记账
 * 页面只调 buy/sell，拿 Result 判断成功与否，不碰任何账务细节
 */
export class TradingService {
  private account: Account = new Account();

  /** 买入：现金足够才成交，成本累加 */
  buy(price: number, qty: number): Result<Account> {
    if (price <= 0) {
      return Result.fail<Account>('行情未就绪');
    }
    if (qty <= 0) {
      return Result.fail<Account>('数量必须大于 0');
    }
    const amount: number = price * qty;
    if (this.account.cash < amount) {
      return Result.fail<Account>('现金不足');
    }
    this.account.cash -= amount;
    this.account.cost += amount;
    this.account.shares += qty;
    return Result.success(this.account);
  }

  /** 卖出：持仓足够才成交，按当前均价扣减成本 */
  sell(price: number, qty: number): Result<Account> {
    if (price <= 0) {
      return Result.fail<Account>('行情未就绪');
    }
    if (qty <= 0) {
      return Result.fail<Account>('数量必须大于 0');
    }
    if (this.account.shares < qty) {
      return Result.fail<Account>('持仓不足');
    }
    const avg: number = this.avgCost;
    this.account.cash += price * qty;
    this.account.cost -= avg * qty;
    this.account.shares -= qty;
    if (this.account.shares === 0) {
      this.account.cost = 0;
    }
    return Result.success(this.account);
  }

  get cash(): number {
    return this.account.cash;
  }

  get shares(): number {
    return this.account.shares;
  }

  /** 持仓均价 */
  get avgCost(): number {
    if (this.account.shares <= 0) {
      return 0;
    }
    return this.account.cost / this.account.shares;
  }

  /** 浮动盈亏 */
  pnl(price: number): number {
    return (price - this.avgCost) * this.account.shares;
  }

  /** 重开剧本时重置账户 */
  reset(): void {
    this.account = new Account();
  }
}