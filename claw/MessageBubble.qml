import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property string role: "assistant" // user | assistant | system
  property string content: ""

  // Layout contract for ListView: consumer sets width.
  implicitHeight: bubble.implicitHeight + Style.marginS

  function bubbleColor() {
    if (root.role === "user") {
      // Prefer container if available, fall back to primary.
      var c = Color.mPrimaryContainer
      if (c === undefined)
        c = Color.mPrimary
      return c
    }

    // assistant/system
    var c2 = Color.mSurface
    if (c2 === undefined)
      c2 = Color.mSurfaceVariant
    return c2
  }

  function textColor() {
    if (root.role === "user") {
      var c = Color.mOnPrimaryContainer
      if (c === undefined)
        c = Color.mOnPrimary
      return c
    }
    return Color.mOnSurface
  }

  Rectangle {
    id: bubble

    width: Math.min(root.width * 0.9, Math.max(240 * Style.uiScaleRatio, contentText.implicitWidth + Style.marginM * 2))
    implicitHeight: contentText.implicitHeight + Style.marginM * 2

    color: root.bubbleColor()
    radius: Style.radiusM
    border.width: 1
    border.color: Color.mOutlineVariant !== undefined ? Color.mOutlineVariant : Color.mOutline

    anchors.left: (root.role === "user") ? undefined : parent.left
    anchors.right: (root.role === "user") ? parent.right : undefined
    anchors.leftMargin: Style.marginM
    anchors.rightMargin: Style.marginM
    anchors.top: parent.top
    anchors.topMargin: Style.marginS

    NText {
      id: contentText
      anchors.fill: parent
      anchors.margins: Style.marginM
      text: root.content
      wrapMode: Text.WordWrap
      color: root.textColor()
      pointSize: Style.fontSizeM
    }
  }
}

