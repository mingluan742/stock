import tradingServiceTest from './TradingService.test';
import localUnitTest from './LocalUnit.test';

export default function testsuite() {
  localUnitTest();
  tradingServiceTest();
}