.pragma library

// Shared status color constants and helpers.

var statusConnected  = "#4CAF50"
var statusConnecting = "#FFA726"
var statusError      = "#F44336"
var statusStreaming   = "#4FC3F7"
var primaryFallback  = "#2196F3"

function connectionStatusColor(connectionState, hasUnread, colorMPrimary, colorMOutline) {
  if (hasUnread)
    return (colorMPrimary !== undefined) ? colorMPrimary : primaryFallback
  if (connectionState === "connected") return statusConnected
  if (connectionState === "connecting") return statusConnecting
  if (connectionState === "error") return statusError
  return colorMOutline
}
