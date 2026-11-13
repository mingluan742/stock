import { KLine } from './KLine';
import { ScenarioEvent } from './ScenarioEvent';

/**
 * 剧本元信息
 */
export interface ScenarioMeta {
  /** 剧本 id，与文件名一致 */
  id: string;
  /** 剧本名称，如"1929 大崩盘" */
  name: string;
  /** 时代背景描述 */
  era: string;
  /** 基准标的，如"道琼斯工业指数" */
  benchmark: string;
  /** 一句话简介 */
  intro: string;
}

/**
 * 市场规则配置：不同年代规则不同，参数化后同一套代码可跑多个市场
 */
export interface MarketRuleConfig {
  /** 涨跌幅限制，0 表示无涨跌停（如 1929 美股） */
  priceLimit: number;
  /** 0 = T+0，1 = T+1 */
  tPlus: number;
  /** 手续费率 */
  feeRate: number;
  /** 是否允许做空 */
  shortSell: boolean;
}

/**
 * 一个完整剧本的数据结构（对应 rawfile/scenarios/*.json）
 */
export interface ScenarioData {
  meta: ScenarioMeta;
  rules: MarketRuleConfig;
  timeline: KLine[];
  events: ScenarioEvent[];
}