import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import "lib/markdown.js" as Markdown

Item {
  id: root

  property string role: "assistant" // user | assistant | system
  property string content: ""
  property bool streaming: false
  property string contentBlocks: ""

  // Parsed content blocks (images + text). Empty when contentBlocks is unset.
  readonly property var _parsedBlocks: {
    if (!root.contentBlocks)
      return []
    try { return JSON.parse(root.contentBlocks) } catch (e) { return [] }
  }

  // Layout contract for ListView: consumer sets width.
  implicitHeight: bubble.implicitHeight + Style.marginS

  function _escapeHtml(s) { return Markdown.escapeHtml(s) }
  function sanitizeUrlToken(url) { return Markdown.sanitizeUrlToken(url) }
  function _autoLinkBareUrlsInMarkdown(md) { return Markdown.autoLinkBareUrlsInMarkdown(md) }
  function _renderPlainWithLinks(s) { return Markdown.renderPlainWithLinks(s) }
  function _renderInlineNoCode(s) { return Markdown.renderInlineNoCode(s) }
  function _renderInlineFormatting(s) { return Markdown.renderInlineFormatting(s) }
  function _renderInlineBoldAndLinks(s) { return Markdown.renderInlineBoldAndLinks(s) }
  function _renderInlineMarkdownLite(line) { return Markdown.renderInlineMarkdownLite(line) }
  function _splitHyphenListLine(line) { return Markdown.splitHyphenListLine(line) }
  function _markdownLiteToHtml(md, styleOpts) { return Markdown.markdownLiteToHtml(md, styleOpts) }
  function _basicMarkdownToHtml(md) { return Markdown.markdownLiteToHtml(md) }
  function normalizeMarkdownForDisplay(md, forceHardLineBreaks) { return Markdown.normalizeMarkdownForDisplay(md, forceHardLineBreaks) }

  function renderRichText(raw) {
    var md = (raw === null || raw === undefined) ? "" : String(raw)
    var fg = root.textColor()

    var primary = Color.mPrimary !== undefined ? Color.mPrimary : fg
    var tertiary = Color.mTertiary !== undefined ? Color.mTertiary : primary
    var secondary = Color.mSecondary !== undefined ? Color.mSecondary : primary
    var styleOpts = {
      codeBg: String(Qt.alpha(Color.mOnSurface, 0.08)),
      codeBlockBg: String(Qt.alpha(Color.mOnSurface, 0.06)),
      codeColor: String(tertiary),
      codeKeywordColor: String(tertiary),
      codeStringColor: String(secondary),
      codeCommentColor: String(Qt.alpha(Color.mOnSurface, 0.45)),
      blockquoteBorder: String(primary),
      blockquoteColor: String(Qt.alpha(Color.mOnSurface, 0.65)),
      headingColor: String(primary),
      tableBorder: String(Qt.alpha(Color.mOnSurface, 0.15))
    }

    // Always use our controlled renderer for consistent spacing across Qt builds.
    // (Qt.convertFromMarkdown output often loses paragraph/list spacing in this environment.)
    var md0 = normalizeMarkdownForDisplay(md, false)
    return '<div style="color: ' + fg + ';">' + _markdownLiteToHtml(md0, styleOpts) + "</div>"
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

  property string _lastUrlContent: ""
  property var _cachedUrls: []

  function extractUrlsCached(raw) {
    if (raw === root._lastUrlContent)
      return root._cachedUrls
    root._lastUrlContent = raw
    root._cachedUrls = extractUrls(raw)
    return root._cachedUrls
  }

  function extractUrls(raw) { return Markdown.extractUrls(raw) }

  function openUrl(url) {
    var u = sanitizeUrlToken(url)
    if (!u)
      return

    // Prefer the same mechanism used by Noctalia itself.
    try {
      Quickshell.execDetached(["xdg-open", u])
      return
    } catch (e) { console.warn("[Claw] xdg-open failed:", e) }

    // Fallback (may be a no-op depending on environment).
    try {
      Qt.openUrlExternally(u)
      return
    } catch (e2) { console.warn("[Claw] Qt.openUrlExternally failed:", e2) }

    try {
      if (ToastService && ToastService.showNotice)
        ToastService.showNotice("OpenClaw Chat", "Failed to open link: " + u, "alert-triangle")
    } catch (e3) { console.warn("[Claw] Toast notification failed:", e3) }
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

      // Content blocks rendering (images + text) when contentBlocks is set
      Repeater {
        model: root._parsedBlocks

        delegate: Item {
          width: contentColumn.width
          implicitHeight: blockImage.visible ? blockImage.implicitHeight
                        : blockText.visible ? blockText.implicitHeight
                        : 0

          Image {
            id: blockImage
            visible: modelData.type === "image"
            width: Math.min(contentColumn.width, 400 * Style.uiScaleRatio)
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 800
            sourceSize.height: 800
            source: {
              if (modelData.type !== "image" || !modelData.source)
                return ""
              var s = modelData.source
              return "data:" + (s.media_type || "image/png") + ";base64," + (s.data || "")
            }
          }

          TextArea {
            id: blockText
            visible: modelData.type === "text"
            width: contentColumn.width
            height: visible ? implicitHeight : 0
            textFormat: TextEdit.RichText
            text: visible ? root.renderRichText(modelData.text || "") : ""
            wrapMode: TextEdit.WordWrap
            readOnly: true
            selectByMouse: true
            padding: 0; topPadding: 0; bottomPadding: 0; leftPadding: 0; rightPadding: 0
            background: null
            color: root.textColor()
            font.pointSize: Math.max(1, Style.fontSizeM * Style.uiScaleRatio)
            implicitHeight: visible ? Math.max(Style.fontSizeM * 1.6, contentHeight) : 0
            implicitWidth: 0
          }
        }
      }

      // Plain text rendering (when no content blocks)
      TextArea {
        id: contentText
        visible: root._parsedBlocks.length === 0

        width: parent.width
        height: visible ? implicitHeight : 0

        textFormat: root.streaming ? TextEdit.PlainText : TextEdit.RichText
        text: visible ? (root.streaming ? root.content : root.renderRichText(root.content)) : ""
        wrapMode: TextEdit.WordWrap
        readOnly: true
        selectByMouse: true

        padding: 0
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0

        background: null
        color: root.textColor()
        font.pointSize: Math.max(1, Style.fontSizeM * Style.uiScaleRatio)

        implicitHeight: visible ? Math.max(Style.fontSizeM * 1.6, contentHeight) : 0
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
            } catch (e) { console.warn("[Claw] linkAt failed:", e) }
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
        visible: !root.streaming && root._parsedBlocks.length === 0 && urlRepeater.count > 0

        Repeater {
          id: urlRepeater
          model: root.streaming ? [] : root.extractUrlsCached(root.content)

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
