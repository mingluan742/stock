import { describe, expect, it } from '@ohos/hypium';
import { AppConfig } from '../main/ets/config/AppConfig';
import { MarketRuleConfig } from '../main/ets/models/Scenario';
import { TradingService } from '../main/ets/services/TradingService';

/** 构造一套规则（可覆盖单项） */
function makeRules(priceLimit: number, tPlus: number, feeRate: number, shortSell: boolean): MarketRuleConfig {
  return {
    priceLimit: priceLimit,
    tPlus: tPlus,
    feeRate: feeRate,
    shortSell: shortSell
  };
}

export default function tradingServiceTest() {
  describe('TradingService', () => {

    it('买入应扣除金额与手续费', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0.001, false));
      const r = t.buy(100, 100, 0);
      expect(r.ok).assertTrue();
      // 100 * 100 = 10000 元，手续费 10 元
      expect(t.cash).assertEqual(AppConfig.INIT_CASH - 10010);
      expect(t.shares).assertEqual(100);
      expect(t.feeTotal).assertEqual(10);
    });

    it('现金不足应拒绝', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0.001, false));
      const r = t.buy(1000, 2000, 0); // 需要 200 万 + 手续费
      expect(r.ok).assertFalse();
      expect(r.message).assertContain('现金不足');
    });

    it('卖出应按均价结转并计算盈亏', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      t.buy(100, 100, 0);   // 成本 10000
      t.buy(200, 100, 0);   // 成本 20000，均价 150
      expect(t.avgCost).assertEqual(150);
      const r = t.sell(200, 100, 0);
      expect(r.ok).assertTrue();
      expect(t.shares).assertEqual(100);
      expect(t.cash).assertEqual(AppConfig.INIT_CASH - 10000); // 卖出 100 股 @200 = 20000，成本扣 15000
    });

    it('T+1 下当日买入不可卖出', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0.1, 1, 0, false));
      t.newDay('2026-01-05');
      t.buy(100, 100, 0);
      const r = t.sell(100, 100, 0);
      expect(r.ok).assertFalse();
      expect(r.message).assertContain('T+1');
      // 换一天后可以卖
      t.newDay('2026-01-06');
      expect(t.sellableShares).assertEqual(100);
      const r2 = t.sell(100, 100, 0);
      expect(r2.ok).assertTrue();
    });

    it('涨停封板不可买入', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0.1, 0, 0, false));
      const r = t.buy(100, 100, 0.1); // 当日 +10%
      expect(r.ok).assertFalse();
      expect(r.message).assertContain('涨停');
    });

    it('跌停封板不可卖出', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0.1, 0, 0, false));
      t.buy(100, 100, 0);
      const r = t.sell(100, 100, -0.1); // 当日 -10%
      expect(r.ok).assertFalse();
      expect(r.message).assertContain('跌停');
    });

    it('不可做空的市场卖出超过持仓应拒绝', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      t.buy(100, 100, 0);
      const r = t.sell(100, 200, 0);
      expect(r.ok).assertFalse();
      expect(r.message).assertContain('持仓不足');
    });

    it('可做空市场允许负持仓并按卖价记成本', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, true));
      const r = t.sell(100, 100, 0); // 开空 100 股
      expect(r.ok).assertTrue();
      expect(t.shares).assertEqual(-100);
      expect(t.avgCost).assertEqual(100);
      // 价格跌到 80 时买入平仓，应盈利 2000
      const r2 = t.buy(80, 100, 0);
      expect(r2.ok).assertTrue();
      expect(t.shares).assertEqual(0);
      expect(t.cash - AppConfig.INIT_CASH).assertEqual(2000);
    });

    it('做空超过上限应拒绝', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, true));
      const r = t.sell(100, 600, 0); // 上限 500 股
      expect(r.ok).assertFalse();
      expect(r.message).assertContain('做空上限');
    });

    it('借款应增加现金与负债，还款应冲减', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      const r1 = t.borrow(200000);
      expect(r1.ok).assertTrue();
      expect(t.cash).assertEqual(AppConfig.INIT_CASH + 200000);
      expect(t.debt).assertEqual(200000);
      const r2 = t.repay(50000);
      expect(r2.ok).assertTrue();
      expect(t.debt).assertEqual(150000);
      // 超出可借额度应拒绝
      const r3 = t.borrow(1000000);
      expect(r3.ok).assertFalse();
    });

    it('贷款按交易日复利计息', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      t.borrow(100000);
      t.newDay('2026-01-05');
      const interest1 = t.debtInterest;
      expect(interest1 > 0).assertTrue();
      t.newDay('2026-01-06');
      expect(t.debtInterest > interest1).assertTrue();
    });

    it('杠杆买入应按保证金检查并自动融资', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      // 5 倍杠杆买 1000 股 @100：市值 10 万，保证金 2 万
      const r = t.buy(100, 1000, 0, 5);
      expect(r.ok).assertTrue();
      expect(t.shares).assertEqual(1000);
      // 现金：100 万 - 保证金 2 万 = 98 万（融资 8 万计入负债）
      expect(t.cash).assertEqual(AppConfig.INIT_CASH - 20000);
      expect(t.debt).assertEqual(80000);
    });

    it('杠杆保证金不足应拒绝', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      // 先花光大部分现金，再 2 倍杠杆买入
      t.buy(100, 9900, 0); // 花 99 万
      const r = t.buy(100, 2000, 0, 2); // 需要市值 20 万，保证金 10 万 > 剩余现金
      expect(r.ok).assertFalse();
      expect(r.message).assertContain('保证金不足');
    });

    it('净资产应为现金加持仓市值减负债，归零即爆仓', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      t.borrow(AppConfig.MAX_LOAN);
      t.buy(100, 19000, 0, 1); // 现金 200 万，买 190 万
      expect(t.netAsset(100)).assertEqual(AppConfig.INIT_CASH + 1000000 - 1900000 + 1900000 - 1000000);
      // 价格跑到 40 时净资产为负
      expect(t.bankrupt(40)).assertTrue();
    });
  });
}