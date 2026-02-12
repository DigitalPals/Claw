.pragma library

// Channel icon and label mappings extracted from Main.qml.

var channelIconMap = {
  "main":       "terminal-2",
  "webchat":    "world",
  "slack":      "brand-slack",
  "whatsapp":   "brand-whatsapp",
  "telegram":   "brand-telegram",
  "discord":    "brand-discord",
  "messenger":  "brand-messenger",
  "instagram":  "brand-instagram",
  "sms":        "message-2",
  "email":      "mail",
  "voice":      "phone",
  "twitter":    "brand-twitter",
  "x":          "brand-twitter",
  "teams":      "brand-teams",
  "line":       "brand-line",
  "wechat":     "brand-wechat",
  "signal":     "brand-signal",
  "viber":      "brand-viber",
  "skype":      "brand-skype",
  "facebook":   "brand-facebook",
  "twitch":     "brand-twitch",
  "youtube":    "brand-youtube",
  "reddit":     "brand-reddit",
  "tiktok":     "brand-tiktok"
}

var channelLabelMap = {
  "main":       "Main (Direct)",
  "webchat":    "Web Chat",
  "slack":      "Slack",
  "whatsapp":   "WhatsApp",
  "telegram":   "Telegram",
  "discord":    "Discord",
  "messenger":  "Messenger",
  "instagram":  "Instagram",
  "sms":        "SMS",
  "email":      "Email",
  "voice":      "Voice",
  "twitter":    "Twitter",
  "x":          "X (Twitter)",
  "teams":      "Microsoft Teams",
  "line":       "LINE",
  "wechat":     "WeChat",
  "signal":     "Signal",
  "viber":      "Viber",
  "skype":      "Skype",
  "facebook":   "Facebook",
  "twitch":     "Twitch",
  "youtube":    "YouTube",
  "reddit":     "Reddit",
  "tiktok":     "TikTok"
}

function resolveChannelIcon(channelId) {
  if (channelIconMap[channelId])
    return channelIconMap[channelId]
  return "message-circle"
}

function virtualChannelLabel(channelType) {
  return channelLabelMap[channelType]
    || (channelType.charAt(0).toUpperCase() + channelType.slice(1))
}
