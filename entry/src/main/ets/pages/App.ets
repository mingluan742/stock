import { AppConfig } from '../config/AppConfig';
import { SaveService, SaveSnapshot } from '../core/SaveService';
import { HistoryView } from '../views/HistoryView';
import { HomeView } from '../views/HomeView';
import { TradeView } from '../views/TradeView';

/**
 * 应用唯一入口页：用状态机切换三个视图
 * - home：主界面（历史剧本 / 随机模拟 / 继续上一局）
 * - history：历史剧本列表
 * - trade：实时盯盘
 * 不使用 router 页面路由，保证在预览器里也能正常点击切换
 */
@Entry
@Component
struct App {
  @State view: string = 'home';
  @State tradeMode: string = 'history';
  @State tradeId: string = AppConfig.DEFAULT_SCENARIO;
  /** 下一局是否从存档继续 */
  @State resume: boolean = false;

  /** 从主界面“继续上一局”进入 */
  resumeGame(): void {
    const snap: SaveSnapshot | null = SaveService.load();
    if (snap === null) {
      return;
    }
    this.tradeMode = 'history';
    this.tradeId = snap.scenarioId;
    this.resume = true;
    this.view = 'trade';
  }

  build() {
    Stack() {
      if (this.view === 'home') {
        HomeView({
          onGoHistory: () => {
            this.resume = false;
            this.view = 'history';
          },
          onGoRandom: () => {
            this.resume = false;
            this.tradeMode = 'random';
            this.view = 'trade';
          },
          onResume: () => {
            this.resumeGame();
          }
        })
      } else if (this.view === 'history') {
        HistoryView({
          onBack: () => {
            this.view = 'home';
          },
          onSelect: (id: string) => {
            this.resume = false;
            this.tradeMode = 'history';
            this.tradeId = id;
            this.view = 'trade';
          }
        })
      } else {
        TradeView({
          mode: this.tradeMode,
          scenarioId: this.tradeId,
          resume: this.resume,
          onBack: () => {
            this.view = this.tradeMode === 'random' ? 'home' : 'history';
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppConfig.COLOR_BG)
  }
}