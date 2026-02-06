import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  // Injected by PluginService
  property var pluginApi: null

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

  function statusColor() {
    var state = "idle"
    if (pluginApi && pluginApi.mainInstance && pluginApi.mainInstance.connectionState)
      state = pluginApi.mainInstance.connectionState
    if (state === "ok")
      return "#4CAF50"
    if (state === "error")
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
        // Tabler icon name; "crab" is lobster-ish.
        icon: "crab"
        color: Color.mOnSurface
      }

      Rectangle {
        width: 7 * Style.uiScaleRatio
        height: width
        radius: width / 2
        color: root.statusColor()
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
