import { AppConfig } from '../config/AppConfig';
import { AppContext } from '../core/AppContext';
import { AchievementItem } from '../models/Achievement';
import { AchievementStats } from '../services/AchievementService';

/**
 * 成就页（明亮主题）：
 * - 顶部进度 + 跨局统计
 * - 两列卡片网格，已解锁高亮，未解锁显示条件
 */
@Component
export struct AchievementView {
  /** 返回主界面 */
  onBack: () => void = () => {};

  @State items: AchievementItem[] = [];
  @State unlockedCount: number = 0;
  @State totalCount: number = 1;
  @State rounds: number = 0;
  @State trades: number = 0;
  @State bankruptcies: number = 0;

  aboutToAppear(): void {
    this.loadData();
  }

  loadData(): void {
    const svc = AppContext.getAchievements();
    this.items = svc.list();
    this.unlockedCount = svc.unlockedCount;
    this.totalCount = svc.totalCount;
    const s: AchievementStats = svc.statsSnapshot;
    this.rounds = s.rounds;
    this.trades = s.trades;
    this.bankruptcies = s.bankruptcies;
  }

  /** 稀有度对应描边色 */
  tierLine(tier: number): string {
    if (tier === 2) {
      return '#E3C88A';
    }
    if (tier === 1) {
      return '#EEE3CC';
    }
    return AppConfig.LIGHT_LINE;
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor('#5A606B')
          .width(26)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onBack();
          })
        Text('成就')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppConfig.LIGHT_TEXT)
          .margin({ left: 4 })
        Blank()
        Text(`${this.unlockedCount} / ${this.totalCount}`)
          .fontSize(12)
          .fontColor(AppConfig.LIGHT_ACCENT)
      }
      .width('100%')
      .padding({ left: 16, right: 20, top: 16 })

      // 进度
      Progress({ value: this.unlockedCount, total: this.totalCount, type: ProgressType.Linear })
        .color(AppConfig.LIGHT_ACCENT)
        .backgroundColor('#EBEDF2')
        .height(6)
        .width('100%')
        .margin({ left: 20, right: 20, top: 12 })
        .borderRadius(3)

      // 跨局统计
      Row() {
        this.statBlock('完成对局', `${this.rounds}`)
        this.statBlock('累计成交', `${this.trades}`)
        this.statBlock('爆仓次数', `${this.bankruptcies}`)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 14 })

      // 成就网格
      Grid() {
        ForEach(this.items, (item: AchievementItem) => {
          GridItem() {
            Column() {
              Row() {
                Text(item.icon)
                  .fontSize(20)
                  .fontColor(item.unlocked ? AppConfig.LIGHT_ACCENT : '#C3C7CE')
                Blank()
                if (item.tier === 2 && item.unlocked) {
                  Text('传说')
                    .fontSize(9)
                    .fontColor(AppConfig.LIGHT_ACCENT)
                    .backgroundColor(AppConfig.LIGHT_GOLD_BG)
                    .borderRadius(4)
                    .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                } else if (item.tier === 1 && item.unlocked) {
                  Text('稀有')
                    .fontSize(9)
                    .fontColor('#9A8A66')
                    .backgroundColor('#FBF7EF')
                    .borderRadius(4)
                    .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                }
              }
              .width('100%')

              Text(item.name)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(item.unlocked ? AppConfig.LIGHT_TEXT : '#9AA0AA')
                .margin({ top: 8 })
                .width('100%')

              Text(item.desc)
                .fontSize(10)
                .fontColor(item.unlocked ? AppConfig.LIGHT_SUB : '#B0B5BD')
                .lineHeight(15)
                .maxLines(2)
                .margin({ top: 4 })
                .width('100%')
            }
            .width('100%')
            .height(116)
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .backgroundColor(item.unlocked ? AppConfig.LIGHT_CARD : '#F1F2F5')
            .borderRadius(14)
            .border({ width: 1, color: item.unlocked ? this.tierLine(item.tier) : '#E9EBF0' })
          }
        }, (item: AchievementItem) => item.id)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 20, right: 20, top: 14, bottom: 16 })
      .scrollBar(BarState.Off)

      Text('成就与对局统计保存在本机，卸载应用后清空')
        .fontSize(10)
        .fontColor('#A6ABB4')
        .margin({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppConfig.LIGHT_BG)
  }

  @Builder
  statBlock(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppConfig.LIGHT_TEXT)
      Text(label)
        .fontSize(10)
        .fontColor(AppConfig.LIGHT_SUB)
        .margin({ top: 3 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }
}