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

  function setStatus(state, errorText) {
    root.connectionState = state || "idle"
    root.lastErrorText = errorText || ""
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
