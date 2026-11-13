import { AppConfig } from '../config/AppConfig';
import { AiService } from '../services/AiService';

/** 预设服务商 */
interface AiPreset {
  name: string;
  tag: string;
  url: string;
  model: string;
}

const PRESETS: AiPreset[] = [
  {
    name: '智谱 GLM-4-Flash', tag: '免费',
    url: 'https://open.bigmodel.cn/api/paas/v4/chat/completions', model: 'glm-4-flash'
  },
  {
    name: '硅基流动', tag: '有免费模型',
    url: 'https://api.siliconflow.cn/v1/chat/completions', model: 'Qwen/Qwen2.5-7B-Instruct'
  },
  {
    name: '百度千帆', tag: '有免费额度',
    url: 'https://qianfan.baidubce.com/v2/chat/completions', model: 'ernie-speed-8k'
  },
  {
    name: '本地 Ollama', tag: '免 Key',
    url: 'http://192.168.1.100:11434/v1/chat/completions', model: 'qwen2.5:3b'
  }
];

/**
 * 模型设置（明亮主题）：
 * 填写兼容 OpenAI 协议的接口地址、模型名与 API Key
 * Key 仅保存在本机，代码中不内置任何密钥
 */
@Component
export struct SettingsView {
  /** 返回上一级 */
  onBack: () => void = () => {};

  @State urlText: string = '';
  @State modelText: string = '';
  @State keyText: string = '';
  @State tip: string = '';
  @State tipOk: boolean = true;

  aboutToAppear(): void {
    const s = AiService.settings;
    this.urlText = s.baseUrl;
    this.modelText = s.model;
    this.keyText = s.key;
  }

  save(): void {
    AiService.save(this.urlText, this.modelText, this.keyText);
    this.tipOk = true;
    if (AiService.isLocalUrl(this.urlText)) {
      this.tip = '已保存。本地服务不需要 Key，请确认手机和电脑在同一 WiFi';
    } else if (this.keyText.trim() === '') {
      this.tip = '已保存，但未填 Key，AI 功能会使用本地文案';
    } else {
      this.tip = '已保存，去结算页试试 AI 复盘';
    }
  }

  /** 一键填入免费服务商 */
  applyPreset(p: AiPreset): void {
    this.urlText = p.url;
    this.modelText = p.model;
    this.tipOk = true;
    if (AiService.isLocalUrl(p.url)) {
      this.tip = '地址里的 IP 换成你电脑的局域网 IP；本地服务不需要 Key';
    } else {
      this.tip = `已填入 ${p.name}，再去官网申请一个 Key 即可`;
    }
  }

  clearKey(): void {
    this.keyText = '';
    AiService.save(this.urlText, this.modelText, '');
    this.tipOk = true;
    this.tip = '已清除 Key';
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
        Text('模型设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppConfig.LIGHT_TEXT)
          .margin({ left: 4 })
      }
      .width('100%')
      .padding({ left: 16, right: 20, top: 16 })

      Scroll() {
        Column() {
          Text('接入一个兼容 OpenAI 协议的大模型接口，结算页就能生成个性化的复盘点评。')
            .fontSize(11)
            .fontColor(AppConfig.LIGHT_SUB)
            .lineHeight(18)
            .width('100%')
            .margin({ top: 16 })

          // 免费服务商快选
          Column() {
            Text('快速选择（都提供免费额度，Key 去官网申请）')
              .fontSize(10)
              .fontColor(AppConfig.LIGHT_SUB)
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(PRESETS, (p: AiPreset) => {
                Text(`${p.name} · ${p.tag}`)
                  .fontSize(10)
                  .fontColor(AppConfig.LIGHT_ACCENT)
                  .backgroundColor(AppConfig.LIGHT_GOLD_BG)
                  .border({ width: 1, color: AppConfig.LIGHT_GOLD_LINE })
                  .borderRadius(9)
                  .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                  .margin({ right: 8, top: 8 })
                  .onClick(() => {
                    this.applyPreset(p);
                  })
              }, (p: AiPreset) => p.name)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 14 })

          // 接口地址
          Column() {
            Text('接口地址')
              .fontSize(10)
              .fontColor(AppConfig.LIGHT_SUB)
            TextInput({ text: this.urlText, placeholder: AiService.DEFAULT_URL })
              .fontSize(12)
              .height(42)
              .fontColor(AppConfig.LIGHT_TEXT)
              .placeholderColor('#B0B5BD')
              .backgroundColor('#F1F2F5')
              .borderRadius(10)
              .margin({ top: 6 })
              .onChange((v: string) => {
                this.urlText = v;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 18 })

          // 模型名
          Column() {
            Text('模型名称')
              .fontSize(10)
              .fontColor(AppConfig.LIGHT_SUB)
            TextInput({ text: this.modelText, placeholder: AiService.DEFAULT_MODEL })
              .fontSize(12)
              .height(42)
              .fontColor(AppConfig.LIGHT_TEXT)
              .placeholderColor('#B0B5BD')
              .backgroundColor('#F1F2F5')
              .borderRadius(10)
              .margin({ top: 6 })
              .onChange((v: string) => {
                this.modelText = v;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 16 })

          // Key
          Column() {
            Text('API Key')
              .fontSize(10)
              .fontColor(AppConfig.LIGHT_SUB)
            TextInput({ text: this.keyText, placeholder: 'sk-...' })
              .type(InputType.Password)
              .fontSize(12)
              .height(42)
              .fontColor(AppConfig.LIGHT_TEXT)
              .placeholderColor('#B0B5BD')
              .backgroundColor('#F1F2F5')
              .borderRadius(10)
              .margin({ top: 6 })
              .onChange((v: string) => {
                this.keyText = v;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 16 })

          if (this.tip !== '') {
            Text(this.tip)
              .fontSize(11)
              .fontColor(this.tipOk ? AppConfig.LIGHT_ACCENT : '#E64545')
              .margin({ top: 12 })
              .width('100%')
          }

          Row({ space: 10 }) {
            Button('保存')
              .layoutWeight(1)
              .height(46)
              .fontSize(15)
              .backgroundColor(AppConfig.LIGHT_ACCENT)
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.save();
              })
            Button('清除 Key')
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .backgroundColor('#EDEFF3')
              .fontColor('#5A606B')
              .onClick(() => {
                this.clearKey();
              })
          }
          .width('100%')
          .margin({ top: 22 })

          Column() {
            Text('说明')
              .fontSize(11)
              .fontColor(AppConfig.LIGHT_TEXT)
            Text('· Key 只保存在本机，不会上传到任何第三方服务器\n· 未填 Key 时，复盘页仍会显示本地生成的点评\n· 请求失败会自动退回本地文案，不影响使用\n· 接口需兼容 /chat/completions 格式（DeepSeek、通义、智谱等均可）')
              .fontSize(10)
              .fontColor('#8B909A')
              .lineHeight(19)
              .margin({ top: 8 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .margin({ top: 22, bottom: 24 })
          .backgroundColor(AppConfig.LIGHT_CARD)
          .borderRadius(12)
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppConfig.LIGHT_BG)
  }
}