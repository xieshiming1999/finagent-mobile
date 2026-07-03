/// Shared JS code generators for the unified Bridge API.
///
/// Three JS environments share the same `Bridge` object API:
/// - ScriptTool (flutter_js) — sync, pre-fetch cache
/// - Monitor (flutter_js) — sync, pre-fetch cache
/// - WebView dashboard — async, Promise-based
///
/// This class generates the JS snippets each environment injects.
class BridgeJs {
  // ---------------------------------------------------------------------------
  // Pure-JS functions (work in any environment)
  // ---------------------------------------------------------------------------

  /// Data processing methods on Bridge object.
  static const dataFunctions = r'''
    Bridge.parseCSV = function(text, sep) {
      sep = sep || ',';
      var rows = [];
      var lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line) continue;
        var fields = [];
        var j = 0;
        while (j < line.length) {
          if (line[j] === '"') {
            var buf = '';
            j++;
            while (j < line.length) {
              if (line[j] === '"') {
                if (j + 1 < line.length && line[j + 1] === '"') {
                  buf += '"'; j += 2;
                } else { j++; break; }
              } else { buf += line[j]; j++; }
            }
            fields.push(buf);
            if (j < line.length && line[j] === sep) j++;
          } else {
            var si = line.indexOf(sep, j);
            if (si === -1) { fields.push(line.substring(j).trim()); break; }
            fields.push(line.substring(j, si).trim());
            j = si + sep.length;
          }
        }
        rows.push(fields);
      }
      return rows;
    };
    Bridge.toCSV = function(arr, sep) {
      sep = sep || ',';
      return arr.map(function(row) {
        if (!Array.isArray(row)) return String(row);
        return row.map(function(cell) {
          var s = String(cell);
          if (s.indexOf(sep) >= 0 || s.indexOf('"') >= 0 || s.indexOf('\n') >= 0) {
            return '"' + s.replace(/"/g, '""') + '"';
          }
          return s;
        }).join(sep);
      }).join('\n');
    };
    Bridge.base64Encode = function(text) {
      var bytes = [];
      for (var i = 0; i < text.length; i++) {
        var c = text.charCodeAt(i);
        if (c < 0x80) { bytes.push(c); }
        else if (c < 0x800) { bytes.push(0xC0|(c>>6), 0x80|(c&0x3F)); }
        else { bytes.push(0xE0|(c>>12), 0x80|((c>>6)&0x3F), 0x80|(c&0x3F)); }
      }
      var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      var r = '';
      for (var i = 0; i < bytes.length; i += 3) {
        var b0 = bytes[i], b1 = bytes[i+1], b2 = bytes[i+2];
        r += chars[b0 >> 2];
        r += chars[((b0 & 3) << 4) | ((b1 || 0) >> 4)];
        r += (b1 !== undefined) ? chars[((b1 & 15) << 2) | ((b2 || 0) >> 6)] : '=';
        r += (b2 !== undefined) ? chars[b2 & 63] : '=';
      }
      return r;
    };
    Bridge.base64Decode = function(text) {
      var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      var bytes = [];
      for (var i = 0; i < text.length; i += 4) {
        var b = [chars.indexOf(text[i]), chars.indexOf(text[i+1]), chars.indexOf(text[i+2]), chars.indexOf(text[i+3])];
        bytes.push((b[0]<<2)|(b[1]>>4));
        if (b[2] >= 0) bytes.push(((b[1]&15)<<4)|(b[2]>>2));
        if (b[3] >= 0) bytes.push(((b[2]&3)<<6)|b[3]);
      }
      var r = '';
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] < 0x80) { r += String.fromCharCode(bytes[i]); }
        else if (bytes[i] < 0xE0) { r += String.fromCharCode(((bytes[i]&0x1F)<<6)|(bytes[i+1]&0x3F)); i++; }
        else { r += String.fromCharCode(((bytes[i]&0x0F)<<12)|((bytes[i+1]&0x3F)<<6)|(bytes[i+2]&0x3F)); i+=2; }
      }
      return r;
    };
    Bridge.hexEncode = function(text) {
      var r = '';
      for (var i = 0; i < text.length; i++) {
        var c = text.charCodeAt(i);
        if (c < 0x80) { r += ('0'+c.toString(16)).slice(-2); }
        else {
          var bytes = [];
          if (c < 0x800) { bytes.push(0xC0|(c>>6), 0x80|(c&0x3F)); }
          else { bytes.push(0xE0|(c>>12), 0x80|((c>>6)&0x3F), 0x80|(c&0x3F)); }
          for (var j = 0; j < bytes.length; j++) r += ('0'+bytes[j].toString(16)).slice(-2);
        }
      }
      return r;
    };
    Bridge.hexDecode = function(hex) {
      var bytes = [];
      for (var i = 0; i < hex.length; i += 2) bytes.push(parseInt(hex.substr(i, 2), 16));
      var r = '';
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] < 0x80) { r += String.fromCharCode(bytes[i]); }
        else if (bytes[i] < 0xE0) { r += String.fromCharCode(((bytes[i]&0x1F)<<6)|(bytes[i+1]&0x3F)); i++; }
        else { r += String.fromCharCode(((bytes[i]&0x0F)<<12)|((bytes[i+1]&0x3F)<<6)|(bytes[i+2]&0x3F)); i+=2; }
      }
      return r;
    };
''';

  /// Statistical helpers on Bridge object.
  static const statsFunctions = r'''
    Bridge.sum = function(arr) { return arr.reduce(function(a,b){return a+b},0); };
    Bridge.avg = function(arr) { return arr.length ? Bridge.sum(arr)/arr.length : 0; };
    Bridge.median = function(arr) {
      if(!arr.length) return 0;
      var s = arr.slice().sort(function(a,b){return a-b});
      var m = Math.floor(s.length/2);
      return s.length%2 ? s[m] : (s[m-1]+s[m])/2;
    };
    Bridge.groupBy = function(arr, key) {
      var r = {};
      arr.forEach(function(item) {
        var k = typeof key==='function' ? key(item) : item[key];
        if(!r[k]) r[k]=[];
        r[k].push(item);
      });
      return r;
    };
    Bridge.unique = function(arr) {
      var seen = {};
      return arr.filter(function(item) {
        var k = typeof item==='object' ? JSON.stringify(item) : String(item);
        if(seen[k]) return false;
        seen[k] = true;
        return true;
      });
    };
    Bridge.sortBy = function(arr, key, desc) {
      return arr.slice().sort(function(a,b) {
        var va = typeof key==='function' ? key(a) : a[key];
        var vb = typeof key==='function' ? key(b) : b[key];
        if(va < vb) return desc ? 1 : -1;
        if(va > vb) return desc ? -1 : 1;
        return 0;
      });
    };
    Bridge.flatten = function(arr) {
      var result = [];
      arr.forEach(function(item) {
        if(Array.isArray(item)) { result = result.concat(Bridge.flatten(item)); }
        else { result.push(item); }
      });
      return result;
    };
''';

  // ---------------------------------------------------------------------------
  // flutter_js environments (sync, pre-fetch cache)
  // ---------------------------------------------------------------------------

  /// HTTP + Agent bridge for flutter_js (Monitor & ScriptTool).
  /// Requires `__fetchCache` and `__apiConfig` to be injected before this.
  static const httpBridge = r'''
    function callService(path, params, method) {
      method = (method || 'GET').toUpperCase();
      var key = method + ':' + path + '|' + JSON.stringify(params || {});
      var cached = __fetchCache[key];
      if (cached && cached.error) throw new Error('callService("' + path + '") error: ' + cached.error);
      if (cached) return cached;
      throw new Error('callService("' + path + '") not pre-fetched. Keys: ' + Object.keys(__fetchCache).join(', '));
    }
    Bridge.fetch = callService;
    Bridge.get = function(url, options) { return callService(url, (options||{}).params, 'GET'); };
    Bridge.post = function(url, body) { return callService(url, body, 'POST'); };
    Bridge.put = function(url, body) { return callService(url, body, 'PUT'); };
    Bridge.delete = function(url, options) { return callService(url, (options||{}).params, 'DELETE'); };
    Bridge.callService = callService;
    Bridge.notify = function(msg, sev) { __sideEffects.notifications.push({type: sev==='alert'?'alert':'notify', message: msg}); };
    Bridge.alert = function(msg) { __sideEffects.notifications.push({type:'alert', message: msg}); };
    Bridge.sendToAgent = function(msg, data) { __sideEffects.notifications.push({type:'agent_message', message: msg, data: data||{}}); };
    Bridge.getConfig = function(key) { return __apiConfig[key] || null; };
''';

  /// File bridge using sendMessage channels (for ScriptTool).
  static const fileBridgeSendMessage = r'''
    Bridge.readFile = function(path) { return sendMessage('readFile', path); };
    Bridge.writeFile = function(path, content) { return sendMessage('writeFile', JSON.stringify([path, content])); };
    Bridge.listDir = function(path) { return JSON.parse(sendMessage('listDir', path || '.')); };
    Bridge.fileExists = function(path) { return sendMessage('fileExists', path) === 'true'; };
    Bridge.fileStat = function(path) { return JSON.parse(sendMessage('fileStat', path)); };
''';

  /// File bridge using pre-fetch cache + sideEffects (for Monitor).
  static const fileBridgeCache = r'''
    Bridge.readFile = function(path) {
      var key = '__file:' + path;
      if (__fetchCache[key]) return __fetchCache[key];
      return null;
    };
    Bridge.writeFile = function(path, content) {
      if (!__sideEffects.fileOps) __sideEffects.fileOps = [];
      __sideEffects.fileOps.push({ op: 'write', path: path, content: content });
    };
    Bridge.listDir = function(path) {
      var key = '__dir:' + (path || '.');
      if (__fetchCache[key]) return __fetchCache[key];
      return [];
    };
    Bridge.fileExists = function(path) {
      var key = '__file:' + path;
      return __fetchCache[key] !== undefined && __fetchCache[key] !== null;
    };
    Bridge.fileStat = function(path) {
      var key = '__stat:' + path;
      if (__fetchCache[key]) return __fetchCache[key];
      return null;
    };
''';

  /// hash function using Dart's crypto (for flutter_js via sendMessage).
  static const hashSendMessage = r'''
    Bridge.hash = function(text, algo) {
      var args = algo ? JSON.stringify([text, algo]) : JSON.stringify([text]);
      return sendMessage('hash', args);
    };
    Bridge.parseXML = function(text) { return JSON.parse(sendMessage('parseXML', text)); };
''';

  /// Console shim pushing to __sideEffects.logs (Monitor / agent-tool ScriptTool).
  static const consoleSideEffects = r'''
    var console = {
      log: function() { __sideEffects.logs.push(Array.prototype.slice.call(arguments).map(function(a) { return typeof a === 'object' ? JSON.stringify(a) : String(a); }).join(' ')); },
      error: function() { console.log.apply(null, arguments); },
      warn: function() { console.log.apply(null, arguments); }
    };
''';

  /// Console shim pushing to __logs array (shared ScriptTool).
  static const consoleArray = r'''
    var __logs = [];
    var console = {
      log: function() {
        var args = Array.prototype.slice.call(arguments);
        __logs.push(args.map(function(a) {
          return typeof a === 'object' ? JSON.stringify(a) : String(a);
        }).join(' '));
      },
      error: function() { console.log.apply(null, arguments); },
      warn: function() { console.log.apply(null, arguments); }
    };
''';

  /// Backward-compatible global aliases for ScriptTool.
  static const globalAliases = r'''
    var readFile = Bridge.readFile;
    var writeFile = Bridge.writeFile;
    var listDir = Bridge.listDir;
    var fileExists = Bridge.fileExists;
    var fileStat = Bridge.fileStat;
    var parseCSV = Bridge.parseCSV;
    var toCSV = Bridge.toCSV;
    var base64Encode = Bridge.base64Encode;
    var base64Decode = Bridge.base64Decode;
    var hexEncode = Bridge.hexEncode;
    var hexDecode = Bridge.hexDecode;
    var hash = Bridge.hash;
    var parseXML = Bridge.parseXML;
    var sum = Bridge.sum;
    var avg = Bridge.avg;
    var median = Bridge.median;
    var groupBy = Bridge.groupBy;
    var unique = Bridge.unique;
    var sortBy = Bridge.sortBy;
    var flatten = Bridge.flatten;
''';

  // ---------------------------------------------------------------------------
  // WebView environment (async, Promise-based)
  // ---------------------------------------------------------------------------

  /// Full Bridge script for WebView HTML injection.
  /// Includes HTTP, file ops, state, agent comm, sendToMonitor, onPush, data/stats.
  static const webViewBridge = r'''<script>
var Bridge=(function(){var _id=0,_cb={};window.__bridgeCallback__=function(id,data){if(_cb[id]){_cb[id](data);delete _cb[id]}};function _send(msg){return new Promise(function(resolve){var id=String(++_id);msg.id=id;_cb[id]=resolve;if(window.AgentBridge){AgentBridge.postMessage(JSON.stringify(msg))}else{resolve({error:"AgentBridge not available"})}})}var B={fetch:function(p,params,m){return _send({type:"http",method:m||"GET",path:p,params:params||{}})},post:function(p,body){return _send({type:"http",method:"POST",path:p,params:body||{}})},get:function(p,opts){return _send({type:"http",method:"GET",path:p,params:(opts||{}).params||{}})},put:function(p,body){return _send({type:"http",method:"PUT",path:p,params:body||{}})},delete:function(p,opts){return _send({type:"http",method:"DELETE",path:p,params:(opts||{}).params||{}})},readFile:function(path){return _send({type:"readFile",path:path}).then(function(r){return r.content})},writeFile:function(path,content){return _send({type:"writeFile",path:path,content:content})},listDir:function(path){return _send({type:"listDir",path:path||"."}).then(function(r){return r.entries||[]})},fileExists:function(path){return _send({type:"fileExists",path:path}).then(function(r){return r.exists||false})},fileStat:function(path){return _send({type:"fileStat",path:path})},getState:function(key){return _send({type:"getState",key:key}).then(function(r){return r.value})},setState:function(key,value){return _send({type:"setState",key:key,value:value})},sendToAgent:function(msg,data){return _send({type:"agent_message",message:msg,source:document.title||"dashboard",data:data||{}})},sendToMonitor:function(monitorId,channel,data){return _send({type:"sendToMonitor",monitorId:monitorId,channel:channel,data:data||{}})},notify:function(msg){return _send({type:"notify",message:msg})},alert:function(msg){return _send({type:"notify",message:"⚠ "+msg})},getConfig:function(key){return _send({type:"getConfig",key:key}).then(function(r){return r.value})},onPush:function(ch,fn){if(!window.__pushHandlers__)window.__pushHandlers__={};window.__pushHandlers__[ch]=fn}};B.parseCSV=function(t,s){s=s||',';var rows=[];var lines=t.split('\n');for(var i=0;i<lines.length;i++){var l=lines[i].trim();if(!l)continue;var f=[];var j=0;while(j<l.length){if(l[j]==='"'){var b='';j++;while(j<l.length){if(l[j]==='"'){if(j+1<l.length&&l[j+1]==='"'){b+='"';j+=2}else{j++;break}}else{b+=l[j];j++}}f.push(b);if(j<l.length&&l[j]===s)j++}else{var si=l.indexOf(s,j);if(si===-1){f.push(l.substring(j).trim());break}f.push(l.substring(j,si).trim());j=si+s.length}}rows.push(f)}return rows};B.toCSV=function(a,s){s=s||',';return a.map(function(r){if(!Array.isArray(r))return String(r);return r.map(function(c){var v=String(c);if(v.indexOf(s)>=0||v.indexOf('"')>=0||v.indexOf('\n')>=0)return '"'+v.replace(/"/g,'""')+'"';return v}).join(s)}).join('\n')};B.base64Encode=function(t){var b=[];for(var i=0;i<t.length;i++){var c=t.charCodeAt(i);if(c<0x80)b.push(c);else if(c<0x800)b.push(0xC0|(c>>6),0x80|(c&0x3F));else b.push(0xE0|(c>>12),0x80|((c>>6)&0x3F),0x80|(c&0x3F))}var ch='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';var r='';for(var i=0;i<b.length;i+=3){var b0=b[i],b1=b[i+1],b2=b[i+2];r+=ch[b0>>2];r+=ch[((b0&3)<<4)|((b1||0)>>4)];r+=(b1!==undefined)?ch[((b1&15)<<2)|((b2||0)>>6)]:'=';r+=(b2!==undefined)?ch[b2&63]:'='}return r};B.base64Decode=function(t){var ch='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';var b=[];for(var i=0;i<t.length;i+=4){var v=[ch.indexOf(t[i]),ch.indexOf(t[i+1]),ch.indexOf(t[i+2]),ch.indexOf(t[i+3])];b.push((v[0]<<2)|(v[1]>>4));if(v[2]>=0)b.push(((v[1]&15)<<4)|(v[2]>>2));if(v[3]>=0)b.push(((v[2]&3)<<6)|v[3])}var r='';for(var i=0;i<b.length;i++){if(b[i]<0x80)r+=String.fromCharCode(b[i]);else if(b[i]<0xE0){r+=String.fromCharCode(((b[i]&0x1F)<<6)|(b[i+1]&0x3F));i++}else{r+=String.fromCharCode(((b[i]&0x0F)<<12)|((b[i+1]&0x3F)<<6)|(b[i+2]&0x3F));i+=2}}return r};B.hexEncode=function(t){var r='';for(var i=0;i<t.length;i++){var c=t.charCodeAt(i);if(c<0x80)r+=('0'+c.toString(16)).slice(-2);else{var b=[];if(c<0x800)b.push(0xC0|(c>>6),0x80|(c&0x3F));else b.push(0xE0|(c>>12),0x80|((c>>6)&0x3F),0x80|(c&0x3F));for(var j=0;j<b.length;j++)r+=('0'+b[j].toString(16)).slice(-2)}}return r};B.hexDecode=function(h){var b=[];for(var i=0;i<h.length;i+=2)b.push(parseInt(h.substr(i,2),16));var r='';for(var i=0;i<b.length;i++){if(b[i]<0x80)r+=String.fromCharCode(b[i]);else if(b[i]<0xE0){r+=String.fromCharCode(((b[i]&0x1F)<<6)|(b[i+1]&0x3F));i++}else{r+=String.fromCharCode(((b[i]&0x0F)<<12)|((b[i+1]&0x3F)<<6)|(b[i+2]&0x3F));i+=2}}return r};B.sum=function(a){return a.reduce(function(x,y){return x+y},0)};B.avg=function(a){return a.length?B.sum(a)/a.length:0};B.median=function(a){if(!a.length)return 0;var s=a.slice().sort(function(x,y){return x-y});var m=Math.floor(s.length/2);return s.length%2?s[m]:(s[m-1]+s[m])/2};B.groupBy=function(a,k){var r={};a.forEach(function(i){var v=typeof k==='function'?k(i):i[k];if(!r[v])r[v]=[];r[v].push(i)});return r};B.unique=function(a){var s={};return a.filter(function(i){var k=typeof i==='object'?JSON.stringify(i):String(i);if(s[k])return false;s[k]=true;return true})};B.sortBy=function(a,k,d){return a.slice().sort(function(x,y){var va=typeof k==='function'?k(x):x[k];var vb=typeof k==='function'?k(y):y[k];if(va<vb)return d?1:-1;if(va>vb)return d?-1:1;return 0})};B.flatten=function(a){var r=[];a.forEach(function(i){if(Array.isArray(i))r=r.concat(B.flatten(i));else r.push(i)});return r};return B})();
</script>''';
}
