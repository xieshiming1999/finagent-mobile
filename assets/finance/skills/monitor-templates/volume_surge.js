// Monitor Template: volume_surge
// Params: ts_code, name, multiplier, market
var data = callService('/api/finance/quote', {ts_code: '{{ts_code}}', market: '{{market}}'});
function firstRow(resp) {
  if (!resp) return null;
  if (resp.data && resp.data[0] && resp.columns) {
    var out = {};
    for (var i = 0; i < resp.columns.length; i++) out[resp.columns[i]] = resp.data[0][i];
    return out;
  }
  return resp.data && resp.data[0] ? resp.data[0] : null;
}
var row = firstRow(data);
if (!row) return {value: '--', label: '{{name}} 量能'};

var todayVol = parseFloat(row.vol || row.volume || row['成交量'] || 0);
var price = parseFloat(row.close || row.price || row['最新价'] || 0);
var prevClose = parseFloat(row.pre_close || row.preClose || row.close || price);
var change = row.pct_chg != null ? parseFloat(row.pct_chg) : (prevClose > 0 ? ((price - prevClose) / prevClose * 100) : 0);
var prevVol = state.lastVol || todayVol;
var ratio = prevVol > 0 ? (todayVol / prevVol) : 0;
state.lastVol = todayVol;

var multiplier = {{multiplier}};
if (ratio >= multiplier) {
  Bridge.alert('{{name}} 成交量放大 ' + ratio.toFixed(1) + ' 倍（阈值 ' + multiplier + ' 倍），价格 ' + price.toFixed(2));
}

return {value: price, label: '{{name}}', change: parseFloat(change.toFixed(2)), unit: ''};
