import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../config/AppConfig';
import { AppContext } from '../core/AppContext';
import { MarketRuleConfig, ScenarioMeta } from '../models/Scenario';

/** 主界面展示用的剧本条目 */
interface ScenarioItem {
  id: string;
  name: string;
  era: string;
  benchmark: string;
  eventCount: number;
  ruleText: string;
}

/**
 * 主界面：
 * - 历史剧本：进入真实发生过的市场（1929 / 2015）
 * - 随机模拟：算法即时生成一局未知行情
 */
@Entry
@Component
struct Home {
  @State items: ScenarioItem[] = [];
  @State loading: boolean = true;

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      AppContext.init(host.resourceManager);
    }
    this.loadList();
  }

  /** 预加载剧本目录，供首页展示事件数与规则摘要 */
  async loadList(): Promise<void> {
    try {
      const market = AppContext.getMarket();
      const metas: ScenarioMeta[] = await market.listScenarios();
      const list: ScenarioItem[] = [];
      for (const m of metas) {
        await market.load(m.id);
        const rules: MarketRuleConfig | null = market.rules;
        list.push({
          id: m.id,
          name: m.name,
          era: m.era,
          benchmark: m.benchmark,
          eventCount: market.eventCount,
          ruleText: rules === null ? '' : this.ruleText(rules)
        });
      }
      this.items = list;
    } catch (err) {
      const e = err as Error;
      console.error(`[StockLab] 剧本列表加载失败: ${e.message}`);
      this.items = [];
    }
    this.loading = false;
  }

  ruleText(rules: MarketRuleConfig): string {
    const parts: string[] = [];
    parts.push(rules.priceLimit > 0 ? `±${Math.round(rules.priceLimit * 100)}% 涨跌停` : '无涨跌停');
    parts.push(rules.tPlus === 1 ? 'T+1' : 'T+0');
    if (rules.shortSell) {
      parts.push('可做空');
    }
    return parts.join(' · ');
  }

  enterHistory(id: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/Index',
      params: { mode: 'history', id: id }
    }).catch((err: BusinessError) => {
      console.error(`[StockLab] 跳转失败: ${err.message}`);
    });
  }

  enterRandom(): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/Index',
      params: { mode: 'random', id: '' }
    }).catch((err: BusinessError) => {
      console.error(`[StockLab] 跳转失败: ${err.message}`);
    });
  }

  build() {
    Scroll() {
      Column() {
        // 品牌区
        Column() {
          Text(AppConfig.APP_NAME)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppConfig.COLOR_TEXT)
          Text('在历史的风浪里，练习你的判断')
            .fontSize(12)
            .fontColor(AppConfig.COLOR_SUB)
            .margin({ top: 8 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 32 })

        // 历史剧本
        Row() {
          Text('历史剧本')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppConfig.COLOR_TEXT)
          Text('复盘真实发生过的市场')
            .fontSize(11)
            .fontColor('#6B717C')
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 32 })

        if (this.loading) {
          Text('剧本加载中…')
            .fontSize(12)
            .fontColor(AppConfig.COLOR_SUB)
            .margin({ top: 16 })
        }

        ForEach(this.items, (item: ScenarioItem) => {
          Column() {
            Row() {
              Text(item.name)
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppConfig.COLOR_TEXT)
              Blank()
              Text(`${item.eventCount} 个历史事件`)
                .fontSize(10)
                .fontColor(AppConfig.COLOR_ACCENT)
            }
            .width('100%')

            Text(`${item.era} · ${item.benchmark}`)
              .fontSize(11)
              .fontColor(AppConfig.COLOR_SUB)
              .margin({ top: 6 })

            Text(item.ruleText)
              .fontSize(10)
              .fontColor('#6B717C')
              .margin({ top: 4 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .margin({ top: 12 })
          .backgroundColor(AppConfig.COLOR_CARD)
          .borderRadius(14)
          .onClick(() => {
            this.enterHistory(item.id);
          })
        }, (item: ScenarioItem) => item.id)

        // 随机模拟
        Row() {
          Text('随机模拟')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppConfig.COLOR_TEXT)
          Text('没有答案，只有判断')
            .fontSize(11)
            .fontColor('#6B717C')
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 32 })

        Column() {
          Text('随机模拟股市')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppConfig.COLOR_TEXT)
          Text('算法即时生成一段全新行情：走势、波动、突发消息都无法预测。观察趋势、控制仓位，看看你的判断能否穿过未知的牛熊。')
            .fontSize(11)
            .fontColor('#8A8F99')
            .lineHeight(18)
            .margin({ top: 8 })
            .width('100%')
          Button('开始一局')
            .width('100%')
            .height(44)
            .fontSize(15)
            .margin({ top: 16 })
            .backgroundColor(AppConfig.COLOR_ACCENT)
            .fontColor('#12141A')
            .onClick(() => {
              this.enterRandom();
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(20)
        .margin({ top: 12 })
        .backgroundColor('#1A1E26')
        .borderRadius(14)
        .border({ width: 1, color: '#3A3325' })

        Text('数据为教学演示，非精确历史行情')
          .fontSize(10)
          .fontColor('#4E535C')
          .margin({ top: 28, bottom: 28 })
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppConfig.COLOR_BG)
    .scrollBar(BarState.Off)
  }
}