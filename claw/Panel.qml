import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  // Injected by PluginPanelSlot
  property var pluginApi: null

  // SmartPanel properties (required)
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true

  // Preferred dimensions
  property real contentPreferredWidth: 720 * Style.uiScaleRatio
  property real contentPreferredHeight: 640 * Style.uiScaleRatio

  anchors.fill: parent

  // UI state
  property bool showSettings: false
  property bool isSending: false
  property string lastErrorText: ""
  property int lastHttpStatus: 0

  // Local editable settings (used at runtime; Save persists).
  property string editGatewayUrl: "http://127.0.0.1:18789"
  property string editToken: ""
  property string editAgentId: "main"
  property string editUser: "noctalia:claw"
  property string editSessionKey: ""
  property bool editStream: true
  property bool openAiEndpointEnabledHint: true
  property int requestTimeoutMs: 60000
  property bool editNotifyOnResponse: true
  property bool editNotifyOnlyWhenAppInactive: true

  // Slash command menu state
  property bool commandMenuOpen: false
  property int commandSelectedIndex: 0

  // Common commands appear first via rank (lower = higher).
  readonly property var commands: ([
    { name: "new", template: "/new", hasArgs: false, usage: "", rank: 10, description: "Start a new chat (clears history)." },
    { name: "clear", template: "/clear", hasArgs: false, usage: "", rank: 20, description: "Alias for /new." },
    { name: "settings", template: "/settings", hasArgs: false, usage: "", rank: 30, description: "Toggle the in-panel settings." },
    { name: "help", template: "/help", hasArgs: false, usage: "", rank: 40, description: "Show command help." },
    { name: "stream", template: "/stream ", hasArgs: true, usage: "on|off", rank: 50, description: "Enable/disable streaming responses." },
    { name: "agent", template: "/agent ", hasArgs: true, usage: "<id>", rank: 60, description: "Set agent id for routing." }
  ])

  // Local components
  // (File in this plugin folder)
  // qmllint: disable=unqualified
  // MessageBubble.qml is resolved relative to this file.

  // If the plugin main instance exposes a messagesModel, use it so chat persists
  // across panel close/reopen. Fall back to a local model if not available.
  ListModel { id: fallbackMessagesModel }
  ListModel { id: commandSuggestionsModel }

  function msgModel() {
    if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.messagesModel)
      return pluginApi.mainInstance.messagesModel
    return fallbackMessagesModel
  }

  function appendSystemMessage(text) {
    _appendMessage("system", text)
  }

  function pickSetting(key, fallback) {
    if (pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings[key] !== undefined)
      return pluginApi.pluginSettings[key]
    if (pluginApi && pluginApi.manifest && pluginApi.manifest.metadata
        && pluginApi.manifest.metadata.defaultSettings
        && pluginApi.manifest.metadata.defaultSettings[key] !== undefined)
      return pluginApi.manifest.metadata.defaultSettings[key]
    return fallback
  }

  function reloadFromSettings() {
    root.editGatewayUrl = pickSetting("gatewayUrl", "http://127.0.0.1:18789")
    root.editToken = pickSetting("token", "")
    root.editAgentId = pickSetting("agentId", "main")
    root.editUser = pickSetting("user", "noctalia:claw")
    root.editSessionKey = pickSetting("sessionKey", "")
    root.editStream = !!pickSetting("stream", true)
    root.openAiEndpointEnabledHint = !!pickSetting("openAiEndpointEnabledHint", true)
    root.requestTimeoutMs = pickSetting("requestTimeoutMs", 60000)
    root.editNotifyOnResponse = !!pickSetting("notifyOnResponse", true)
    root.editNotifyOnlyWhenAppInactive = !!pickSetting("notifyOnlyWhenAppInactive", true)
  }

  onPluginApiChanged: reloadFromSettings()
  Component.onCompleted: reloadFromSettings()

  function _setStatus(state, text) {
    if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.setStatus)
      pluginApi.mainInstance.setStatus(state, text || "")
  }

  function saveSettingsPartial() {
    if (!pluginApi)
      return

    pluginApi.pluginSettings.agentId = root.editAgentId
    pluginApi.pluginSettings.stream = root.editStream
    pluginApi.saveSettings()
  }

  function clearChat() {
    if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.clearMessages)
      pluginApi.mainInstance.clearMessages()
    else
      msgModel().clear()
    root.lastErrorText = ""
    root.lastHttpStatus = 0
    // Don't reset connection status when clearing chat history; it's a separate concern.
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

  function _maybeNotifyResponse(text, isError) {
    if (!root.editNotifyOnResponse)
      return

    if (root.editNotifyOnlyWhenAppInactive) {
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

  function _trimTrailingSlashes(s) {
    return (s || "").replace(/\/+$/, "")
  }

  function _appendMessage(role, content) {
    if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.appendMessage)
      pluginApi.mainInstance.appendMessage(role, content)
    else
      msgModel().append({ role: role, content: content, ts: Date.now() })

    if (chatList.count > 0)
      chatList.positionViewAtIndex(chatList.count - 1, ListView.End)
  }

  function _setMessageContent(index, content) {
    var m = msgModel()
    if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.setMessageContent) {
      pluginApi.mainInstance.setMessageContent(index, content)
    } else {
      if (index < 0 || index >= m.count)
        return
      m.setProperty(index, "content", content)
    }

    if (chatList.count > 0)
      chatList.positionViewAtIndex(chatList.count - 1, ListView.End)
  }

  function _buildOutgoingMessages(newUserText) {
    var arr = []
    var model = msgModel()
    for (var i = 0; i < model.count; i++) {
      var m = model.get(i)
      if (m.role === "system" || m.role === "user" || m.role === "assistant")
        arr.push({ role: m.role, content: m.content })
    }
    arr.push({ role: "user", content: newUserText })
    return arr
  }

  function commandShouldOpen(text) {
    if (!text)
      return false
    if (text.length < 1)
      return false
    if (text[0] !== "/")
      return false
    // Only while typing the command token (no whitespace yet).
    return text.indexOf(" ") === -1 && text.indexOf("\t") === -1 && text.indexOf("\n") === -1
  }

  function rebuildCommandSuggestions(text) {
    if (!commandShouldOpen(text)) {
      root.commandMenuOpen = false
      commandSuggestionsModel.clear()
      root.commandSelectedIndex = 0
      return
    }

    var q = text.substring(1).toLowerCase()
    var candidates = []

    for (var i = 0; i < root.commands.length; i++) {
      var c = root.commands[i]
      if (!q || c.name.indexOf(q) === 0)
        candidates.push(c)
    }

    candidates.sort(function(a, b) {
      if (a.rank !== b.rank)
        return a.rank - b.rank
      if (a.name < b.name) return -1
      if (a.name > b.name) return 1
      return 0
    })

    commandSuggestionsModel.clear()
    for (var j = 0; j < candidates.length; j++) {
      var x = candidates[j]
      commandSuggestionsModel.append({
        name: x.name,
        template: x.template,
        hasArgs: x.hasArgs,
        usage: x.usage,
        description: x.description
      })
    }

    root.commandMenuOpen = (commandSuggestionsModel.count > 0)
    if (root.commandSelectedIndex >= commandSuggestionsModel.count)
      root.commandSelectedIndex = 0
  }

  function insertSelectedCommand() {
    if (!root.commandMenuOpen || commandSuggestionsModel.count < 1)
      return
    var idx = root.commandSelectedIndex
    if (idx < 0 || idx >= commandSuggestionsModel.count)
      idx = 0
    var row = commandSuggestionsModel.get(idx)
    composerInput.text = row.template
    // Put cursor at end.
    if (composerInput.cursorPosition !== undefined)
      composerInput.cursorPosition = composerInput.text.length
    // Dropdown will close when there is whitespace (for arg commands) or on next rebuild.
    rebuildCommandSuggestions(composerInput.text)
  }

  function runSlashCommand(text) {
    var t = (text || "").trim()
    if (!t || t[0] !== "/")
      return false

    // Parse: /cmd [args...]
    var parts = t.substring(1).split(/\s+/)
    var cmd = (parts[0] || "").toLowerCase()
    var args = parts.slice(1)

    if (cmd === "new" || cmd === "clear") {
      clearChat()
      return true
    }

    if (cmd === "settings") {
      root.showSettings = !root.showSettings
      return true
    }

    if (cmd === "help") {
      var help = "Commands:\\n"
        for (var i = 0; i < root.commands.length; i++) {
          var c = root.commands[i]
          var usage = c.usage ? (" " + c.usage) : ""
          help += "  " + c.template.trim() + usage + " - " + c.description + "\n"
        }
      appendSystemMessage(help.trim())
      return true
    }

    if (cmd === "stream") {
      if (args.length < 1) {
        appendSystemMessage("Usage: /stream on|off")
        return true
      }
      var v = (args[0] || "").toLowerCase()
      if (v === "on" || v === "true" || v === "1") {
        root.editStream = true
        saveSettingsPartial()
        appendSystemMessage("Streaming enabled.")
        return true
      }
      if (v === "off" || v === "false" || v === "0") {
        root.editStream = false
        saveSettingsPartial()
        appendSystemMessage("Streaming disabled.")
        return true
      }
      appendSystemMessage("Usage: /stream on|off")
      return true
    }

    if (cmd === "agent") {
      if (args.length < 1) {
        appendSystemMessage("Usage: /agent <id>")
        return true
      }
      var id = args.join(" ").trim()
      if (!id) {
        appendSystemMessage("Usage: /agent <id>")
        return true
      }
      root.editAgentId = id
      saveSettingsPartial()
      appendSystemMessage("Agent set to: " + id)
      return true
    }

    appendSystemMessage("Unknown command: /" + cmd + ". Type /help for commands.")
    return true
  }

  function handleComposerKey(event) {
    if (!root.commandMenuOpen) {
      // Normal behavior: Enter sends.
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.sendMessage()
        event.accepted = true
      }
      return
    }

    if (event.key === Qt.Key_Escape) {
      root.commandMenuOpen = false
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Down) {
      root.commandSelectedIndex = Math.min(root.commandSelectedIndex + 1, commandSuggestionsModel.count - 1)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Up) {
      root.commandSelectedIndex = Math.max(root.commandSelectedIndex - 1, 0)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_PageDown) {
      root.commandSelectedIndex = Math.min(root.commandSelectedIndex + 5, commandSuggestionsModel.count - 1)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_PageUp) {
      root.commandSelectedIndex = Math.max(root.commandSelectedIndex - 5, 0)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      insertSelectedCommand()
      event.accepted = true
      return
    }
  }

  function sendMessage() {
    if (root.isSending)
      return

    var text = (composerInput.text || "").trim()
    if (!text)
      return

    // Slash commands are handled locally and do not call the gateway.
    if (text[0] === "/") {
      var handled = runSlashCommand(text)
      if (handled) {
        composerInput.text = ""
        rebuildCommandSuggestions("")
        return
      }
    }

    var outgoing = _buildOutgoingMessages(text)

    _appendMessage("user", text)
    composerInput.text = ""

    _appendMessage("assistant", "...")
    var assistantIndex = msgModel().count - 1

    root.lastErrorText = ""
    root.lastHttpStatus = 0
    root.isSending = true
    _setStatus("idle", "")

    if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.beginRequest)
      pluginApi.mainInstance.beginRequest()

    _requestChatCompletions(outgoing, assistantIndex, root.editStream, true)
  }

  function _requestChatCompletions(outgoingMessages, assistantIndex, stream, allowFallback) {
    var base = _trimTrailingSlashes(root.editGatewayUrl)
    var url = base + "/v1/chat/completions"

    var xhr = new XMLHttpRequest()

    var timeoutTimer = Qt.createQmlObject(
      'import QtQuick 2.0; Timer { repeat: false }',
      root,
      "clawTimeoutTimer"
    )

    var processedLen = 0
    var sseBuffer = ""
    var assistantText = ""
    var sawAnyDelta = false

    function fail(msg, status) {
      root.isSending = false
      root.lastHttpStatus = status || 0
      root.lastErrorText = msg || "Request failed"
      _setStatus("error", root.lastErrorText)
      _setMessageContent(assistantIndex, "Error: " + root.lastErrorText)

      _maybeNotifyResponse(root.lastErrorText, true)

      if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.endRequest)
        pluginApi.mainInstance.endRequest()
    }

    function finishOk() {
      root.isSending = false
      root.lastHttpStatus = xhr.status || 0
      root.lastErrorText = ""
      _setStatus("ok", "")

      if (!assistantText)
        _setMessageContent(assistantIndex, "(empty response)")

      _maybeNotifyResponse(assistantText, false)

      if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.endRequest)
        pluginApi.mainInstance.endRequest()
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
              _setMessageContent(assistantIndex, assistantText)
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
        _setMessageContent(assistantIndex, "...")
        _requestChatCompletions(outgoingMessages, assistantIndex, false, false)
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
            _setMessageContent(assistantIndex, assistantText || "(empty response)")
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
            _setMessageContent(assistantIndex, assistantText || "(empty response)")
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

      if (status === 401 || status === 403) {
        msgText = "Authentication/authorization failed (HTTP " + status + "). Check token and gateway config."
      } else if (status === 405) {
        msgText = "Method Not Allowed (HTTP 405). This server is refusing POST/OPTIONS, which usually means you're hitting the OpenClaw Control UI or a reverse proxy that only allows GET. Point Claw at the OpenClaw Gateway API base URL and ensure /v1/chat/completions is enabled."
      } else if (status === 404 && root.openAiEndpointEnabledHint) {
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
        _setMessageContent(assistantIndex, "...")
        _requestChatCompletions(outgoingMessages, assistantIndex, false, false)
        return
      }

      fail(msgText, status)
    }

    timeoutTimer.interval = root.requestTimeoutMs
    timeoutTimer.triggered.connect(function() {
      try { xhr.abort() } catch (e) {}

      if (stream && allowFallback) {
        _setMessageContent(assistantIndex, "...")
        _requestChatCompletions(outgoingMessages, assistantIndex, false, false)
        return
      }

      fail("Request timed out after " + root.requestTimeoutMs + "ms.", 0)
    })

    // Prefer both: header selection + model hint for gateways that route by model.
    var modelName = "openclaw"
    var agentId = (root.editAgentId || "").trim()
    if (agentId.length > 0)
      modelName = "openclaw:" + agentId

    var payload = {
      model: modelName,
      messages: outgoingMessages,
      stream: !!stream,
      user: root.editUser
    }

    xhr.open("POST", url)
    xhr.setRequestHeader("Content-Type", "application/json")

    var token = (root.editToken || "").trim()
    if (token.length > 0)
      xhr.setRequestHeader("Authorization", "Bearer " + token)

    if (agentId.length > 0)
      xhr.setRequestHeader("x-openclaw-agent-id", agentId)

    var sessionKey = (root.editSessionKey || "").trim()
    if (sessionKey.length > 0)
      xhr.setRequestHeader("x-openclaw-session-key", sessionKey)

    timeoutTimer.start()
    xhr.send(JSON.stringify(payload))
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        Rectangle {
          Layout.fillWidth: true
          color: Color.mSurface
          radius: Style.radiusL
          border.width: 1
          border.color: Style.capsuleBorderColor

          implicitHeight: headerRow.implicitHeight + Style.marginS * 2

          RowLayout {
            id: headerRow
            anchors.fill: parent
            anchors.margins: Style.marginS
            spacing: Style.marginM

            NText {
              text: "Claw"
              pointSize: Style.fontSizeL
              font.weight: Font.Bold
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            Rectangle {
              width: 9 * Style.uiScaleRatio
              height: width
              radius: width / 2
              color: {
                var state = "idle"
                if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.connectionState)
                  state = pluginApi.mainInstance.connectionState
                if (state === "ok") return "#4CAF50"
                if (state === "error") return "#F44336"
                return Color.mOutline
              }
              border.width: 1
              border.color: Color.mOutline
            }

            NIconButton {
              icon: root.showSettings ? "settings-off" : "settings"
              onClicked: root.showSettings = !root.showSettings
            }

            NIconButton {
              icon: "trash"
              onClicked: root.clearChat()
            }
          }
        }
      }

      // Settings (collapsible)
      Rectangle {
        Layout.fillWidth: true
        color: Color.mSurfaceVariant
        radius: Style.radiusL
        visible: root.showSettings

        // Rectangle doesn't auto-size to its children; give it an implicit height.
        implicitHeight: settingsLayout.implicitHeight + Style.marginM * 2

        ColumnLayout {
          id: settingsLayout
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.marginM
          spacing: Style.marginS

          NText {
            Layout.fillWidth: true
            text: "Gateway"
            pointSize: Style.fontSizeM
            font.weight: Font.DemiBold
            color: Color.mOnSurface
          }

          NTextInput {
            Layout.fillWidth: true
            label: "Gateway URL"
            description: "Example: http://127.0.0.1:18789"
            text: root.editGatewayUrl
            onTextChanged: root.editGatewayUrl = text
          }

          NLabel {
            Layout.fillWidth: true
            label: "Token"
            description: "Sent as Authorization: Bearer <token|password>. Do not expose the gateway unauthenticated."
          }

          TextField {
            Layout.fillWidth: true
            text: root.editToken
            placeholderText: "(optional)"
            echoMode: TextInput.Password
            onTextChanged: root.editToken = text
          }

          NTextInput {
            Layout.fillWidth: true
            label: "Agent ID"
            description: "Sent as x-openclaw-agent-id. Also used as model openclaw:<agentId>"
            text: root.editAgentId
            onTextChanged: root.editAgentId = text
          }

          NTextInput {
            Layout.fillWidth: true
            label: "User"
            description: "OpenAI 'user' field for stable sessions. Default: noctalia:claw"
            text: root.editUser
            onTextChanged: root.editUser = text
          }

          NTextInput {
            Layout.fillWidth: true
            label: "Session Key (optional)"
            description: "If set, sent as x-openclaw-session-key"
            text: root.editSessionKey
            onTextChanged: root.editSessionKey = text
          }

          NToggle {
            Layout.fillWidth: true
            label: "Stream responses (SSE)"
            description: "Token-by-token feel when supported. Auto-falls back to non-streaming if needed."
            checked: root.editStream
            onCheckedChanged: root.editStream = checked
          }

          NToggle {
            Layout.fillWidth: true
            label: "Notify when response arrives"
            description: "Show a Noctalia toast notification when OpenClaw finishes responding."
            checked: root.editNotifyOnResponse
            onCheckedChanged: root.editNotifyOnResponse = checked
          }

          NToggle {
            Layout.fillWidth: true
            label: "Only notify when app inactive"
            description: "Only notify if Noctalia is not the focused application."
            checked: root.editNotifyOnlyWhenAppInactive
            enabled: root.editNotifyOnResponse
            onCheckedChanged: root.editNotifyOnlyWhenAppInactive = checked
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NButton {
              text: "Save"
              onClicked: {
                if (!root.pluginApi)
                  return

                root.pluginApi.pluginSettings.gatewayUrl = root.editGatewayUrl
                root.pluginApi.pluginSettings.token = root.editToken
                root.pluginApi.pluginSettings.agentId = root.editAgentId
                root.pluginApi.pluginSettings.user = root.editUser
                root.pluginApi.pluginSettings.sessionKey = root.editSessionKey
                root.pluginApi.pluginSettings.stream = root.editStream
                root.pluginApi.pluginSettings.notifyOnResponse = root.editNotifyOnResponse
                root.pluginApi.pluginSettings.notifyOnlyWhenAppInactive = root.editNotifyOnlyWhenAppInactive
                root.pluginApi.saveSettings()
              }
            }

            Item { Layout.fillWidth: true }

            NText {
              text: root.isSending ? "Sending..." : ""
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              visible: root.isSending
            }
          }

          NText {
            Layout.fillWidth: true
            visible: !(root.editToken && root.editToken.trim().length > 0)
            text: "Note: token is empty. If your gateway requires auth, requests will fail with 401/403."
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            pointSize: Style.fontSizeS
          }

          NText {
            Layout.fillWidth: true
            visible: !!root.lastErrorText
            text: root.lastErrorText
            color: "#F44336"
            wrapMode: Text.WordWrap
            pointSize: Style.fontSizeS
          }

          NText {
            Layout.fillWidth: true
            visible: (root.lastHttpStatus === 404 || root.lastHttpStatus === 403) && root.openAiEndpointEnabledHint
            text: "If this is OpenClaw Gateway: enable gateway.http.endpoints.chatCompletions.enabled = true"
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            pointSize: Style.fontSizeS
          }
        }
      }

      // Chat body
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurface
        radius: Style.radiusL
        border.width: 1
        border.color: Style.capsuleBorderColor

        NScrollView {
          anchors.fill: parent

          ListView {
            id: chatList
            width: parent.width
            height: parent.height
            clip: true
            spacing: Style.marginS
            model: msgModel()

            delegate: MessageBubble {
              width: ListView.view.width
              role: model.role
              content: model.content
            }
          }
        }
      }

      // Footer composer
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        Item {
          id: composerArea
          Layout.fillWidth: true
          implicitHeight: composerInput.implicitHeight

          NTextInput {
            id: composerInput
            anchors.fill: parent
            placeholderText: "Message OpenClaw..."
            enabled: !root.isSending

            onTextChanged: rebuildCommandSuggestions(text)
            Keys.onPressed: handleComposerKey(event)
          }

          // Slash command dropdown
          Rectangle {
            id: commandMenu
            visible: root.commandMenuOpen && commandSuggestionsModel.count > 0
            width: composerArea.width
            // Cap height; list is scrollable.
            height: Math.min(240 * Style.uiScaleRatio, commandList.contentHeight + Style.marginS * 2)
            radius: Style.radiusM
            color: Color.mSurface
            border.width: 1
            border.color: Color.mOutlineVariant !== undefined ? Color.mOutlineVariant : Color.mOutline
            clip: true

            anchors.left: composerArea.left
            anchors.bottom: composerArea.top
            anchors.bottomMargin: Style.marginS

            ListView {
              id: commandList
              anchors.fill: parent
              anchors.margins: Style.marginS
              model: commandSuggestionsModel
              clip: true
              currentIndex: root.commandSelectedIndex
              onCurrentIndexChanged: root.commandSelectedIndex = currentIndex

              delegate: Rectangle {
                width: ListView.view.width
                height: cmdRow.implicitHeight + Style.marginS
                radius: Style.radiusS
                color: (index === root.commandSelectedIndex)
                  ? (Color.mSecondaryContainer !== undefined ? Color.mSecondaryContainer : Color.mSurfaceVariant)
                  : "transparent"

                RowLayout {
                  id: cmdRow
                  anchors.fill: parent
                  anchors.margins: Style.marginS
                  spacing: Style.marginM

                  NText {
                    text: "/" + model.name
                    color: Color.mOnSurface
                    font.weight: Font.DemiBold
                    pointSize: Style.fontSizeM
                  }

                  NText {
                    text: model.usage ? model.usage : ""
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                    visible: !!model.usage
                  }

                  Item { Layout.fillWidth: true }

                  NText {
                    text: model.description
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                    elide: Text.ElideRight
                    Layout.maximumWidth: 320 * Style.uiScaleRatio
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    root.commandSelectedIndex = index
                    insertSelectedCommand()
                  }
                }
              }
            }
          }
        }

        NButton {
          text: "Send"
          enabled: !root.isSending && (composerInput.text || "").trim().length > 0
          onClicked: root.sendMessage()
        }
      }
    }
  }
}
