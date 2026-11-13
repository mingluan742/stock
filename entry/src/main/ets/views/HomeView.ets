import { AppConfig } from '../config/AppConfig';
import { AppContext } from '../core/AppContext';

/**
 * 主界面（明亮主题）：只保留两个入口
 * - 历史剧本 → 剧本列表页（History）
 * - 随机模拟 → 直接生成一局陌生行情
 */
@Component
export struct HomeView {
  /** 进入历史剧本列表 */
  onGoHistory: () => void = () => {};
  /** 进入随机模拟 */
  onGoRandom: () => void = () => {};

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      AppContext.init(host.resourceManager);
    }
  }

  goHistory(): void {
    this.onGoHistory();
  }

  goRandom(): void {
    this.onGoRandom();
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

      Blank()

      Text('数据为教学演示，非精确历史行情')
        .fontSize(10)
        .fontColor('#A6ABB4')
        .margin({ bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .backgroundColor(AppConfig.LIGHT_BG)
  }
}