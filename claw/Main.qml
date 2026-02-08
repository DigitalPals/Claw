import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
  id: root

  // Injected by PluginService
  property var pluginApi: null

  // idle | ok | error
  property string connectionState: "idle"
  property string lastErrorText: ""

  // Request/UX state (owned by main so it survives panel close).
  property bool isSending: false
  property int lastRequestHttpStatus: 0
  property string lastRequestErrorText: ""
  property bool panelActive: false
  property bool panelAtBottom: false
  property bool hasUnread: false

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

  function setPanelActive(active) {
    root.panelActive = !!active
  }

  function markRead() {
    root.hasUnread = false
  }

  function clearMessages() {
    messagesModel.clear()
  }

  function clearChat() {
    clearMessages()
    root.lastRequestHttpStatus = 0
    root.lastRequestErrorText = ""
    root.hasUnread = false
    // Don't touch connectionState; it's a separate concern.
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
    if (!root.panelActive || !root.panelAtBottom)
      root.hasUnread = true
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

  function _truncateForToast(s, maxLen) {
    var t = (s === null || s === undefined) ? "" : String(s)
    t = t.replace(/\r\n/g, "\n").replace(/\r/g, "\n")
    // Prefer first non-empty line.
    var parts = t.split("\n")
    for (var i = 0; i < parts.length; i++) {
      var line = String(parts[i] || "").trim()
      if (line.length > 0) {
        t = line
        break
      }
    }
    if (t.length > maxLen)
      t = t.substring(0, maxLen - 1) + "…"
    return t
  }

  function _maybeNotifyResponse(text, isError, opts) {
    // Notify only when Noctalia isn't focused; otherwise rely on unread badge.
    var notifyOn = opts && opts.notifyOnResponse !== undefined
      ? !!opts.notifyOnResponse
      : !!_pickSetting("notifyOnResponse", true)
    if (!notifyOn)
      return

    var onlyWhenInactive = opts && opts.notifyOnlyWhenAppInactive !== undefined
      ? !!opts.notifyOnlyWhenAppInactive
      : !!_pickSetting("notifyOnlyWhenAppInactive", true)
    if (onlyWhenInactive) {
      try {
        if (Qt.application && Qt.application.active)
          return
      } catch (e0) {}
    }

    var title = "Claw"
    var body = _truncateForToast(text || "", 180)
    if (!body)
      body = isError ? "Request failed" : "Response received"

    if (ToastService && ToastService.showNotice)
      ToastService.showNotice(title, body, isError ? "alert-triangle" : "message")
  }

  function _buildOutgoingMessages(newUserText) {
    var arr = []
    for (var i = 0; i < messagesModel.count; i++) {
      var m = messagesModel.get(i)
      if (m.role === "system" || m.role === "user" || m.role === "assistant")
        arr.push({ role: m.role, content: m.content })
    }
    arr.push({ role: "user", content: newUserText })
    return arr
  }

  function sendUserText(text, opts) {
    if (root.isSending)
      return

    var t = (text || "").trim()
    if (!t)
      return

    var outgoing = _buildOutgoingMessages(t)

    appendMessage("user", t)
    appendMessage("assistant", "...")
    var assistantIndex = messagesModel.count - 1

    root.lastRequestErrorText = ""
    root.lastRequestHttpStatus = 0
    root.isSending = true
    beginRequest()

    var stream = opts && opts.stream !== undefined
      ? !!opts.stream
      : !!_pickSetting("stream", true)

    _requestChatCompletions(outgoing, assistantIndex, stream, true, opts || {})
  }

  function _requestChatCompletions(outgoingMessages, assistantIndex, stream, allowFallback, opts) {
    var base = _trimTrailingSlashes((opts && opts.gatewayUrl !== undefined)
      ? opts.gatewayUrl
      : _pickSetting("gatewayUrl", "http://127.0.0.1:18789"))
    var url = base + "/v1/chat/completions"

    var xhr = new XMLHttpRequest()

    var timeoutTimer = Qt.createQmlObject(
      'import QtQuick 2.0; Timer { repeat: false }',
      root,
      "clawMainTimeoutTimer"
    )

    var processedLen = 0
    var sseBuffer = ""
    var assistantText = ""
    var sawAnyDelta = false

    function finishSending() {
      root.isSending = false
      endRequest()
    }

    function markUnreadIfNeeded() {
      if (!root.panelActive || !root.panelAtBottom)
        root.hasUnread = true
    }

    function fail(msg, status) {
      root.lastRequestHttpStatus = status || 0
      root.lastRequestErrorText = msg || "Request failed"
      setStatus("error", root.lastRequestErrorText)
      setMessageContent(assistantIndex, "Error: " + root.lastRequestErrorText)
      markUnreadIfNeeded()
      _maybeNotifyResponse(root.lastRequestErrorText, true, opts)
      finishSending()
    }

    function finishOk() {
      root.lastRequestHttpStatus = xhr.status || 0
      root.lastRequestErrorText = ""
      setStatus("ok", "")

      if (!assistantText)
        setMessageContent(assistantIndex, "(empty response)")

      markUnreadIfNeeded()
      _maybeNotifyResponse(assistantText, false, opts)
      finishSending()
    }

    function drainSse() {
      var text = xhr.responseText || ""
      if (text.length <= processedLen)
        return

      var chunk = text.substring(processedLen)
      processedLen = text.length

      // Normalize CRLF/CR for simpler parsing.
      sseBuffer += chunk
      sseBuffer = sseBuffer.replace(/\r/g, "")

      // SSE events separated by blank line.
      while (true) {
        var sep = sseBuffer.indexOf("\n\n")
        if (sep === -1)
          break

        var evt = sseBuffer.substring(0, sep)
        sseBuffer = sseBuffer.substring(sep + 2)

        var lines = evt.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i]
          if (line.indexOf("data:") !== 0)
            continue

          var data = line.substring(5).trim()
          if (data === "[DONE]")
            return

          try {
            var obj = JSON.parse(data)
            var choice0 = (obj.choices && obj.choices.length) ? obj.choices[0] : null
            var delta = choice0 && choice0.delta ? choice0.delta : null
            var dtext = (delta && delta.content) ? delta.content : ""

            if (dtext) {
              sawAnyDelta = true
              assistantText += dtext
              setMessageContent(assistantIndex, assistantText)
            }
          } catch (e) {
            // Ignore parse errors for partial frames; final-state handles fallback.
          }
        }
      }
    }

    xhr.onprogress = function() {
      if (stream)
        drainSse()
    }

    xhr.onerror = function() {
      timeoutTimer.stop()

      if (stream && allowFallback) {
        setMessageContent(assistantIndex, "...")
        _requestChatCompletions(outgoingMessages, assistantIndex, false, false, opts)
        return
      }

      fail("Network error (request failed).", 0)
    }

    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return

      timeoutTimer.stop()

      if (stream)
        drainSse()

      if (xhr.status >= 200 && xhr.status < 300) {
        var contentType = xhr.getResponseHeader("Content-Type") || ""
        if (contentType.indexOf("text/html") !== -1) {
          fail("Received HTML from server. This usually means the Gateway URL points at the OpenClaw Control UI or a proxy that is not forwarding API requests.", xhr.status)
          return
        }

        if (!stream) {
          try {
            var obj = JSON.parse(xhr.responseText || "")
            var c0 = (obj.choices && obj.choices.length) ? obj.choices[0] : null
            var msg = c0 && c0.message ? c0.message : null
            assistantText = (msg && msg.content) ? msg.content : ""
            setMessageContent(assistantIndex, assistantText || "(empty response)")
            finishOk()
            return
          } catch (e0) {
            fail("Response parse error.", xhr.status)
            return
          }
        }

        // stream=true success path
        if (!sawAnyDelta) {
          // Some environments buffer the whole response; try a JSON parse fallback.
          try {
            var obj2 = JSON.parse(xhr.responseText || "")
            var c02 = (obj2.choices && obj2.choices.length) ? obj2.choices[0] : null
            var msg2 = c02 && c02.message ? c02.message : null
            assistantText = (msg2 && msg2.content) ? msg2.content : ""
            setMessageContent(assistantIndex, assistantText || "(empty response)")
          } catch (e2) {
            // If parsing failed, but HTTP succeeded, keep whatever we accumulated.
          }
        }

        finishOk()
        return
      }

      // Non-2xx handling
      var status = xhr.status || 0
      var msgText = "HTTP " + status

      var hintEnabled = opts && opts.openAiEndpointEnabledHint !== undefined
        ? !!opts.openAiEndpointEnabledHint
        : !!_pickSetting("openAiEndpointEnabledHint", true)

      if (status === 401 || status === 403) {
        msgText = "Authentication/authorization failed (HTTP " + status + "). Check token and gateway config."
      } else if (status === 405) {
        msgText = "Method Not Allowed (HTTP 405). This server is refusing POST/OPTIONS, which usually means you're hitting the OpenClaw Control UI or a reverse proxy that only allows GET. Point Claw at the OpenClaw Gateway API base URL and ensure /v1/chat/completions is enabled."
      } else if (status === 404 && hintEnabled) {
        msgText = "Endpoint not found (HTTP 404). The gateway chat-completions endpoint may be disabled. Enable: gateway.http.endpoints.chatCompletions.enabled = true"
      } else {
        // Best-effort parse of error message.
        try {
          var errObj = JSON.parse(xhr.responseText || "")
          if (errObj && errObj.error && errObj.error.message)
            msgText = errObj.error.message
        } catch (e3) {}
      }

      if (stream && allowFallback) {
        setMessageContent(assistantIndex, "...")
        _requestChatCompletions(outgoingMessages, assistantIndex, false, false, opts)
        return
      }

      fail(msgText, status)
    }

    var timeoutMs = (opts && opts.requestTimeoutMs !== undefined)
      ? opts.requestTimeoutMs
      : _pickSetting("requestTimeoutMs", 60000)

    timeoutTimer.interval = timeoutMs
    timeoutTimer.triggered.connect(function() {
      try { xhr.abort() } catch (e) {}

      if (stream && allowFallback) {
        setMessageContent(assistantIndex, "...")
        _requestChatCompletions(outgoingMessages, assistantIndex, false, false, opts)
        return
      }

      fail("Request timed out after " + timeoutMs + "ms.", 0)
    })

    // Prefer both: header selection + model hint for gateways that route by model.
    var agentId = (opts && opts.agentId !== undefined)
      ? (opts.agentId || "")
      : (_pickSetting("agentId", "main") || "")
    agentId = String(agentId).trim()

    var modelName = "openclaw"
    if (agentId.length > 0)
      modelName = "openclaw:" + agentId

    var payload = {
      model: modelName,
      messages: outgoingMessages,
      stream: !!stream,
      user: (opts && opts.user !== undefined) ? opts.user : _pickSetting("user", "noctalia:claw")
    }

    xhr.open("POST", url)
    xhr.setRequestHeader("Content-Type", "application/json")

    var token = (opts && opts.token !== undefined) ? opts.token : _pickSetting("token", "")
    token = String(token || "").trim()
    if (token.length > 0)
      xhr.setRequestHeader("Authorization", "Bearer " + token)

    if (agentId.length > 0)
      xhr.setRequestHeader("x-openclaw-agent-id", agentId)

    var sessionKey = (opts && opts.sessionKey !== undefined) ? opts.sessionKey : _pickSetting("sessionKey", "")
    sessionKey = String(sessionKey || "").trim()
    if (sessionKey.length > 0)
      xhr.setRequestHeader("x-openclaw-session-key", sessionKey)

    timeoutTimer.start()
    xhr.send(JSON.stringify(payload))
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
