import { AppConfig } from '../config/AppConfig';
import { AppContext } from '../core/AppContext';
import { SaveService, SaveSnapshot } from '../core/SaveService';

/**
 * 主界面（明亮主题）：两个入口 + 可选的“继续上一局”
 * - 历史剧本 → 剧本列表页（History）
 * - 随机模拟 → 直接生成一局陌生行情
 */
@Component
export struct HomeView {
  /** 进入历史剧本列表 */
  onGoHistory: () => void = () => {};
  /** 进入随机模拟 */
  onGoRandom: () => void = () => {};
  /** 继续未完成的存档 */
  onResume: () => void = () => {};
  /** 进入成就页 */
  onGoAchievement: () => void = () => {};
  /** 重看新手教程 */
  onGoTutorial: () => void = () => {};
  /** 模型设置 */
  onGoSettings: () => void = () => {};

  @State hasResume: boolean = false;
  @State resumeTitle: string = '';
  @State resumeInfo: string = '';
  @State achText: string = '';

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      AppContext.init(host.resourceManager);
    }
    this.loadResumeInfo();
    const svc = AppContext.getAchievements();
    this.achText = `${svc.unlockedCount} / ${svc.totalCount}`;
  }

  /** 读取存档摘要（主界面每次重新显示都会刷新） */
  loadResumeInfo(): void {
    const snap: SaveSnapshot | null = SaveService.load();
    if (snap === null || snap.cursor >= snap.totalDays - 1) {
      this.hasResume = false;
      return;
    }
    this.hasResume = true;
    this.resumeTitle = snap.scenarioName;
    this.resumeInfo = `第 ${snap.cursor + 1} / ${snap.totalDays} 交易日`;
  }

  goHistory(): void {
    this.onGoHistory();
  }

  goRandom(): void {
    this.onGoRandom();
  }

  resumeGame(): void {
    this.onResume();
  }

  build() {
    Column() {
      // 品牌区
      Column() {
        Text(AppConfig.APP_NAME)
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppConfig.LIGHT_TEXT)
        Text('在历史的风浪里，练习你的判断')
          .fontSize(12)
          .fontColor(AppConfig.LIGHT_SUB)
          .margin({ top: 10 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 64 })

      // 继续上一局（存在未完成存档时显示）
      if (this.hasResume) {
        Column() {
          Row() {
            Column() {
              Text('继续上一局')
                .fontSize(13)
                .fontColor(AppConfig.LIGHT_ACCENT)
              Text(`${this.resumeTitle} · ${this.resumeInfo}`)
                .fontSize(11)
                .fontColor(AppConfig.LIGHT_SUB)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(20)
              .fontColor('#D4B87A')
          }
          .width('100%')
        }
        .width('100%')
        .padding(14)
        .margin({ top: 24 })
        .backgroundColor('#FFFBF2')
        .borderRadius(12)
        .border({ width: 1, color: '#F3E7CC' })
        .onClick(() => {
          this.resumeGame();
        })
      }

      Blank()

      // 入口 1：历史剧本
      Row() {
        Column() {
          Text('历史剧本')
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppConfig.LIGHT_TEXT)
          Text('真实发生过的市场，重来一遍')
            .fontSize(11)
            .fontColor(AppConfig.LIGHT_SUB)
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('›')
          .fontSize(24)
          .fontColor('#C4C8D0')
      }
      .width('100%')
      .padding(20)
      .backgroundColor(AppConfig.LIGHT_CARD)
      .borderRadius(16)
      .shadow({ radius: 16, color: 'rgba(16,24,40,0.06)', offsetX: 0, offsetY: 4 })
      .onClick(() => {
        this.goHistory();
      })

      // 入口 2：随机模拟
      Row() {
        Column() {
          Text('随机模拟股市')
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppConfig.LIGHT_TEXT)
          Text('算法即时生成一段未知行情')
            .fontSize(11)
            .fontColor('#9A8A66')
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('›')
          .fontSize(24)
          .fontColor('#D4B87A')
      }
      .width('100%')
      .padding(20)
      .margin({ top: 14 })
      .backgroundColor(AppConfig.LIGHT_GOLD_BG)
      .borderRadius(16)
      .border({ width: 1, color: AppConfig.LIGHT_GOLD_LINE })
      .onClick(() => {
        this.goRandom();
      })

      // 入口 3：成就
      Row() {
        Text('★')
          .fontSize(15)
          .fontColor(AppConfig.LIGHT_ACCENT)
        Text('成就')
          .fontSize(13)
          .fontColor(AppConfig.LIGHT_TEXT)
          .margin({ left: 8 })
        Blank()
        Text(this.achText)
          .fontSize(11)
          .fontColor(AppConfig.LIGHT_SUB)
        Text('›')
          .fontSize(18)
          .fontColor('#C4C8D0')
          .margin({ left: 6 })
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 14 })
      .margin({ top: 14 })
      .backgroundColor(AppConfig.LIGHT_CARD)
      .borderRadius(14)
      .onClick(() => {
        this.onGoAchievement();
      })

      Row({ space: 18 }) {
        Text('新手教程 ›')
          .fontSize(11)
          .fontColor('#8B909A')
          .padding({ top: 10, bottom: 4 })
          .onClick(() => {
            this.onGoTutorial();
          })
        Text('模型设置 ›')
          .fontSize(11)
          .fontColor('#8B909A')
          .padding({ top: 10, bottom: 4 })
          .onClick(() => {
            this.onGoSettings();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Blank()

      Text('数据为教学演示，非精确历史行情')
        .fontSize(10)
        .fontColor('#A6ABB4')
        .margin({ bottom: 28 })    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .backgroundColor(AppConfig.LIGHT_BG)
  }
}