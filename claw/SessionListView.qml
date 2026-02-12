import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "lib/commands.js" as Commands
import "lib/theme.js" as Theme

Rectangle {
  id: root

  property var sessionsList: []
  property var unreadSessions: ({})

  signal sessionSelected(string sessionKey)

  color: Color.mSurface
  radius: Style.radiusL
  border.width: 1
  border.color: Style.capsuleBorderColor

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
              text: modelData.displayName || Commands.sessionDisplayName(modelData.key || "")
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
            color: (Color.mPrimary !== undefined) ? Color.mPrimary : Theme.primaryFallback
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
            if (key)
              root.sessionSelected(key)
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
