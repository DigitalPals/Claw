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

function renderInlineBoldAndLinks(s) {
  var raw = (s === null || s === undefined) ? "" : String(s)
  var out = ""
  var i = 0

  while (i < raw.length) {
    var open = raw.indexOf("**", i)
    if (open === -1) {
      out += renderInlineNoCode(raw.substring(i))
      break
    }

    out += renderInlineNoCode(raw.substring(i, open))

    var close = raw.indexOf("**", open + 2)
    if (close === -1) {
      out += renderInlineNoCode(raw.substring(open))
      break
    }

    var inner = raw.substring(open + 2, close)
    out += "<b>" + renderInlineNoCode(inner) + "</b>"
    i = close + 2
  }

  return out
}

function renderInlineMarkdownLite(line) {
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
    out += renderInlineBoldAndLinks(buf)
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
    out += renderInlineBoldAndLinks("`" + buf)
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

function markdownLiteToHtml(md) {
  var s = (md === null || md === undefined) ? "" : String(md)

  s = s.replace(/\r\n/g, "\n").replace(/\r/g, "\n")

  var lines = s.split("\n")
  var out = ""
  var inFence = false
  var fenceBuf = ""

  function flushFence() {
    var escaped = escapeHtml(fenceBuf)
    out += "<pre><tt>" + escaped + "</tt></pre>"
    fenceBuf = ""
  }

  for (var li = 0; li < lines.length; li++) {
    var line = lines[li]
    var trimmed = (line || "").trim()

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

    if (li > 0)
      out += "<br/>"

    if (!line) {
      continue
    }

    var logicalLines = splitHyphenListLine(line)
    for (var jj = 0; jj < logicalLines.length; jj++) {
      if (jj > 0)
        out += "<br/>"
      out += renderInlineMarkdownLite(logicalLines[jj])
    }
  }

  if (inFence) {
    if (out.length > 0)
      out += "<br/>"
    flushFence()
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
