import { util } from '@kit.ArkTS';
import { resourceManager } from '@kit.LocalizationKit';
import { IMarketDataSource } from './IMarketDataSource';
import { allBuiltinData } from './data/BuiltinScenarioData';
import { ScenarioData, ScenarioMeta } from '../models/Scenario';

/**
 * 内置剧本数据源：优先读 rawfile/scenarios/ 下的 JSON；
 * 预览器等环境 rawfile 资源未打包（读出空内容）时，自动回退到
 * ArkTS 内置数据（data/BuiltinScenarioData.ets），保证任何环境可运行。
 * 实现 IMarketDataSource，未来可换成 RemoteScenarioSource 而不影响上层
 */
export class BuiltinScenarioSource implements IMarketDataSource {
  private rm: resourceManager.ResourceManager;
  /** 剧本清单：新增剧本时在这里登记 id 即可 */
  private ids: string[] = ['crash-1929', 'a-share-2015'];
  /** 内存缓存，避免重复解析 JSON */
  private cache: Map<string, ScenarioData> = new Map<string, ScenarioData>();

  constructor(rm: resourceManager.ResourceManager) {
    this.rm = rm;
  }

  async listScenarios(): Promise<ScenarioMeta[]> {
    const result: ScenarioMeta[] = [];
    for (const id of this.ids) {
      const data = await this.loadScenario(id);
      result.push(data.meta);
    }
    return result;
  }

  async loadScenario(id: string): Promise<ScenarioData> {
    const cached = this.cache.get(id);
    if (cached !== undefined) {
      return cached;
    }
    let data: ScenarioData | null = await this.loadFromRawfile(id);
    if (data === null) {
      data = this.loadFromBuiltin(id);
    }
    if (data === null) {
      throw new Error(`剧本 ${id} 不存在`);
    }
    this.cache.set(id, data);
    return data;
  }

  /**
   * 途径1：从 rawfile 读取并解析 JSON
   * 返回 null 表示 rawfile 不可用（如预览器未打包资源读出空内容）
   */
  private async loadFromRawfile(id: string): Promise<ScenarioData | null> {
    try {
      const bytes: Uint8Array = await this.rm.getRawFileContent(`scenarios/${id}.json`);
      const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
      if (text === undefined || text === null || text.trim().length === 0) {
        return null;
      }
      return JSON.parse(text) as ScenarioData;
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] rawfile 读取失败(${id}): ${e.message}，使用内置数据`);
      return null;
    }
  }

  /** 途径2：从 ArkTS 内置常量读取（rawfile 不可用时的兜底） */
  private loadFromBuiltin(id: string): ScenarioData | null {
    const all: ScenarioData[] = allBuiltinData();
    for (const d of all) {
      if (d.meta.id === id) {
        return d;
      }
    }
    return null;
  }
}