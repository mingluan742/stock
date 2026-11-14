import { AppConfig } from '../config/AppConfig';
import { RatePoint, RateSeries, RateService } from '../services/RateService';

/** 快捷区间 */
interface QuickRange {
  label: string;
  days: number;
}

const QUICK: QuickRange[] = [
  { label: '30天', days: 30 },
  { label: '90天', days: 90 },
  { label: '半年', days: 182 },
  { label: '一年', days: 365 }
];

/**
 * 汇率走势页（亮色，与盯盘页统一）：
 * - 数据源：欧洲央行参考汇率（frankfurter 公开接口），真实数据、免 Key
 * - 货币对：美元 / 欧元 / 日元 / 英镑 / 港币 / 澳元 对人民币
 * - 区间：30 天 ~ 一年快捷选择，也可自选起止日
 * - 模拟交易：虚拟资金按真实汇率买卖该货币对，支持多空、加仓、一键平仓
 */
@Component
export struct RateView {
  /** 返回主界面 */
  onBack: () => void = () => {};

  @State base: string = 'USD';
  @State activeDays: number = 90;
  @State startText: string = '';
  @State endText: string = '';
  @State loading: boolean = false;
  @State errorText: string = '';

  @State rateText: string = '--';
  @State changeText: string = '';
  @State up: boolean = true;
  @State openText: string = '--';
  @State closeText: string = '--';
  @State highText: string = '--';
  @State lowText: string = '--';
  @State volText: string = '--';
  @State countText: string = '';

  // ===== 模拟交易 =====
  /** 虚拟现金（元） */
  @State tradeCash: number = 1000000;
  /** 持仓份额（外币，正=多头 负=空头） */
  @State tradeShares: number = 0;
  /** 开仓均价 */
  @State tradeAvg: number = 0;
  /** 投入金额输入 */
  @State amountText: string = '100000';
  /** 交易提示 */
  @State tradeTip: string = '';

  // 日期选择弹层
  @State pickerOpen: boolean = false;
  @State pickerIsStart: boolean = true;
  @State pickerDate: Date = new Date();
  @State pickTip: string = '';

  private startDate: Date = new Date();
  private endDate: Date = new Date();
  private points: RatePoint[] = [];
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    this.setRange(90);
  }

  /** 快捷区间：结束日取今天 */
  setRange(days: number): void {
    const end: Date = new Date();
    const start: Date = new Date(end.getTime() - days * 86400000);
    this.startDate = start;
    this.endDate = end;
    this.activeDays = days;
    this.startText = RateService.fmt(start);
    this.endText = RateService.fmt(end);
    this.load();
  }

  /** 切换货币对 */
  switchBase(code: string): void {
    if (this.base === code) {
      return;
    }
    this.base = code;
    this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const s: RateSeries = await RateService.fetch(this.base, this.startDate, this.endDate);
      this.points = s.points;
      this.computeStats(s.points);
      this.drawChart();
    } catch (err) {
      const e = err as Error;
      this.errorText = `数据加载失败：${e.message}`;
      this.points = [];
      this.rateText = '--';
      this.countText = '';
    }
    this.loading = false;
  }

  /** 数值格式：小于 1 保留 4 位（日元等） */
  fmtRate(v: number): string {
    if (v < 1) {
      return v.toFixed(4);
    }
    return v.toFixed(2);
  }

  computeStats(pts: RatePoint[]): void {
    const n: number = pts.length;
    const first: number = pts[0].value;
    const last: number = pts[n - 1].value;
    const chg: number = (last - first) / first;
    this.rateText = this.fmtRate(last);
    this.up = chg >= 0;
    const sign: string = chg >= 0 ? '+' : '';
    this.changeText = `${sign}${(chg * 100).toFixed(2)}%`;
    this.openText = this.fmtRate(first);
    this.closeText = this.fmtRate(last);
    this.countText = `${n} 个交易日`;

    let hi: number = pts[0].value;
    let lo: number = pts[0].value;
    let hiDate: string = pts[0].date;
    let loDate: string = pts[0].date;
    for (const p of pts) {
      if (p.value > hi) {
        hi = p.value;
        hiDate = p.date;
      }
      if (p.value < lo) {
        lo = p.value;
        loDate = p.date;
      }
    }
    this.highText = `${this.fmtRate(hi)}（${hiDate.substring(5)}）`;
    this.lowText = `${this.fmtRate(lo)}（${loDate.substring(5)}）`;

    // 年化波动率：日对数收益标准差 × √250
    if (n >= 3) {
      const rets: number[] = [];
      for (let i = 1; i < n; i++) {
        rets.push(Math.log(pts[i].value / pts[i - 1].value));
      }
      let mean: number = 0;
      for (const r of rets) {
        mean += r;
      }
      mean = mean / rets.length;
      let sq: number = 0;
      for (const r of rets) {
        sq += (r - mean) * (r - mean);
      }
      const std: number = Math.sqrt(sq / rets.length);
      this.volText = `${(std * Math.sqrt(250) * 100).toFixed(2)}%`;
    } else {
      this.volText = '--';
    }
  }

  // ===== 模拟交易 =====

  /** 当前成交价：区间最后一个交易日 */
  tradePrice(): number {
    return this.points.length > 0 ? this.points[this.points.length - 1].value : 0;
  }

  /** 净资产 = 现金 + 持仓市值 */
  netValue(): number {
    return this.tradeCash + this.tradeShares * this.tradePrice();
  }

  /** 浮动盈亏 */
  pnlValue(): number {
    if (this.tradeShares === 0) {
      return 0;
    }
    return this.tradeShares * (this.tradePrice() - this.tradeAvg);
  }

  /** 金额千分位 */
  fmtMoney(v: number): string {
    const s: string = Math.abs(Math.round(v)).toString();
    let rest: string = s;
    let out: string = '';
    while (rest.length > 3) {
      out = `,${rest.substring(rest.length - 3)}${out}`;
      rest = rest.substring(0, rest.length - 3);
    }
    return rest + out;
  }

  /** 持仓描述 */
  sharesLabel(): string {
    if (this.tradeShares > 0) {
      return `多 ${Math.abs(this.tradeShares).toFixed(2)} ${this.base}`;
    }
    if (this.tradeShares < 0) {
      return `空 ${Math.abs(this.tradeShares).toFixed(2)} ${this.base}`;
    }
    return '空仓';
  }

  /** 盈亏描述 */
  pnlLabel(): string {
    const p: number = this.pnlValue();
    if (p === 0) {
      return '0';
    }
    return `${p >= 0 ? '+' : '-'}${this.fmtMoney(Math.abs(p))}`;
  }

  /** 解析投入金额 */
  parseAmount(): number {
    const v: number = parseFloat(this.amountText);
    if (!isFinite(v) || v <= 0) {
      return 0;
    }
    return v;
  }

  /** 一键填满可用现金 */
  fillTradeMax(): void {
    this.amountText = `${Math.floor(this.tradeCash)}`;
    this.tradeTip = '';
  }

  /** 应用一笔成交：delta > 0 买入，delta < 0 卖出（单位：外币） */
  applyTrade(delta: number, price: number): void {
    const old: number = this.tradeShares;
    const nu: number = old + delta;
    if (old === 0 || (old > 0 && delta > 0) || (old < 0 && delta < 0)) {
      // 同向开仓 / 加仓：均价加权
      const absOld: number = Math.abs(old);
      const absAdd: number = Math.abs(delta);
      this.tradeAvg = absOld === 0
        ? price
        : (absOld * this.tradeAvg + absAdd * price) / (absOld + absAdd);
    } else if ((old > 0 && nu < 0) || (old < 0 && nu > 0)) {
      // 反向穿仓：直接翻转为新方向
      this.tradeAvg = price;
    }
    // 部分平仓：均价不变
    this.tradeShares = nu;
    this.tradeCash -= delta * price;
  }

  /** 买入：看涨，多支付现金 */
  buyRate(): void {
    const price: number = this.tradePrice();
    if (price <= 0) {
      this.tradeTip = '汇率数据尚未加载';
      return;
    }
    const amt: number = this.parseAmount();
    if (amt <= 0) {
      this.tradeTip = '请输入有效金额';
      return;
    }
    if (amt > this.tradeCash) {
      this.tradeTip = `可用现金不足（当前 ${this.fmtMoney(this.tradeCash)} 元）`;
      return;
    }
    this.applyTrade(amt / price, price);
    this.tradeTip = '';
    this.showTip(`已买入 ${(amt / price).toFixed(2)} ${this.base}`);
  }

  /** 卖出：看跌，空头或平多 */
  sellRate(): void {
    const price: number = this.tradePrice();
    if (price <= 0) {
      this.tradeTip = '汇率数据尚未加载';
      return;
    }
    const amt: number = this.parseAmount();
    if (amt <= 0) {
      this.tradeTip = '请输入有效金额';
      return;
    }
    this.applyTrade(-amt / price, price);
    this.tradeTip = '';
    this.showTip(`已卖出 ${(amt / price).toFixed(2)} ${this.base}`);
  }

  /** 一键平仓：按当前汇率结算 */
  closePosition(): void {
    if (this.tradeShares === 0) {
      this.tradeTip = '当前没有持仓';
      return;
    }
    const pnl: number = this.pnlValue();
    this.tradeCash = this.netValue();
    this.tradeShares = 0;
    this.tradeAvg = 0;
    this.tradeTip = '';
    this.showTip(`已平仓，本笔${pnl >= 0 ? '盈利' : '亏损'} ${this.fmtMoney(Math.abs(pnl))} 元`);
  }

  /** 轻提示 */
  showTip(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1400 });
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] toast 失败: ${e.message}`);
    }
  }

  /** 打开日期选择 */
  openPicker(isStart: boolean): void {
    this.pickerIsStart = isStart;
    this.pickerDate = isStart ? this.startDate : this.endDate;
    this.pickTip = '';
    this.pickerOpen = true;
  }

  confirmPicker(): void {
    const s: Date = this.pickerIsStart ? this.pickerDate : this.startDate;
    const e: Date = this.pickerIsStart ? this.endDate : this.pickerDate;
    const days: number = RateService.dayDiff(s, e);
    if (days <= 0) {
      this.pickTip = '结束日期需要晚于开始日期';
      return;
    }
    if (days < RateService.MIN_DAYS || days > RateService.MAX_DAYS) {
      this.pickTip = `跨度需要在 ${RateService.MIN_DAYS}~${RateService.MAX_DAYS} 天之间，当前 ${days} 天`;
      return;
    }
    this.startDate = s;
    this.endDate = e;
    this.startText = RateService.fmt(s);
    this.endText = RateService.fmt(e);
    this.activeDays = 0;
    this.pickerOpen = false;
    this.load();
  }

  /** 绘制汇率曲线 */
  drawChart(): void {
    const c = this.ctx;
    const w: number = c.width;
    const h: number = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    c.clearRect(0, 0, w, h);
    const padL: number = 8;
    const padR: number = 8;
    const padT: number = 12;
    const padB: number = 12;
    const plotW: number = w - padL - padR;
    const plotH: number = h - padT - padB;

    c.strokeStyle = '#E6E9EF';
    c.lineWidth = 1;
    for (let i = 0; i <= 3; i++) {
      const gy: number = padT + (plotH * i) / 3;
      c.beginPath();
      c.moveTo(padL, gy);
      c.lineTo(padL + plotW, gy);
      c.stroke();
    }

    const n: number = this.points.length;
    if (n < 2) {
      return;
    }
    let minP: number = this.points[0].value;
    let maxP: number = this.points[0].value;
    for (const p of this.points) {
      if (p.value < minP) {
        minP = p.value;
      }
      if (p.value > maxP) {
        maxP = p.value;
      }
    }
    let range: number = maxP - minP;
    if (range < maxP * 0.0005) {
      range = Math.max(0.0001, maxP * 0.0005);
    }
    minP -= range * 0.12;
    maxP += range * 0.12;
    const span: number = maxP - minP;
    const stepX: number = plotW / (n - 1);
    const rising: boolean = this.points[n - 1].value >= this.points[0].value;
    const lineColor: string = rising ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN;
    const topColor: string = rising ? 'rgba(230,69,69,0.18)' : 'rgba(46,158,91,0.18)';
    const bottomColor: string = rising ? 'rgba(230,69,69,0.01)' : 'rgba(46,158,91,0.01)';

    // 面积
    c.beginPath();
    for (let i = 0; i < n; i++) {
      const x: number = padL + i * stepX;
      const y: number = padT + ((maxP - this.points[i].value) / span) * plotH;
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
      const x: number = padL + i * stepX;
      const y: number = padT + ((maxP - this.points[i].value) / span) * plotH;
      if (i === 0) {
        c.moveTo(x, y);
      } else {
        c.lineTo(x, y);
      }
    }
    c.strokeStyle = lineColor;
    c.lineWidth = 1.8;
    c.stroke();

    // 端点
    const lx: number = padL + plotW;
    const ly: number = padT + ((maxP - this.points[n - 1].value) / span) * plotH;
    c.beginPath();
    c.arc(lx, ly, 3.2, 0, Math.PI * 2);
    c.fillStyle = lineColor;
    c.fill();
  }

  build() {
    Stack() {
      Scroll() {
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
          Text('汇率走势')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppConfig.COLOR_TEXT)
            .margin({ left: 4 })
          Blank()
          Text('欧洲央行数据')
            .fontSize(10)
            .fontColor(AppConfig.COLOR_SUB)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14 })

        // 货币对
        Scroll() {
          Row({ space: 8 }) {
            ForEach(RateService.BASES, (code: string) => {
              Column() {
                Text(code)
                  .fontSize(13)
                  .fontWeight(this.base === code ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.base === code ? '#12141A' : '#4A4F58')
                Text('CNY')
                  .fontSize(8)
                  .fontColor(this.base === code ? '#12141A' : '#9AA0A9')
                  .margin({ top: 1 })
              }
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(this.base === code ? AppConfig.COLOR_ACCENT : '#EAEDF3')
              .borderRadius(10)
              .onClick(() => {
                this.switchBase(code);
              })
            }, (code: string) => code)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ top: 12 })

        // 快捷区间
        Row({ space: 8 }) {
          ForEach(QUICK, (q: QuickRange) => {
            Text(q.label)
              .fontSize(11)
              .fontColor(this.activeDays === q.days ? '#12141A' : '#7A808B')
              .backgroundColor(this.activeDays === q.days ? '#B7791F' : '#1E222A')
              .borderRadius(8)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => {
                this.setRange(q.days);
              })
          }, (q: QuickRange) => q.label)
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 10 })

        // 自选起止日
        Row() {
          Text(this.startText)
            .fontSize(11)
            .fontColor(AppConfig.COLOR_TEXT)
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .backgroundColor('#1E222A')
            .borderRadius(8)
            .onClick(() => {
              this.openPicker(true);
            })
          Text('→')
            .fontSize(11)
            .fontColor('#9AA0A9')
            .margin({ left: 8, right: 8 })
          Text(this.endText)
            .fontSize(11)
            .fontColor(AppConfig.COLOR_TEXT)
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .backgroundColor('#1E222A')
            .borderRadius(8)
            .onClick(() => {
              this.openPicker(false);
            })
          Blank()
          Text(this.countText)
            .fontSize(10)
            .fontColor('#9AA0A9')
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 10 })

        // 价格区
        Row() {
          Column() {
            Text(this.rateText)
              .fontSize(34)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.up ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
            Text(`${this.base} / CNY　${this.changeText}`)
              .fontSize(12)
              .fontColor(this.up ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Column() {
            Text(`波动率 ${this.volText}`)
              .fontSize(10)
              .fontColor(AppConfig.COLOR_SUB)
            Text('数据不加修饰')
              .fontSize(9)
              .fontColor('#5C626D')
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12 })

        // 图表
        Stack() {
          Canvas(this.ctx)
            .width('100%')
            .height(200)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .border({ width: 1, color: '#E9EBF0' })
            .onReady(() => {
              this.drawChart();
            })

          if (this.loading) {
            Column() {
              LoadingProgress()
                .width(24)
                .height(24)
                .color(AppConfig.LIGHT_GOLD_LINE)
              Text('正在拉取真实汇率…')
                .fontSize(10)
                .fontColor(AppConfig.COLOR_SUB)
                .margin({ top: 8 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('rgba(21,24,33,0.86)')
            .borderRadius(12)
          }

          if (!this.loading && this.errorText !== '') {
            Column() {
              Text(this.errorText)
                .fontSize(11)
                .fontColor('#E64545')
                .textAlign(TextAlign.Center)
                .padding({ left: 20, right: 20 })
              Button('重试')
                .height(32)
                .fontSize(12)
                .margin({ top: 10 })
                .backgroundColor('#EFF1F5')
                .fontColor(AppConfig.LIGHT_ACCENT)
                .onClick(() => {
                  this.load();
                })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('rgba(21,24,33,0.92)')
            .borderRadius(12)
          }
        }
        .width('100%')
        .height(200)
        .margin({ left: 16, right: 16, top: 12 })

        // 统计
        Row() {
          Column() {
            Text('期初')
              .fontSize(10)
              .fontColor(AppConfig.COLOR_SUB)
            Text(this.openText)
              .fontSize(13)
              .fontColor(AppConfig.COLOR_TEXT)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column() {
            Text('期末')
              .fontSize(10)
              .fontColor(AppConfig.COLOR_SUB)
            Text(this.closeText)
              .fontSize(13)
              .fontColor(AppConfig.COLOR_TEXT)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)

          Column() {
            Text('最高')
              .fontSize(10)
              .fontColor(AppConfig.COLOR_SUB)
            Text(this.highText)
              .fontSize(12)
              .fontColor(AppConfig.COLOR_TEXT)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)

          Column() {
            Text('最低')
              .fontSize(10)
              .fontColor(AppConfig.COLOR_SUB)
            Text(this.lowText)
              .fontSize(12)
              .fontColor(AppConfig.COLOR_TEXT)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.End)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14 })

        // 模拟交易卡（虚拟资金，真实汇率）
        Column() {
          Row() {
            Text('模拟交易')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppConfig.COLOR_TEXT)
            Text('虚拟资金 · 不涉及真实交易')
              .fontSize(9)
              .fontColor('#9AA0A9')
              .margin({ left: 8 })
            Blank()
            Text(`净资产 ${this.fmtMoney(this.netValue())}`)
              .fontSize(10)
              .fontColor(AppConfig.COLOR_SUB)
          }
          .width('100%')

          Row() {
            Column() {
              Text(`现金 ${this.fmtMoney(this.tradeCash)}`)
                .fontSize(9)
                .fontColor('#9AA0A9')
              Text(this.sharesLabel())
                .fontSize(11)
                .fontColor(this.tradeShares > 0 ? AppConfig.COLOR_UP
                  : (this.tradeShares < 0 ? AppConfig.COLOR_DOWN : '#9AA0A9'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Column() {
              Text(`浮动盈亏 ${this.pnlLabel()}`)
                .fontSize(10)
                .fontColor(this.pnlValue() >= 0 ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
              Text(this.tradeAvg > 0 ? `成本 ${this.fmtRate(this.tradeAvg)}` : '点击下方按钮开仓')
                .fontSize(9)
                .fontColor('#9AA0A9')
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.End)
            .layoutWeight(1)
          }
          .width('100%')
          .margin({ top: 8 })

          Row() {
            Text('¥')
              .fontSize(12)
              .fontColor('#7A808B')
              .margin({ left: 8 })
            TextInput({ text: this.amountText })
              .type(InputType.Number)
              .layoutWeight(1)
              .height(34)
              .fontSize(14)
              .fontColor(AppConfig.COLOR_TEXT)
              .backgroundColor(Color.Transparent)
              .onChange((v: string) => {
                this.amountText = v;
                this.tradeTip = '';
              })
            Text('MAX')
              .fontSize(9)
              .fontColor('#2E9E5B')
              .backgroundColor('#E4F4EA')
              .borderRadius(6)
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .margin({ right: 4 })
              .onClick(() => {
                this.fillTradeMax();
              })
          }
          .width('100%')
          .height(36)
          .margin({ top: 8 })
          .backgroundColor('#F4F6F9')
          .borderRadius(10)

          if (this.tradeTip !== '') {
            Text(this.tradeTip)
              .fontSize(10)
              .fontColor('#E64545')
              .margin({ top: 6 })
          }

          Row({ space: 10 }) {
            Button('▲ 买入 · 看涨')
              .layoutWeight(1)
              .height(44)
              .fontSize(14)
              .backgroundColor('#BFE8D2')
              .fontColor('#1F6B45')
              .borderRadius(12)
              .onClick(() => {
                this.buyRate();
              })
            Button('▼ 卖出 · 看跌')
              .layoutWeight(1)
              .height(44)
              .fontSize(14)
              .backgroundColor('#F7D9E1')
              .fontColor('#A63D5C')
              .borderRadius(12)
              .onClick(() => {
                this.sellRate();
              })
          }
          .width('100%')
          .margin({ top: 10 })

          Row() {
            Text('相同方向重复操作可加仓，反方向操作会先平掉旧仓')
              .fontSize(8)
              .fontColor('#B4B9C0')
            Blank()
            Text('一键平仓')
              .fontSize(10)
              .fontColor(AppConfig.LIGHT_ACCENT)
              .padding({ top: 6, bottom: 2, left: 8 })
              .onClick(() => {
                this.closePosition();
              })
          }
          .width('100%')
          .margin({ top: 6 })
        }
        .width('100%')
        .padding(12)
        .margin({ left: 16, right: 16, top: 12 })
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .border({ width: 1, color: '#E9EBF0' })
        .alignItems(HorizontalAlign.Start)

        Text('数据来自欧洲央行每日参考汇率，仅含交易日，周末与部分节假日无数据。')
          .fontSize(9)
          .fontColor('#5C626D')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24, bottom: 20 })
        }
        .width('100%')
        .padding({ bottom: 12 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

      // 日期选择弹层
      if (this.pickerOpen) {
        Column() {
          Column() {
            Row() {
              Text('取消')
                .fontSize(13)
                .fontColor(AppConfig.COLOR_SUB)
                .padding(8)
                .onClick(() => {
                  this.pickerOpen = false;
                })
              Blank()
              Text(this.pickerIsStart ? '选择开始日期' : '选择结束日期')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppConfig.COLOR_TEXT)
              Blank()
              Text('确定')
                .fontSize(13)
                .fontColor(AppConfig.LIGHT_ACCENT)
                .padding(8)
                .onClick(() => {
                  this.confirmPicker();
                })
            }
            .width('100%')

            if (this.pickTip !== '') {
              Text(this.pickTip)
                .fontSize(10)
                .fontColor('#E64545')
                .width('100%')
                .margin({ top: 4 })
            }

            DatePicker({
              start: new Date(2015, 0, 1),
              end: new Date(),
              selected: this.pickerDate
            })
              .width('100%')
              .onDateChange((value: Date) => {
                this.pickerDate = value;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 16 })
          .backgroundColor('#FFFFFF')
          .borderRadius({ topLeft: 20, topRight: 20 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('rgba(20,24,30,0.32)')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppConfig.COLOR_BG)
  }
}