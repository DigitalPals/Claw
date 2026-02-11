import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  // Injected by PluginService
  property var pluginApi: null
  // Use a typed Item so property change notifications (ex: hasUnreadChanged)
  // reliably trigger bindings. Accessing through a plain `var` can miss updates.
  readonly property Item main: (pluginApi && pluginApi.mainInstance) ? pluginApi.mainInstance : null
  readonly property bool hasUnread: main ? !!main.hasUnread : false
  readonly property string connectionState: main ? (main.connectionState || "idle") : "idle"

  // Required properties for bar widgets
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""

  // Widget dimensions
  implicitWidth: content.implicitWidth + Style.marginM * 2
  implicitHeight: Style.barHeight

  property bool hovered: false

  color: hovered ? Style.capsuleBorderColor : Style.capsuleColor
  radius: Style.radiusM
  border.width: 1
  border.color: Style.capsuleBorderColor

  // Single indicator:
  // - Theme primary when there's an unread response.
  // - Otherwise green/red/neutral based on connection state.
  readonly property color statusIndicatorColor: {
    if (root.hasUnread)
      return (Color.mPrimary !== undefined) ? Color.mPrimary : "#2196F3"
    if (root.connectionState === "connected")
      return "#4CAF50"
    if (root.connectionState === "connecting")
      return "#FFA726"
    if (root.connectionState === "error")
      return "#F44336"
    return Color.mOutline
  }

  RowLayout {
    id: content
    anchors.centerIn: parent
    spacing: Style.marginS

    Item {
      implicitWidth: iconItem.implicitWidth
      implicitHeight: iconItem.implicitHeight

      NIcon {
        id: iconItem
        icon: "message-chatbot"
        color: Color.mOnSurface
      }

      Rectangle {
        width: 7 * Style.uiScaleRatio
        height: width
        radius: width / 2
        color: root.statusIndicatorColor
        border.width: 1
        border.color: Style.capsuleColor
        anchors.right: iconItem.right
        anchors.top: iconItem.top
        anchors.rightMargin: -2 * Style.uiScaleRatio
        anchors.topMargin: -2 * Style.uiScaleRatio
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onEntered: root.hovered = true
    onExited: root.hovered = false
    onClicked: {
      if (!root.pluginApi)
        return

      if (root.pluginApi.togglePanel)
        root.pluginApi.togglePanel(root.screen, root)
      else if (root.pluginApi.openPanel)
        root.pluginApi.openPanel(root.screen, root)
    }
  }
}
