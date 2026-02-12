.pragma library

// Pure markdown/HTML rendering functions extracted from MessageBubble.qml.
// Every function is a top-level declaration so QML can import them as a namespace.

function escapeHtml(s) {
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

function autoLinkBareUrlsInMarkdown(md) {
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

function renderPlainWithLinks(s) {
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
        var escHref = escapeHtml(href)
        out += '<a href="' + escHref + '">' + escHref + "</a>" + escapeHtml(trailing)
      } else {
        out += escapeHtml(raw.substring(i, j))
      }

      i = j
      continue
    }

    out += escapeHtml(raw[i])
    i += 1
  }

  return out
}

function renderInlineNoCode(s) {
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
            out += '<a href="' + escapeHtml(href) + '">' + escapeHtml(label) + "</a>"
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
      out += renderPlainWithLinks(raw.substring(i, j))
      i = j
      continue
    }

    out += escapeHtml(raw[i])
    i += 1
  }

  return out
}

function renderInlineFormatting(s) {
  var raw = (s === null || s === undefined) ? "" : String(s)

  var delimiters = [
    { open: "***", close: "***", openTag: "<b><i>", closeTag: "</i></b>", boundary: false },
    { open: "___", close: "___", openTag: "<b><i>", closeTag: "</i></b>", boundary: true },
    { open: "**", close: "**", openTag: "<b>", closeTag: "</b>", boundary: false },
    { open: "__", close: "__", openTag: "<b>", closeTag: "</b>", boundary: true },
    { open: "~~", close: "~~", openTag: "<s>", closeTag: "</s>", boundary: false },
    { open: "*", close: "*", openTag: "<i>", closeTag: "</i>", boundary: false },
    { open: "_", close: "_", openTag: "<i>", closeTag: "</i>", boundary: true },
  ]

  function isWordChar(ch) { return /[a-zA-Z0-9_]/.test(ch) }

  function findDelim(str, delim, start, needBoundary) {
    var pos = start
    while (pos <= str.length - delim.length) {
      var idx = str.indexOf(delim, pos)
      if (idx === -1) return -1
      if (!needBoundary) return idx

      var before = idx > 0 ? str[idx - 1] : ""
      var afterIdx = idx + delim.length
      var after = afterIdx < str.length ? str[afterIdx] : ""

      if (before && after && isWordChar(before) && isWordChar(after)) {
        pos = idx + 1
        continue
      }
      return idx
    }
    return -1
  }

  // Find the earliest opening delimiter
  var bestPos = -1
  var bestDelim = null

  for (var d = 0; d < delimiters.length; d++) {
    var pos = findDelim(raw, delimiters[d].open, 0, delimiters[d].boundary)
    if (pos !== -1 && (bestPos === -1 || pos < bestPos)) {
      bestPos = pos
      bestDelim = delimiters[d]
    }
  }

  if (bestDelim === null) {
    return renderInlineNoCode(raw)
  }

  // Find closing delimiter
  var closePos = findDelim(raw, bestDelim.close, bestPos + bestDelim.open.length, bestDelim.boundary)
  if (closePos === -1) {
    var unclosedEnd = bestPos + bestDelim.open.length
    return renderInlineNoCode(raw.substring(0, unclosedEnd)) + renderInlineFormatting(raw.substring(unclosedEnd))
  }

  var before = raw.substring(0, bestPos)
  var inner = raw.substring(bestPos + bestDelim.open.length, closePos)
  var after = raw.substring(closePos + bestDelim.close.length)

  return renderInlineNoCode(before)
       + bestDelim.openTag + renderInlineFormatting(inner) + bestDelim.closeTag
       + renderInlineFormatting(after)
}

function renderInlineBoldAndLinks(s) { return renderInlineFormatting(s) }

function renderInlineMarkdownLite(line) {
  var raw0 = (line === null || line === undefined) ? "" : String(line)
  var raw = ""
  for (var k = 0; k < raw0.length; k++) {
    var ch = raw0[k]
    if (ch === "\\" && (k + 1) < raw0.length) {
      var next = raw0[k + 1]
      if (next === "`" || next === "*" || next === "[" || next === "]" || next === "(" || next === ")"
          || next === "_" || next === "~" || next === "#" || next === "-" || next === ">") {
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
    out += renderInlineFormatting(buf)
    buf = ""
  }

  for (var i = 0; i < raw.length; i++) {
    var c = raw[i]
    if (c === "`") {
      if (inCode) {
        out += "<tt>" + escapeHtml(buf) + "</tt>"
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
    out += renderInlineFormatting("`" + buf)
  } else {
    flushText()
  }

  return out
}

function splitHyphenListLine(line) {
  var s = (line === null || line === undefined) ? "" : String(line)
  function isSepWs(ch) {
    return ch === " " || ch === "\t" || ch === "\u00A0"
  }

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

    seps.push({ l: l + 1, r: r })
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

var _keywords = null
function _getKeywords() {
  if (_keywords) return _keywords
  _keywords = {}
  var words = [
    "export","if","then","else","elif","fi","for","in","do","done","while","until",
    "case","esac","function","return","local","source","echo","sudo","cd","mkdir","rm",
    "var","let","const","def","class","import","from","async","await","try","catch",
    "except","finally","throw","new","this","self","switch","break","continue","yield",
    "typeof","instanceof","raise","with","as","pass","lambda","print","not","and","or",
    "func","defer","go","range","select","chan","struct","enum","impl","trait","pub",
    "mod","use","fn","mut","loop","match","where","type","package","interface",
    "true","false","null","undefined","None","True","False","nil",
  ]
  for (var i = 0; i < words.length; i++) _keywords[words[i]] = true
  return _keywords
}

function syntaxHighlightCode(raw, opts) {
  if (!opts) return escapeHtml(raw)
  var lines = (raw || "").split("\n")
  var result = []
  for (var li = 0; li < lines.length; li++)
    result.push(_highlightLine(lines[li], opts))
  return result.join("\n")
}

function _highlightLine(line, opts) {
  var trimmed = (line || "").replace(/^\s+/, "")

  // Full-line comment: # or //
  if ((trimmed[0] === "#" && trimmed[1] !== "!") || trimmed.substring(0, 2) === "//") {
    if (opts.commentColor)
      return '<span style="color: ' + opts.commentColor + ';">' + escapeHtml(line) + '</span>'
    return escapeHtml(line)
  }

  var out = ""
  var i = 0
  var kw = _getKeywords()

  while (i < line.length) {
    // Strings
    if (line[i] === '"' || line[i] === "'") {
      var quote = line[i]
      var j = i + 1
      while (j < line.length && line[j] !== quote) {
        if (line[j] === "\\") j++
        j++
      }
      if (j < line.length) j++
      var str = line.substring(i, j)
      if (opts.stringColor)
        out += '<span style="color: ' + opts.stringColor + ';">' + escapeHtml(str) + '</span>'
      else
        out += escapeHtml(str)
      i = j
      continue
    }

    // Inline comment: # preceded by whitespace
    if (line[i] === "#" && i > 0 && /\s/.test(line[i - 1])) {
      var rest = line.substring(i)
      if (opts.commentColor)
        out += '<span style="color: ' + opts.commentColor + ';">' + escapeHtml(rest) + '</span>'
      else
        out += escapeHtml(rest)
      break
    }

    // Words (identifiers / keywords)
    if (/[a-zA-Z_]/.test(line[i])) {
      var j2 = i
      while (j2 < line.length && /[a-zA-Z0-9_]/.test(line[j2])) j2++
      var word = line.substring(i, j2)
      if (kw[word] && opts.keywordColor)
        out += '<span style="color: ' + opts.keywordColor + ';">' + escapeHtml(word) + '</span>'
      else
        out += escapeHtml(word)
      i = j2
      continue
    }

    out += escapeHtml(line[i])
    i++
  }
  return out
}

function markdownLiteToHtml(md, styleOpts) {
  var s = (md === null || md === undefined) ? "" : String(md)

  s = s.replace(/\r\n/g, "\n").replace(/\r/g, "\n")

  var lines = s.split("\n")
  var out = ""
  var inFence = false
  var fenceBuf = ""
  var listStack = []  // [{tag: "ul"/"ol", indent: number}]
  var inBlockquote = false
  var inTable = false
  var tableRows = []
  var tableHasHeader = false
  var lastLineType = "none"

  function flushFence() {
    var hlOpts = null
    if (styleOpts && styleOpts.codeKeywordColor)
      hlOpts = { keywordColor: styleOpts.codeKeywordColor, stringColor: styleOpts.codeStringColor, commentColor: styleOpts.codeCommentColor }
    out += "<pre><tt>" + syntaxHighlightCode(fenceBuf, hlOpts) + "</tt></pre>"
    fenceBuf = ""
  }

  function flushTable() {
    if (tableRows.length === 0) { inTable = false; return }
    var borderColor = (styleOpts && styleOpts.tableBorder) ? styleOpts.tableBorder : ""
    var cellStyle = borderColor
        ? ' style="border: 1px solid ' + borderColor + '; padding: 4px 8px;"'
        : ' style="padding: 4px 8px;"'
    out += '<table cellspacing="0" cellpadding="0" style="border-collapse: collapse;">'
    for (var ti = 0; ti < tableRows.length; ti++) {
      out += "<tr>"
      var tag = (tableHasHeader && ti === 0) ? "th" : "td"
      for (var ci = 0; ci < tableRows[ti].length; ci++)
        out += "<" + tag + cellStyle + ">" + renderInlineMarkdownLite(tableRows[ti][ci]) + "</" + tag + ">"
      out += "</tr>"
    }
    out += "</table>"
    tableRows = []
    tableHasHeader = false
    inTable = false
  }

  function getIndent(ln) {
    var count = 0
    for (var ci = 0; ci < (ln || "").length; ci++) {
      if (ln[ci] === " ") count++
      else if (ln[ci] === "\t") count += 4
      else break
    }
    return count
  }

  function closeAllLists() {
    while (listStack.length > 0)
      out += "</" + listStack.pop().tag + ">"
  }

  function closeListsToIndent(indent) {
    while (listStack.length > 0 && listStack[listStack.length - 1].indent > indent)
      out += "</" + listStack.pop().tag + ">"
  }

  function closeBlockquote() {
    if (inBlockquote) {
      out += "</td></tr></table>"
      inBlockquote = false
    }
  }

  function closeBlocks() {
    if (inTable) flushTable()
    closeAllLists()
    closeBlockquote()
  }

  for (var li = 0; li < lines.length; li++) {
    var line = lines[li]
    var trimmed = (line || "").trim()

    // Fenced code blocks
    if (trimmed.indexOf("```") === 0) {
      if (inFence) {
        flushFence()
        inFence = false
        lastLineType = "block"
      } else {
        closeBlocks()
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

    // Blank line — close open blocks
    if (!trimmed) {
      closeBlocks()
      if (lastLineType === "text" || lastLineType === "blank")
        out += "<br/>"
      lastLineType = "blank"
      continue
    }

    // Horizontal rule: ---, ***, ___  (3+ of the same character)
    if (/^(-{3,}|\*{3,}|_{3,})$/.test(trimmed)) {
      closeBlocks()
      out += "<hr/>"
      lastLineType = "block"
      continue
    }

    // Headings: # through ####
    var headingMatch = trimmed.match(/^(#{1,4})\s+(.*)/)
    if (headingMatch) {
      closeBlocks()
      var level = headingMatch[1].length
      var hStyle = (styleOpts && styleOpts.headingColor) ? ' style="color: ' + styleOpts.headingColor + ';"' : ""
      out += "<h" + level + hStyle + ">" + renderInlineMarkdownLite(headingMatch[2]) + "</h" + level + ">"
      lastLineType = "block"
      continue
    }

    // Unordered list: - text  or  * text
    var ulMatch = trimmed.match(/^[-*]\s+(.*)/)
    if (ulMatch) {
      closeBlockquote()
      var indent = getIndent(line)
      closeListsToIndent(indent)
      var top = listStack.length > 0 ? listStack[listStack.length - 1] : null
      if (!top || top.indent < indent) {
        listStack.push({ tag: "ul", indent: indent })
        out += "<ul>"
      } else if (top.tag !== "ul") {
        out += "</" + listStack.pop().tag + ">"
        listStack.push({ tag: "ul", indent: indent })
        out += "<ul>"
      }
      out += "<li>" + renderInlineMarkdownLite(ulMatch[1]) + "</li>"
      lastLineType = "block"
      continue
    }

    // Ordered list: 1. text
    var olMatch = trimmed.match(/^\d+\.\s+(.*)/)
    if (olMatch) {
      closeBlockquote()
      var indent2 = getIndent(line)
      closeListsToIndent(indent2)
      var top2 = listStack.length > 0 ? listStack[listStack.length - 1] : null
      if (!top2 || top2.indent < indent2) {
        listStack.push({ tag: "ol", indent: indent2 })
        out += "<ol>"
      } else if (top2.tag !== "ol") {
        out += "</" + listStack.pop().tag + ">"
        listStack.push({ tag: "ol", indent: indent2 })
        out += "<ol>"
      }
      out += "<li>" + renderInlineMarkdownLite(olMatch[1]) + "</li>"
      lastLineType = "block"
      continue
    }

    // Blockquote: > text
    var bqMatch = trimmed.match(/^>\s?(.*)/)
    if (bqMatch) {
      if (inTable) flushTable()
      closeAllLists()
      if (!inBlockquote) {
        inBlockquote = true
        var borderColor = (styleOpts && styleOpts.blockquoteBorder) ? styleOpts.blockquoteBorder : "#808080"
        var bqTextStyle = "padding-left: 8px;"
        if (styleOpts && styleOpts.blockquoteColor) bqTextStyle += " color: " + styleOpts.blockquoteColor + ";"
        out += '<table cellspacing="0" cellpadding="0"><tr>'
            + '<td width="3" style="background-color: ' + borderColor + ';"></td>'
            + '<td style="' + bqTextStyle + '">'
      } else {
        out += "<br/>"
      }
      out += renderInlineMarkdownLite(bqMatch[1])
      lastLineType = "block"
      continue
    }

    // Table row: | cell | cell |
    if (trimmed[0] === "|" && trimmed[trimmed.length - 1] === "|") {
      // Separator line: |---|---| (only pipes, dashes, colons, spaces)
      if (/^[|\s:-]+$/.test(trimmed) && trimmed.indexOf("-") !== -1) {
        if (inTable && tableRows.length > 0)
          tableHasHeader = true
        lastLineType = "block"
        continue
      }
      if (!inTable) {
        closeBlocks()
        inTable = true
      }
      var cells = trimmed.substring(1, trimmed.length - 1).split("|")
      var row = []
      for (var ci = 0; ci < cells.length; ci++)
        row.push(cells[ci].trim())
      tableRows.push(row)
      lastLineType = "block"
      continue
    }

    // Regular text
    closeBlocks()
    if (lastLineType !== "none")
      out += "<br/>"

    var logicalLines = splitHyphenListLine(line)
    for (var jj = 0; jj < logicalLines.length; jj++) {
      if (jj > 0)
        out += "<br/>"
      out += renderInlineMarkdownLite(logicalLines[jj])
    }
    lastLineType = "text"
  }

  closeBlocks()
  if (inFence) {
    if (out.length > 0)
      out += "<br/>"
    flushFence()
  }

  // Post-process: apply styleOpts for code styling
  if (styleOpts) {
    // Extract <pre> blocks to protect them from inline code styling
    var prePlaceholders = []
    out = out.replace(/<pre[^>]*>[\s\S]*?<\/pre>/g, function(match) {
      var idx = prePlaceholders.length
      var placeholder = "\x00PRE" + idx + "\x00"
      prePlaceholders.push({ placeholder: placeholder, content: match })
      return placeholder
    })

    // Style inline code
    if (styleOpts.codeBg || styleOpts.codeColor) {
      var codeStyle = ""
      if (styleOpts.codeBg) codeStyle += "background-color: " + styleOpts.codeBg + ";"
      if (styleOpts.codeColor) codeStyle += " color: " + styleOpts.codeColor + ";"
      out = out.replace(/<tt>/g, '<span style="' + codeStyle + '"><tt>')
      out = out.replace(/<\/tt>/g, '</tt></span>')
    }

    // Restore <pre> blocks with optional styling
    for (var pi = 0; pi < prePlaceholders.length; pi++) {
      var preContent = prePlaceholders[pi].content
      if (styleOpts.codeBlockBg) {
        preContent = preContent.replace(/<pre>/, '<pre style="background-color: ' + styleOpts.codeBlockBg + '; padding: 8px;">')
      }
      out = out.split(prePlaceholders[pi].placeholder).join(preContent)
    }
  }

  return out
}

function normalizeMarkdownForDisplay(md, forceHardLineBreaks) {
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
    var s2 = (line === null || line === undefined) ? "" : String(line)

    s2 = s2.replace(/\*\*([^*\n]{1,120}):\*\*\s*/g, "\n\n**$1:**\n")
    s2 = s2.replace(/(^|[.!?])\s*([A-Z][^:\n]{1,80}):\s*(?=(\d{1,2}\.)|-\s)/g, "$1\n\n$2:\n")
    s2 = s2.replace(/([^\n])\s+(\d{1,2})\.\s+/g, "$1\n$2. ")

    var bulletCount = 0
    var mre
    var re = /(^|\s)-\s+/g
    while ((mre = re.exec(s2)) !== null)
      bulletCount++
    if (bulletCount >= 2)
      s2 = s2.replace(/([^\n])\s+-\s+/g, "$1\n- ")

    s2 = s2.replace(/\n{3,}/g, "\n\n")

    return s2.split("\n")
  }

  for (var li = 0; li < lines.length; li++) {
    var line0 = lines[li]

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

    var expanded = expandInlineStructureToLines(line0)
    for (var ei = 0; ei < expanded.length; ei++) {
      var lineE = expanded[ei]

      if (!lineE) {
        out += "\n"
        continue
      }

      var logicalLines = splitHyphenListLine(lineE)
      for (var j = 0; j < logicalLines.length; j++) {
        var line = logicalLines[j]
        out += line

        if (forceHardLineBreaks && !isListLike(line))
          out += "  "

        if (j < logicalLines.length - 1)
          out += "\n"
        else
          out += "\n"
      }
    }
  }

  return out
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
