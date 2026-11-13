import { AppConfig } from '../config/AppConfig';
import { TutorialService } from '../services/TutorialService';

/** 教程步骤内容 */
interface TutorialStep {
  title: string;
  body: string;
  hint: string;
  bullets: string[];
}

const STEPS: TutorialStep[] = [
  {
    title: '在历史的浪里练习',
    body: '这里没有真钱，也没有风险。你会在 7 段真实发生过的行情里买卖，看看当年的人是怎么被情绪推着走的。',
    hint: '所有数据仅用于教学，不构成任何投资建议。',
    bullets: ['1929 大崩盘、1987 黑色星期一、2000 互联网泡沫', '2008 次贷危机、2015 A股股灾、2016 熔断、2020 疫情']
  },
  {
    title: '先看懂盘面',
    body: '顶部大字是当前价格和涨跌幅，中间是不断向右生长的走势图，可以切换分时线或 K 线蜡烛。',
    hint: '右上角可以暂停。想快点看完就切到 K 线，一根蜡烛代表一个交易日。',
    bullets: ['红涨绿跌，和历史 A 股习惯一致', '下方「历史现场」会按日期累积当年的真实事件']
  },
  {
    title: '一次下单只要两个参数',
    body: '底部面板是常驻的，不用跳页。先填投入保证金，再拖杠杆倍数，股数、手续费、能承受的反向波动会自动算出来。',
    hint: '不确定填多少就点 MAX，系统会留出手续费。杠杆越高，越容易爆仓。',
    bullets: ['买入 = 按保证金 × 杠杆 建仓', '卖出 = 一键平掉全部可卖持仓']
  },
  {
    title: '复盘才是重点',
    body: '剧本走完或爆仓后进入结算页：收益率、最大回撤、胜率，还有每笔买卖落在曲线的什么位置。',
    hint: '成就系统会记录你的操作风格，条件达成后才揭晓。',
    bullets: ['对照「同期标的涨跌」，看自己是否跑赢什么都不做', '用逐笔流水回看当时为什么买']
  }
];

/**
 * 新手教程（明亮主题）：
 * 4 步图文讲解，底部可用口令「我是老手」直接跳过
 */
@Component
export struct TutorialView {
  /** 完成或跳过 */
  onDone: () => void = () => {};

  @State step: number = 0;
  @State title: string = '';
  @State body: string = '';
  @State hint: string = '';
  @State bullets: string[] = [];
  @State skipInput: string = '';
  @State skipError: string = '';

  aboutToAppear(): void {
    this.applyStep(0);
  }

  applyStep(i: number): void {
    this.step = i;
    const s: TutorialStep = STEPS[i];
    this.title = s.title;
    this.body = s.body;
    this.hint = s.hint;
    this.bullets = s.bullets;
  }

  next(): void {
    if (this.step < STEPS.length - 1) {
      this.applyStep(this.step + 1);
      return;
    }
    TutorialService.complete();
    this.onDone();
  }

  prev(): void {
    if (this.step > 0) {
      this.applyStep(this.step - 1);
    }
  }

  /** 输入口令时实时匹配，匹配即跳过 */
  onSkipChange(v: string): void {
    this.skipInput = v;
    this.skipError = '';
    if (TutorialService.isSkipWord(v)) {
      this.doSkip();
    }
  }

  doSkip(): void {
    if (!TutorialService.isSkipWord(this.skipInput)) {
      this.skipError = `口令不对，请输入「${TutorialService.SKIP_WORD}」`;
      return;
    }
    TutorialService.skip();
    this.onDone();
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('新手教程')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppConfig.LIGHT_TEXT)
        Blank()
        Text(`${this.step + 1} / ${STEPS.length}`)
          .fontSize(12)
          .fontColor(AppConfig.LIGHT_SUB)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 28 })

      // 步骤指示
      Row({ space: 6 }) {
        ForEach([0, 1, 2, 3], (i: number) => {
          Row()
            .width(i === this.step ? 22 : 6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(i <= this.step ? AppConfig.LIGHT_ACCENT : '#E3E5EA')
        }, (i: number) => `${i}`)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16 })

      // 正文卡片
      Column() {
        Text(this.title)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppConfig.LIGHT_TEXT)
          .width('100%')

        Text(this.body)
          .fontSize(13)
          .fontColor('#5A606B')
          .lineHeight(23)
          .margin({ top: 14 })
          .width('100%')

        Column() {
          ForEach(this.bullets, (b: string) => {
            Row() {
              Text('·')
                .fontSize(15)
                .fontColor(AppConfig.LIGHT_ACCENT)
                .width(14)
              Text(b)
                .fontSize(11)
                .fontColor('#7A808B')
                .lineHeight(18)
                .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 6 })
            .alignItems(VerticalAlign.Top)
          }, (b: string, i: number) => `${i}-${b}`)
        }
        .width('100%')
        .margin({ top: 18 })
        .alignItems(HorizontalAlign.Start)

        Text(this.hint)
          .fontSize(11)
          .fontColor('#9A8A66')
          .lineHeight(18)
          .width('100%')
          .padding(12)
          .margin({ top: 18 })
          .backgroundColor(AppConfig.LIGHT_GOLD_BG)
          .borderRadius(10)
      }
      .width('100%')
      .padding(22)
      .margin({ left: 24, right: 24, top: 20 })
      .backgroundColor(AppConfig.LIGHT_CARD)
      .borderRadius(18)
      .alignItems(HorizontalAlign.Start)
      .shadow({ radius: 16, color: 'rgba(16,24,40,0.06)', offsetX: 0, offsetY: 4 })

      Blank()

      // 口令跳过
      Column() {
        Row() {
          TextInput({ text: this.skipInput, placeholder: `已会用？输入「${TutorialService.SKIP_WORD}」跳过` })
            .layoutWeight(1)
            .height(42)
            .fontSize(12)
            .fontColor(AppConfig.LIGHT_TEXT)
            .placeholderColor('#A6ABB4')
            .backgroundColor('#F1F2F5')
            .borderRadius(10)
            .onChange((v: string) => {
              this.onSkipChange(v);
            })
          Button('跳过')
            .height(42)
            .fontSize(12)
            .margin({ left: 8 })
            .backgroundColor('#EDEFF3')
            .fontColor('#5A606B')
            .onClick(() => {
              this.doSkip();
            })
        }
        .width('100%')

        if (this.skipError !== '') {
          Text(this.skipError)
            .fontSize(10)
            .fontColor('#E64545')
            .width('100%')
            .margin({ top: 6 })
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 8 })

      // 翻页
      Row({ space: 10 }) {
        if (this.step > 0) {
          Button('上一步')
            .layoutWeight(1)
            .height(46)
            .fontSize(14)
            .backgroundColor('#EDEFF3')
            .fontColor('#5A606B')
            .onClick(() => {
              this.prev();
            })
        }
        Button(this.step === STEPS.length - 1 ? '开始练习' : '下一步')
          .layoutWeight(1.6)
          .height(46)
          .fontSize(15)
          .backgroundColor(AppConfig.LIGHT_ACCENT)
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.next();
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppConfig.LIGHT_BG)
  }
}