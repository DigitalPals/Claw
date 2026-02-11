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

  function _escapeHtml(s) {
    var out = (s === null || s === undefined) ? "" : String(s)
    out = out.replace(/&/g, "&amp;")
    out = out.replace(/</g, "&lt;")
    out = out.replace(/>/g, "&gt;")
    out = out.replace(/\"/g, "&quot;")
    out = out.replace(/'/g, "&#39;")
    return out
  }

  function sanitizeUrlToken(url) {
    var u = (url === null || url === undefined) ? "" : String(url)
    u = u.trim()
    if (!u)
      return ""

    // Remove surrounding angle brackets if present.
    if (u.length >= 2 && u[0] === "<" && u[u.length - 1] === ">")
      u = u.substring(1, u.length - 1)

    function isHostOnlyHttpUrl(s) {
      var rest = ""
      if (s.indexOf("https://") === 0)
        rest = s.substring(8)
      else if (s.indexOf("http://") === 0)
        rest = s.substring(7)
      else
        return false
      return rest.indexOf("/") === -1
    }

    function endsWithIgnoreCase(s, suffix) {
      if (s.length < suffix.length)
        return false
      return s.substring(s.length - suffix.length).toLowerCase() === suffix.toLowerCase()
    }

    function isTrailingPunct(ch) {
      return ch === ")" || ch === "]" || ch === "}" || ch === "." || ch === "," || ch === ";"
          || ch === ":" || ch === "!" || ch === "?" || ch === "*"
    }

    // Strip a single trailing slash temporarily so we can remove trailing emphasis (or %2A) before it.
    var hadSlash = (u.length > 0 && u[u.length - 1] === "/")
    if (hadSlash)
      u = u.substring(0, u.length - 1)

    // Remove markdown emphasis stars at the end.
    while (u.length > 0 && u[u.length - 1] === "*")
      u = u.substring(0, u.length - 1)

    // Remove percent-encoded asterisks at the end: %2A%2A...
    while (endsWithIgnoreCase(u, "%2a"))
      u = u.substring(0, u.length - 3)

    // Trim common trailing punctuation.
    while (u.length > 0 && isTrailingPunct(u[u.length - 1]))
      u = u.substring(0, u.length - 1)

    // Restore slash if it was a real path delimiter; otherwise drop it for host-only URLs.
    if (hadSlash && !isHostOnlyHttpUrl(u))
      u = u + "/"

    return u
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
        // Also trim '*' to handle markdown emphasis like **https://example.com**.
        while (url.length > 0 && /[\\)\\]\\}\\.,;:!?\\*]/.test(url[url.length - 1])) {
          trailing = url[url.length - 1] + trailing
          url = url.substring(0, url.length - 1)
        }

        out += "<" + sanitizeUrlToken(url) + ">" + trailing
        i = j
        continue
      }

      out += s[i]
      i += 1
    }

    return out
  }

  function _basicMarkdownToHtml(md) {
    // Backwards-compat shim: keep the old name but route to the improved fallback.
    return _markdownLiteToHtml(md)
  }

  function _renderPlainWithLinks(s) {
    // Render plain text safely (escape HTML) while making URLs clickable.
    var raw = (s === null || s === undefined) ? "" : String(s)
    var out = ""
    var i = 0

    function isWs(ch) { return /\s/.test(ch) }

    while (i < raw.length) {
      if (raw.substring(i, i + 7) === "http://" || raw.substring(i, i + 8) === "https://") {
        var j = i
        while (j < raw.length && !isWs(raw[j]))
          j++

        var urlToken = raw.substring(i, j)
        var trailing = ""
        while (urlToken.length > 0 && /[\\)\\]\\}\\.,;:!?\\*]/.test(urlToken[urlToken.length - 1])) {
          trailing = urlToken[urlToken.length - 1] + trailing
          urlToken = urlToken.substring(0, urlToken.length - 1)
        }

        var href = sanitizeUrlToken(urlToken)
        if (href) {
          var escHref = _escapeHtml(href)
          out += '<a href="' + escHref + '">' + escHref + "</a>" + _escapeHtml(trailing)
        } else {
          out += _escapeHtml(raw.substring(i, j))
        }

        i = j
        continue
      }

      out += _escapeHtml(raw[i])
      i += 1
    }

    return out
  }

  function _renderInlineNoCode(s) {
    // Supports:
    // - Markdown links: [label](url)
    // - Bare URLs: https://...
    // Everything else is escaped.
    var raw = (s === null || s === undefined) ? "" : String(s)
    var out = ""
    var i = 0

    function isWs(ch) { return /\s/.test(ch) }

    while (i < raw.length) {
      // Markdown link: [label](url)
      if (raw[i] === "[") {
        var closeBracket = raw.indexOf("]", i + 1)
        if (closeBracket !== -1 && closeBracket + 1 < raw.length && raw[closeBracket + 1] === "(") {
          var closeParen = raw.indexOf(")", closeBracket + 2)
          if (closeParen !== -1) {
            var label = raw.substring(i + 1, closeBracket)
            var hrefRaw = raw.substring(closeBracket + 2, closeParen)
            var href = sanitizeUrlToken(hrefRaw)

            if (href) {
              out += '<a href="' + _escapeHtml(href) + '">' + _escapeHtml(label) + "</a>"
              i = closeParen + 1
              continue
            }
          }
        }
      }

      // Bare URLs.
      if (raw.substring(i, i + 7) === "http://" || raw.substring(i, i + 8) === "https://") {
        var j = i
        while (j < raw.length && !isWs(raw[j]))
          j++
        out += _renderPlainWithLinks(raw.substring(i, j))
        i = j
        continue
      }

      out += _escapeHtml(raw[i])
      i += 1
    }

    return out
  }

  function _renderInlineBoldAndLinks(s) {
    // Handle **bold** segments; within each segment, render links safely.
    var raw = (s === null || s === undefined) ? "" : String(s)
    var out = ""
    var i = 0

    while (i < raw.length) {
      var open = raw.indexOf("**", i)
      if (open === -1) {
        out += _renderInlineNoCode(raw.substring(i))
        break
      }

      // Emit prefix.
      out += _renderInlineNoCode(raw.substring(i, open))

      var close = raw.indexOf("**", open + 2)
      if (close === -1) {
        // Unclosed, treat literally.
        out += _renderInlineNoCode(raw.substring(open))
        break
      }

      var inner = raw.substring(open + 2, close)
      out += "<b>" + _renderInlineNoCode(inner) + "</b>"
      i = close + 2
    }

    return out
  }

  function _renderInlineMarkdownLite(line) {
    // Inline rendering with:
    // - Backslash escapes for markdown punctuation (so \\`foo\\` becomes `foo`).
    // - Inline code spans using backticks.
    // - Bold using **...** outside code.
    var raw0 = (line === null || line === undefined) ? "" : String(line)
    var raw = ""
    for (var k = 0; k < raw0.length; k++) {
      var ch = raw0[k]
      if (ch === "\\" && (k + 1) < raw0.length) {
        var next = raw0[k + 1]
        if (next === "`" || next === "*" || next === "[" || next === "]" || next === "(" || next === ")") {
          raw += next
          k += 1
          continue
        }
      }
      raw += ch
    }

    var out = ""
    var buf = ""
    var inCode = false

    function flushText() {
      if (!buf)
        return
      out += _renderInlineBoldAndLinks(buf)
      buf = ""
    }

    for (var i = 0; i < raw.length; i++) {
      var c = raw[i]
      if (c === "`") {
        if (inCode) {
          out += "<tt>" + _escapeHtml(buf) + "</tt>"
          buf = ""
          inCode = false
        } else {
          flushText()
          inCode = true
        }
        continue
      }
      buf += c
    }

    if (inCode) {
      // Unclosed: treat the leading backtick as literal.
      out += _renderInlineBoldAndLinks("`" + buf)
    } else {
      flushText()
    }

    return out
  }

  function _splitHyphenListLine(line) {
    // Heuristic: turn "A - B - C" into multiple lines.
    // Only trigger when it looks like a real list (2+ separators).
    var s = (line === null || line === undefined) ? "" : String(line)
    function isSepWs(ch) {
      return ch === " " || ch === "\t" || ch === "\u00A0"
    }

    // Find whitespace-dash-whitespace patterns, consuming any run of whitespace on both sides.
    var seps = []
    for (var i = 1; i < s.length - 1; i++) {
      if (s[i] !== "-")
        continue
      if (!isSepWs(s[i - 1]) || !isSepWs(s[i + 1]))
        continue

      var l = i - 1
      while (l >= 0 && isSepWs(s[l]))
        l--
      var r = i + 1
      while (r < s.length && isSepWs(s[r]))
        r++

      seps.push({ l: l + 1, r: r }) // [l, r) is the separator region
      i = r - 1
    }

    if (seps.length < 2)
      return [s]

    var out = []
    var last = 0
    for (var j = 0; j < seps.length; j++) {
      var seg = s.substring(last, seps[j].l)
      if (j === 0)
        out.push(seg.replace(/\s+$/, ""))
      else
        out.push("- " + seg.replace(/^\s+/, "").replace(/\s+$/, ""))
      last = seps[j].r
    }

    var tail = s.substring(last)
    out.push("- " + tail.replace(/^\s+/, ""))
    return out
  }

  function _markdownLiteToHtml(md) {
    // Safe, dependency-free markdown-lite renderer for environments where
    // Qt.convertFromMarkdown isn't available.
    // Supports:
    // - **bold**
    // - `inline code`
    // - ``` fenced code blocks ```
    // - [label](url) and bare URLs
    // - List-ish hyphen splitting ("A - B - C")
    var s = (md === null || md === undefined) ? "" : String(md)

    s = s.replace(/\r\n/g, "\n").replace(/\r/g, "\n")

    var lines = s.split("\n")
    var out = ""
    var inFence = false
    var fenceBuf = ""

    function flushFence() {
      // Use <pre> for better readability. Keep content escaped.
      // Qt rich text supports <pre>; <tt> gives a reasonable monospace fallback.
      var escaped = _escapeHtml(fenceBuf)
      out += "<pre><tt>" + escaped + "</tt></pre>"
      fenceBuf = ""
    }

    for (var li = 0; li < lines.length; li++) {
      var line = lines[li]
      var trimmed = (line || "").trim()

      // Fence delimiter: ``` or ```lang
      if (trimmed.indexOf("```") === 0) {
        if (inFence) {
          flushFence()
          inFence = false
        } else {
          inFence = true
          fenceBuf = ""
        }
        continue
      }

      if (inFence) {
        if (fenceBuf.length > 0)
          fenceBuf += "\n"
        fenceBuf += line
        continue
      }

      // Outside fences: render line-by-line with <br/>.
      if (li > 0)
        out += "<br/>"

      if (!line) {
        // Blank line.
        continue
      }

      // If the model returns "inline list on one line", split it into lines.
      var logicalLines = _splitHyphenListLine(line)
      for (var jj = 0; jj < logicalLines.length; jj++) {
        if (jj > 0)
          out += "<br/>"
        out += _renderInlineMarkdownLite(logicalLines[jj])
      }
    }

    if (inFence) {
      // Unclosed fence: render what we have as code.
      // Add a line break before the code block if we already emitted content.
      if (out.length > 0)
        out += "<br/>"
      flushFence()
    }

    return out
  }

  function normalizeMarkdownForDisplay(md, forceHardLineBreaks) {
    // Normalize assistant output so spacing is preserved even when the markdown renderer
    // treats single newlines as soft wraps.
    //
    // - Keeps fenced code blocks intact.
    // - Splits "A - B - C" into multiple lines (2+ separators) outside fences.
    // - Optionally forces hard line breaks ("two trailing spaces") for non-list lines.
    var s = (md === null || md === undefined) ? "" : String(md)
    s = s.replace(/\r\n/g, "\n").replace(/\r/g, "\n")

    var lines = s.split("\n")
    var out = ""
    var inFence = false

    function trimLeft(x) {
      return (x || "").replace(/^\s+/, "")
    }

    function isFenceLine(line) {
      return trimLeft(line).indexOf("```") === 0
    }

    function isListLike(line) {
      var t = trimLeft(line)
      if (t.indexOf("- ") === 0 || t.indexOf("* ") === 0)
        return true
      if (/^\d+\.\s/.test(t))
        return true
      if (t.indexOf(">") === 0)
        return true
      if (t.indexOf("#") === 0)
        return true
      return false
    }

    function expandInlineStructureToLines(line) {
      // Take common LLM "inline structured" text and insert real newlines so it renders
      // as headings + lists instead of a single paragraph.
      var s2 = (line === null || line === undefined) ? "" : String(line)

      // If the model emits section headings as bold with a trailing colon, break around them.
      // Example: "... **The flow:** 1. ..." -> blank line, heading, newline, list.
      s2 = s2.replace(/\*\*([^*\n]{1,120}):\*\*\s*/g, "\n\n**$1:**\n")

      // If the model emits a plain heading with a colon and then a list marker inline,
      // split it into its own paragraph.
      // Example: "The flow: 1. ..." -> "The flow:\n1. ..."
      s2 = s2.replace(/(^|[.!?])\s*([A-Z][^:\n]{1,80}):\s*(?=(\d{1,2}\.)|-\s)/g, "$1\n\n$2:\n")

      // Split numbered list items onto their own lines: " ... 1. X 2. Y" -> "\n1. X\n2. Y"
      s2 = s2.replace(/([^\n])\s+(\d{1,2})\.\s+/g, "$1\n$2. ")

      // Split inline bullets onto their own lines when there are multiple bullets.
      var bulletCount = 0
      var mre
      var re = /(^|\s)-\s+/g
      while ((mre = re.exec(s2)) !== null)
        bulletCount++
      if (bulletCount >= 2)
        s2 = s2.replace(/([^\n])\s+-\s+/g, "$1\n- ")

      // Collapse accidental 3+ blank lines.
      s2 = s2.replace(/\n{3,}/g, "\n\n")

      return s2.split("\n")
    }

    for (var li = 0; li < lines.length; li++) {
      var line0 = lines[li]

      // Keep fence delimiters and fence content untouched.
      if (isFenceLine(line0)) {
        inFence = !inFence
        out += line0
        if (li < lines.length - 1)
          out += "\n"
        continue
      }

      if (inFence) {
        out += line0
        if (li < lines.length - 1)
          out += "\n"
        continue
      }

      // Expand inline structure in this line (headings / numbered lists / bullets).
      var expanded = expandInlineStructureToLines(line0)
      for (var ei = 0; ei < expanded.length; ei++) {
        var lineE = expanded[ei]

        // Preserve blank lines.
        if (!lineE) {
          // Always keep blank lines to allow paragraph spacing.
          out += "\n"
          continue
        }

        // Expand inline " - " lists into real line breaks.
        var logicalLines = _splitHyphenListLine(lineE)
        for (var j = 0; j < logicalLines.length; j++) {
          var line = logicalLines[j]
          out += line

          // Force hard breaks for "paragraph-ish" lines so Qt markdown doesn't collapse them.
          // Avoid interfering with list/quote/heading syntax where line breaks are already structural.
          if (forceHardLineBreaks && !isListLike(line))
            out += "  "

          // Newline between logical lines and between expanded lines.
          if (j < logicalLines.length - 1)
            out += "\n"
          else
            out += "\n"
        }
      }
    }

    return out
  }

  function renderRichText(raw) {
    var md = (raw === null || raw === undefined) ? "" : String(raw)
    var fg = root.textColor()

    // Always use our controlled renderer for consistent spacing across Qt builds.
    // (Qt.convertFromMarkdown output often loses paragraph/list spacing in this environment.)
    var md0 = normalizeMarkdownForDisplay(md, false)
    return '<div style="color: ' + fg + ';">' + _markdownLiteToHtml(md0) + "</div>"
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
      var url = sanitizeUrlToken(m[1])
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
    var u = sanitizeUrlToken(url)
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
        visible: !root.streaming && root._parsedBlocks.length === 0 && urlRepeater.count > 0

        Repeater {
          id: urlRepeater
          model: root.streaming ? [] : root.extractUrls(root.content)

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
