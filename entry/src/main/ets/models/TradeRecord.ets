/**
 * 交易流水：每笔成交记录，用于结算复盘
 */
export interface TradeRecord {
  /** 成交交易日 */
  date: string;
  /** '买' / '卖' */
  side: string;
  /** 成交价 */
  price: number;
  /** 成交股数 */
  qty: number;
  /** 手续费 */
  fee: number;
  /** 成交金额（price × qty） */
  amount: number;
  /** 本笔已实现盈亏（平仓时相对均价；开仓为 0） */
  realized: number;
}