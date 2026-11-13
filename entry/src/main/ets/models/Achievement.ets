/**
 * 成就定义与判定上下文
 */

/** 成就定义（静态配置） */
export interface AchievementDef {
  /** 唯一 id，用于持久化 */
  id: string;
  /** 成就名 */
  name: string;
  /** 解锁条件描述（未解锁时显示） */
  desc: string;
  /** 图标字符（用文字符号，避免引入图片资源） */
  icon: string;
  /** 稀有度：0 普通 / 1 稀有 / 2 传说 */
  tier: number;
}

/** 成就列表项（含解锁状态，供 UI 渲染） */
export interface AchievementItem {
  id: string;
  name: string;
  desc: string;
  icon: string;
  tier: number;
  unlocked: boolean;
}

/** 判定成就所需的一局快照 */
export interface AchievementContext {
  /** 剧本 id（random 为随机局） */
  scenarioId: string;
  /** history / random */
  mode: string;
  dayIndex: number;
  totalDays: number;
  /** 剧本已播完 */
  finished: boolean;
  /** 已爆仓 */
  bankrupt: boolean;
  /** 当前净资产 */
  netAsset: number;
  /** 当前价（计算持仓相关） */
  price: number;
  /** 持仓股数，负数为空头 */
  shares: number;
  /** 最大回撤 0~1 */
  maxDrawdown: number;
  /** 成交笔数 */
  tradeCount: number;
  /** 买入笔数 */
  buyCount: number;
  /** 卖出笔数 */
  sellCount: number;
  /** 胜率 0~1 */
  winRate: number;
  /** 本局用过的最高杠杆倍数 */
  maxLeverage: number;
  /** 本局累计借款金额 */
  totalBorrowed: number;
}