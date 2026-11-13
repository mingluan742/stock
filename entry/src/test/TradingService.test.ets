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

    it('做空规模超出净资产 50 倍应拒绝', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, true));
      // 净资产 100 万，敏口上限 = 5000 万市值；@100 元最多 50 万股
      const r = t.sell(100, 600000, 0);
      expect(r.ok).assertFalse();
      expect(r.message).assertContain('做空规模');
      const r2 = t.sell(100, 500000, 0);
      expect(r2.ok).assertTrue();
      expect(t.shares).assertEqual(-500000);
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

    it('50 倍杠杆按保证金买入', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      // 50x 买 1000 股 @100：市值 10 万，保证金 2000，融资 9.8 万
      const r = t.buy(100, 1000, 0, 50);
      expect(r.ok).assertTrue();
      expect(t.cash).assertEqual(AppConfig.INIT_CASH - 2000);
      expect(t.debt).assertEqual(98000);
    });

    it('杠杆配资不占用普通借款额度', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      const r = t.buy(100, 10000, 0, 50); // 融资 98 万
      expect(r.ok).assertTrue();
      expect(t.loanAvailable).assertEqual(AppConfig.MAX_LOAN);
      const r2 = t.borrow(AppConfig.MAX_LOAN);
      expect(r2.ok).assertTrue();
    });

    it('50 倍全仓后超出总债务上限应拒绝', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      // 50x 全仓：现金 100 万 → 市值 5000 万，融资 4900 万
      const r = t.buy(100, 500000, 0, 50);
      expect(r.ok).assertTrue();
      expect(t.debt).assertEqual(49000000);
      const r2 = t.buy(100, 10000, 0, 50);
      expect(r2.ok).assertFalse();
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

    it('买卖应写入交易流水并计算已实现盈亏', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      t.newDay('2026-01-05');
      t.buy(100, 200, 0);          // 成本 20000
      expect(t.tradeCount).assertEqual(1);
      expect(t.tradeRecords[0].side).assertEqual('买');
      expect(t.tradeRecords[0].date).assertEqual('2026-01-05');
      expect(t.tradeRecords[0].realized).assertEqual(0);
      t.newDay('2026-01-06');
      t.sell(120, 100, 0);         // 卖 100 股 @120，相对均价 100 盈利 2000
      expect(t.tradeCount).assertEqual(2);
      expect(t.tradeRecords[1].side).assertEqual('卖');
      expect(t.tradeRecords[1].realized).assertEqual(2000);
    });

    it('胜率应按盈利卖出笔数统计', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      t.buy(100, 200, 0);
      t.sell(120, 100, 0);   // 盈利
      t.sell(90, 100, 0);    // 亏损
      expect(t.winRate).assertEqual(0.5);
    });

    it('应按净值峰值跟踪最大回撤', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      t.buy(100, 100, 0);
      t.updateNetTracking(100);   // 峰值 100 万
      expect(t.peakNet).assertEqual(AppConfig.INIT_CASH);
      expect(t.maxDrawdown).assertEqual(0);
      t.updateNetTracking(80);    // 净值 99.8 万，回撤 0.2%
      expect(t.maxDrawdown).assertEqual(0.002);
      t.updateNetTracking(100);   // 价格回来了，回撤保持峰值记录
      expect(t.maxDrawdown).assertEqual(0.002);
    });

    it('快照应带上流水与回撤，恢复后一致', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      t.newDay('2026-01-05');
      t.buy(100, 200, 0);
      t.updateNetTracking(90);
      const snap = t.snapshot();
      const t2 = new TradingService();
      t2.setRules(makeRules(0, 0, 0, false));
      t2.restore(snap);
      expect(t2.tradeCount).assertEqual(1);
      expect(t2.shares).assertEqual(200);
      expect(t2.maxDrawdown).assertEqual(t.maxDrawdown);
    });

    it('重置后应清空流水与回撤', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      t.buy(100, 200, 0);
      t.updateNetTracking(50);
      t.reset();
      expect(t.tradeCount).assertEqual(0);
      expect(t.maxDrawdown).assertEqual(0);
      expect(t.cash).assertEqual(AppConfig.INIT_CASH);
    });

    it('应统计买卖笔数、最高杠杆与累计借款', 0, () => {
      const t = new TradingService();
      t.setRules(makeRules(0, 0, 0, false));
      expect(t.buyCount).assertEqual(0);
      expect(t.maxLeverageUsed).assertEqual(1);
      t.buy(100, 100, 0, 10);
      t.sell(110, 100, 0);
      expect(t.buyCount).assertEqual(1);
      expect(t.sellCount).assertEqual(1);
      expect(t.maxLeverageUsed).assertEqual(10);
      // 更高杠杆应刷新记录
      t.buy(100, 100, 0, 50);
      expect(t.maxLeverageUsed).assertEqual(50);
      // 累计借款：还清后再借也累计
      t.borrow(200000);
      t.repay(200000);
      t.borrow(100000);
      expect(t.totalBorrowed).assertEqual(300000);
      // 重置后清零
      t.reset();
      expect(t.maxLeverageUsed).assertEqual(1);
      expect(t.totalBorrowed).assertEqual(0);
    });
  });
}