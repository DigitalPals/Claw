import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
  id: root

  property string role: "assistant" // user | assistant | system
  property string content: ""

  // Layout contract for ListView: consumer sets width.
  implicitHeight: bubble.implicitHeight + Style.marginS

  function _escapeHtml(s) {
    var out = (s === null || s === undefined) ? "" : String(s)
    out = out.replace(/&/g, "&amp;")
    out = out.replace(/</g, "&lt;")
    out = out.replace(/>/g, "&gt;")
    out = out.replace(/\"/g, "&quot;")
    out = out.replace(/'/g, "&#39;")
    return out
  }

  // Wrap bare URLs with <...> so Qt markdown conversion will generate clickable links.
  // Avoids changing anything inside fenced code blocks or inline code spans.
  function _autoLinkBareUrlsInMarkdown(md) {
    var s = (md === null || md === undefined) ? "" : String(md)
    var out = ""
    var i = 0
    var inFence = false
    var inInline = false

    while (i < s.length) {
      // Fenced code blocks (```).
      if (!inInline && s.substring(i, i + 3) === "```") {
        inFence = !inFence
        out += "```"
        i += 3
        continue
      }

      // Inline code spans (`...`) only when not in a fence.
      if (!inFence && s[i] === "`") {
        inInline = !inInline
        out += "`"
        i += 1
        continue
      }

      // Outside code: autolink bare URLs.
      if (!inFence && !inInline
          && (s.substring(i, i + 7) === "http://" || s.substring(i, i + 8) === "https://")) {
        var j = i
        while (j < s.length && !/\s/.test(s[j]))
          j++

        var url = s.substring(i, j)
        var trailing = ""
        // Trim common trailing punctuation that is unlikely to be part of the URL.
        while (url.length > 0 && /[\\)\\]\\}\\.,;:!?]/.test(url[url.length - 1])) {
          trailing = url[url.length - 1] + trailing
          url = url.substring(0, url.length - 1)
        }

        out += "<" + url + ">" + trailing
        i = j
        continue
      }

      out += s[i]
      i += 1
    }

    return out
  }

  function _basicMarkdownToHtml(md) {
    // Minimal fallback if Qt.convertFromMarkdown isn't available.
    // Goal: keep it safe (escaped) and useful (links + basic emphasis).
    var s = (md === null || md === undefined) ? "" : String(md)
    s = _escapeHtml(s)

    // Newlines.
    s = s.replace(/\\r\\n/g, "\\n").replace(/\\r/g, "\\n")
    s = s.replace(/\\n/g, "<br/>")
    return s
  }

  function renderRichText(raw) {
    var md = (raw === null || raw === undefined) ? "" : String(raw)
    var fg = root.textColor()

    try {
      if (Qt && typeof Qt.convertFromMarkdown === "function") {
        // Improve UX: clickable bare URLs + proper markdown rendering (e.g. **...**).
        var md2 = _autoLinkBareUrlsInMarkdown(md)
        var html = Qt.convertFromMarkdown(md2)
        // Wrap to force a reasonable default foreground color in dark themes.
        // (Relying on TextArea.color does not consistently apply to rich text across builds.)
        return '<span style="color: ' + fg + ';">' + String(html) + "</span>"
      }
    } catch (e) {}

    // Fallback: plain escaped text with line breaks. Links are still available via chips below.
    return '<span style="color: ' + fg + ';">' + _basicMarkdownToHtml(md) + "</span>"
  }

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

  function extractUrls(raw) {
    var s = (raw === null || raw === undefined) ? "" : String(raw)
    var re = new RegExp("(https?:\\/\\/[^\\s<]+)", "g")
    var out = []
    var seen = {}
    var m

    while ((m = re.exec(s)) !== null) {
      var url = m[1]
      // Trim common trailing punctuation.
      while (url.length > 0 && /[\\)\\]\\}\\.,;:!?\\*]/.test(url[url.length - 1]))
        url = url.substring(0, url.length - 1)
      if (url.length === 0)
        continue
      if (seen[url])
        continue
      seen[url] = true
      out.push(url)
    }

    return out
  }

  function openUrl(url) {
    var u = (url === null || url === undefined) ? "" : String(url)
    u = u.trim()
    if (!u)
      return

    // Prefer the same mechanism used by Noctalia itself.
    try {
      Quickshell.execDetached(["xdg-open", u])
      return
    } catch (e) {}

    // Fallback (may be a no-op depending on environment).
    try {
      Qt.openUrlExternally(u)
      return
    } catch (e2) {}

    try {
      if (ToastService && ToastService.showNotice)
        ToastService.showNotice("Claw", "Failed to open link: " + u, "alert-triangle")
    } catch (e3) {}
  }

  Rectangle {
    id: bubble

    width: Math.min(root.width * 0.9, 820 * Style.uiScaleRatio)
    implicitHeight: contentColumn.implicitHeight + Style.marginM * 2
    clip: true

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

    Column {
      id: contentColumn
      x: Style.marginM
      y: Style.marginM
      width: parent.width - Style.marginM * 2
      spacing: Style.marginS

      // Use a Controls text editor for selection/copy. Plain Text doesn't support interaction
      // flags in Noctalia's Qt build.
      TextArea {
        id: contentText

        width: parent.width
        height: implicitHeight

        textFormat: TextEdit.RichText
        text: root.renderRichText(root.content)
        wrapMode: TextEdit.WordWrap
        readOnly: true
        selectByMouse: true
        activeFocusOnPress: false
        focusPolicy: Qt.NoFocus

        padding: 0
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0

        background: null
        color: root.textColor()
        font.pointSize: Math.max(1, Style.fontSizeM * Style.uiScaleRatio)

        implicitHeight: Math.max(Style.fontSizeM * 1.6, contentHeight)
        implicitWidth: 0

        // Handle link clicks ourselves. Text interaction flags are not available in this environment.
        // We only accept the event when the pointer is on a link; otherwise we let TextArea handle
        // selection/copy.
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          hoverEnabled: true
          propagateComposedEvents: true
          preventStealing: true

          function _linkAt(mouse) {
            try {
              if (contentText && typeof contentText.linkAt === "function")
                return contentText.linkAt(mouse.x, mouse.y)
            } catch (e) {}
            return ""
          }

          onPositionChanged: mouse => {
            var link = _linkAt(mouse)
            cursorShape = link ? Qt.PointingHandCursor : Qt.IBeamCursor
            mouse.accepted = false
          }

          onPressed: mouse => {
            var link = _linkAt(mouse)
            if (link) {
              mouse.accepted = true
              root.openUrl(link)
              return
            }
            mouse.accepted = false
          }
        }
      }

      Flow {
        id: linkRow
        width: parent.width
        spacing: Style.marginS
        visible: urlRepeater.count > 0

        Repeater {
          id: urlRepeater
          model: root.extractUrls(root.content)

          delegate: Rectangle {
            radius: Style.radiusS
            color: Qt.alpha(Color.mOnSurface, 0.06)
            border.width: 1
            border.color: Qt.alpha(Color.mOnSurface, 0.12)

            implicitHeight: linkText.implicitHeight + Style.marginS * 2
            implicitWidth: Math.min(linkText.implicitWidth + Style.marginS * 2, bubble.width - Style.marginM * 2)

            NText {
              id: linkText
              anchors.centerIn: parent
              text: modelData
              pointSize: Style.fontSizeS
              wrapMode: Text.NoWrap
              elide: Text.ElideRight
              color: Color.mPrimary !== undefined ? Color.mPrimary : root.textColor()
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton
              onClicked: function() {
                root.openUrl(modelData)
              }
            }
          }
        }
      }
    }
  }
}
