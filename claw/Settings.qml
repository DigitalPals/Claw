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
  property string editGatewayUrl: "http://127.0.0.1:18789"
  property string editToken: ""
  property string editAgentId: "main"
  property string editUser: "noctalia:claw"
  property string editSessionKey: ""
  property bool editStream: true
  property bool editHint: true
  property int editTimeoutMs: 60000
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
    root.editGatewayUrl = pickSetting("gatewayUrl", "http://127.0.0.1:18789")
    root.editToken = pickSetting("token", "")
    root.editAgentId = pickSetting("agentId", "main")
    root.editUser = pickSetting("user", "noctalia:claw")
    root.editSessionKey = pickSetting("sessionKey", "")
    root.editStream = !!pickSetting("stream", true)
    root.editHint = !!pickSetting("openAiEndpointEnabledHint", true)
    root.editTimeoutMs = pickSetting("requestTimeoutMs", 60000)
    root.editNotifyOnResponse = !!pickSetting("notifyOnResponse", true)
    root.editNotifyOnlyWhenAppInactive = !!pickSetting("notifyOnlyWhenAppInactive", true)
  }

  onPluginApiChanged: reloadFromSettings()
  Component.onCompleted: reloadFromSettings()

  // Required by the settings dialog system.
  function saveSettings() {
    if (!pluginApi)
      return

    pluginApi.pluginSettings.gatewayUrl = root.editGatewayUrl
    pluginApi.pluginSettings.token = root.editToken
    pluginApi.pluginSettings.agentId = root.editAgentId
    pluginApi.pluginSettings.user = root.editUser
    pluginApi.pluginSettings.sessionKey = root.editSessionKey
    pluginApi.pluginSettings.stream = root.editStream
    pluginApi.pluginSettings.openAiEndpointEnabledHint = root.editHint
    pluginApi.pluginSettings.requestTimeoutMs = root.editTimeoutMs
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
    text: "Chat panel for OpenClaw Gateway via the OpenAI-compatible /v1/chat/completions endpoint."
    color: Color.mOnSurfaceVariant
    wrapMode: Text.WordWrap
  }

  NTextInput {
    Layout.fillWidth: true
    label: "Gateway URL"
    description: "Base URL. Default: http://127.0.0.1:18789"
    text: root.editGatewayUrl
    onTextChanged: root.editGatewayUrl = text
  }

  NLabel {
    Layout.fillWidth: true
    label: "Token"
    description: "Authorization: Bearer <token|password>. Avoid exposing the gateway without auth."
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
    description: "Sent as x-openclaw-agent-id (also used as model openclaw:<agentId>)"
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
    description: "Attempt server-sent events streaming; the panel will fall back to non-streaming if needed."
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

  NToggle {
    Layout.fillWidth: true
    label: "Show endpoint-disabled hint"
    description: "Show help text when the gateway returns 404/403 for chat completions."
    checked: root.editHint
    onCheckedChanged: root.editHint = checked
  }

  NTextInput {
    Layout.fillWidth: true
    label: "Request timeout (ms)"
    description: "Abort and show an error after this duration."
    placeholderText: "60000"
    text: String(root.editTimeoutMs)
    onTextChanged: {
      var n = parseInt(text, 10)
      if (!isNaN(n))
        root.editTimeoutMs = n
    }
  }
}
