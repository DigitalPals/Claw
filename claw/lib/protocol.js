.pragma library

// Pure protocol/state management functions extracted from Main.qml.

function channelFromSessionKey(sessionKey) {
  var parts = (sessionKey || "").split(":")
  if (parts.length >= 3 && parts[0] === "agent")
    return parts[2]
  if (parts.length >= 2)
    return parts[1]
  return ""
}

function extractTextFromContent(content) {
  if (content == null)
    return ""
  if (typeof content === "string")
    return content
  if (Array.isArray(content)) {
    var parts = []
    for (var i = 0; i < content.length; i++) {
      var block = content[i]
      if (block && block.type === "text" && block.text)
        parts.push(block.text)
    }
    return parts.join("\n")
  }
  return ""
}

function extractContentBlocksJson(contentArray) {
  var hasNonText = false
  for (var i = 0; i < contentArray.length; i++) {
    if (contentArray[i] && contentArray[i].type !== "text") {
      hasNonText = true
      break
    }
  }
  if (!hasNonText)
    return ""
  return JSON.stringify(contentArray)
}

function truncateForToast(s, maxLen) {
  var t = (s === null || s === undefined) ? "" : String(s)
  t = t.replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  var parts = t.split("\n")
  for (var i = 0; i < parts.length; i++) {
    var line = String(parts[i] || "").trim()
    if (line.length > 0) {
      t = line
      break
    }
  }
  if (t.length > maxLen)
    t = t.substring(0, maxLen - 1) + "\u2026"
  return t
}

function ensureInstanceId(currentId) {
  if (currentId)
    return currentId
  var s = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return s.replace(/[xy]/g, function(c) {
    var r = Math.random() * 16 | 0
    return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16)
  })
}

function markSessionUnread(currentUnread, sessionKey) {
  if (!sessionKey)
    return currentUnread
  if (currentUnread[sessionKey])
    return currentUnread
  var fresh = {}
  for (var k in currentUnread)
    fresh[k] = true
  fresh[sessionKey] = true
  return fresh
}

function clearSessionUnread(currentUnread, sessionKey) {
  if (!sessionKey)
    return currentUnread
  if (!currentUnread[sessionKey])
    return currentUnread
  var fresh = {}
  for (var k in currentUnread) {
    if (k !== sessionKey)
      fresh[k] = true
  }
  return fresh
}

function clearChannelSessions(currentUnread, channelId) {
  if (!channelId)
    return currentUnread
  var fresh = {}
  var changed = false
  for (var k in currentUnread) {
    if (channelFromSessionKey(k) === channelId)
      changed = true
    else
      fresh[k] = true
  }
  return changed ? fresh : currentUnread
}

function formatTokenUsage(used, limit) {
  if (!used && !limit)
    return ""
  function fmt(n) {
    if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, "") + "M"
    if (n >= 1000) return Math.round(n / 1000) + "k"
    return String(n)
  }
  if (!limit)
    return fmt(used)
  var pct = Math.round(used / limit * 100)
  return fmt(used) + "/" + fmt(limit) + " (" + pct + "%)"
}

// Extract model id from server response text like "Model set to opus (anthropic/claude-opus-4-6)."
function parseModelFromResponse(text) {
  if (!text) return ""
  var m = text.match(/\bModel (?:set|switched) to \S+ \(([^)]+)\)/)
  return m ? m[1] : ""
}

function computeActivityState(connectionState, isStreaming, isSending) {
  if (connectionState !== "connected") return "disconnected"
  if (isStreaming) return "streaming"
  if (isSending) return "thinking"
  return "idle"
}

function filterSessionsForChannel(allSessions, channelId) {
  var filtered = []
  for (var i = 0; i < allSessions.length; i++) {
    var s = allSessions[i]
    var sCh = s.channel || channelFromSessionKey(s.key || "")
    if (sCh === channelId)
      filtered.push(s)
  }
  return filtered
}
