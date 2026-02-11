.pragma library

// Pure UI helper functions extracted from Panel.qml.

function commandShouldOpen(text) {
  if (!text)
    return false
  if (text.length < 1)
    return false
  if (text[0] !== "/")
    return false
  return text.indexOf(" ") === -1 && text.indexOf("\t") === -1 && text.indexOf("\n") === -1
}

function sessionDisplayName(sessionKey) {
  var parts = (sessionKey || "").split(":")
  if (parts.length >= 4 && parts[0] === "agent") {
    return parts.slice(3).join(":")
  }
  if (parts.length === 3 && parts[0] === "agent") {
    return parts[2]
  }
  if (parts.length >= 3)
    return parts.slice(2).join(":")
  if (parts.length >= 2)
    return parts[1]
  return sessionKey
}

function channelLabel(channelId, channelMeta) {
  for (var i = 0; i < channelMeta.length; i++) {
    if (channelMeta[i].id === channelId)
      return channelMeta[i].label || channelId
  }
  return channelId
}

function channelHasUnread(channelId, unreadSessions, channelFromSessionKeyFn) {
  for (var k in unreadSessions) {
    if (channelFromSessionKeyFn(k) === channelId)
      return true
  }
  return false
}

function breadcrumbText(viewMode, selectedChannelId, activeSessionKey, channelMeta) {
  if (viewMode === "sessions")
    return channelLabel(selectedChannelId, channelMeta)
  if (viewMode === "chat")
    return channelLabel(selectedChannelId, channelMeta) + " \u203A " + sessionDisplayName(activeSessionKey)
  return "OpenClaw Chat"
}
