import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

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

  ListModel { id: messagesModel }

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
  }

  onPluginApiChanged: reloadFromSettings()
  Component.onCompleted: reloadFromSettings()

  function _setStatus(state, text) {
    if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.setStatus)
      pluginApi.mainInstance.setStatus(state, text || "")
  }

  function clearChat() {
    messagesModel.clear()
    root.lastErrorText = ""
    root.lastHttpStatus = 0
    _setStatus("idle", "")
  }

  function _trimTrailingSlashes(s) {
    return (s || "").replace(/\/+$/, "")
  }

  function _appendMessage(role, content) {
    messagesModel.append({
      role: role,
      content: content,
      ts: Date.now()
    })

    if (chatList.count > 0)
      chatList.positionViewAtIndex(chatList.count - 1, ListView.End)
  }

  function _setMessageContent(index, content) {
    if (index < 0 || index >= messagesModel.count)
      return
    messagesModel.setProperty(index, "content", content)

    if (chatList.count > 0)
      chatList.positionViewAtIndex(chatList.count - 1, ListView.End)
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

  function sendMessage() {
    if (root.isSending)
      return

    var text = (composerInput.text || "").trim()
    if (!text)
      return

    var outgoing = _buildOutgoingMessages(text)

    _appendMessage("user", text)
    composerInput.text = ""

    _appendMessage("assistant", "...")
    var assistantIndex = messagesModel.count - 1

    root.lastErrorText = ""
    root.lastHttpStatus = 0
    root.isSending = true
    _setStatus("idle", "")

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
    }

    function finishOk() {
      root.isSending = false
      root.lastHttpStatus = xhr.status || 0
      root.lastErrorText = ""
      _setStatus("ok", "")

      if (!assistantText)
        _setMessageContent(assistantIndex, "(empty response)")
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

        NText {
          text: "Claw"
          pointSize: Style.fontSizeL
          font.weight: Font.Bold
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        Rectangle {
          width: 10 * Style.uiScaleRatio
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

      // Settings (collapsible)
      Rectangle {
        Layout.fillWidth: true
        color: Color.mSurfaceVariant
        radius: Style.radiusL
        visible: root.showSettings

        ColumnLayout {
          anchors.fill: parent
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
        color: Color.mSurfaceVariant
        radius: Style.radiusL

        NScrollView {
          anchors.fill: parent

          ListView {
            id: chatList
            width: parent.width
            height: parent.height
            clip: true
            spacing: Style.marginS
            model: messagesModel

            delegate: Item {
              width: ListView.view.width
              height: bubble.implicitHeight + Style.marginS

              Rectangle {
                id: bubble

                width: Math.min(parent.width * 0.9, Math.max(220 * Style.uiScaleRatio, contentText.implicitWidth + Style.marginM * 2))
                color: (model.role === "user") ? Color.mPrimary : Color.mSurface
                radius: Style.radiusM

                anchors.left: (model.role === "user") ? undefined : parent.left
                anchors.right: (model.role === "user") ? parent.right : undefined
                anchors.leftMargin: Style.marginM
                anchors.rightMargin: Style.marginM
                anchors.top: parent.top
                anchors.topMargin: Style.marginS

                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: Style.marginM
                  spacing: Style.marginXS

                  NText {
                    id: contentText
                    Layout.fillWidth: true
                    text: model.content
                    wrapMode: Text.WordWrap
                    color: (model.role === "user") ? Color.mOnPrimary : Color.mOnSurface
                    pointSize: Style.fontSizeM
                  }
                }
              }
            }
          }
        }
      }

      // Footer composer
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NTextInput {
          id: composerInput
          Layout.fillWidth: true
          placeholderText: "Message OpenClaw..."
          enabled: !root.isSending

          Keys.onReturnPressed: root.sendMessage()
          Keys.onEnterPressed: root.sendMessage()
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

