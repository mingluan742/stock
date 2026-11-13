import { AppConfig } from '../config/AppConfig';
import { HistoryView } from '../views/HistoryView';
import { HomeView } from '../views/HomeView';
import { TradeView } from '../views/TradeView';

/**
 * 应用唯一入口页：用状态机切换三个视图
 * - home：主界面（历史剧本 / 随机模拟）
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

  build() {
    Stack() {
      if (this.view === 'home') {
        HomeView({
          onGoHistory: () => {
            this.view = 'history';
          },
          onGoRandom: () => {
            this.tradeMode = 'random';
            this.view = 'trade';
          }
        })
      } else if (this.view === 'history') {
        HistoryView({
          onBack: () => {
            this.view = 'home';
          },
          onSelect: (id: string) => {
            this.tradeMode = 'history';
            this.tradeId = id;
            this.view = 'trade';
          }
        })
      } else {
        TradeView({
          mode: this.tradeMode,
          scenarioId: this.tradeId,
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