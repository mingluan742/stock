---
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: 'caa9e22d-fb4f-4173-8e61-7a1c972adf55'
  PropagateID: 'caa9e22d-fb4f-4173-8e61-7a1c972adf55'
  ReservedCode1: 'b1a72e2d-870c-493c-9f66-4086868a4bb7'
  ReservedCode2: 'b1a72e2d-870c-493c-9f66-4086868a4bb7'
---

# 涨跌实验室（StockLab）

一款 HarmonyOS 的"历史股市模拟器"：在真实发生过的市场里（1929 大崩盘、2015 A股股灾）或用算法随机生成的市场里，实时盯盘、买卖、加杠杆、借贷款，体验不同的市场规则与人性。

> 数据为教学演示，关键历史点位取自公开资料，节点之间为插值生成，非精确历史行情，不构成任何投资建议。

## 快速开始

- 开发工具：DevEco Studio（SDK 6.1.1 / API 24）
- 打开 `D:\Stock` 工程，等待 Sync 完成
- 预览器打开 `pages/App.ets`（页面用状态机切换，预览器可直接点击）
- 或连接模拟器 / 真机运行

## 功能

| 模块 | 说明 |
|---|---|
| 历史剧本 | 1929 大崩盘（道指 744 个交易日）、2015 A股股灾（上证 168 个交易日） |
| 随机模拟 | 算法即时生成：随机股票名、260~440 个交易日、分段牛熊、随机突发消息、随机市场规则 |
| 实时盯盘 | 定时推进行情，Canvas 分时曲线自动生长；可分时 / K线双模式切换 |
| 历史现场 | 走到历史事件日自动累积事件卡片，可上下滑动回看 |
| 交易规则 | 手续费、T+1、涨跌停封板、做空，全部按剧本规则生效 |
| 贷款 | 额度 100 万、年化 8%、按交易日复利计息、可借可还；净资产 ≤ 0 爆仓 |
| 杠杆 | 1x / 2x / 3x / 5x，按保证金交易，不足部分自动融资 |
| 存档 | 自动保存当前对局（每 5 个交易日 + 每次交易），主界面可"继续上一局" |

## 技术架构

单体应用分五层 + 两个横切关注点：

```
L1 表现层   views/（HomeView / HistoryView / TradeView）+ pages/App.ets（状态机入口）
L2 调度层   视图内状态与交互编排（@State / @Prop）
L3 业务层   services/（MarketService 行情、TradingService 交易、RandomScenarioService 随机生成）
L4 数据层   repository/（IMarketDataSource 接口 + BuiltinScenarioSource 实现）
L5 存储层   core/SaveService（AppStorage + PersistentStorage JSON 快照）
横切 A     core/（Result 统一返回、EventBus 事件总线、AppContext 服务定位）
横切 B     config/（常量与主题色）+ models/（实体接口）
```

目录结构：

```
entry/src/main/ets/
├─ pages/App.ets            唯一入口页，状态机切换三个视图
├─ views/                   三个视图组件（主界面 / 剧本列表 / 盯盘）
├─ services/                行情、交易、随机生成
├─ repository/              数据源接口与内置实现
│  └─ data/                 ArkTS 内置剧本数据（rawfile 不可用时的回退）
├─ core/                    Result / EventBus / AppContext / SaveService
├─ models/                  KLine / Scenario / ScenarioEvent / Account
├─ config/AppConfig.ets     常量与主题色
└─ entryability/            应用入口，装配服务与持久化键
```

关键设计：

- **接口驱动数据源**：`IMarketDataSource` 定义"剧本目录 + 加载剧本"，`BuiltinScenarioSource` 优先读 rawfile，失败自动回退 ArkTS 内置数据（兼容预览器）；
- **规则参数化**：每个剧本自带 `rules`（涨跌停、T+1、费率、能否做空），同一套交易代码跑出不同市场；
- **状态机代替路由**：三视图用 `@State view` 切换，避免预览器不支持 router 的问题；
- **确定性伪随机**：K线高低点用 `Math.sin` 按蜡烛序号派生，重绘不闪烁；
- **单例装配**：`AppContext` 统一创建服务，换数据源只改一行。

## 市场规则

| 规则 | 实现 |
|---|---|
| 手续费 | 买卖双边按 `feeRate` 收取，累计显示 |
| T+1 | 当日买入的仓位冻结，次日可卖 |
| 涨跌停 | 当日涨跌达到限制的 95% 视为封板：涨停买不进、跌停卖不出 |
| 做空 | 仅允许做空的剧本可负持仓，上限 500 股，按卖出价记空头均价 |
| 贷款 | 上限 100 万，日利率 0.032%（年化 8% / 250 交易日），复利计息 |
| 杠杆 | 保证金 = 市值 / 倍数；融资额 = 市值 - 保证金，计入负债 |
| 爆仓 | 净资产 = 现金 + 持仓市值 - 负债 ≤ 0 即爆仓 |

## 单元测试

`entry/src/test/TradingService.test.ets` 覆盖 14 个用例：手续费、现金校验、均价结转、T+1、涨跌停、做空、贷款计息、杠杆保证金、净资产与爆仓。

- DevEco 中右键 `entry/src/test` → Run Tests
- 或命令行：`hvigorw --mode module -p module=entry@default -p product=default test`

## 版本记录

| 版本 | 内容 |
|---|---|
| v0.1 | 工程初始化 |
| v0.3 | 实时盯盘引擎：Canvas 分时/K线双模式 + 历史事件滚动列表 + 模拟交易 |
| v0.4 | 主界面 + 随机模拟股市生成器 |
| v0.5 | 主界面精简为双入口，新增历史剧本列表页 |
| v0.6 | 主界面与列表改为明亮主题 |
| v0.7 | P0 交易规则（手续费/T+1/涨跌停/做空）+ 数量输入 + 贷款与爆仓 |
| v0.8 | 修复预览器无法跳转：单页状态机 + 视图组件化 |
| v0.9 | 杠杆交易 + 对局存档/继续 + 单元测试 + README |

## 待办

- [ ] 结算复盘页（收益率、最大回撤、买卖点标注）
- [ ] 交易流水记录页
- [ ] 更多历史剧本（1987 黑色星期一、2000 互联网泡沫、2008 次贷、2016 熔断、2020 疫情熔断）
- [ ] 设计书与实现对齐

> AI生成