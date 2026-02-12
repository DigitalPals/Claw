import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Widgets
import "lib/commands.js" as Commands

Item {
  id: root

  // Props
  property bool isSending: false

  // Pending image state (owned here, readable from outside)
  property string pendingImageBase64: ""
  property string pendingImageMediaType: ""

  // Signals
  signal sendRequested(string text)
  signal clearPendingImageRequested()

  // Computed
  readonly property bool hasImage: root.pendingImageBase64.length > 0
  readonly property string composerText: (composerInput.text || "").trim()

  function clearComposer() {
    composerInput.text = ""
    rebuildCommandSuggestions("")
  }

  function clearPendingImage() {
    root.pendingImageBase64 = ""
    root.pendingImageMediaType = ""
  }

  // Clipboard image capture state
  property bool isCapturingClipboard: false
  property string _clipboardTypes: ""

  // Slash command menu state
  property bool commandMenuOpen: false
  property int commandSelectedIndex: 0

  // Command suggestions for the autocomplete dropdown.
  readonly property var commands: ([
    { name: "new", template: "/new", hasArgs: false, usage: "", rank: 10, description: "Reset session / start new chat." },
    { name: "help", template: "/help", hasArgs: false, usage: "", rank: 20, description: "Show available commands." },
    { name: "status", template: "/status", hasArgs: false, usage: "", rank: 30, description: "Show current status and provider usage." },
    { name: "think", template: "/think ", hasArgs: true, usage: "off|minimal|low|medium|high|xhigh", rank: 40, description: "Set reasoning depth." },
    { name: "model", template: "/model ", hasArgs: true, usage: "<name>", rank: 50, description: "Select LLM provider/model." },
    { name: "usage", template: "/usage ", hasArgs: true, usage: "off|tokens|full|cost", rank: 60, description: "Control per-response usage footer." },
    { name: "stop", template: "/stop", hasArgs: false, usage: "", rank: 70, description: "Stop current operation." },
    { name: "compact", template: "/compact", hasArgs: false, usage: "", rank: 80, description: "Compact message history." },
    { name: "verbose", template: "/verbose ", hasArgs: true, usage: "on|full|off", rank: 90, description: "Control verbosity." },
    { name: "settings", template: "/settings", hasArgs: false, usage: "", rank: 200, description: "[Local] Toggle the in-panel settings." },
    { name: "channels", template: "/channels", hasArgs: false, usage: "", rank: 210, description: "[Local] Navigate to channels view." },
    { name: "abort", template: "/abort", hasArgs: false, usage: "", rank: 220, description: "[Local] Abort active response." },
    { name: "agent", template: "/agent ", hasArgs: true, usage: "<id>", rank: 230, description: "[Local] Set agent id for routing." }
  ])

  ListModel { id: commandSuggestionsModel }

  // Clipboard type detection process
  Process {
    id: clipboardTypeProcess
    command: ["wl-paste", "--list-types"]
    stdout: SplitParser {
      onRead: data => {
        root._clipboardTypes += data + "\n"
      }
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) {
        clipboardTimeoutTimer.stop()
        root.isCapturingClipboard = false
        return
      }
      var types = root._clipboardTypes.trim().split("\n")
      var imageType = ""
      for (var i = 0; i < types.length; i++) {
        var t = types[i].trim()
        if (t === "image/png" || t === "image/jpeg" || t === "image/gif" || t === "image/webp") {
          imageType = t
          break
        }
      }
      if (imageType) {
        if (clipboardImageProcess.running) {
          clipboardTimeoutTimer.stop()
          root.isCapturingClipboard = false
          return
        }
        root.pendingImageMediaType = imageType
        root.pendingImageBase64 = ""
        clipboardImageProcess.command = ["bash", "-c", "wl-paste --type '" + imageType + "' | base64 -w0"]
        clipboardImageProcess.running = true
      } else {
        clipboardTimeoutTimer.stop()
        root.isCapturingClipboard = false
      }
    }
  }

  // Clipboard image capture process (base64)
  Process {
    id: clipboardImageProcess
    stdout: SplitParser {
      onRead: data => {
        root.pendingImageBase64 += data
        // Abort if base64 data exceeds ~10 MB (decoded)
        if (root.pendingImageBase64.length > 14000000) {
          console.warn("[Claw] Clipboard image too large, aborting capture")
          clipboardImageProcess.running = false
          root.pendingImageBase64 = ""
          root.pendingImageMediaType = ""
        }
      }
    }
    onExited: (exitCode, exitStatus) => {
      clipboardTimeoutTimer.stop()
      root.isCapturingClipboard = false
      if (exitCode !== 0) {
        root.pendingImageBase64 = ""
        root.pendingImageMediaType = ""
      }
    }
  }

  // Clipboard capture timeout (10s)
  Timer {
    id: clipboardTimeoutTimer
    interval: 10000
    repeat: false
    onTriggered: {
      console.warn("[Claw] Clipboard capture timed out")
      clipboardTypeProcess.running = false
      clipboardImageProcess.running = false
      root.isCapturingClipboard = false
      root.pendingImageBase64 = ""
      root.pendingImageMediaType = ""
    }
  }

  function tryPasteImage() {
    if (root.isCapturingClipboard)
      return
    root.isCapturingClipboard = true
    root._clipboardTypes = ""
    clipboardTimeoutTimer.start()
    clipboardTypeProcess.running = true
  }

  function rebuildCommandSuggestions(text) {
    if (!Commands.commandShouldOpen(text)) {
      root.commandMenuOpen = false
      commandSuggestionsModel.clear()
      root.commandSelectedIndex = 0
      return
    }

    var q = text.substring(1).toLowerCase()
    var candidates = []

    for (var i = 0; i < root.commands.length; i++) {
      var c = root.commands[i]
      if (!q || c.name.indexOf(q) === 0)
        candidates.push(c)
    }

    candidates.sort(function(a, b) {
      if (a.rank !== b.rank)
        return a.rank - b.rank
      if (a.name < b.name) return -1
      if (a.name > b.name) return 1
      return 0
    })

    commandSuggestionsModel.clear()
    for (var j = 0; j < candidates.length; j++) {
      var x = candidates[j]
      commandSuggestionsModel.append({
        name: x.name,
        template: x.template,
        hasArgs: x.hasArgs,
        usage: x.usage,
        description: x.description
      })
    }

    root.commandMenuOpen = (commandSuggestionsModel.count > 0)
    if (root.commandSelectedIndex >= commandSuggestionsModel.count)
      root.commandSelectedIndex = 0
  }

  function insertSelectedCommand() {
    if (!root.commandMenuOpen || commandSuggestionsModel.count < 1)
      return
    var idx = root.commandSelectedIndex
    if (idx < 0 || idx >= commandSuggestionsModel.count)
      idx = 0
    var row = commandSuggestionsModel.get(idx)
    composerInput.text = row.template
    if (composerInput.cursorPosition !== undefined)
      composerInput.cursorPosition = composerInput.text.length

    if (!row.hasArgs) {
      root.commandMenuOpen = false
      commandSuggestionsModel.clear()
      root.commandSelectedIndex = 0
    } else {
      rebuildCommandSuggestions(composerInput.text)
    }
  }

  function handleComposerKey(event) {
    // Ctrl+V: try to capture image from clipboard (in addition to normal text paste)
    if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
      tryPasteImage()
      return
    }

    if (!root.commandMenuOpen) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (event.modifiers & Qt.ShiftModifier)
          return
        performSend()
        event.accepted = true
      }
      return
    }

    if (event.key === Qt.Key_Escape) {
      root.commandMenuOpen = false
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Down) {
      root.commandSelectedIndex = Math.min(root.commandSelectedIndex + 1, commandSuggestionsModel.count - 1)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Up) {
      root.commandSelectedIndex = Math.max(root.commandSelectedIndex - 1, 0)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_PageDown) {
      root.commandSelectedIndex = Math.min(root.commandSelectedIndex + 5, commandSuggestionsModel.count - 1)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_PageUp) {
      root.commandSelectedIndex = Math.max(root.commandSelectedIndex - 5, 0)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      insertSelectedCommand()
      event.accepted = true
      return
    }
  }

  function performSend() {
    if (root.isSending)
      return

    var text = composerText
    if (!text && !root.hasImage)
      return

    root.sendRequested(text)
  }

  implicitHeight: composerColumn.implicitHeight

  ColumnLayout {
    id: composerColumn
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.marginM

    // Image preview strip
    Rectangle {
      Layout.fillWidth: true
      visible: root.hasImage
      color: Color.mSurfaceVariant
      radius: Style.radiusM
      implicitHeight: imagePreviewRow.implicitHeight + Style.marginS * 2

      RowLayout {
        id: imagePreviewRow
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginM

        Image {
          Layout.preferredWidth: 80 * Style.uiScaleRatio
          Layout.preferredHeight: 80 * Style.uiScaleRatio
          source: root.pendingImageBase64
            ? ("data:" + root.pendingImageMediaType + ";base64," + root.pendingImageBase64)
            : ""
          fillMode: Image.PreserveAspectFit
          sourceSize.width: 160
          sourceSize.height: 160
        }

        NText {
          text: {
            var sizeBytes = Math.ceil(root.pendingImageBase64.length * 3 / 4)
            if (sizeBytes < 1024) return sizeBytes + " B"
            if (sizeBytes < 1048576) return Math.round(sizeBytes / 1024) + " KB"
            return (sizeBytes / 1048576).toFixed(1) + " MB"
          }
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeS
        }

        Item { Layout.fillWidth: true }

        NIconButton {
          icon: "x"
          onClicked: {
            root.clearPendingImage()
            root.clearPendingImageRequested()
          }
        }
      }
    }

    // Footer composer
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      Control {
        id: composerArea
        Layout.fillWidth: true
        implicitHeight: Math.min(
          composerScroll.contentHeight,
          150 * Style.uiScaleRatio
        )

        focusPolicy: Qt.StrongFocus

        background: Rectangle {
          radius: Style.iRadiusM
          color: Color.mSurface
          border.color: composerInput.activeFocus ? Color.mSecondary : Color.mOutline
          border.width: Style.borderS
          Behavior on border.color {
            ColorAnimation { duration: Style.animationFast }
          }
        }

        contentItem: Flickable {
          id: composerScroll
          clip: true
          contentWidth: width
          contentHeight: composerInput.implicitHeight
          flickableDirection: Flickable.VerticalFlick
          boundsBehavior: Flickable.StopAtBounds

          function ensureCursorVisible() {
            var cursorRect = composerInput.cursorRectangle;
            var cy = cursorRect.y;
            var ch = cursorRect.height;
            if (cy < contentY) contentY = cy;
            else if (cy + ch > contentY + height) contentY = cy + ch - height;
          }

          TextArea {
            id: composerInput
            width: composerScroll.width
            wrapMode: TextEdit.Wrap
            placeholderText: "Message..."
            enabled: !root.isSending

            color: Color.mOnSurface
            placeholderTextColor: Qt.alpha(Color.mOnSurfaceVariant, 0.6)
            selectionColor: Color.mSecondary
            selectedTextColor: Color.mOnSecondary
            font.family: Settings.data.ui.fontDefault
            font.pointSize: Style.fontSizeS * Style.uiScaleRatio
            font.weight: Style.fontWeightRegular

            padding: Style.marginM
            background: null

            onTextChanged: rebuildCommandSuggestions(text)
            Keys.onPressed: handleComposerKey(event)
            onCursorRectangleChanged: composerScroll.ensureCursorVisible()
          }
        }

        // Slash command dropdown
        Rectangle {
          id: commandMenu
          visible: root.commandMenuOpen && commandSuggestionsModel.count > 0
          width: composerArea.width
          height: visible
            ? Math.min(240 * Style.uiScaleRatio, Math.max(48 * Style.uiScaleRatio, commandList.contentHeight + Style.marginS * 2))
            : 0
          radius: Style.radiusM
          color: Color.mSurface
          border.width: 1
          border.color: Color.mOutlineVariant !== undefined ? Color.mOutlineVariant : Color.mOutline
          clip: true
          z: 1000

          anchors.left: composerArea.left
          anchors.bottom: composerArea.top
          anchors.bottomMargin: Style.marginS

          ListView {
            id: commandList
            anchors.fill: parent
            anchors.margins: Style.marginS
            model: commandSuggestionsModel
            clip: true
            currentIndex: root.commandSelectedIndex
            onCurrentIndexChanged: root.commandSelectedIndex = currentIndex

            delegate: Rectangle {
              width: ListView.view.width
              height: cmdRow.implicitHeight + Style.marginS
              radius: Style.radiusS
              color: (index === root.commandSelectedIndex)
                ? (Color.mSecondaryContainer !== undefined ? Color.mSecondaryContainer : Color.mSurfaceVariant)
                : "transparent"

              RowLayout {
                id: cmdRow
                anchors.fill: parent
                anchors.margins: Style.marginS
                spacing: Style.marginM

                NText {
                  text: "/" + model.name
                  color: Color.mOnSurface
                  font.weight: Font.DemiBold
                  pointSize: Style.fontSizeM
                }

                NText {
                  text: model.usage ? model.usage : ""
                  color: Color.mOnSurfaceVariant
                  pointSize: Style.fontSizeS
                  visible: !!model.usage
                }

                Item { Layout.fillWidth: true }

                NText {
                  text: model.description
                  color: Color.mOnSurfaceVariant
                  pointSize: Style.fontSizeS
                  elide: Text.ElideRight
                  Layout.maximumWidth: 320 * Style.uiScaleRatio
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.commandSelectedIndex = index
                  insertSelectedCommand()
                }
              }
            }
          }
        }
      }

      NButton {
        text: "Send"
        enabled: !root.isSending && root.composerText.length > 0
        onClicked: root.performSend()
      }
    }
  }
}
