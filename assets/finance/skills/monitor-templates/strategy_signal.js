// Monitor Template: strategy_signal
// Params: ts_code, name, market, sma_period, volume_period, min_bars
var symbol = '{{ts_code}}';
var name = '{{name}}';
var strategyId = '{{strategy_id}}';
var smaPeriod = {{sma_period}};
var volumePeriod = {{volume_period}};
var minBars = {{min_bars}};
if (!smaPeriod) smaPeriod = 20;
if (!volumePeriod) volumePeriod = 20;
if (!minBars) minBars = Math.max(120, smaPeriod + 2, volumePeriod + 2);
if (!strategyId || strategyId.indexOf('{{') >= 0 || strategyId === 'null') strategyId = '';

var quote = callService('/api/finance/quote', {ts_code: '{{ts_code}}', market: '{{market}}'});
var kline = callService('/api/finance/kline', {
  ts_code: '{{ts_code}}',
  market: '{{market}}',
  adjust: 'qfq',
  limit: {{min_bars}}
});

function rows(resp) {
  if (!resp) return [];
  return resp.data || [];
}
function avg(values) {
  if (!values.length) return null;
  var total = 0;
  for (var i = 0; i < values.length; i++) total += parseFloat(values[i] || 0);
  return total / values.length;
}
function closeOf(row) {
  return parseFloat(row.close || row.price || row['收盘'] || 0);
}
function volumeOf(row) {
  return parseFloat(row.volume || row.vol || row['成交量'] || 0);
}

var bars = rows(kline);
if (!bars.length || bars.length < minBars) {
  return {
    value: '--',
    label: name,
    state: 'data_missing',
    signal: 'wait',
    reason: 'kline rows ' + bars.length + ' < required ' + minBars,
    source: kline && kline.source,
    cacheStatus: kline && kline.cacheStatus
  };
}

var closes = bars.map(closeOf);
var volumes = bars.map(volumeOf);
var lastClose = closes[closes.length - 1];
var prevClose = closes[closes.length - 2];
var sma = avg(closes.slice(-smaPeriod));
var prevSma = avg(closes.slice(-(smaPeriod + 1), -1));
var volAvg = avg(volumes.slice(-volumePeriod));
var lastVol = volumes[volumes.length - 1];
var entry = prevClose <= prevSma && lastClose > sma && lastVol > volAvg;

if (entry) {
  Bridge.alert(name + ' strategy_signal entry: close crossed SMA' + smaPeriod + ' with volume confirmation.');
  Bridge.sendToAgent(
    '策略信号已触发：' + name + ' ' + symbol + '。请先计算可以买多少和风险，不要直接下单；需要用户确认后才允许进入雪球模拟盘或 Portfolio 写入。',
    {
      template: 'strategy_signal',
      strategyId: strategyId,
      code: symbol,
      name: name,
      signal: 'entry',
      price: lastClose,
      sma: sma,
      volumeAverage: volAvg,
      lastVolume: lastVol,
      bars: bars.length,
      confirmationRequired: true,
      tradeBoundary: 'No Portfolio or XueqiuTrade action before explicit user confirmation.'
    }
  );
}

return {
  template: 'strategy_signal',
  strategyId: strategyId,
  code: symbol,
  value: lastClose,
  label: name,
  unit: '',
  state: 'ok',
  signal: entry ? 'entry' : 'wait',
  sma: sma,
  volumeAverage: volAvg,
  lastVolume: lastVol,
  bars: bars.length,
  quoteCacheStatus: quote && quote.cacheStatus,
  klineCacheStatus: kline && kline.cacheStatus,
  confirmationRequired: true,
  confirmation: 'Strategy signal is alert-only. Confirm symbol, price, size, account, stop and take-profit before any Portfolio or XueqiuTrade action.'
};
