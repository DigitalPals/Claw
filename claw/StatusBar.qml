import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "lib/protocol.js" as Protocol
import "lib/theme.js" as Theme

Rectangle {
  id: root

  // Bound from Panel.qml
  property string connectionState: "idle"
  property string activityState: "disconnected"
  property string agentId: ""
  property string sessionName: ""
  property string activeModel: ""
  property string activeThinkLevel: ""
  property int tokenUsed: 0
  property int tokenLimit: 0

  color: Color.mSurfaceVariant
  radius: Style.radiusM

  implicitHeight: col.implicitHeight + Style.marginS * 2

  ColumnLayout {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.marginS
    spacing: 2

    // Line 1: status dot + connection/activity state | model (right-aligned)
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      Rectangle {
        width: 7 * Style.uiScaleRatio
        height: width
        radius: width / 2
        color: {
          if (root.activityState === "streaming") return Theme.statusStreaming
          if (root.activityState === "thinking") return Theme.statusConnecting
          if (root.activityState === "idle") return Theme.statusConnected
          if (root.connectionState === "connecting") return Theme.statusConnecting
          if (root.connectionState === "error") return Theme.statusError
          return Color.mOutline
        }

        SequentialAnimation on opacity {
          running: root.activityState === "streaming" || root.activityState === "thinking" || root.connectionState === "connecting"
          loops: Animation.Infinite
          NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
        }
      }

      NText {
        text: {
          var parts = []
          if (root.connectionState === "connecting") parts.push("connecting")
          else if (root.connectionState === "error") parts.push("error")
          else if (root.connectionState === "connected") parts.push("connected")
          else parts.push(root.connectionState)

          if (root.connectionState === "connected" && root.activityState !== "idle")
            parts.push(root.activityState)

          return parts.join(" | ")
        }
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
      }

      Item { Layout.fillWidth: true }

      NText {
        text: root.activeModel
        visible: !!root.activeModel
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
        font.italic: true
        elide: Text.ElideLeft
      }
    }

    // Line 2: think level + token usage (hidden if no data)
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS
      visible: !!root.activeThinkLevel || root.tokenUsed > 0

      NText {
        text: root.activeThinkLevel ? ("think: " + root.activeThinkLevel) : ""
        visible: !!root.activeThinkLevel
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
      }

      NText {
        text: Protocol.formatTokenUsage(root.tokenUsed, root.tokenLimit)
        visible: root.tokenUsed > 0
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
      }
    }
  }
}
