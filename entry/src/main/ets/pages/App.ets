import { AppConfig } from '../config/AppConfig';
import { SaveService, SaveSnapshot } from '../core/SaveService';
import { TutorialService } from '../services/TutorialService';
import { AchievementView } from '../views/AchievementView';
import { HistoryView } from '../views/HistoryView';
import { HomeView } from '../views/HomeView';
import { RateView } from '../views/RateView';
import { ResultView } from '../views/ResultView';
import { SettingsView } from '../views/SettingsView';
import { TradeView } from '../views/TradeView';
import { TutorialView } from '../views/TutorialView';
import { WelcomeView } from '../views/WelcomeView';

/**
 * 应用唯一入口页：用状态机切换四个视图
 * - home：主界面（历史剧本 / 随机模拟 / 继续上一局）
 * - history：历史剧本列表
 * - trade：实时盯盘
 * - result：结算复盘
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
  /** 从哪个视图进入设置页（返回时回到原处） */
  @State settingsFrom: string = 'home';

  /** 首次启动先问是不是新手；选了新手但没看完的，下次接着看 */
  aboutToAppear(): void {
    if (TutorialService.needsWelcome) {
      this.view = 'welcome';
    } else if (TutorialService.pendingTutorial) {
      this.view = 'tutorial';
    }
  }

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
          },
          onGoAchievement: () => {
            this.view = 'achievement';
          },
          onGoTutorial: () => {
            this.view = 'tutorial';
          },
          onGoSettings: () => {
            this.settingsFrom = 'home';
            this.view = 'settings';
          },
          onGoRate: () => {
            this.view = 'rate';
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
      } else if (this.view === 'achievement') {
        AchievementView({
          onBack: () => {
            this.view = 'home';
          }
        })
      } else if (this.view === 'tutorial') {
        TutorialView({
          onDone: () => {
            this.view = 'home';
          }
        })
      } else if (this.view === 'welcome') {
        WelcomeView({
          onNewbie: () => {
            TutorialService.chooseNewbie();
            this.view = 'tutorial';
          },
          onExpert: () => {
            TutorialService.chooseExpert();
            this.view = 'home';
          }
        })
      } else if (this.view === 'settings') {
        SettingsView({
          onBack: () => {
            this.view = this.settingsFrom;
          }
        })
      } else if (this.view === 'rate') {
        RateView({
          onBack: () => {
            this.view = 'home';
          }
        })
      } else if (this.view === 'trade') {
        TradeView({
          mode: this.tradeMode,
          scenarioId: this.tradeId,
          resume: this.resume,
          onBack: () => {
            this.view = this.tradeMode === 'random' ? 'home' : 'history';
          },
          onFinish: () => {
            this.view = 'result';
          }
        })
      } else {
        ResultView({
          mode: this.tradeMode,
          scenarioId: this.tradeId,
          onBack: () => {
            this.view = this.tradeMode === 'random' ? 'home' : 'history';
          },
          onReplay: () => {
            this.resume = false;
            this.view = 'trade';
          },
          onGoSettings: () => {
            this.settingsFrom = 'result';
            this.view = 'settings';
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppConfig.COLOR_BG)
  }
}