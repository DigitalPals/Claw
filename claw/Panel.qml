import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets
import "lib/commands.js" as Commands
import "lib/settings.js" as SettingsLib
import "lib/theme.js" as Theme

Item {
  id: root

  // Injected by PluginPanelSlot
  property var pluginApi: null
  property bool isInsidePopout: false
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
  readonly property bool isStreaming: main ? !!main.isStreaming : false
  readonly property string lastErrorText: main ? (main.lastErrorText || "") : ""
  readonly property bool hasUnread: main ? !!main.hasUnread : false
  readonly property string connectionState: main ? (main.connectionState || "idle") : "idle"
  readonly property var unreadSessions: main ? (main.unreadSessions || ({})) : ({})

  // Navigation bindings from Main
  readonly property string viewMode: main ? (main.viewMode || "channels") : "channels"
  readonly property var channelMeta: main ? (main.channelMeta || []) : []
  readonly property var sessionsList: main ? (main.sessionsList || []) : []
  readonly property string activeSessionKey: main ? (main.activeSessionKey || "") : ""
  onActiveSessionKeyChanged: {
    if (chatComposer)
      chatComposer.clearPendingImage()
  }
  readonly property string selectedChannelId: main ? (main.selectedChannelId || "") : ""

  // Local editable settings (used at runtime; Save persists).
  property string editWsUrl: "ws://127.0.0.1:18789"
  property string editToken: ""
  property string editAgentId: "main"
  property bool editAutoReconnect: true
  property bool editNotifyOnResponse: true
  property bool editNotifyOnlyWhenAppInactive: true

  // If the plugin main instance exposes a messagesModel, use it so chat persists
  // across panel close/reopen. Fall back to a local model if not available.
  ListModel { id: fallbackMessagesModel }

  function msgModel() {
    if (main && main.messagesModel)
      return main.messagesModel
    return fallbackMessagesModel
  }

  function appendSystemMessage(text) {
    _appendMessage("system", text)
  }

  function reloadFromSettings() {
    var s = SettingsLib.loadEditableSettings(pluginApi)
    root.editWsUrl = s.wsUrl
    root.editToken = s.token
    root.editAgentId = s.agentId
    root.editAutoReconnect = s.autoReconnect
    root.editNotifyOnResponse = s.notifyOnResponse
    root.editNotifyOnlyWhenAppInactive = s.notifyOnlyWhenAppInactive
  }

  onPluginApiChanged: reloadFromSettings()
  Component.onCompleted: {
    reloadFromSettings()
    if (!root.isInsidePopout && main && main.setPanelActive)
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
    if (!root.isInsidePopout) {
      if (main && main.setPanelActive)
        main.setPanelActive(false)
      if (main)
        main.panelAtBottom = false
    }
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

  function _breadcrumbText() { return Commands.breadcrumbText(root.viewMode, root.selectedChannelId, root.activeSessionKey, root.channelMeta) }

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
      if (main && main.viewMode !== "channels")
        main.navigateToChannels()
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

  function performSend(text) {
    if (root.isSending)
      return

    var hasImage = chatComposer.hasImage

    if (!text && !hasImage)
      return

    // Client-only slash commands (settings, channels, abort, agent) are handled locally.
    // All other /commands fall through and are sent to the gateway.
    if (text && text[0] === "/") {
      var handled = runSlashCommand(text)
      if (handled) {
        chatComposer.clearComposer()
        return
      }
    }

    if (root.connectionState !== "connected") {
      root.appendSystemMessage("Not connected. Message not sent.")
      return
    }

    root.userScrolledUp = false
    chatComposer.clearComposer()

    if (main && root.activeSessionKey) {
      var attachments = []
      var contentBlocksJson = ""
      if (hasImage) {
        attachments = [{
          type: "image",
          mimeType: chatComposer.pendingImageMediaType,
          content: chatComposer.pendingImageBase64
        }]
        var displayBlocks = [{
          type: "image",
          source: {
            type: "base64",
            media_type: chatComposer.pendingImageMediaType,
            data: chatComposer.pendingImageBase64
          }
        }]
        if (text)
          displayBlocks.push({ type: "text", text: text })
        contentBlocksJson = JSON.stringify(displayBlocks)
        chatComposer.clearPendingImage()
      }
      main.sendChat(root.activeSessionKey, text, attachments, contentBlocksJson)
    } else {
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
                chatComposer.clearPendingImage()
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
              color: Theme.connectionStatusColor(root.connectionState, root.hasUnread, Color.mPrimary, Color.mOutline)
              border.width: 1
              border.color: Color.mOutline
            }

            NIconButton {
              icon: root.showSettings ? "settings-off" : "settings"
              onClicked: root.showSettings = !root.showSettings
            }

            NIconButton {
              icon: "external-link"
              visible: !root.isInsidePopout
              onClicked: {
                if (main) {
                  main.popoutWindowVisible = true
                  if (root.pluginApi && root.pluginApi.closePanel) {
                    root.pluginApi.withCurrentScreen(function(screen) {
                      root.pluginApi.closePanel(screen)
                    })
                  }
                }
              }
            }

            NIconButton {
              icon: "trash"
              onClicked: root.clearChat()
            }
          }
        }
      }

      // Status bar (only in chat/session view)
      StatusBar {
        Layout.fillWidth: true
        visible: root.viewMode === "chat"
        connectionState: root.connectionState
        activityState: main ? (main.activityState || "disconnected") : "disconnected"
        activeModel: main ? (main.activeModel || "") : ""
        activeThinkLevel: main ? (main.activeThinkLevel || "") : ""
        tokenUsed: main ? (main.tokenUsed || 0) : 0
        tokenLimit: main ? (main.tokenLimit || 0) : 0
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
            color: Theme.statusError
            wrapMode: Text.WordWrap
            pointSize: Style.fontSizeS
          }
        }
      }

      // Channel list view
      ChannelListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.viewMode === "channels"
        channelMeta: root.channelMeta
        unreadSessions: root.unreadSessions
        connectionState: root.connectionState
        onChannelSelected: channelId => {
          if (main && main.selectChannel)
            main.selectChannel(channelId)
        }
      }

      // Session list view
      SessionListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.viewMode === "sessions"
        sessionsList: root.sessionsList
        unreadSessions: root.unreadSessions
        onSessionSelected: sessionKey => {
          if (main && main.selectSession)
            main.selectSession(sessionKey)
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

            footer: Item {
              width: ListView.view.width
              height: thinkingRow.visible ? thinkingRow.implicitHeight + Style.marginM * 2 : 0

              Row {
                id: thinkingRow
                visible: root.isStreaming || root.isSending
                anchors.left: parent.left
                anchors.leftMargin: Style.marginM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.marginS

                NText {
                  text: "Thinking"
                  color: Color.mOnSurfaceVariant
                  pointSize: Style.fontSizeS
                  font.italic: true
                }

                Repeater {
                  model: 3
                  NText {
                    required property int index
                    text: "."
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                    font.italic: true
                    opacity: 0.3

                    SequentialAnimation on opacity {
                      running: thinkingRow.visible
                      loops: Animation.Infinite
                      PauseAnimation { duration: index * 300 }
                      NumberAnimation { to: 1.0; duration: 400; easing.type: Easing.InOutQuad }
                      NumberAnimation { to: 0.3; duration: 400; easing.type: Easing.InOutQuad }
                      PauseAnimation { duration: (2 - index) * 300 }
                    }
                  }
                }
              }
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

      // Composer (image preview + text input + command autocomplete + send button)
      ChatComposer {
        id: chatComposer
        Layout.fillWidth: true
        visible: root.viewMode === "chat"
        isSending: root.isSending
        onSendRequested: text => root.performSend(text)
        onClearPendingImageRequested: {}  // no-op; image state lives in composer
      }
    }
  }
}
