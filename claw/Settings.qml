import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

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
    text: "Claw"
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
