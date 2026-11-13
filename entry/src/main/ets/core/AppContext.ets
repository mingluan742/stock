import { resourceManager } from '@kit.LocalizationKit';
import { BuiltinScenarioSource } from '../repository/BuiltinScenarioSource';
import { MarketService } from '../services/MarketService';
import { TradingService } from '../services/TradingService';

/**
 * 服务定位器：全局单例的装配与获取入口
 * 换数据源只改这里一行（例如将来 new RemoteScenarioSource(...)）
 */
export class AppContext {
  private static marketService: MarketService | null = null;
  private static tradingService: TradingService | null = null;

  /** 应用启动时调用一次；重复调用安全 */
  static init(rm: resourceManager.ResourceManager): void {
    if (AppContext.marketService === null) {
      const source = new BuiltinScenarioSource(rm);
      AppContext.marketService = new MarketService(source);
    }
    if (AppContext.tradingService === null) {
      AppContext.tradingService = new TradingService();
    }
  }

  static getMarket(): MarketService {
    if (AppContext.marketService === null) {
      throw new Error('AppContext 尚未初始化，请先在 EntryAbility.onCreate 中调用 init');
    }
    return AppContext.marketService;
  }

  static getTrading(): TradingService {
    if (AppContext.tradingService === null) {
      throw new Error('AppContext 尚未初始化，请先在 EntryAbility.onCreate 中调用 init');
    }
    return AppContext.tradingService;
  }
}