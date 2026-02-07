import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  // Injected by PluginService
  property var pluginApi: null

  // idle | ok | error
  property string connectionState: "idle"
  property string lastErrorText: ""

  // Used to avoid heartbeat overwriting status while a request is in-flight.
  property int activeRequests: 0

  // Heartbeat config (kept simple; can be promoted to settings later).
  property int heartbeatIntervalMs: 5000
  property int heartbeatTimeoutMs: 1500
  property bool heartbeatInFlight: false
  property var heartbeatXhr: null

  // Keep chat in memory across panel open/close.
  // The panel uses this model directly, so messages persist as long as the plugin main instance lives.
  property alias messagesModel: messagesModel

  function setStatus(state, errorText) {
    root.connectionState = state || "idle"
    root.lastErrorText = errorText || ""
  }

  function beginRequest() {
    root.activeRequests = (root.activeRequests || 0) + 1
  }

  function endRequest() {
    root.activeRequests = Math.max(0, (root.activeRequests || 0) - 1)
  }

  function clearMessages() {
    messagesModel.clear()
  }

  function appendMessage(role, content) {
    messagesModel.append({
      role: role,
      content: content,
      ts: Date.now()
    })
    return messagesModel.count - 1
  }

  function setMessageContent(index, content) {
    if (index < 0 || index >= messagesModel.count)
      return
    messagesModel.setProperty(index, "content", content)
  }

  ListModel {
    id: messagesModel
  }

  function _pickSetting(key, fallback) {
    if (pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings[key] !== undefined)
      return pluginApi.pluginSettings[key]
    if (pluginApi && pluginApi.manifest && pluginApi.manifest.metadata
        && pluginApi.manifest.metadata.defaultSettings
        && pluginApi.manifest.metadata.defaultSettings[key] !== undefined)
      return pluginApi.manifest.metadata.defaultSettings[key]
    return fallback
  }

  function _trimTrailingSlashes(s) {
    var out = (s || "").trim()
    while (out.length > 1 && out[out.length - 1] === "/")
      out = out.substring(0, out.length - 1)
    return out
  }

  function heartbeatOnce() {
    // Don't fight with user-initiated requests (the panel updates status itself).
    if ((root.activeRequests || 0) > 0)
      return
    if (root.heartbeatInFlight)
      return

    var base = _trimTrailingSlashes(_pickSetting("gatewayUrl", "http://127.0.0.1:18789"))
    if (!base) {
      root.setStatus("idle", "")
      return
    }

    var url = base + "/v1/chat/completions"
    var xhr = new XMLHttpRequest()
    root.heartbeatInFlight = true
    root.heartbeatXhr = xhr

    function finish(state, msg) {
      heartbeatTimeoutTimer.stop()
      root.heartbeatInFlight = false
      root.heartbeatXhr = null
      // Status might have changed while we were waiting.
      if ((root.activeRequests || 0) > 0)
        return
      root.setStatus(state, msg || "")
    }

    xhr.onerror = function() {
      if (root.heartbeatXhr !== xhr)
        return
      finish("error", "Gateway unreachable (network error).")
    }

    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return

      if (root.heartbeatXhr !== xhr)
        return

      heartbeatTimeoutTimer.stop()

      var status = xhr.status || 0
      var contentType = xhr.getResponseHeader("Content-Type") || ""

      // Some servers (e.g. the Control UI) will happily answer with HTML.
      if (status >= 200 && status < 300 && contentType.indexOf("text/html") !== -1) {
        finish("error", "Gateway URL points at an HTML UI, not the API.")
        return
      }

      if (status >= 200 && status < 300) {
        finish("ok", "")
        return
      }

      if (status === 401 || status === 403) {
        finish("error", "Authentication/authorization failed (HTTP " + status + ").")
        return
      }

      if (status === 404) {
        finish("error", "Endpoint not found (HTTP 404).")
        return
      }

      // Many servers return 405 for OPTIONS even though the route exists; treat it as "reachable".
      if (status === 405) {
        finish("ok", "")
        return
      }

      if (status === 0) {
        finish("error", "Gateway unreachable (no HTTP response).")
        return
      }

      finish("error", "HTTP " + status)
    }

    try {
      xhr.open("OPTIONS", url)

      var token = (_pickSetting("token", "") || "").trim()
      if (token.length > 0)
        xhr.setRequestHeader("Authorization", "Bearer " + token)

      heartbeatTimeoutTimer.stop()
      heartbeatTimeoutTimer.start()
      xhr.send()
    } catch (e2) {
      finish("error", "Heartbeat failed to start.")
    }
  }

  Timer {
    id: heartbeatTimeoutTimer
    interval: root.heartbeatTimeoutMs
    repeat: false
    onTriggered: {
      var xhr = root.heartbeatXhr
      root.heartbeatInFlight = false
      root.heartbeatXhr = null
      try { xhr.abort() } catch (e) {}
      // Avoid overwriting an active request state.
      if ((root.activeRequests || 0) === 0)
        root.setStatus("error", "Gateway heartbeat timed out after " + root.heartbeatTimeoutMs + "ms.")
    }
  }

  Timer {
    id: heartbeatTimer
    interval: root.heartbeatIntervalMs
    repeat: true
    running: false
    onTriggered: root.heartbeatOnce()
  }

  Component.onCompleted: {
    root.heartbeatOnce()
    heartbeatTimer.start()
  }

  onPluginApiChanged: {
    root.heartbeatOnce()
    if (pluginApi)
      heartbeatTimer.start()
    else
      heartbeatTimer.stop()
  }

  // Optional IPC hook (best-effort). Without a screen reference, it can't reliably open a panel,
  // so this is just a stub target for future expansion.
  IpcHandler {
    target: "plugin:claw"

    function ping() {
      return {
        ok: true,
        connectionState: root.connectionState,
        lastErrorText: root.lastErrorText
      }
    }
  }
}
