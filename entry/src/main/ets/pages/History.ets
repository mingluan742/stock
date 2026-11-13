import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../config/AppConfig';
import { AppContext } from '../core/AppContext';
import { MarketRuleConfig, ScenarioMeta } from '../models/Scenario';

/** 剧本列表条目 */
interface ScenarioItem {
  id: string;
  name: string;
  era: string;
  benchmark: string;
  eventCount: number;
  ruleText: string;
}

/**
 * 历史剧本列表页：
 * 列出内置的历史市场，点击进入实时盯盘
 */
@Entry
@Component
struct History {
  @State items: ScenarioItem[] = [];
  @State loading: boolean = true;

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      AppContext.init(host.resourceManager);
    }
    this.loadList();
  }

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

  enter(id: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/Index',
      params: { mode: 'history', id: id }
    }).catch((err: BusinessError) => {
      console.error(`[StockLab] 跳转失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      // 顶栏：返回 + 标题
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor(AppConfig.COLOR_SUB)
          .width(26)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text('历史剧本')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppConfig.COLOR_TEXT)
          .margin({ left: 4 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16 })

      Text('真实发生过的市场，重来一遍，看看当年的人经历了什么')
        .fontSize(11)
        .fontColor(AppConfig.COLOR_SUB)
        .width('100%')
        .padding({ left: 20, right: 20, top: 8 })

      if (this.loading) {
        Text('剧本加载中…')
          .fontSize(12)
          .fontColor(AppConfig.COLOR_SUB)
          .margin({ top: 24, left: 20 })
          .width('100%')
      }

      List() {
        ForEach(this.items, (item: ScenarioItem) => {
          ListItem() {
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
            .backgroundColor(AppConfig.COLOR_CARD)
            .borderRadius(14)
            .onClick(() => {
              this.enter(item.id);
            })
          }
          .margin({ bottom: 12 })
        }, (item: ScenarioItem) => item.id)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 20, right: 20, top: 16 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppConfig.COLOR_BG)
  }
}