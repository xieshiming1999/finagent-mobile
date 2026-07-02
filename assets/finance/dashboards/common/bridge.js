/**
 * AgentBridge Helper — wraps window.AgentBridge for dashboard templates.
 * Usage: Bridge.fetch('https://api.example.com/data', {params}).then(data => ...)
 *        Bridge.fetch('/relative/path', {params}).then(data => ...)  // via native proxy
 */
var Bridge = (function() {
  var _id = 0;
  var _callbacks = {};

  // Listen for bridge responses
  window.__bridgeCallback__ = function(id, data) {
    if (_callbacks[id]) {
      _callbacks[id](data);
      delete _callbacks[id];
    }
  };

  function _send(msg) {
    return new Promise(function(resolve) {
      var id = String(++_id);
      msg.id = id;
      _callbacks[id] = resolve;
      if (window.AgentBridge) {
        window.AgentBridge.postMessage(JSON.stringify(msg));
      } else {
        resolve({error: 'AgentBridge not available'});
      }
    });
  }

  function _isFullUrl(path) {
    return path && (path.indexOf('http://') === 0 || path.indexOf('https://') === 0);
  }

  function _directFetch(url, params, method) {
    method = method || 'GET';
    var fetchUrl = url;
    var opts = { method: method, headers: { 'Accept': 'application/json' } };

    if (method === 'GET' && params && Object.keys(params).length > 0) {
      var qs = Object.keys(params).map(function(k) {
        return encodeURIComponent(k) + '=' + encodeURIComponent(params[k]);
      }).join('&');
      fetchUrl = url + (url.indexOf('?') >= 0 ? '&' : '?') + qs;
    } else if (method === 'POST') {
      opts.headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(params || {});
    }

    return window.fetch(fetchUrl, opts)
      .then(function(resp) { return resp.json(); })
      .catch(function(err) { return { error: err.message || String(err) }; });
  }

  return {
    /** HTTP GET/POST. Full URLs fetch directly; relative paths go via native proxy. */
    fetch: function(path, params, method) {
      if (_isFullUrl(path)) {
        return _directFetch(path, params, method);
      }
      return _send({
        type: 'http',
        method: method || 'GET',
        path: path,
        params: params || {}
      });
    },

    /** POST shorthand */
    post: function(path, body) {
      if (_isFullUrl(path)) {
        return _directFetch(path, body, 'POST');
      }
      return _send({
        type: 'http',
        method: 'POST',
        path: path,
        params: body || {}
      });
    },

    /** Send message to agent (triggers agent.run). */
    sendToAgent: function(message, data) {
      return _send({
        type: 'agent_message',
        message: message,
        source: document.title || 'dashboard',
        data: data || {}
      });
    },

    /** Display-only notification (no agent processing). */
    notify: function(message) {
      return _send({
        type: 'notify',
        message: message
      });
    },

    /** Convenience: notify as alert style. */
    alert: function(message) {
      return _send({
        type: 'notify',
        message: '⚠ ' + message
      });
    },

    /** Register handler for native push data. */
    onPush: function(channel, handler) {
      if (!window.__pushHandlers__) window.__pushHandlers__ = {};
      window.__pushHandlers__[channel] = handler;
    }
  };
})();

// Wire up __onPush__ to dispatch to registered handlers
window.__onPush__ = function(channel, data) {
  if (window.__pushHandlers__ && window.__pushHandlers__[channel]) {
    window.__pushHandlers__[channel](data);
  }
};
