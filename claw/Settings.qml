import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets
import "lib/settings.js" as SettingsLib

ColumnLayout {
  id: root

  // Injected by the settings dialog system.
  property var pluginApi: null

  spacing: Style.marginM

  // Local editable state.
  property string editWsUrl: "ws://127.0.0.1:18789"
  property string editToken: ""
  property string editAgentId: "main"
  property bool editAutoReconnect: true
  property bool editNotifyOnResponse: true
  property bool editNotifyOnlyWhenAppInactive: true

  function pickSetting(key, fallback) {
    return SettingsLib.pickSetting(pluginApi, key, fallback)
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
  Component.onCompleted: reloadFromSettings()

  // Required by the settings dialog system.
  function saveSettings() {
    if (!pluginApi)
      return

    pluginApi.pluginSettings.wsUrl = root.editWsUrl
    pluginApi.pluginSettings.token = root.editToken
    pluginApi.pluginSettings.agentId = root.editAgentId
    pluginApi.pluginSettings.autoReconnect = root.editAutoReconnect
    pluginApi.pluginSettings.notifyOnResponse = root.editNotifyOnResponse
    pluginApi.pluginSettings.notifyOnlyWhenAppInactive = root.editNotifyOnlyWhenAppInactive

    pluginApi.saveSettings()
    Logger.i("Claw", "Settings saved")
  }

  NText {
    text: "OpenClaw Chat"
    pointSize: Style.fontSizeXL
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NText {
    Layout.fillWidth: true
    text: "Unified inbox for OpenClaw Gateway channels via WebSocket."
    color: Color.mOnSurfaceVariant
    wrapMode: Text.WordWrap
  }

  NTextInput {
    Layout.fillWidth: true
    label: "WebSocket URL"
    description: "Gateway WebSocket endpoint. Default: ws://127.0.0.1:18789"
    text: root.editWsUrl
    onTextChanged: root.editWsUrl = text
  }

  NLabel {
    Layout.fillWidth: true
    label: "Token"
    description: "Sent during WebSocket handshake. Avoid exposing the gateway without auth."
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
}
