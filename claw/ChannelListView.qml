import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "lib/commands.js" as Commands
import "lib/protocol.js" as Protocol
import "lib/theme.js" as Theme

Rectangle {
  id: root

  property var channelMeta: []
  property var unreadSessions: ({})
  property string connectionState: "idle"

  signal channelSelected(string channelId)

  color: Color.mSurface
  radius: Style.radiusL
  border.width: 1
  border.color: Style.capsuleBorderColor

  function _channelHasUnread(channelId) {
    return Commands.channelHasUnread(channelId, root.unreadSessions, Protocol.channelFromSessionKey)
  }

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
            color: (Color.mPrimary !== undefined) ? Color.mPrimary : Theme.primaryFallback
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
          onClicked: root.channelSelected(modelData.id)
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
