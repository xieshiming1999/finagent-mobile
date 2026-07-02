// Monitor Template: watchlist
// Params: items (JSON array), market, change_threshold
var items = {{items}};
var market = '{{market}}';
var threshold = {{change_threshold}};
var quoteResponses = [
  {{quote_calls}}
];
var rows = [];
var alerts = [];

function firstRow(resp) {
  if (!resp) return null;
  if (resp.data && resp.data[0] && resp.columns) {
    var out = {};
    for (var i = 0; i < resp.columns.length; i++) out[resp.columns[i]] = resp.data[0][i];
    return out;
  }
  return resp.data && resp.data[0] ? resp.data[0] : null;
}

for (var i = 0; i < items.length; i++) {
  var item = items[i];
  try {
    var row = firstRow(quoteResponses[i]);
    if (!row) {
      rows.push({name: item.name, code: item.ts_code, price: '--', change: 0, signal: ''});
      continue;
    }
    var price = parseFloat(row.close || row.price || row['最新价'] || 0);
    var prevClose = parseFloat(row.pre_close || row.preClose || row.close || price);
    var change = row.pct_chg != null ? parseFloat(row.pct_chg) : (prevClose > 0 ? ((price - prevClose) / prevClose * 100) : 0);
    var signal = '';
    if (Math.abs(change) >= threshold) {
      signal = change > 0 ? 'up' : 'down';
      alerts.push(item.name + (change > 0 ? ' 涨 ' : ' 跌 ') + Math.abs(change).toFixed(2) + '%');
    }
    rows.push({name: item.name, code: item.ts_code, price: price, change: parseFloat(change.toFixed(2)), signal: signal});
  } catch (e) {
    rows.push({name: item.name, code: item.ts_code, price: '--', change: 0, signal: 'error'});
  }
}

if (alerts.length > 0) {
  Bridge.alert('自选异动：' + alerts.join('；'));
}

return {rows: rows, title: '自选盯盘', alerts: alerts};
