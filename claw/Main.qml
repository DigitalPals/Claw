import QtQuick
import QtWebSockets
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
  id: root

  // Injected by PluginService
  property var pluginApi: null

  // idle | connecting | connected | error
  property string connectionState: "idle"
  property string lastErrorText: ""

  // Request/UX state (owned by main so it survives panel close).
  property bool isSending: false
  property bool panelActive: false
  property bool panelAtBottom: false
  property bool hasUnread: false

  // Keep chat in memory across panel open/close.
  property alias messagesModel: messagesModel

  // Channel/session navigation state
  property var channelMeta: []          // from channels.status
  property var channelOrder: []
  property var channelAccounts: ({})
  property var sessionsList: []          // from sessions.list
  property string viewMode: "channels"   // "channels" | "sessions" | "chat"
  property string selectedChannelId: ""
  property string activeSessionKey: ""

  // Streaming state
  property int _activeAssistantIndex: -1
  property string _activeAssistantText: ""

  // Protocol request tracking
  property int _nextReqId: 1
  property var _pendingRequests: ({})    // id -> { callback, timer }

  // Reconnection state
  property int _reconnectAttempts: 0

  // Tick keepalive interval from server (default 15s)
  property int _tickIntervalMs: 15000

  function setStatus(state, errorText) {
    root.connectionState = state || "idle"
    root.lastErrorText = errorText || ""
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
    root.hasUnread = false
    root._activeAssistantIndex = -1
    root._activeAssistantText = ""
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
      t = t.substring(0, maxLen - 1) + "\u2026"
    return t
  }

  function _maybeNotifyResponse(text, isError, opts) {
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

  // ──────────────────────────────────────────────
  // WebSocket
  // ──────────────────────────────────────────────

  WebSocket {
    id: ws
    url: root._pickSetting("wsUrl", "ws://127.0.0.1:18789")
    active: false

    onStatusChanged: {
      console.log("[Claw] WS status changed:", ws.status,
                  "(0=Connecting, 1=Open, 2=Closing, 3=Closed, 4=Error)",
                  "url:", ws.url, "errorString:", ws.errorString)
      if (ws.status === WebSocket.Open) {
        console.log("[Claw] WS open, starting handshake")
        root.setStatus("connecting", "")
        root._reconnectAttempts = 0
        // Start fallback timer in case server doesn't send connect.challenge
        connectFallbackTimer.start()
      } else if (ws.status === WebSocket.Closed) {
        console.log("[Claw] WS closed")
        root._handleDisconnect("WebSocket closed")
      } else if (ws.status === WebSocket.Error) {
        console.log("[Claw] WS error:", ws.errorString)
        root._handleDisconnect(ws.errorString || "WebSocket error")
      }
    }

    onTextMessageReceived: function(message) {
      console.log("[Claw] WS recv:", message.substring(0, 200))
      root._dispatchFrame(message)
    }
  }

  // Fallback timer: if no connect.challenge arrives within 500ms, send connect anyway
  Timer {
    id: connectFallbackTimer
    interval: 500
    repeat: false
    onTriggered: {
      if (root.connectionState === "connecting")
        root._sendConnect("", 0)
    }
  }

  // Reconnection timer with exponential backoff
  Timer {
    id: reconnectTimer
    repeat: false
    onTriggered: {
      if (!ws.active) {
        ws.url = root._pickSetting("wsUrl", "ws://127.0.0.1:18789")
        ws.active = true
      }
    }
  }

  // Tick keepalive timer
  Timer {
    id: tickTimer
    interval: root._tickIntervalMs
    repeat: true
    running: false
    onTriggered: {
      if (root.connectionState === "connected")
        root.fetchChannels()
    }
  }

  // ──────────────────────────────────────────────
  // Frame Dispatcher
  // ──────────────────────────────────────────────

  function _dispatchFrame(raw) {
    var frame
    try {
      frame = JSON.parse(raw)
    } catch (e) {
      return
    }

    if (frame.type === "res")
      _handleResponse(frame)
    else if (frame.type === "event")
      _handleEvent(frame)
  }

  // ──────────────────────────────────────────────
  // Request / Response
  // ──────────────────────────────────────────────

  function _sendRequest(method, params, callback, timeoutMs) {
    var id = String(root._nextReqId++)
    var frame = {
      type: "req",
      id: id,
      method: method,
      params: params || {}
    }

    var timer = null
    if (timeoutMs && timeoutMs > 0) {
      timer = Qt.createQmlObject(
        'import QtQuick; Timer { repeat: false }',
        root,
        "clawReqTimeout_" + id
      )
      timer.interval = timeoutMs
      timer.triggered.connect(function() {
        var entry = root._pendingRequests[id]
        if (entry) {
          delete root._pendingRequests[id]
          if (entry.timer)
            entry.timer.destroy()
          if (entry.callback)
            entry.callback({ ok: false, error: { message: "Request timed out" } })
        }
      })
      timer.start()
    }

    var pending = root._pendingRequests
    pending[id] = { callback: callback || null, timer: timer }
    root._pendingRequests = pending

    var json = JSON.stringify(frame)
    console.log("[Claw] WS send:", json.substring(0, 200))
    ws.sendTextMessage(json)
    return id
  }

  function _handleResponse(frame) {
    var id = frame.id
    var pending = root._pendingRequests
    var entry = pending[id]
    if (!entry)
      return

    delete pending[id]
    root._pendingRequests = pending

    if (entry.timer) {
      entry.timer.stop()
      entry.timer.destroy()
    }

    if (entry.callback)
      entry.callback(frame)
  }

  function _cancelAllPending() {
    var pending = root._pendingRequests
    for (var id in pending) {
      var entry = pending[id]
      if (entry.timer) {
        entry.timer.stop()
        entry.timer.destroy()
      }
    }
    root._pendingRequests = ({})
  }

  // ──────────────────────────────────────────────
  // Event Handling
  // ──────────────────────────────────────────────

  function _handleEvent(frame) {
    var event = frame.event || ""
    if (event === "connect.challenge") {
      connectFallbackTimer.stop()
      var p = frame.payload || {}
      root._sendConnect(p.nonce || "", p.ts || 0)
    } else if (event === "chat") {
      root._handleChatEvent(frame.payload || {})
    }
  }

  // ──────────────────────────────────────────────
  // Connect Handshake
  // ──────────────────────────────────────────────

  // Unique instance ID for this client session
  property string _instanceId: ""

  function _ensureInstanceId() {
    if (!root._instanceId) {
      // Generate a simple UUID-like string
      var s = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
      root._instanceId = s.replace(/[xy]/g, function(c) {
        var r = Math.random() * 16 | 0
        return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16)
      })
    }
    return root._instanceId
  }

  function _sendConnect(nonce, ts) {
    var token = String(_pickSetting("token", "") || "").trim()
    var params = {
      minProtocol: 3,
      maxProtocol: 3,
      client: {
        id: "gateway-client",
        version: "0.2.0",
        platform: "linux",
        mode: "backend",
        instanceId: _ensureInstanceId()
      },
      role: "operator",
      scopes: [],
      caps: [],
      auth: { token: token }
    }

    console.log("[Claw] _sendConnect nonce:", nonce, "ts:", ts)
    _sendRequest("connect", params, function(res) {
      console.log("[Claw] connect response:", JSON.stringify(res).substring(0, 300))
      if (res.ok) {
        var payload = res.payload || {}
        // Extract tick interval from policy
        if (payload.policy && payload.policy.tickIntervalMs)
          root._tickIntervalMs = payload.policy.tickIntervalMs

        root.setStatus("connected", "")
        tickTimer.start()
        root.fetchChannels()
      } else {
        var errMsg = (res.error && res.error.message) ? res.error.message : "Connect handshake failed"
        console.log("[Claw] connect failed:", errMsg)
        root.setStatus("error", errMsg)
      }
    }, 10000)
  }

  // ──────────────────────────────────────────────
  // Disconnect / Reconnect
  // ──────────────────────────────────────────────

  function _handleDisconnect(reason) {
    console.log("[Claw] _handleDisconnect:", reason, "state:", root.connectionState, "ws.active:", ws.active)
    connectFallbackTimer.stop()
    tickTimer.stop()
    _cancelAllPending()

    // Don't overwrite a manual "idle" state
    if (root.connectionState !== "idle")
      root.setStatus("error", reason || "Disconnected")

    root.isSending = false
    root._activeAssistantIndex = -1
    root._activeAssistantText = ""

    var autoReconnect = !!_pickSetting("autoReconnect", true)
    if (autoReconnect && ws.active) {
      ws.active = false
      root._reconnectAttempts++
      var maxDelay = _pickSetting("reconnectMaxDelayMs", 30000)
      var delay = Math.min(1000 * Math.pow(2, root._reconnectAttempts - 1), maxDelay)
      root.setStatus("connecting", "Reconnecting in " + Math.round(delay / 1000) + "s...")
      reconnectTimer.interval = delay
      reconnectTimer.start()
    }
  }

  function disconnect() {
    reconnectTimer.stop()
    connectFallbackTimer.stop()
    tickTimer.stop()
    _cancelAllPending()
    ws.active = false
    root.setStatus("idle", "")
  }

  function reconnect() {
    disconnect()
    root._reconnectAttempts = 0
    root.setStatus("connecting", "")
    var wsUrl = root._pickSetting("wsUrl", "ws://127.0.0.1:18789")
    console.log("[Claw] reconnect() → url:", wsUrl, "pluginApi:", !!root.pluginApi)
    ws.url = wsUrl
    ws.active = true
  }

  // ──────────────────────────────────────────────
  // Channel / Session API
  // ──────────────────────────────────────────────

  function fetchChannels() {
    _sendRequest("channels.status", {}, function(res) {
      if (!res.ok)
        return

      var payload = res.payload || {}
      root.channelMeta = payload.channelMeta || []
      root.channelOrder = payload.channelOrder || []
      root.channelAccounts = payload.channelAccounts || {}
    }, 10000)
  }

  function fetchSessions(channelId) {
    var params = {}
    if (channelId)
      params.channelId = channelId

    _sendRequest("sessions.list", params, function(res) {
      if (!res.ok)
        return
      var payload = res.payload || {}
      root.sessionsList = payload.sessions || []
    }, 10000)
  }

  function fetchHistory(sessionKey, callback) {
    _sendRequest("chat.history", { sessionKey: sessionKey }, function(res) {
      if (!res.ok) {
        if (callback)
          callback([])
        return
      }
      var payload = res.payload || {}
      var rawMessages = payload.messages || []
      // Filter to displayable roles only
      var messages = []
      for (var i = 0; i < rawMessages.length; i++) {
        var m = rawMessages[i]
        var role = m.role || ""
        if (role === "user" || role === "assistant") {
          // Content may be a string or an array of content blocks
          var content = ""
          if (typeof m.content === "string") {
            content = m.content
          } else if (Array.isArray(m.content)) {
            var parts = []
            for (var j = 0; j < m.content.length; j++) {
              var block = m.content[j]
              if (block && block.type === "text" && block.text)
                parts.push(block.text)
            }
            content = parts.join("\n")
          }
          if (content)
            messages.push({ role: role, content: content })
        }
      }
      if (callback)
        callback(messages)
    }, 15000)
  }

  function sendChat(sessionKey, messageText) {
    if (root.isSending)
      return

    var t = (messageText || "").trim()
    if (!t)
      return

    appendMessage("user", t)
    appendMessage("assistant", "...")
    root._activeAssistantIndex = messagesModel.count - 1
    root._activeAssistantText = ""
    root.isSending = true

    var idempotencyKey = "claw-" + Date.now() + "-" + Math.random().toString(36).substring(2, 10)
    var agentId = String(_pickSetting("agentId", "main") || "").trim()

    _sendRequest("chat.send", {
      sessionKey: sessionKey,
      message: t,
      agentId: agentId,
      idempotencyKey: idempotencyKey
    }, function(res) {
      if (!res.ok) {
        var errMsg = (res.error && res.error.message) ? res.error.message : "Send failed"
        setMessageContent(root._activeAssistantIndex, "Error: " + errMsg)
        root.isSending = false
        root._activeAssistantIndex = -1
        root._activeAssistantText = ""
        _maybeNotifyResponse(errMsg, true)
      }
      // On success, streaming events will arrive via chat events
    }, 30000)
  }

  function abortChat(sessionKey) {
    _sendRequest("chat.abort", { sessionKey: sessionKey }, function(res) {
      // Best-effort; streaming handler will deal with the aborted state
    }, 5000)
  }

  // ──────────────────────────────────────────────
  // Chat Event Handling (streaming)
  // ──────────────────────────────────────────────

  function _extractTextFromContent(content) {
    if (typeof content === "string")
      return content
    if (Array.isArray(content)) {
      var parts = []
      for (var i = 0; i < content.length; i++) {
        var block = content[i]
        if (block && block.type === "text" && block.text)
          parts.push(block.text)
      }
      return parts.join("\n")
    }
    return ""
  }

  function _handleChatEvent(payload) {
    var sessionKey = payload.sessionKey || ""
    // Only handle events for the active session
    if (sessionKey !== root.activeSessionKey)
      return

    var state = payload.state || ""
    var message = payload.message || {}
    var text = _extractTextFromContent(message.content)

    if (state === "delta") {
      // Delta events carry accumulated full text in message.content
      if (root._activeAssistantIndex >= 0) {
        root._activeAssistantText = text
        setMessageContent(root._activeAssistantIndex, text || "...")
      }
    } else if (state === "final") {
      var finalText = text || root._activeAssistantText
      if (root._activeAssistantIndex >= 0)
        setMessageContent(root._activeAssistantIndex, finalText || "(empty response)")
      _maybeNotifyResponse(finalText, false)
      root.isSending = false
      root._activeAssistantIndex = -1
      root._activeAssistantText = ""
    } else if (state === "aborted") {
      if (root._activeAssistantIndex >= 0) {
        var abortedText = root._activeAssistantText || ""
        if (abortedText)
          setMessageContent(root._activeAssistantIndex, abortedText + "\n\n(aborted)")
        else
          setMessageContent(root._activeAssistantIndex, "(aborted)")
      }
      root.isSending = false
      root._activeAssistantIndex = -1
      root._activeAssistantText = ""
    } else if (state === "error") {
      var errMsg = (payload.error && typeof payload.error === "string") ? payload.error
        : (payload.error && payload.error.message) ? payload.error.message
        : "Unknown error"
      if (root._activeAssistantIndex >= 0)
        setMessageContent(root._activeAssistantIndex, "Error: " + errMsg)
      _maybeNotifyResponse(errMsg, true)
      root.isSending = false
      root._activeAssistantIndex = -1
      root._activeAssistantText = ""
    }
  }

  // ──────────────────────────────────────────────
  // Navigation
  // ──────────────────────────────────────────────

  function selectChannel(channelId) {
    root.selectedChannelId = channelId
    root.viewMode = "sessions"
    root.sessionsList = []
    fetchSessions(channelId)
  }

  function selectSession(sessionKey) {
    root.activeSessionKey = sessionKey
    root.viewMode = "chat"
    clearMessages()
    root.hasUnread = false
    root._activeAssistantIndex = -1
    root._activeAssistantText = ""

    fetchHistory(sessionKey, function(messages) {
      for (var i = 0; i < messages.length; i++) {
        var m = messages[i]
        appendMessage(m.role || "assistant", m.content || "")
      }
    })
  }

  function navigateBack() {
    if (root.viewMode === "chat") {
      root.viewMode = "sessions"
      root.activeSessionKey = ""
      clearMessages()
    } else if (root.viewMode === "sessions") {
      root.viewMode = "channels"
      root.selectedChannelId = ""
      root.sessionsList = []
    }
  }

  // ──────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────

  Component.onCompleted: {
    // Don't connect here; wait for pluginApi to be injected so settings are available.
  }

  onPluginApiChanged: {
    if (pluginApi)
      reconnect()
    else
      disconnect()
  }

  // Optional IPC hook
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
