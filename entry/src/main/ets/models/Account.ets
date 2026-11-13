import { AppConfig } from '../config/AppConfig';

/**
 * 账户实体：现金 + 持仓 + 持仓总成本
 * 成本用"总成本"而非"均价"，买入直接累加、卖出按均价扣减，避免浮点误差累积
 */
export class Account {
  /** 可用现金 */
  cash: number = AppConfig.INIT_CASH;
  /** 持仓股数 */
  shares: number = 0;
  /** 持仓总成本（股数 × 均价） */
  cost: number = 0;
}