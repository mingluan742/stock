import { AppConfig } from '../config/AppConfig';

/**
 * 首次打开的自述页：先问一句"你是新手吗"
 * - 新手 → 看完整 4 步教程
 * - 老手 → 直接进主界面
 * 只问一次，选择结果记在本机
 */
@Component
export struct WelcomeView {
  /** 选择「我是新手」 */
  onNewbie: () => void = () => {};
  /** 选择「我是老手」 */
  onExpert: () => void = () => {};

  build() {
    Column() {
      Blank()

      // 品牌
      Column() {
        Text(AppConfig.APP_NAME)
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppConfig.LIGHT_TEXT)
        Text('在历史的风浪里，练习你的判断')
          .fontSize(12)
          .fontColor(AppConfig.LIGHT_SUB)
          .margin({ top: 10 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Text('第一次来，先确认一件事')
        .fontSize(13)
        .fontColor('#5A606B')
        .width('100%')
        .margin({ top: 56 })

      Text('你之前接触过股票、K 线这类东西吗？')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppConfig.LIGHT_TEXT)
        .lineHeight(30)
        .width('100%')
        .margin({ top: 10 })

      Text('选「新手」会用 4 页带你过一遍行情、下单和复盘；选「老手」直接开始。')
        .fontSize(11)
        .fontColor('#8B909A')
        .lineHeight(19)
        .width('100%')
        .margin({ top: 12 })

      Blank()

      // 新手
      Column() {
        Text('我是新手')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
        Text('花两分钟先看一遍，少走弯路')
          .fontSize(11)
          .fontColor('rgba(255,255,255,0.78)')
          .margin({ top: 4 })
      }
      .width('100%')
      .padding({ top: 16, bottom: 16 })
      .backgroundColor(AppConfig.LIGHT_ACCENT)
      .borderRadius(14)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.onNewbie();
      })

      // 老手
      Column() {
        Text('我是老手')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppConfig.LIGHT_TEXT)
        Text('直接进主界面，教程可随时重看')
          .fontSize(11)
          .fontColor(AppConfig.LIGHT_SUB)
          .margin({ top: 4 })
      }
      .width('100%')
      .padding({ top: 16, bottom: 16 })
      .margin({ top: 12 })
      .backgroundColor(AppConfig.LIGHT_CARD)
      .borderRadius(14)
      .border({ width: 1, color: AppConfig.LIGHT_LINE })
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.onExpert();
      })

      Text('这个选择只在你第一次打开时出现')
        .fontSize(10)
        .fontColor('#A6ABB4')
        .margin({ top: 18, bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 28, right: 28 })
    .backgroundColor(AppConfig.LIGHT_BG)
    .alignItems(HorizontalAlign.Start)
  }
}