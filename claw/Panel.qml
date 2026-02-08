import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

Item {
  id: root

  // Injected by PluginPanelSlot
  property var pluginApi: null
  // Use a typed Item so property change notifications (ex: hasUnreadChanged)
  // reliably trigger bindings. Accessing through a plain `var` can miss updates.
  readonly property Item main: (pluginApi && pluginApi.mainInstance) ? pluginApi.mainInstance : null

  // SmartPanel properties (required)
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true

  // Preferred dimensions
  property real contentPreferredWidth: 720 * Style.uiScaleRatio
  property real contentPreferredHeight: 640 * Style.uiScaleRatio

  anchors.fill: parent

  // Scroll state
  property bool userScrolledUp: false
  property bool _autoScrolling: false

  function _scrollToEnd() {
    if (chatList.count < 1)
      return
    root._autoScrolling = true
    chatList.positionViewAtIndex(chatList.count - 1, ListView.End)
    Qt.callLater(function() { root._autoScrolling = false })
  }

  // UI state
  property bool showSettings: false
  readonly property bool isSending: main ? !!main.isSending : false
  readonly property string lastErrorText: main ? (main.lastRequestErrorText || "") : ""
  readonly property int lastHttpStatus: main ? (main.lastRequestHttpStatus || 0) : 0
  readonly property bool hasUnread: main ? !!main.hasUnread : false
  readonly property string connectionState: main ? (main.connectionState || "idle") : "idle"

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

  // Command suggestions for the autocomplete dropdown.
  // Gateway commands are sent as regular messages; the gateway processes them server-side.
  // Client-only commands (settings, stream, agent) are handled locally.
  readonly property var commands: ([
    { name: "new", template: "/new", hasArgs: false, usage: "", rank: 10, description: "Reset session / start new chat." },
    { name: "help", template: "/help", hasArgs: false, usage: "", rank: 20, description: "Show available commands." },
    { name: "status", template: "/status", hasArgs: false, usage: "", rank: 30, description: "Show current status and provider usage." },
    { name: "think", template: "/think ", hasArgs: true, usage: "off|minimal|low|medium|high|xhigh", rank: 40, description: "Set reasoning depth." },
    { name: "model", template: "/model ", hasArgs: true, usage: "<name>", rank: 50, description: "Select LLM provider/model." },
    { name: "usage", template: "/usage ", hasArgs: true, usage: "off|tokens|full|cost", rank: 60, description: "Control per-response usage footer." },
    { name: "stop", template: "/stop", hasArgs: false, usage: "", rank: 70, description: "Stop current operation." },
    { name: "compact", template: "/compact", hasArgs: false, usage: "", rank: 80, description: "Compact message history." },
    { name: "verbose", template: "/verbose ", hasArgs: true, usage: "on|full|off", rank: 90, description: "Control verbosity." },
    { name: "settings", template: "/settings", hasArgs: false, usage: "", rank: 200, description: "[Local] Toggle the in-panel settings." },
    { name: "stream", template: "/stream ", hasArgs: true, usage: "on|off", rank: 210, description: "[Local] Enable/disable SSE streaming." },
    { name: "agent", template: "/agent ", hasArgs: true, usage: "<id>", rank: 220, description: "[Local] Set agent id for routing." }
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
    if (main && main.messagesModel)
      return main.messagesModel
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
  Component.onCompleted: {
    reloadFromSettings()
    if (main && main.setPanelActive)
      main.setPanelActive(true)
    Qt.callLater(function() {
      root._scrollToEnd()
      Qt.callLater(function() {
        if (main) {
          main.panelAtBottom = chatList.atYEnd
          if (chatList.atYEnd)
            main.markRead()
        }
      })
    })
  }

  Component.onDestruction: {
    if (main && main.setPanelActive)
      main.setPanelActive(false)
    if (main)
      main.panelAtBottom = false
  }

  function _setStatus(state, text) {
    if (main && main.setStatus)
      main.setStatus(state, text || "")
  }

  function saveSettingsPartial() {
    if (!pluginApi)
      return

    pluginApi.pluginSettings.agentId = root.editAgentId
    pluginApi.pluginSettings.stream = root.editStream
    pluginApi.saveSettings()
  }

  function clearChat() {
    if (main && main.clearChat)
      main.clearChat()
    else
      msgModel().clear()
  }

  function _trimTrailingSlashes(s) {
    return (s || "").replace(/\/+$/, "")
  }

  function _appendMessage(role, content) {
    if (main && main.appendMessage)
      main.appendMessage(role, content)
    else
      msgModel().append({ role: role, content: content, ts: Date.now() })

    if (!root.userScrolledUp)
      _scrollToEnd()
  }

  function _setMessageContent(index, content) {
    var m = msgModel()
    if (main && main.setMessageContent) {
      main.setMessageContent(index, content)
    } else {
      if (index < 0 || index >= m.count)
        return
      m.setProperty(index, "content", content)
    }

    if (!root.userScrolledUp)
      _scrollToEnd()
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

    // No-arg commands match their own prefix forever, so close the menu
    // immediately. Arg commands (template ends with space) will close once
    // rebuildCommandSuggestions sees whitespace.
    if (!row.hasArgs) {
      root.commandMenuOpen = false
      commandSuggestionsModel.clear()
      root.commandSelectedIndex = 0
    } else {
      rebuildCommandSuggestions(composerInput.text)
    }
  }

  function runSlashCommand(text) {
    var t = (text || "").trim()
    if (!t || t[0] !== "/")
      return false

    // Parse: /cmd [args...]
    var parts = t.substring(1).split(/\s+/)
    var cmd = (parts[0] || "").toLowerCase()
    var args = parts.slice(1)

    // --- Client-only commands (never sent to gateway) ---

    if (cmd === "settings") {
      root.showSettings = !root.showSettings
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

    // --- Commands with local side-effects + sent to gateway ---

    if (cmd === "new" || cmd === "clear") {
      clearChat()
      // Fall through to send to gateway so the server resets its session too.
      return false
    }

    // All other /commands are forwarded to the gateway as regular messages.
    return false
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

    // Client-only slash commands (settings, stream, agent) are handled locally.
    // All other /commands fall through and are sent to the gateway.
    if (text[0] === "/") {
      var handled = runSlashCommand(text)
      if (handled) {
        composerInput.text = ""
        rebuildCommandSuggestions("")
        return
      }
    }

    root.userScrolledUp = false
    composerInput.text = ""
    if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.sendUserText) {
      pluginApi.mainInstance.sendUserText(text, {
        gatewayUrl: root.editGatewayUrl,
        token: root.editToken,
        agentId: root.editAgentId,
        user: root.editUser,
        sessionKey: root.editSessionKey,
        stream: root.editStream,
        openAiEndpointEnabledHint: root.openAiEndpointEnabledHint,
        requestTimeoutMs: root.requestTimeoutMs,
        notifyOnResponse: root.editNotifyOnResponse,
        notifyOnlyWhenAppInactive: root.editNotifyOnlyWhenAppInactive
      })
    } else {
      // Fallback: keep history in view if main instance doesn't provide request handling.
      _appendMessage("user", text)
    }
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
                // Single indicator behavior: unread overrides status color.
                if (root.hasUnread)
                  return (Color.mPrimary !== undefined) ? Color.mPrimary : "#2196F3"
                if (root.connectionState === "ok") return "#4CAF50"
                if (root.connectionState === "error") return "#F44336"
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

            onAtYEndChanged: {
              if (main)
                main.panelAtBottom = chatList.atYEnd
              if (chatList.atYEnd) {
                root.userScrolledUp = false
                if (main && main.markRead)
                  main.markRead()
              } else if (!root._autoScrolling && !chatList.moving) {
                root.userScrolledUp = true
              }
            }

            onMovementEnded: {
              if (!chatList.atYEnd)
                root.userScrolledUp = true
            }

            onCountChanged: {
              if (!root.userScrolledUp)
                root._scrollToEnd()
            }

            onContentHeightChanged: {
              if (!root.userScrolledUp)
                root._scrollToEnd()
            }

            delegate: MessageBubble {
              width: ListView.view.width
              role: model.role
              content: model.content
            }
          }
        }

        NIconButton {
          icon: "arrow-down"
          visible: root.userScrolledUp
          z: 100
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottomMargin: Style.marginM
          onClicked: {
            root.userScrolledUp = false
            root._scrollToEnd()
            if (main && main.markRead)
              main.markRead()
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
            // Avoid a 0-height deadlock: ListView.contentHeight can stay 0 until the view has a non-zero height.
            height: visible
              ? Math.min(240 * Style.uiScaleRatio, Math.max(48 * Style.uiScaleRatio, commandList.contentHeight + Style.marginS * 2))
              : 0
            radius: Style.radiusM
            color: Color.mSurface
            border.width: 1
            border.color: Color.mOutlineVariant !== undefined ? Color.mOutlineVariant : Color.mOutline
            clip: true
            z: 1000

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
