.pragma library

// Shared settings helpers used by Main.qml, Panel.qml, and Settings.qml.

function pickSetting(pluginApi, key, fallback) {
  if (pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings[key] !== undefined)
    return pluginApi.pluginSettings[key]
  if (pluginApi && pluginApi.manifest && pluginApi.manifest.metadata
      && pluginApi.manifest.metadata.defaultSettings
      && pluginApi.manifest.metadata.defaultSettings[key] !== undefined)
    return pluginApi.manifest.metadata.defaultSettings[key]
  return fallback
}

function loadEditableSettings(pluginApi) {
  return {
    wsUrl: pickSetting(pluginApi, "wsUrl", "ws://127.0.0.1:18789"),
    token: pickSetting(pluginApi, "token", ""),
    agentId: pickSetting(pluginApi, "agentId", "main"),
    autoReconnect: !!pickSetting(pluginApi, "autoReconnect", true),
    notifyOnResponse: !!pickSetting(pluginApi, "notifyOnResponse", true),
    notifyOnlyWhenAppInactive: !!pickSetting(pluginApi, "notifyOnlyWhenAppInactive", true)
  }
}
