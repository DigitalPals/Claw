import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  // Injected by PluginService
  property var pluginApi: null

  // idle | ok | error
  property string connectionState: "idle"
  property string lastErrorText: ""

  // Keep chat in memory across panel open/close.
  // The panel uses this model directly, so messages persist as long as the plugin main instance lives.
  property alias messagesModel: messagesModel

  function setStatus(state, errorText) {
    root.connectionState = state || "idle"
    root.lastErrorText = errorText || ""
  }

  function clearMessages() {
    messagesModel.clear()
  }

  function appendMessage(role, content) {
    messagesModel.append({
      role: role,
      content: content,
      ts: Date.now()
    })
    return messagesModel.count - 1
  }

  function setMessageContent(index, content) {
    if (index < 0 || index >= messagesModel.count)
      return
    messagesModel.setProperty(index, "content", content)
  }

  ListModel {
    id: messagesModel
  }

  // Optional IPC hook (best-effort). Without a screen reference, it can't reliably open a panel,
  // so this is just a stub target for future expansion.
  IpcHandler {
    target: "plugin:claw"

    function ping() {
      return {
        ok: true,
        connectionState: root.connectionState,
        lastErrorText: root.lastErrorText
      }
    }
  }
}
