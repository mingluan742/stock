import { ScenarioData, ScenarioMeta } from '../models/Scenario';

/**
 * 行情数据源"插座标准"（接口）
 * 上层只依赖本接口，不关心数据来自内置 JSON 还是未来网络
 * 新增数据来源 = 新增一个 implements 类，上层代码零改动
 */
export interface IMarketDataSource {
  /** 列出所有可用剧本 */
  listScenarios(): Promise<ScenarioMeta[]>;
  /** 按 id 加载完整剧本数据 */
  loadScenario(id: string): Promise<ScenarioData>;
}