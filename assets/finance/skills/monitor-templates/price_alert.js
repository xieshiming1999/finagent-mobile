// Monitor Template: price_alert
// Params: ts_code, name, upper, lower, market
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
if (!row) return {value: '--', label: '{{name}}', change: 0};

var price = parseFloat(row.close || row.price || row['最新价'] || 0);
var prevClose = parseFloat(row.pre_close || row.preClose || row.close || price);
var change = row.pct_chg != null ? parseFloat(row.pct_chg) : (prevClose > 0 ? ((price - prevClose) / prevClose * 100) : 0);

var upper = {{upper}};
var lower = {{lower}};
if (upper && price >= upper) {
  Bridge.alert('{{name}} 突破上限 ' + upper + '，当前价格 ' + price.toFixed(2));
}
if (lower && price <= lower) {
  Bridge.alert('{{name}} 跌破下限 ' + lower + '，当前价格 ' + price.toFixed(2));
}

if (!state.series) state.series = [];
state.series.push(price);
if (state.series.length > 60) state.series = state.series.slice(-60);

return {value: price, label: '{{name}}', change: parseFloat(change.toFixed(2)), unit: ''};
