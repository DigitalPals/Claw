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
  property var unreadSessions: ({})
  readonly property bool hasUnread: Object.keys(unreadSessions).length > 0

  // Keep chat in memory across panel open/close.
  property alias messagesModel: messagesModel

  // Channel/session navigation state
  property var channelMeta: []          // unified: configured + virtual channels
  property var channelOrder: []
  property var channelAccounts: ({})
  property var allSessions: []          // all sessions from sessions.list
  property var sessionsList: []          // filtered for selected channel
  property string viewMode: "channels"   // "channels" | "sessions" | "chat"
  property string selectedChannelId: ""
  property string activeSessionKey: ""

  readonly property var _channelIconMap: ({
    "main":       "terminal-2",
    "webchat":    "world",
    "slack":      "brand-slack",
    "whatsapp":   "brand-whatsapp",
    "telegram":   "brand-telegram",
    "discord":    "brand-discord",
    "messenger":  "brand-messenger",
    "instagram":  "brand-instagram",
    "sms":        "message-2",
    "email":      "mail",
    "voice":      "phone",
    "twitter":    "brand-twitter",
    "x":          "brand-twitter",
    "teams":      "brand-teams",
    "line":       "brand-line",
    "wechat":     "brand-wechat",
    "signal":     "brand-signal",
    "viber":      "brand-viber",
    "skype":      "brand-skype",
    "facebook":   "brand-facebook",
    "twitch":     "brand-twitch",
    "youtube":    "brand-youtube",
    "reddit":     "brand-reddit",
    "tiktok":     "brand-tiktok"
  })

  readonly property var _channelLabelMap: ({
    "main":       "Main (Direct)",
    "webchat":    "Web Chat",
    "slack":      "Slack",
    "whatsapp":   "WhatsApp",
    "telegram":   "Telegram",
    "discord":    "Discord",
    "messenger":  "Messenger",
    "instagram":  "Instagram",
    "sms":        "SMS",
    "email":      "Email",
    "voice":      "Voice",
    "twitter":    "Twitter",
    "x":          "X (Twitter)",
    "teams":      "Microsoft Teams",
    "line":       "LINE",
    "wechat":     "WeChat",
    "signal":     "Signal",
    "viber":      "Viber",
    "skype":      "Skype",
    "facebook":   "Facebook",
    "twitch":     "Twitch",
    "youtube":    "YouTube",
    "reddit":     "Reddit",
    "tiktok":     "TikTok"
  })

  // Streaming state
  property int _activeAssistantIndex: -1
  property string _activeAssistantText: ""

  // Protocol request tracking
  property int _nextReqId: 1
  property var _pendingRequests: ({})    // id -> { callback, timer }

  // Reconnection state
  property int _reconnectAttempts: 0
  property bool _disconnecting: false

  // Tick keepalive interval from server (default 15s)
  property int _tickIntervalMs: 15000

  readonly property string _defaultWsUrl: "ws://127.0.0.1:18789"

  function setStatus(state, errorText) {
    root.connectionState = state || "idle"
    root.lastErrorText = errorText || ""
  }

  function setPanelActive(active) {
    root.panelActive = !!active
  }

  function markRead() {
    _clearSessionUnread(root.activeSessionKey)
  }

  function clearMessages() {
    messagesModel.clear()
  }

  function clearChat() {
    clearMessages()
    _clearSessionUnread(root.activeSessionKey)
    root._activeAssistantIndex = -1
    root._activeAssistantText = ""
  }

  function _markSessionUnread(sessionKey) {
    if (!sessionKey)
      return
    var old = root.unreadSessions
    if (old[sessionKey])
      return
    var fresh = {}
    for (var k in old)
      fresh[k] = true
    fresh[sessionKey] = true
    root.unreadSessions = fresh
  }

  function _clearSessionUnread(sessionKey) {
    if (!sessionKey)
      return
    var old = root.unreadSessions
    if (!old[sessionKey])
      return
    var fresh = {}
    for (var k in old) {
      if (k !== sessionKey)
        fresh[k] = true
    }
    root.unreadSessions = fresh
  }

  function _clearChannelSessions(channelId) {
    if (!channelId)
      return
    var old = root.unreadSessions
    var fresh = {}
    var changed = false
    for (var k in old) {
      if (_channelFromSessionKey(k) === channelId)
        changed = true
      else
        fresh[k] = true
    }
    if (changed)
      root.unreadSessions = fresh
  }

  readonly property int _maxMessages: 500

  function appendMessage(role, content, contentBlocks) {
    messagesModel.append({
      role: role,
      content: content,
      ts: Date.now(),
      streaming: false,
      contentBlocks: contentBlocks || ""
    })

    // Trim oldest messages if over cap
    while (messagesModel.count > root._maxMessages) {
      messagesModel.remove(0)
      if (root._activeAssistantIndex > 0)
        root._activeAssistantIndex -= 1
      else if (root._activeAssistantIndex === 0)
        root._activeAssistantIndex = -1  // removed the active message
    }

    return messagesModel.count - 1
  }

  function setMessageContent(index, content) {
    if (index < 0 || index >= messagesModel.count)
      return
    messagesModel.setProperty(index, "content", content)
    if (!root.panelActive || !root.panelAtBottom)
      _markSessionUnread(root.activeSessionKey)
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
      } catch (e0) { console.warn("[Claw] Qt.application.active check failed:", e0) }
    }

    var title = "OpenClaw Chat"
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
    url: root._pickSetting("wsUrl", root._defaultWsUrl)
    active: false

    onStatusChanged: {
      console.log("[Claw] WS status changed:", ws.status,
                  "(0=Connecting, 1=Open, 2=Closing, 3=Closed, 4=Error)",
                  "url:", ws.url, "errorString:", ws.errorString)
      if (ws.status === WebSocket.Open) {
        console.log("[Claw] WS open, starting handshake")
        root._disconnecting = false
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
      console.log("[Claw] WS recv:", message.substring(0, 500))
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
        root._disconnecting = false
        ws.url = root._pickSetting("wsUrl", root._defaultWsUrl)
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
      console.warn("[Claw] Failed to parse frame:", e, raw.substring(0, 200))
      return
    }

    if (!frame || typeof frame.type !== "string") {
      console.warn("[Claw] Malformed frame (no type):", raw.substring(0, 200))
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

    var effectiveTimeout = (timeoutMs && timeoutMs > 0) ? timeoutMs : 60000
    var timer = null
    {
      timer = Qt.createQmlObject(
        'import QtQuick; Timer { repeat: false }',
        root,
        "clawReqTimeout_" + id
      )
      timer.interval = effectiveTimeout
      timer.triggered.connect(function() {
        var entry = root._pendingRequests[id]
        if (entry) {
          delete root._pendingRequests[id]
          try { if (entry.timer) entry.timer.destroy() } catch(e) { console.warn("[Claw] Timer destroy failed:", e) }
          if (entry.callback)
            entry.callback({ ok: false, error: { message: "Request timed out: " + method } })
        }
      })
      timer.start()
    }

    // Guard: don't send on a closed socket — fail immediately
    if (ws.status !== WebSocket.Open) {
      if (timer)
        timer.destroy()
      if (callback)
        callback({ ok: false, error: { message: "WebSocket not connected" } })
      return null
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
      try { entry.timer.stop(); entry.timer.destroy() } catch(e) { console.warn("[Claw] Timer cleanup failed:", e) }
    }

    if (entry.callback)
      entry.callback(frame)
  }

  function _cancelAllPending() {
    var pending = root._pendingRequests
    root._pendingRequests = ({})
    for (var id in pending) {
      var entry = pending[id]
      if (entry.timer) {
        try { entry.timer.stop(); entry.timer.destroy() } catch(e) { console.warn("[Claw] Timer cleanup failed:", e) }
      }
      if (entry.callback) {
        try {
          entry.callback({ ok: false, error: { message: "Connection lost" } })
        } catch (e) {
          console.warn("[Claw] Error in pending callback:", e)
        }
      }
    }
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
    if (root._disconnecting)
      return
    root._disconnecting = true
    console.log("[Claw] _handleDisconnect:", reason, "state:", root.connectionState, "ws.active:", ws.active)
    connectFallbackTimer.stop()
    tickTimer.stop()

    // Cancel pending requests FIRST so their error callbacks can still
    // reference valid streaming state (_activeAssistantIndex, etc.)
    _cancelAllPending()

    // Don't overwrite a manual "idle" state
    if (root.connectionState !== "idle")
      root.setStatus("error", reason || "Disconnected")

    // Now reset streaming state
    root.isSending = false
    root._activeAssistantIndex = -1
    root._activeAssistantText = ""

    var autoReconnect = !!_pickSetting("autoReconnect", true)
    if (autoReconnect && ws.active) {
      ws.active = false
      root._reconnectAttempts = Math.min(root._reconnectAttempts + 1, 20)
      var maxDelay = _pickSetting("reconnectMaxDelayMs", 30000)
      var delay = Math.min(1000 * Math.pow(2, root._reconnectAttempts - 1), maxDelay)
      root.setStatus("connecting", "Reconnecting in " + Math.round(delay / 1000) + "s...")
      reconnectTimer.stop()
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
    root._disconnecting = false
    root._reconnectAttempts = 0
    root.setStatus("connecting", "")
    var wsUrl = root._pickSetting("wsUrl", root._defaultWsUrl)
    console.log("[Claw] reconnect() → url:", wsUrl, "pluginApi:", !!root.pluginApi)
    ws.url = wsUrl
    ws.active = true
  }

  // ──────────────────────────────────────────────
  // Channel / Session API
  // ──────────────────────────────────────────────

  // Extract the channel type from a session key.
  // Format: "agent:<agentId>:<channelType>[:<peer>...]"
  function _channelFromSessionKey(sessionKey) {
    var parts = (sessionKey || "").split(":")
    if (parts.length >= 3 && parts[0] === "agent")
      return parts[2]
    if (parts.length >= 2)
      return parts[1]
    return ""
  }

  function _virtualChannelLabel(channelType) {
    return _channelLabelMap[channelType]
      || (channelType.charAt(0).toUpperCase() + channelType.slice(1))
  }

  function _resolveChannelIcon(channelId) {
    if (_channelIconMap[channelId])
      return _channelIconMap[channelId]
    return "message-circle"
  }

  function fetchChannels() {
    _sendRequest("channels.status", {}, function(res) {
      if (!res.ok)
        return

      var payload = res.payload || {}
      var order = payload.channelOrder || []
      root.channelOrder = order
      root.channelAccounts = payload.channelAccounts || {}

      // Prefer server-provided channelMeta array; fall back to building from maps
      var configuredMeta = payload.channelMeta || []
      if (configuredMeta.length === 0 && order.length > 0) {
        var labels = payload.channelLabels || {}
        var detailLabels = payload.channelDetailLabels || {}
        var images = payload.channelSystemImages || {}
        for (var i = 0; i < order.length; i++) {
          var cid = order[i]
          configuredMeta.push({
            id: cid,
            label: labels[cid] || cid,
            detailLabel: detailLabels[cid] || "",
            systemImage: _resolveChannelIcon(cid)
          })
        }
      }

      // Also fetch all sessions to discover virtual channels
      _sendRequest("sessions.list", {}, function(sessRes) {
        var sessions = []
        if (sessRes.ok)
          sessions = (sessRes.payload || {}).sessions || []
        root.allSessions = sessions

        // Build set of configured channel IDs
        var configuredIds = {}
        for (var ci = 0; ci < configuredMeta.length; ci++)
          configuredIds[configuredMeta[ci].id] = true

        // Discover virtual channels from session data
        var virtualMap = {}
        for (var j = 0; j < sessions.length; j++) {
          var s = sessions[j]
          var ch = s.channel || _channelFromSessionKey(s.key || "")
          if (ch && !configuredIds[ch] && !virtualMap[ch])
            virtualMap[ch] = true
        }

        // Build unified channel list: configured first, then virtual
        var unified = []
        for (var k = 0; k < configuredMeta.length; k++) {
          var cm = configuredMeta[k]
          cm.systemImage = _resolveChannelIcon(cm.id)
          unified.push(cm)
        }
        for (var vch in virtualMap) {
          unified.push({
            id: vch,
            label: _virtualChannelLabel(vch),
            detailLabel: "",
            systemImage: _resolveChannelIcon(vch),
            virtual: true
          })
        }

        root.channelMeta = unified
        console.log("[Claw] fetchChannels: " + unified.length + " channels (" + configuredMeta.length + " configured, " + Object.keys(virtualMap).length + " virtual), " + sessions.length + " total sessions")
      }, 10000)
    }, 10000)
  }

  function _filterSessionsForChannel(channelId) {
    var filtered = []
    for (var i = 0; i < root.allSessions.length; i++) {
      var s = root.allSessions[i]
      // Prefer the explicit channel field; fall back to parsing the key
      var sCh = s.channel || _channelFromSessionKey(s.key || "")
      if (sCh === channelId)
        filtered.push(s)
    }
    return filtered
  }

  function fetchSessions(channelId) {
    // First, filter from cached allSessions for immediate display
    var cached = _filterSessionsForChannel(channelId)
    root.sessionsList = cached
    console.log("[Claw] fetchSessions(" + channelId + "): " + cached.length + " cached from " + root.allSessions.length + " total")

    // Then refresh from server
    _sendRequest("sessions.list", {}, function(res) {
      if (!res.ok)
        return
      var sessions = (res.payload || {}).sessions || []
      root.allSessions = sessions
      // Log first session to see field names
      if (sessions.length > 0)
        console.log("[Claw] sessions[0] keys: " + JSON.stringify(Object.keys(sessions[0])) + " sample: " + JSON.stringify(sessions[0]).substring(0, 200))
      // Re-filter if still viewing this channel
      if (root.selectedChannelId === channelId) {
        var filtered = _filterSessionsForChannel(channelId)
        root.sessionsList = filtered
        console.log("[Claw] fetchSessions(" + channelId + ") refreshed: " + filtered.length + " sessions")
      }
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
          var contentBlocks = ""
          if (typeof m.content === "string") {
            content = m.content
          } else if (Array.isArray(m.content)) {
            contentBlocks = _extractContentBlocksJson(m.content)
            var parts = []
            for (var j = 0; j < m.content.length; j++) {
              var block = m.content[j]
              if (block && block.type === "text" && block.text)
                parts.push(block.text)
            }
            content = parts.join("\n")
          }
          if (content || contentBlocks)
            messages.push({ role: role, content: content, contentBlocks: contentBlocks })
        }
      }
      if (callback)
        callback(messages)
    }, 15000)
  }

  function _extractContentBlocksJson(contentArray) {
    // Only serialize if there are non-text blocks (images, etc.)
    var hasNonText = false
    for (var i = 0; i < contentArray.length; i++) {
      if (contentArray[i] && contentArray[i].type !== "text") {
        hasNonText = true
        break
      }
    }
    if (!hasNonText)
      return ""
    return JSON.stringify(contentArray)
  }

  function sendChatWithAttachments(sessionKey, messageText, attachments, contentBlocksJson) {
    if (root.isSending)
      return
    if (!sessionKey) {
      console.warn("[Claw] sendChatWithAttachments: no sessionKey")
      return
    }
    if ((messageText || "").length > 50000) {
      console.warn("[Claw] Message too long, truncating")
      messageText = messageText.substring(0, 50000)
    }

    var displayText = messageText || "(image)"
    appendMessage("user", displayText, contentBlocksJson || "")
    appendMessage("assistant", "...")
    root._activeAssistantIndex = messagesModel.count - 1
    messagesModel.setProperty(root._activeAssistantIndex, "streaming", true)
    root._activeAssistantText = ""
    root.isSending = true

    var idempotencyKey = "claw-" + Date.now() + "-" + Math.random().toString(36).substring(2, 10)

    _sendRequest("chat.send", {
      sessionKey: sessionKey,
      message: (messageText || "").trim() || " ",
      idempotencyKey: idempotencyKey,
      attachments: attachments
    }, function(res) {
      if (!res.ok) {
        var errMsg = (res.error && res.error.message) ? res.error.message : "Send failed"
        _handleSendError(errMsg)
      }
      // On success, streaming events will arrive via chat events
    }, 300000)
  }

  function sendChat(sessionKey, messageText) {
    if (root.isSending)
      return
    if (!sessionKey) {
      console.warn("[Claw] sendChat: no sessionKey")
      return
    }

    var t = (messageText || "").trim()
    if (!t)
      return
    if (t.length > 50000) {
      console.warn("[Claw] Message too long, truncating")
      t = t.substring(0, 50000)
    }

    appendMessage("user", t)
    appendMessage("assistant", "...")
    root._activeAssistantIndex = messagesModel.count - 1
    messagesModel.setProperty(root._activeAssistantIndex, "streaming", true)
    root._activeAssistantText = ""
    root.isSending = true

    var idempotencyKey = "claw-" + Date.now() + "-" + Math.random().toString(36).substring(2, 10)

    _sendRequest("chat.send", {
      sessionKey: sessionKey,
      message: t,
      idempotencyKey: idempotencyKey
    }, function(res) {
      if (!res.ok) {
        var errMsg = (res.error && res.error.message) ? res.error.message : "Send failed"
        _handleSendError(errMsg)
      }
      // On success, streaming events will arrive via chat events
    }, 300000)
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
    if (content == null)
      return ""
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

  function _finishStreaming(index) {
    if (index >= 0 && index < messagesModel.count)
      messagesModel.setProperty(index, "streaming", false)
  }

  function _endStreaming() {
    root.isSending = false
    root._activeAssistantIndex = -1
    root._activeAssistantText = ""
  }

  function _handleSendError(errMsg) {
    _finishStreaming(root._activeAssistantIndex)
    setMessageContent(root._activeAssistantIndex, "Error: " + errMsg)
    _endStreaming()
    _maybeNotifyResponse(errMsg, true)
  }

  function _handleChatEvent(payload) {
    var sessionKey = payload.sessionKey || ""
    var state = payload.state || ""
    var message = payload.message || {}
    var text = _extractTextFromContent(message.content)

    // Active session: handle streaming UI as before
    if (sessionKey === root.activeSessionKey) {
      if (state === "delta") {
        if (root._activeAssistantIndex >= 0) {
          root._activeAssistantText = text
          setMessageContent(root._activeAssistantIndex, text || "...")
        }
      } else if (state === "final") {
        var finalText = text || root._activeAssistantText
        _finishStreaming(root._activeAssistantIndex)
        setMessageContent(root._activeAssistantIndex, finalText || "(empty response)")
        _maybeNotifyResponse(finalText, false)
        _endStreaming()
      } else if (state === "aborted") {
        _finishStreaming(root._activeAssistantIndex)
        var abortedText = root._activeAssistantText || ""
        if (abortedText)
          setMessageContent(root._activeAssistantIndex, abortedText + "\n\n(aborted)")
        else
          setMessageContent(root._activeAssistantIndex, "(aborted)")
        _endStreaming()
      } else if (state === "error") {
        var errMsg = (payload.error && typeof payload.error === "string") ? payload.error
          : (payload.error && payload.error.message) ? payload.error.message
          : "Unknown error"
        _finishStreaming(root._activeAssistantIndex)
        setMessageContent(root._activeAssistantIndex, "Error: " + errMsg)
        _maybeNotifyResponse(errMsg, true)
        _endStreaming()
      }
      return
    }

    // Non-active session: mark session unread on final/error (not delta to avoid spam)
    if (state === "final" || state === "error") {
      _markSessionUnread(sessionKey)

      if (state === "error") {
        var bgErrMsg = (payload.error && typeof payload.error === "string") ? payload.error
          : (payload.error && payload.error.message) ? payload.error.message
          : "Unknown error"
        _maybeNotifyResponse(bgErrMsg, true)
      } else {
        _maybeNotifyResponse(text, false)
      }
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
    _clearSessionUnread(sessionKey)
    root._activeAssistantIndex = -1
    root._activeAssistantText = ""

    fetchHistory(sessionKey, function(messages) {
      // Discard if user navigated away during fetch
      if (root.activeSessionKey !== sessionKey)
        return
      for (var i = 0; i < messages.length; i++) {
        var m = messages[i]
        appendMessage(m.role || "assistant", m.content || "", m.contentBlocks || "")
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
