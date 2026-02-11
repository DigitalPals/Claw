import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
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
  readonly property string lastErrorText: main ? (main.lastErrorText || "") : ""
  readonly property bool hasUnread: main ? !!main.hasUnread : false
  readonly property string connectionState: main ? (main.connectionState || "idle") : "idle"
  readonly property var unreadSessions: main ? (main.unreadSessions || ({})) : ({})

  // Navigation bindings from Main
  readonly property string viewMode: main ? (main.viewMode || "channels") : "channels"
  readonly property var channelMeta: main ? (main.channelMeta || []) : []
  readonly property var sessionsList: main ? (main.sessionsList || []) : []
  readonly property string activeSessionKey: main ? (main.activeSessionKey || "") : ""
  onActiveSessionKeyChanged: clearPendingImage()
  readonly property string selectedChannelId: main ? (main.selectedChannelId || "") : ""

  // Local editable settings (used at runtime; Save persists).
  property string editWsUrl: "ws://127.0.0.1:18789"
  property string editToken: ""
  property string editAgentId: "main"
  property bool editAutoReconnect: true
  property bool editNotifyOnResponse: true
  property bool editNotifyOnlyWhenAppInactive: true

  // Clipboard image capture state
  property string pendingImageBase64: ""
  property string pendingImageMediaType: ""
  property bool isCapturingClipboard: false
  property string _clipboardTypes: ""

  // Slash command menu state
  property bool commandMenuOpen: false
  property int commandSelectedIndex: 0

  // Command suggestions for the autocomplete dropdown.
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
    { name: "channels", template: "/channels", hasArgs: false, usage: "", rank: 210, description: "[Local] Navigate to channels view." },
    { name: "abort", template: "/abort", hasArgs: false, usage: "", rank: 220, description: "[Local] Abort active response." },
    { name: "agent", template: "/agent ", hasArgs: true, usage: "<id>", rank: 230, description: "[Local] Set agent id for routing." }
  ])

  // Local components
  // (File in this plugin folder)
  // qmllint: disable=unqualified
  // MessageBubble.qml is resolved relative to this file.

  // If the plugin main instance exposes a messagesModel, use it so chat persists
  // across panel close/reopen. Fall back to a local model if not available.
  ListModel { id: fallbackMessagesModel }
  ListModel { id: commandSuggestionsModel }

  // Clipboard type detection process
  Process {
    id: clipboardTypeProcess
    command: ["wl-paste", "--list-types"]
    stdout: SplitParser {
      onRead: data => {
        root._clipboardTypes += data + "\n"
      }
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) {
        clipboardTimeoutTimer.stop()
        root.isCapturingClipboard = false
        return
      }
      var types = root._clipboardTypes.trim().split("\n")
      var imageType = ""
      for (var i = 0; i < types.length; i++) {
        var t = types[i].trim()
        if (t === "image/png" || t === "image/jpeg" || t === "image/gif" || t === "image/webp") {
          imageType = t
          break
        }
      }
      if (imageType) {
        if (clipboardImageProcess.running) {
          clipboardTimeoutTimer.stop()
          root.isCapturingClipboard = false
          return
        }
        root.pendingImageMediaType = imageType
        root.pendingImageBase64 = ""
        clipboardImageProcess.command = ["bash", "-c", "wl-paste --type '" + imageType + "' | base64 -w0"]
        clipboardImageProcess.running = true
      } else {
        clipboardTimeoutTimer.stop()
        root.isCapturingClipboard = false
      }
    }
  }

  // Clipboard image capture process (base64)
  Process {
    id: clipboardImageProcess
    stdout: SplitParser {
      onRead: data => {
        root.pendingImageBase64 += data
        // Abort if base64 data exceeds ~10 MB (decoded)
        if (root.pendingImageBase64.length > 14000000) {
          console.warn("[Claw] Clipboard image too large, aborting capture")
          clipboardImageProcess.running = false
          root.pendingImageBase64 = ""
          root.pendingImageMediaType = ""
        }
      }
    }
    onExited: (exitCode, exitStatus) => {
      clipboardTimeoutTimer.stop()
      root.isCapturingClipboard = false
      if (exitCode !== 0) {
        root.pendingImageBase64 = ""
        root.pendingImageMediaType = ""
      }
    }
  }

  // Clipboard capture timeout (10s) — kills hung wl-paste processes
  Timer {
    id: clipboardTimeoutTimer
    interval: 10000
    repeat: false
    onTriggered: {
      console.warn("[Claw] Clipboard capture timed out")
      clipboardTypeProcess.running = false
      clipboardImageProcess.running = false
      root.isCapturingClipboard = false
      root.pendingImageBase64 = ""
      root.pendingImageMediaType = ""
    }
  }

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
    root.editWsUrl = pickSetting("wsUrl", "ws://127.0.0.1:18789")
    root.editToken = pickSetting("token", "")
    root.editAgentId = pickSetting("agentId", "main")
    root.editAutoReconnect = !!pickSetting("autoReconnect", true)
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
    pluginApi.saveSettings()
  }

  function clearChat() {
    if (main && main.clearChat)
      main.clearChat()
    else
      msgModel().clear()
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

  function tryPasteImage() {
    if (root.isCapturingClipboard)
      return
    root.isCapturingClipboard = true
    root._clipboardTypes = ""
    clipboardTimeoutTimer.start()
    clipboardTypeProcess.running = true
  }

  function clearPendingImage() {
    root.pendingImageBase64 = ""
    root.pendingImageMediaType = ""
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

    if (!row.hasArgs) {
      root.commandMenuOpen = false
      commandSuggestionsModel.clear()
      root.commandSelectedIndex = 0
    } else {
      rebuildCommandSuggestions(composerInput.text)
    }
  }

  function _channelLabel(channelId) {
    var meta = root.channelMeta
    for (var i = 0; i < meta.length; i++) {
      if (meta[i].id === channelId)
        return meta[i].label || channelId
    }
    return channelId
  }

  function _channelHasUnread(channelId) {
    var sessions = root.unreadSessions
    for (var k in sessions) {
      if (main && main._channelFromSessionKey(k) === channelId)
        return true
    }
    return false
  }

  function _sessionDisplayName(sessionKey) {
    // Session keys: "agent:<agentId>:<channel>[:<peer>...]"
    // Examples: "agent:main:slack:channel:c0ae9n9jkkp", "agent:main:main"
    var parts = (sessionKey || "").split(":")
    if (parts.length >= 4 && parts[0] === "agent") {
      // Has peer info after channel type — show it
      return parts.slice(3).join(":")
    }
    if (parts.length === 3 && parts[0] === "agent") {
      // e.g. "agent:main:main" — channel is the session itself
      return parts[2]
    }
    if (parts.length >= 3)
      return parts.slice(2).join(":")
    if (parts.length >= 2)
      return parts[1]
    return sessionKey
  }

  function _breadcrumbText() {
    if (root.viewMode === "sessions")
      return "Claw \u203A " + _channelLabel(root.selectedChannelId)
    if (root.viewMode === "chat")
      return "Claw \u203A " + _channelLabel(root.selectedChannelId) + " \u203A " + _sessionDisplayName(root.activeSessionKey)
    return "Claw"
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

    if (cmd === "channels") {
      if (main && main.viewMode !== "channels") {
        // Navigate all the way back to channels
        main.viewMode = "channels"
        main.selectedChannelId = ""
        main.activeSessionKey = ""
        main.sessionsList = []
        main.clearMessages()
      }
      return true
    }

    if (cmd === "abort") {
      if (main && root.activeSessionKey)
        main.abortChat(root.activeSessionKey)
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
      return false
    }

    // All other /commands are forwarded to the gateway as regular messages.
    return false
  }

  function handleComposerKey(event) {
    // Ctrl+V: try to capture image from clipboard (in addition to normal text paste)
    if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
      tryPasteImage()
      // Don't accept event — let normal text paste proceed too
      return
    }

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
    var hasImage = root.pendingImageBase64.length > 0

    if (!text && !hasImage)
      return

    // Client-only slash commands (settings, channels, abort, agent) are handled locally.
    // All other /commands fall through and are sent to the gateway.
    if (text && text[0] === "/") {
      var handled = runSlashCommand(text)
      if (handled) {
        composerInput.text = ""
        rebuildCommandSuggestions("")
        return
      }
    }

    if (root.connectionState !== "connected") {
      root.appendSystemMessage("Not connected. Message not sent.")
      return
    }

    root.userScrolledUp = false
    composerInput.text = ""

    if (main && root.activeSessionKey) {
      if (hasImage) {
        var attachments = [{
          type: "image",
          mimeType: root.pendingImageMediaType,
          content: root.pendingImageBase64
        }]
        // Build content blocks for local display in message bubbles
        var displayBlocks = [{
          type: "image",
          source: {
            type: "base64",
            media_type: root.pendingImageMediaType,
            data: root.pendingImageBase64
          }
        }]
        if (text)
          displayBlocks.push({ type: "text", text: text })
        main.sendChatWithAttachments(root.activeSessionKey, text, attachments, JSON.stringify(displayBlocks))
        clearPendingImage()
      } else {
        main.sendChat(root.activeSessionKey, text)
      }
    } else {
      // Fallback: keep history in view if no active session
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

            NIconButton {
              icon: "arrow-left"
              visible: root.viewMode !== "channels"
              onClicked: {
                root.clearPendingImage()
                if (main && main.navigateBack)
                  main.navigateBack()
              }
            }

            NText {
              text: root._breadcrumbText()
              pointSize: Style.fontSizeL
              font.weight: Font.Bold
              color: Color.mOnSurface
              Layout.fillWidth: true
              elide: Text.ElideRight
            }

            Rectangle {
              width: 9 * Style.uiScaleRatio
              height: width
              radius: width / 2
              color: {
                if (root.hasUnread)
                  return (Color.mPrimary !== undefined) ? Color.mPrimary : "#2196F3"
                if (root.connectionState === "connected") return "#4CAF50"
                if (root.connectionState === "connecting") return "#FFA726"
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
            label: "WebSocket URL"
            description: "Example: ws://127.0.0.1:18789"
            text: root.editWsUrl
            onTextChanged: root.editWsUrl = text
          }

          NLabel {
            Layout.fillWidth: true
            label: "Token"
            description: "Sent during WebSocket handshake. Do not expose the gateway unauthenticated."
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
            description: "Agent used for routing chat messages."
            text: root.editAgentId
            onTextChanged: root.editAgentId = text
          }

          NToggle {
            Layout.fillWidth: true
            label: "Auto-reconnect"
            description: "Automatically reconnect with exponential backoff on disconnect."
            checked: root.editAutoReconnect
            onCheckedChanged: root.editAutoReconnect = checked
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

                root.pluginApi.pluginSettings.wsUrl = root.editWsUrl
                root.pluginApi.pluginSettings.token = root.editToken
                root.pluginApi.pluginSettings.agentId = root.editAgentId
                root.pluginApi.pluginSettings.autoReconnect = root.editAutoReconnect
                root.pluginApi.pluginSettings.notifyOnResponse = root.editNotifyOnResponse
                root.pluginApi.pluginSettings.notifyOnlyWhenAppInactive = root.editNotifyOnlyWhenAppInactive
                root.pluginApi.saveSettings()

                // Trigger reconnect with new settings
                if (root.isSending)
                  console.warn("[Claw] Reconnecting while send is active; in-flight request will error")
                if (main && main.reconnect)
                  main.reconnect()
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
            text: "Note: token is empty. If your gateway requires auth, the connection will fail."
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
        }
      }

      // Channel list view
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurface
        radius: Style.radiusL
        border.width: 1
        border.color: Style.capsuleBorderColor
        visible: root.viewMode === "channels"

        NScrollView {
          anchors.fill: parent

          ListView {
            id: channelList
            width: parent.width
            height: parent.height
            clip: true
            spacing: 1
            model: root.channelMeta

            delegate: Rectangle {
              width: ListView.view.width
              implicitHeight: channelRow.implicitHeight + Style.marginM * 2
              color: channelMouseArea.containsMouse
                ? (Color.mSecondaryContainer !== undefined ? Color.mSecondaryContainer : Color.mSurfaceVariant)
                : "transparent"

              RowLayout {
                id: channelRow
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginM

                NIcon {
                  icon: modelData.systemImage || "message-circle"
                  color: Color.mOnSurface
                  pointSize: Style.fontSizeXL
                  Layout.preferredWidth: Math.ceil(Style.fontSizeXL * Style.uiScaleRatio * 2)
                  Layout.alignment: Qt.AlignVCenter
                  horizontalAlignment: Text.AlignHCenter
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  spacing: 2

                  NText {
                    Layout.fillWidth: true
                    text: modelData.label || modelData.id || "Channel"
                    color: Color.mOnSurface
                    font.weight: root._channelHasUnread(modelData.id) ? Font.ExtraBold : Font.DemiBold
                    pointSize: Style.fontSizeM
                  }

                  NText {
                    Layout.fillWidth: true
                    text: modelData.detailLabel || ""
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                    visible: !!(modelData.detailLabel)
                  }
                }

                // Unread indicator dot
                Rectangle {
                  width: 8 * Style.uiScaleRatio
                  height: width
                  radius: width / 2
                  color: (Color.mPrimary !== undefined) ? Color.mPrimary : "#2196F3"
                  visible: root._channelHasUnread(modelData.id)
                  Layout.alignment: Qt.AlignVCenter
                }

                NIcon {
                  icon: "chevron-right"
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignVCenter
                }
              }

              MouseArea {
                id: channelMouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  if (main && main.selectChannel)
                    main.selectChannel(modelData.id)
                }
              }
            }
          }
        }

        // Empty state
        NText {
          anchors.centerIn: parent
          visible: root.channelMeta.length === 0
          text: root.connectionState === "connected" ? "No channels available" : "Connecting..."
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeM
        }
      }

      // Session list view
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurface
        radius: Style.radiusL
        border.width: 1
        border.color: Style.capsuleBorderColor
        visible: root.viewMode === "sessions"

        NScrollView {
          anchors.fill: parent

          ListView {
            id: sessionList
            width: parent.width
            height: parent.height
            clip: true
            spacing: 1
            model: root.sessionsList

            delegate: Rectangle {
              width: ListView.view.width
              implicitHeight: sessionRow.implicitHeight + Style.marginM * 2
              color: sessionMouseArea.containsMouse
                ? (Color.mSecondaryContainer !== undefined ? Color.mSecondaryContainer : Color.mSurfaceVariant)
                : "transparent"

              RowLayout {
                id: sessionRow
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginM

                ColumnLayout {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  spacing: 2

                  NText {
                    Layout.fillWidth: true
                    text: modelData.displayName || root._sessionDisplayName(modelData.key || "")
                    color: Color.mOnSurface
                    font.weight: root.unreadSessions[modelData.key] ? Font.ExtraBold : Font.DemiBold
                    pointSize: Style.fontSizeM
                  }

                  NText {
                    Layout.fillWidth: true
                    text: modelData.key || ""
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                  }
                }

                // Unread indicator dot
                Rectangle {
                  width: 8 * Style.uiScaleRatio
                  height: width
                  radius: width / 2
                  color: (Color.mPrimary !== undefined) ? Color.mPrimary : "#2196F3"
                  visible: !!root.unreadSessions[modelData.key]
                  Layout.alignment: Qt.AlignVCenter
                }

                NIcon {
                  icon: "chevron-right"
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignVCenter
                }
              }

              MouseArea {
                id: sessionMouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  var key = modelData.key || ""
                  if (main && main.selectSession && key)
                    main.selectSession(key)
                }
              }
            }
          }
        }

        // Empty state
        NText {
          anchors.centerIn: parent
          visible: root.sessionsList.length === 0
          text: "No sessions"
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeM
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
        visible: root.viewMode === "chat"

        NScrollView {
          anchors.fill: parent
          showGradientMasks: false

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
              streaming: model.streaming || false
              contentBlocks: model.contentBlocks || ""
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

      // Image preview strip (visible when an image is pending)
      Rectangle {
        Layout.fillWidth: true
        visible: root.viewMode === "chat" && root.pendingImageBase64.length > 0
        color: Color.mSurfaceVariant
        radius: Style.radiusM
        implicitHeight: imagePreviewRow.implicitHeight + Style.marginS * 2

        RowLayout {
          id: imagePreviewRow
          anchors.fill: parent
          anchors.margins: Style.marginS
          spacing: Style.marginM

          Image {
            Layout.preferredWidth: 80 * Style.uiScaleRatio
            Layout.preferredHeight: 80 * Style.uiScaleRatio
            source: root.pendingImageBase64
              ? ("data:" + root.pendingImageMediaType + ";base64," + root.pendingImageBase64)
              : ""
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 160
            sourceSize.height: 160
          }

          NText {
            text: {
              var sizeBytes = Math.ceil(root.pendingImageBase64.length * 3 / 4)
              if (sizeBytes < 1024) return sizeBytes + " B"
              if (sizeBytes < 1048576) return Math.round(sizeBytes / 1024) + " KB"
              return (sizeBytes / 1048576).toFixed(1) + " MB"
            }
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeS
          }

          Item { Layout.fillWidth: true }

          NIconButton {
            icon: "x"
            onClicked: root.clearPendingImage()
          }
        }
      }

      // Footer composer
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        visible: root.viewMode === "chat"

        Item {
          id: composerArea
          Layout.fillWidth: true
          implicitHeight: composerInput.implicitHeight

          NTextInput {
            id: composerInput
            anchors.fill: parent
            placeholderText: "Message..."
            enabled: !root.isSending

            onTextChanged: rebuildCommandSuggestions(text)
            Keys.onPressed: handleComposerKey(event)
          }

          // Slash command dropdown
          Rectangle {
            id: commandMenu
            visible: root.commandMenuOpen && commandSuggestionsModel.count > 0
            width: composerArea.width
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
