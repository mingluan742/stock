import { AppConfig } from '../config/AppConfig';
import { AppContext } from '../core/AppContext';
import { AchievementItem } from '../models/Achievement';
import { KLine } from '../models/KLine';
import { TradeRecord } from '../models/TradeRecord';
import { AiService, ReviewInput } from '../services/AiService';

/** 复盘页流水展示项（把数值格式化成文本，避免模板里做运算） */
interface FlowItem {
  date: string;
  side: string;
  priceText: string;
  qtyText: string;
  realizedText: string;
  up: boolean;
}

/** 图上最多标注的买卖点数量，避免密集重叠 */
const MARK_LIMIT: number = 80;

/**
 * 结算复盘页：
 * - 汇总收益率、最大回撤、交易笔数、胜率、手续费
 * - 用整段行情曲线标注买卖点，直观看到"每次操作落在什么位置"
 * - 逐笔列出交易流水
 * 数据直接取自 AppContext 中的行情与交易服务，无需路由传参
 */
@Component
export struct ResultView {
  /** 进入模式：history / random */
  @Prop mode: string = 'history';
  @Prop scenarioId: string = AppConfig.DEFAULT_SCENARIO;
  /** 返回上一级 */
  onBack: () => void = () => {};
  /** 重播本局 */
  onReplay: () => void = () => {};
  /** 去模型设置 */
  onGoSettings: () => void = () => {};

  @State scenarioName: string = '';
  @State eraText: string = '';
  @State returnText: string = '0.00%';
  @State returnUp: boolean = true;
  @State netText: string = '--';
  @State initText: string = '--';
  @State drawdownText: string = '0.00%';
  @State tradeCountText: string = '0';
  @State winRateText: string = '--';
  @State feeText: string = '0';
  @State debtText: string = '0';
  @State interestText: string = '0';
  @State benchText: string = '';
  @State verdictText: string = '';
  @State flows: FlowItem[] = [];
  /** 本局新解锁的成就 */
  @State newItems: AchievementItem[] = [];
  // AI 复盘
  @State aiText: string = '';
  @State aiLoading: boolean = false;
  @State aiError: string = '';
  @State hasKey: boolean = false;

  private retValue: number = 0;
  private benchValue: number = 0;
  private isBankrupt: boolean = false;

  private prices: number[] = [];
  private dateIndex: Map<string, number> = new Map<string, number>();
  private records: TradeRecord[] = [];
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    this.loadData();
  }

  /** 从行情/交易服务汇总本局结果 */
  loadData(): void {
    const market = AppContext.getMarket();
    const trading = AppContext.getTrading();
    const meta = market.meta;
    if (meta !== null) {
      this.scenarioName = meta.name;
      this.eraText = meta.era;
    }
    this.prices = market.historyPrices();
    const dates: string[] = market.historyDates();
    this.dateIndex = new Map<string, number>();
    for (let i = 0; i < dates.length; i++) {
      this.dateIndex.set(dates[i], i);
    }
    this.records = trading.tradeRecords;

    const lastPrice: number = this.prices.length > 0 ? this.prices[this.prices.length - 1] : 0;
    // 多标的：按各股票最新价设置估值（合并净资产才准确）
    if (market.stocks.length > 0) {
      const map: Record<string, number> = {};
      for (const st of market.stocks) {
        const tl: KLine[] = st.timeline;
        if (tl.length > 0) {
          map[st.id] = tl[tl.length - 1].price;
        }
      }
      trading.setValuationPrices(map);
    }
    const net: number = trading.netAsset(lastPrice);
    const ret: number = (net - AppConfig.INIT_CASH) / AppConfig.INIT_CASH;
    this.returnUp = ret >= 0;
    this.retValue = ret;
    this.isBankrupt = net <= 0;
    this.returnText = `${ret >= 0 ? '+' : ''}${(ret * 100).toFixed(2)}%`;
    this.netText = `${net < 0 ? '-' : ''}${this.formatMoney(Math.abs(net))}`;
    this.initText = this.formatMoney(AppConfig.INIT_CASH);
    this.drawdownText = `${(trading.maxDrawdown * 100).toFixed(2)}%`;
    this.tradeCountText = `${trading.tradeCount} 笔`;
    this.winRateText = trading.tradeCount === 0 ? '--' : `${(trading.winRate * 100).toFixed(0)}%`;
    this.feeText = this.formatMoney(trading.feeTotal);
    this.debtText = this.formatMoney(trading.debt);
    this.interestText = this.formatMoney(trading.debtInterest);
    // 同期标的涨跌：对照"什么都不做"的结果
    let bench: number = 0;
    if (this.prices.length >= 2 && this.prices[0] > 0) {
      bench = (this.prices[this.prices.length - 1] - this.prices[0]) / this.prices[0];
      const sign: string = bench >= 0 ? '+' : '';
      this.benchText = `同期标的 ${sign}${(bench * 100).toFixed(2)}%，${ret >= bench ? '跑赢' : '跑输'} ${Math.abs((ret - bench) * 100).toFixed(2)} 个百分点`;
    } else {
      this.benchText = '';
    }
    this.benchValue = bench;

    if (trading.tradeCount === 0) {
      this.verdictText = '一局下来没有出手。在市场里，"不做"也是一种选择。';
    } else if (ret < -0.5) {
      this.verdictText = '亏损超过一半。杠杆和重仓在极端行情里会放大伤害，先学会控制仓位。';
    } else if (ret < 0) {
      this.verdictText = '小亏收场。多数人输在频繁交易与追涨杀跌上，手续费也是一种成本。';
    } else if (ret > 0.3) {
      this.verdictText = '收益不错。但请把这一局的运气与判断分开看，下一次未必一样。';
    } else {
      this.verdictText = '略有盈利。稳定比暴利更难。';
    }

    this.buildFlows();
    this.newItems = AppContext.getAchievements().sessionUnlocked();
    this.hasKey = AiService.hasKey;
    this.drawEquity();
  }

  buildFlows(): void {
    const list: FlowItem[] = [];
    // 最新一笔在最上面
    for (let i = this.records.length - 1; i >= 0; i--) {
      const r: TradeRecord = this.records[i];
      list.push({
        date: r.date,
        side: r.side,
        priceText: r.price.toFixed(2),
        qtyText: `${r.qty} 股`,
        realizedText: r.realized === 0 ? '—' : `${r.realized > 0 ? '+' : '-'}${this.formatMoney(Math.abs(r.realized))}`,
        up: r.side === '买'
      });
    }
    this.flows = list;
  }

  /** 把最近 20 笔交易整理成给模型看的摘要 */
  buildFlowText(): string {
    const list: TradeRecord[] = this.records;
    const start: number = Math.max(0, list.length - 20);
    let out: string = '';
    for (let i = start; i < list.length; i++) {
      const r: TradeRecord = list[i];
      if (out !== '') {
        out += '\n';
      }
      let pnl: string = '开仓';
      if (r.realized !== 0) {
        pnl = r.realized > 0 ? `+${Math.round(r.realized)}` : `${Math.round(r.realized)}`;
      }
      out += `${r.date} ${r.side} ${r.price.toFixed(2)} ${r.qty}股 ${pnl}`;
    }
    return out;
  }

  /** 请求 AI 复盘点评 */
  async requestAi(): Promise<void> {
    if (!AiService.hasKey) {
      this.aiError = '还没有配置 API Key，去主界面「模型设置」填一个';
      return;
    }
    this.aiLoading = true;
    this.aiError = '';
    try {
      const t = AppContext.getTrading();
      const input: ReviewInput = {
        scenarioName: this.scenarioName,
        era: this.eraText,
        mode: this.mode,
        returnPct: this.retValue,
        benchPct: this.benchValue,
        maxDrawdown: t.maxDrawdown,
        tradeCount: t.tradeCount,
        winRate: t.winRate,
        feeTotal: t.feeTotal,
        maxLeverage: t.maxLeverageUsed,
        debt: t.debt,
        bankrupt: this.isBankrupt,
        flowText: this.buildFlowText()
      };
      const text: string = await AiService.review(input);
      this.aiText = text;
    } catch (err) {
      const e = err as Error;
      this.aiError = `AI 点评失败：${e.message}`;
    }
    this.aiLoading = false;
  }

  formatMoney(v: number): string {
    const s: string = Math.abs(Math.round(v)).toString();
    let rest: string = s;
    let out: string = '';
    while (rest.length > 3) {
      out = `,${rest.substring(rest.length - 3)}${out}`;
      rest = rest.substring(0, rest.length - 3);
    }
    return rest + out;
  }

  /** 绘制完整行情曲线并标注买卖点 */
  drawEquity(): void {
    const c = this.ctx;
    const w: number = c.width;
    const h: number = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    c.clearRect(0, 0, w, h);
    const padL: number = 8;
    const padR: number = 8;
    const padT: number = 14;
    const padB: number = 14;
    const plotW: number = w - padL - padR;
    const plotH: number = h - padT - padB;

    // 横向网格
    c.strokeStyle = '#23272F';
    c.lineWidth = 1;
    for (let i = 0; i <= 3; i++) {
      const gy: number = padT + (plotH * i) / 3;
      c.beginPath();
      c.moveTo(padL, gy);
      c.lineTo(padL + plotW, gy);
      c.stroke();
    }

    const n: number = this.prices.length;
    if (n < 2) {
      return;
    }
    let minP: number = this.prices[0];
    let maxP: number = this.prices[0];
    for (const p of this.prices) {
      if (p < minP) {
        minP = p;
      }
      if (p > maxP) {
        maxP = p;
      }
    }
    let range: number = maxP - minP;
    if (range < maxP * 0.001) {
      range = Math.max(0.01, maxP * 0.001);
    }
    minP -= range * 0.12;
    maxP += range * 0.12;
    const span: number = maxP - minP;
    const stepX: number = plotW / (n - 1);
    const up: boolean = this.prices[n - 1] >= this.prices[0];
    const lineColor: string = up ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN;
    const topColor: string = up ? 'rgba(230,69,69,0.26)' : 'rgba(46,158,91,0.26)';
    const bottomColor: string = up ? 'rgba(230,69,69,0.02)' : 'rgba(46,158,91,0.02)';

    const xOf = (i: number): number => padL + i * stepX;
    const yOf = (p: number): number => padT + ((maxP - p) / span) * plotH;

    // 面积
    c.beginPath();
    for (let i = 0; i < n; i++) {
      const x: number = xOf(i);
      const y: number = yOf(this.prices[i]);
      if (i === 0) {
        c.moveTo(x, y);
      } else {
        c.lineTo(x, y);
      }
    }
    c.lineTo(padL + plotW, padT + plotH);
    c.lineTo(padL, padT + plotH);
    c.closePath();
    const grad: CanvasGradient = c.createLinearGradient(0, padT, 0, padT + plotH);
    grad.addColorStop(0, topColor);
    grad.addColorStop(1, bottomColor);
    c.fillStyle = grad;
    c.fill();

    // 折线
    c.beginPath();
    for (let i = 0; i < n; i++) {
      const x: number = xOf(i);
      const y: number = yOf(this.prices[i]);
      if (i === 0) {
        c.moveTo(x, y);
      } else {
        c.lineTo(x, y);
      }
    }
    c.strokeStyle = lineColor;
    c.lineWidth = 1.6;
    c.stroke();

    // 买卖点（只标注最近 MARK_LIMIT 笔）
    const start: number = Math.max(0, this.records.length - MARK_LIMIT);
    for (let i = start; i < this.records.length; i++) {
      const r: TradeRecord = this.records[i];
      const idx: number | undefined = this.dateIndex.get(r.date);
      if (idx === undefined || idx < 0 || idx >= n) {
        continue;
      }
      const x: number = xOf(idx);
      const y: number = yOf(this.prices[idx]);
      if (r.side === '买') {
        // 买点：红三角，标在价格点下方
        c.beginPath();
        c.moveTo(x, y + 3);
        c.lineTo(x - 3.6, y + 10);
        c.lineTo(x + 3.6, y + 10);
        c.closePath();
        c.fillStyle = AppConfig.COLOR_UP;
        c.fill();
      } else {
        // 卖点：绿三角，标在价格点上方
        c.beginPath();
        c.moveTo(x, y - 3);
        c.lineTo(x - 3.6, y - 10);
        c.lineTo(x + 3.6, y - 10);
        c.closePath();
        c.fillStyle = AppConfig.COLOR_DOWN;
        c.fill();
      }
    }
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor(AppConfig.COLOR_SUB)
          .width(26)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onBack();
          })
        Text('结算复盘')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppConfig.COLOR_TEXT)
          .margin({ left: 4 })
        Blank()
        Text(this.scenarioName)
          .fontSize(12)
          .fontColor(AppConfig.COLOR_ACCENT)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 6 })

      Scroll() {
        Column() {
          // 收益卡
          Column() {
            Text(this.eraText)
              .fontSize(11)
              .fontColor(AppConfig.COLOR_SUB)
            Text(this.returnText)
              .fontSize(44)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.returnUp ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
              .margin({ top: 6 })
            Text('本局收益率')
              .fontSize(11)
              .fontColor(AppConfig.COLOR_SUB)
              .margin({ top: 2 })
            Row() {
              Column() {
                Text('初始资金')
                  .fontSize(10)
                  .fontColor(AppConfig.COLOR_SUB)
                Text(this.initText)
                  .fontSize(13)
                  .fontColor(AppConfig.COLOR_TEXT)
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column() {
                Text('最终净资产')
                  .fontSize(10)
                  .fontColor(AppConfig.COLOR_SUB)
                Text(this.netText)
                  .fontSize(13)
                  .fontColor(AppConfig.COLOR_TEXT)
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.End)
              .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 14 })
          }
          .width('100%')
          .padding(18)
          .backgroundColor(AppConfig.COLOR_CARD)
          .borderRadius(14)
          .alignItems(HorizontalAlign.Start)

          // 四宫格指标
          Row({ space: 10 }) {
            this.metricCard('最大回撤', this.drawdownText)
            this.metricCard('交易笔数', this.tradeCountText)
          }
          .width('100%')
          .margin({ top: 10 })

          Row({ space: 10 }) {
            this.metricCard('胜率', this.winRateText)
            this.metricCard('手续费', this.feeText)
          }
          .width('100%')
          .margin({ top: 10 })

          Row({ space: 10 }) {
            this.metricCard('累计利息', this.interestText)
            this.metricCard('期末负债', this.debtText)
          }
          .width('100%')
          .margin({ top: 10 })

          // 对照说明
          if (this.benchText !== '') {
            Text(this.benchText)
              .fontSize(11)
              .fontColor('#9AA0AA')
              .width('100%')
              .margin({ top: 10, left: 2 })
          }

          // 本局新解锁成就
          if (this.newItems.length > 0) {
            Column() {
              Row() {
                Text('本局解锁')
                  .fontSize(11)
                  .fontColor(AppConfig.COLOR_ACCENT)
                Blank()
                Text(`${this.newItems.length} 个成就`)
                  .fontSize(10)
                  .fontColor(AppConfig.COLOR_SUB)
              }
              .width('100%')

              ForEach(this.newItems, (item: AchievementItem) => {
                Row() {
                  Text(item.icon)
                    .fontSize(14)
                    .fontColor(AppConfig.COLOR_ACCENT)
                    .width(20)
                  Text(item.name)
                    .fontSize(12)
                    .fontColor(AppConfig.COLOR_TEXT)
                    .layoutWeight(1)
                  Text(item.tier === 2 ? '传说' : (item.tier === 1 ? '稀有' : ''))
                    .fontSize(9)
                    .fontColor('#C9A227')
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
              }, (item: AchievementItem) => item.id)
            }
            .width('100%')
            .padding(14)
            .margin({ top: 10 })
            .backgroundColor(AppConfig.COLOR_CARD)
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)
          }

          Text(this.verdictText)
            .fontSize(12)
            .fontColor('#C9CDD6')
            .lineHeight(19)
            .width('100%')
            .padding(12)
            .margin({ top: 10 })
            .backgroundColor('#181C24')
            .borderRadius(10)

          // AI 复盘点评
          Column() {
            Row() {
              Text('AI 复盘教练')
                .fontSize(11)
                .fontColor(AppConfig.COLOR_ACCENT)
              Blank()
              if (this.aiText !== '' && !this.aiLoading) {
                Text('重新生成')
                  .fontSize(10)
                  .fontColor(AppConfig.COLOR_SUB)
                  .padding(4)
                  .onClick(() => {
                    this.requestAi();
                  })
              }
            }
            .width('100%')

            if (this.aiLoading) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color(AppConfig.COLOR_ACCENT)
                Text('正在读这一局的操作…')
                  .fontSize(11)
                  .fontColor(AppConfig.COLOR_SUB)
              }
              .width('100%')
              .margin({ top: 10 })
            } else if (this.aiText !== '') {
              Text(this.aiText)
                .fontSize(12)
                .fontColor('#C9CDD6')
                .lineHeight(20)
                .width('100%')
                .margin({ top: 8 })
            } else {
              Text('把收益、回撤、胜率和每笔流水交给模型，生成一段只针对这一局的点评。')
                .fontSize(11)
                .fontColor('#8A8F99')
                .lineHeight(18)
                .width('100%')
                .margin({ top: 8 })
              if (this.hasKey) {
                Button('生成 AI 点评')
                  .height(36)
                  .fontSize(12)
                  .margin({ top: 10 })
                  .backgroundColor('#2A2F3A')
                  .fontColor(AppConfig.COLOR_ACCENT)
                  .onClick(() => {
                    this.requestAi();
                  })
              } else {
                Row({ space: 10 }) {
                  Button('去设置 API Key')
                    .height(36)
                    .fontSize(12)
                    .backgroundColor('#2A2F3A')
                    .fontColor(AppConfig.COLOR_ACCENT)
                    .onClick(() => {
                      this.onGoSettings();
                    })
                }
                .margin({ top: 10 })
              }
            }

            if (this.aiError !== '') {
              Text(this.aiError)
                .fontSize(10)
                .fontColor('#E64545')
                .lineHeight(16)
                .margin({ top: 8 })
                .width('100%')
            }
          }
          .width('100%')
          .padding(14)
          .margin({ top: 10 })
          .backgroundColor(AppConfig.COLOR_CARD)
          .borderRadius(12)
          .alignItems(HorizontalAlign.Start)

          // 行情曲线 + 买卖点
          Column() {
            Row() {
              Text('全程行情与买卖点')
                .fontSize(11)
                .fontColor(AppConfig.COLOR_ACCENT)
              Blank()
              Text('▲ 买入　▼ 卖出')
                .fontSize(10)
                .fontColor(AppConfig.COLOR_SUB)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 6 })

            Canvas(this.ctx)
              .width('100%')
              .height(170)
              .backgroundColor('#151821')
              .borderRadius(10)
              .onReady(() => {
                this.drawEquity();
              })
          }
          .width('100%')
          .padding({ left: 6, right: 6, bottom: 6 })
          .margin({ top: 12 })
          .backgroundColor(AppConfig.COLOR_CARD)
          .borderRadius(14)

          // 交易流水
          Column() {
            Row() {
              Text('交易流水')
                .fontSize(11)
                .fontColor(AppConfig.COLOR_ACCENT)
              Blank()
              Text(`${this.flows.length} 笔 · 负债 ${this.debtText}`)
                .fontSize(10)
                .fontColor(AppConfig.COLOR_SUB)
            }
            .width('100%')
            .margin({ bottom: 6 })

            if (this.flows.length === 0) {
              Text('本局没有成交记录')
                .fontSize(11)
                .fontColor('#6B717C')
                .width('100%')
                .padding({ top: 10, bottom: 10 })
            } else {
              ForEach(this.flows, (item: FlowItem) => {
                Row() {
                  Text(item.date)
                    .fontSize(10)
                    .fontColor('#7A808B')
                    .width(80)
                  Text(item.side)
                    .fontSize(11)
                    .fontColor(item.up ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
                    .width(24)
                  Text(item.priceText)
                    .fontSize(11)
                    .fontColor(AppConfig.COLOR_TEXT)
                    .layoutWeight(1)
                  Text(item.qtyText)
                    .fontSize(10)
                    .fontColor(AppConfig.COLOR_SUB)
                    .width(58)
                    .textAlign(TextAlign.End)
                  Text(item.realizedText)
                    .fontSize(11)
                    .fontColor('#C9CDD6')
                    .width(84)
                    .textAlign(TextAlign.End)
                }
                .width('100%')
                .padding({ top: 7, bottom: 7 })
              }, (item: FlowItem, index: number) => `${index}-${item.date}-${item.side}-${item.priceText}`)
            }
          }
          .width('100%')
          .padding(12)
          .margin({ top: 12 })
          .backgroundColor(AppConfig.COLOR_CARD)
          .borderRadius(14)
          .alignItems(HorizontalAlign.Start)

          Text('数据为教学演示用行情，节点间为插值结果，非精确历史成交价。')
            .fontSize(10)
            .fontColor('#6B717C')
            .width('100%')
            .margin({ top: 12, bottom: 4 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部操作
      Row({ space: 10 }) {
        Button('重播本局')
          .layoutWeight(1)
          .height(46)
          .fontSize(15)
          .backgroundColor('#2A2F3A')
          .fontColor(AppConfig.COLOR_ACCENT)
          .onClick(() => {
            this.onReplay();
          })
        Button('返回')
          .layoutWeight(1)
          .height(46)
          .fontSize(15)
          .backgroundColor(AppConfig.COLOR_ACCENT)
          .fontColor('#12141A')
          .onClick(() => {
            this.onBack();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppConfig.COLOR_BG)
  }

  /** 指标小卡 */
  @Builder
  metricCard(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(10)
        .fontColor(AppConfig.COLOR_SUB)
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppConfig.COLOR_TEXT)
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(AppConfig.COLOR_CARD)
    .borderRadius(12)
  }
}