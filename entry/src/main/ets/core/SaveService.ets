import { AccountSnapshot } from '../services/TradingService';
import { LiveSave } from '../services/RandomScenarioService';

/** 存档快照：用于"继续上一局" */
export interface SaveSnapshot {
  /** history / random */
  mode: string;
  scenarioId: string;
  scenarioName: string;
  /** 当前时间轴游标 */
  cursor: number;
  totalDays: number;
  account: AccountSnapshot;
  savedAt: string;
  /** random 模式专用：活市场生成状态与已生成数据 */
  live?: LiveSave;
}

/**
 * 存档服务：基于 AppStorage + PersistentStorage 的 JSON 字符串持久化
 * 复杂对象存成 JSON 字符串，避免 PersistentStorage 直接存对象时丢失类型
 */
export class SaveService {
  static readonly KEY: string = 'stock_snapshot';

  static save(s: SaveSnapshot): void {
    try {
      AppStorage.setOrCreate<string>(SaveService.KEY, JSON.stringify(s));
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] 存档失败: ${e.message}`);
    }
  }

  static load(): SaveSnapshot | null {
    const raw: string | undefined = AppStorage.get<string>(SaveService.KEY);
    if (raw === undefined || raw === '') {
      return null;
    }
    try {
      return JSON.parse(raw) as SaveSnapshot;
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] 读档失败: ${e.message}`);
      return null;
    }
  }

  static clear(): void {
    try {
      AppStorage.setOrCreate<string>(SaveService.KEY, '');
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] 清档失败: ${e.message}`);
    }
  }
}