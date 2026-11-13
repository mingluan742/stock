import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../config/AppConfig';
import { AppContext } from '../core/AppContext';

/**
 * 主界面：只保留两个入口
 * - 历史剧本 → 剧本列表页（History）
 * - 随机模拟 → 直接生成一局陌生行情
 */
@Entry
@Component
struct Home {

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      AppContext.init(host.resourceManager);
    }
  }

  goHistory(): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/History'
    }).catch((err: BusinessError) => {
      console.error(`[StockLab] 跳转失败: ${err.message}`);
    });
  }

  goRandom(): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/Index',
      params: { mode: 'random', id: '' }
    }).catch((err: BusinessError) => {
      console.error(`[StockLab] 跳转失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      // 品牌区
      Column() {
        Text(AppConfig.APP_NAME)
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppConfig.COLOR_TEXT)
        Text('在历史的风浪里，练习你的判断')
          .fontSize(12)
          .fontColor(AppConfig.COLOR_SUB)
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
            .fontColor(AppConfig.COLOR_TEXT)
          Text('真实发生过的市场，重来一遍')
            .fontSize(11)
            .fontColor(AppConfig.COLOR_SUB)
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('›')
          .fontSize(24)
          .fontColor('#5A606B')
      }
      .width('100%')
      .padding(20)
      .backgroundColor(AppConfig.COLOR_CARD)
      .borderRadius(16)
      .onClick(() => {
        this.goHistory();
      })

      // 入口 2：随机模拟
      Row() {
        Column() {
          Text('随机模拟股市')
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppConfig.COLOR_TEXT)
          Text('算法即时生成一段未知行情')
            .fontSize(11)
            .fontColor(AppConfig.COLOR_SUB)
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('›')
          .fontSize(24)
          .fontColor('#5A606B')
      }
      .width('100%')
      .padding(20)
      .margin({ top: 14 })
      .backgroundColor('#1A1E26')
      .borderRadius(16)
      .border({ width: 1, color: '#3A3325' })
      .onClick(() => {
        this.goRandom();
      })

      Blank()

      Text('数据为教学演示，非精确历史行情')
        .fontSize(10)
        .fontColor('#4E535C')
        .margin({ bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .backgroundColor(AppConfig.COLOR_BG)
  }
}