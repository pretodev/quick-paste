import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

Item {
  id: root

  property var bar: null
  property var anchorItem: null
  property var hostWidget: null
  property bool opened: false
  property int selectedIndex: -1
  property var history: []
  property var loadedHistory: []
  property var legacyHistory: []
  property bool historyLoaded: false
  property bool legacyLoaded: false
  property bool ownHistoryExists: false
  property bool initReady: false
  property bool initialized: false
  property bool captureStarted: false
  property string suppressKey: ""
  property double clockNow: Date.now()

  readonly property int historyLimit: 300
  readonly property string stateRoot: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy"
  readonly property string historyPath: stateRoot + "/qick-paste-history.json"
  readonly property string legacyHistoryPath: stateRoot + "/clipboard-history.json"
  readonly property string captureScript: localPath("capture.sh")
  readonly property string pasteScript: localPath("paste.sh")
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property bool captureOwner: anchorWindow && Quickshell.screens.length > 0
    && anchorWindow.screen === Quickshell.screens[0]

  function localPath(name) {
    var value = String(Qt.resolvedUrl(name))
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function open(payloadJson) {
    selectedIndex = -1
    rebuildDisplay()
    opened = true
    if (bar && typeof bar.requestPopout === "function") bar.requestPopout(hostWidget || root)
    Qt.callLater(function() {
      resultList.positionViewAtBeginning()
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    opened = false
    selectedIndex = -1
    if (bar && bar.activePopout === (hostWidget || root) && typeof bar.releasePopout === "function")
      bar.releasePopout(hostWidget || root)
  }

  function toggle(payloadJson) {
    if (opened) close()
    else open(payloadJson || "{}")
  }

  function maybeInitialize() {
    if (initialized || !initReady || !historyLoaded || !legacyLoaded) return
    initialized = true
    history = ownHistoryExists
      ? loadedHistory
      : ClipboardHistory.importLegacy([], legacyHistory, historyLimit)
    rebuildDisplay()
    if (!ownHistoryExists && history.length > 0 && captureOwner) saveHistory()
    if (captureOwner) startWatchers()
  }

  function startWatchers() {
    if (!currentProc.running) currentProc.running = true
    if (!textWatchProc.running) textWatchProc.running = true
    if (!imageWatchProc.running) imageWatchProc.running = true
  }

  function syncCaptureOwner() {
    if (captureOwner) {
      if (captureStarted) return
      captureStarted = true
      reapProc.running = true
    } else {
      textWatchProc.running = false
      imageWatchProc.running = false
      captureStarted = false
      initReady = true
      maybeInitialize()
    }
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(history.slice(0, historyLimit), null, 2) + "\n")
  }

  function normalizedAppId(value) {
    var result = String(value || "").toLowerCase()
    if (result.slice(-8) === ".desktop") result = result.slice(0, -8)
    return result
  }

  function sourceMetadata() {
    var toplevel = ToplevelManager.activeToplevel
    var appId = toplevel ? String(toplevel.appId || "") : ""
    var normalized = normalizedAppId(appId)
    var values = DesktopEntries.applications.values || []
    var best = null
    for (var i = 0; normalized && i < values.length; i++) {
      var entry = values[i]
      var entryId = normalizedAppId(entry && entry.id)
      if (!entryId) continue
      if (entryId === normalized || entryId.slice(-(normalized.length + 1)) === "." + normalized
          || normalized.slice(-(entryId.length + 1)) === "." + entryId) {
        best = entry
        break
      }
    }
    return {
      sourceAppId: appId,
      sourceName: best ? String(best.name || best.id || appId) : appId,
      sourceIcon: best ? String(best.icon || "") : ""
    }
  }

  function addClipboardJson(line) {
    var entry
    try { entry = ClipboardHistory.normalizeEntry(JSON.parse(String(line || "").trim())) }
    catch (error) { entry = null }
    if (!entry) return

    var key = ClipboardHistory.entryKey(entry)
    if (suppressKey && key === suppressKey) {
      suppressKey = ""
      return
    }

    var source = sourceMetadata()
    entry.capturedAt = Date.now()
    entry.sourceAppId = source.sourceAppId
    entry.sourceName = source.sourceName
    entry.sourceIcon = source.sourceIcon
    history = ClipboardHistory.addEntry(history, entry, historyLimit)
    saveHistory()
    rebuildDisplay()
  }

  function rebuildDisplay() {
    displayModel.clear()
    for (var i = 0; i < history.length; i++) {
      var entry = ClipboardHistory.normalizeEntry(history[i])
      if (!entry) continue
      displayModel.append({
        entryType: entry.type,
        previewText: entry.type === "text" ? entry.text : "",
        previewImage: entry.type === "image" ? Util.fileUrl(entry.path) : "",
        capturedAt: String(entry.capturedAt || 0),
        sourceAppId: entry.sourceAppId || "",
        sourceName: entry.sourceName || "",
        sourceIcon: entry.sourceIcon || "",
        characterCount: entry.type === "text" ? ClipboardHistory.characterCount(entry.text) : 0,
        historyIndex: i
      })
    }
    if (selectedIndex >= displayModel.count) selectedIndex = -1
  }

  function selectIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    selectedIndex = index
    resultList.positionViewAtIndex(index, ListView.Contain)
  }

  function moveSelection(delta) {
    if (displayModel.count === 0) return
    if (selectedIndex < 0) selectIndex(delta < 0 ? displayModel.count - 1 : 0)
    else selectIndex((selectedIndex + delta + displayModel.count) % displayModel.count)
  }

  function scrollHistory(event) {
    var pixelX = event.pixelDelta ? event.pixelDelta.x : 0
    var pixelY = event.pixelDelta ? event.pixelDelta.y : 0
    var angleX = event.angleDelta ? event.angleDelta.x : 0
    var angleY = event.angleDelta ? event.angleDelta.y : 0
    var pixelDelta = pixelY !== 0 ? pixelY : pixelX
    var angleDelta = angleY !== 0 ? angleY : angleX
    var delta = pixelDelta !== 0 ? pixelDelta : angleDelta
    var maximumX = Math.max(0, resultList.contentWidth - resultList.width)
    resultList.contentX = Math.max(0, Math.min(maximumX, resultList.contentX - delta))
    event.accepted = true
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    var entry = history[row.historyIndex]
    suppressKey = ClipboardHistory.entryKey(entry)
    close()
    Quickshell.execDetached([pasteScript, String(row.historyIndex)])
  }

  function appIconSource(icon) {
    var value = String(icon || "")
    if (bar && bar.shell && bar.shell.appLibrary)
      return bar.shell.appLibrary.iconSource(value)
    return Quickshell.iconPath(value || "application-x-executable", true)
  }

  function ageText(value) {
    return ClipboardHistory.relativeTime(Number(value), clockNow)
  }

  Component.onCompleted: syncCaptureOwner()
  onCaptureOwnerChanged: syncCaptureOwner()

  ListModel {
    id: displayModel
    dynamicRoles: true
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.clockNow = Date.now()
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.loadedHistory = ClipboardHistory.parseHistory(text())
      root.ownHistoryExists = true
      root.historyLoaded = true
      if (root.initialized) {
        root.history = root.loadedHistory
        root.rebuildDisplay()
      } else root.maybeInitialize()
    }
    onLoadFailed: {
      root.loadedHistory = []
      root.ownHistoryExists = false
      root.historyLoaded = true
      root.maybeInitialize()
    }
    onFileChanged: reload()
  }

  FileView {
    path: root.legacyHistoryPath
    printErrors: false
    onLoaded: {
      root.legacyHistory = ClipboardHistory.parseHistory(text())
      root.legacyLoaded = true
      root.maybeInitialize()
    }
    onLoadFailed: {
      root.legacyHistory = []
      root.legacyLoaded = true
      root.maybeInitialize()
    }
  }

  Process {
    id: reapProc
    command: ["pkill", "-f", "wl-paste .*--watch .*qick-paste.*/capture\\.sh"]
    onExited: initProc.running = true
  }

  Process {
    id: initProc
    command: ["bash", root.captureScript, "--init"]
    onExited: {
      root.initReady = true
      if (root.initialized && root.captureOwner) root.startWatchers()
      else root.maybeInitialize()
    }
  }

  Process {
    id: currentProc
    command: ["bash", root.captureScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    onExited: if (root.initialized) watchRestartTimer.restart()
    stdout: SplitParser { onRead: function(data) { root.addClipboardJson(data) } }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
    onExited: if (root.initialized) watchRestartTimer.restart()
    stdout: SplitParser { onRead: function(data) { root.addClipboardJson(data) } }
  }

  Timer {
    id: watchRestartTimer
    interval: 1000
    onTriggered: {
      if (!textWatchProc.running) textWatchProc.running = true
      if (!imageWatchProc.running) imageWatchProc.running = true
    }
  }

  PanelWindow {
    id: panel
    screen: root.anchorWindow ? root.anchorWindow.screen : null
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; right: true; bottom: true; left: true }

    WlrLayershell.namespace: "qick-paste"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: sheet
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Math.min(Style.space(360), panel.height * 0.42)
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

      Item {
        id: keyCatcher
        anchors.fill: parent
        anchors.topMargin: sheet.contentTopInset
        anchors.rightMargin: sheet.contentRightInset
        anchors.bottomMargin: sheet.contentBottomInset
        anchors.leftMargin: sheet.contentLeftInset
        focus: true
        z: 2

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.moveSelection(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.moveSelection(1)
            event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.selectedIndex >= 0) {
            root.activateIndex(root.selectedIndex)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: sheet.contentTopInset
        anchors.rightMargin: sheet.contentRightInset
        anchors.bottomMargin: sheet.contentBottomInset
        anchors.leftMargin: sheet.contentLeftInset
        spacing: Style.spacing.md

        Row {
          width: parent.width
          height: Style.space(34)

          Text {
            width: parent.width - countLabel.width
            anchors.verticalCenter: parent.verticalCenter
            text: "Área de transferência"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
          }

          Text {
            id: countLabel
            anchors.verticalCenter: parent.verticalCenter
            text: displayModel.count + (displayModel.count === 1 ? " item" : " itens")
            color: Color.menu.text
            opacity: 0.55
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          width: parent.width
          height: parent.height - y
          clip: true

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            orientation: ListView.Horizontal
            spacing: Style.space(12)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            WheelHandler {
              onWheel: function(event) { root.scrollHistory(event) }
            }

            delegate: BorderSurface {
              id: card
              required property int index
              required property string entryType
              required property string previewText
              required property string previewImage
              required property string capturedAt
              required property string sourceAppId
              required property string sourceName
              required property string sourceIcon
              required property int characterCount
              required property int historyIndex

              readonly property bool selected: root.selectedIndex === index
              width: Math.min(Style.space(292), resultList.width * 0.78)
              height: resultList.height
              radius: Style.cornerRadius
              color: selected ? Color.menu.selectedBackground : Util.alpha(Color.menu.text, 0.035)
              borderSpec: selected
                ? Border.flat(Color.menu.selectedText, Math.max(1, Style.space(2)))
                : Border.surfaceSpec("menu", "border", Util.alpha(Color.menu.border, 0.45), Math.max(1, Style.normalBorderWidth))
              padding: Style.space(14)

              Column {
                anchors.fill: parent
                anchors.topMargin: card.contentTopInset
                anchors.rightMargin: card.contentRightInset
                anchors.bottomMargin: card.contentBottomInset
                anchors.leftMargin: card.contentLeftInset
                spacing: Style.space(10)

                Row {
                  width: parent.width
                  height: Style.space(38)
                  spacing: Style.space(8)

                  Image {
                    width: Style.space(30)
                    height: width
                    anchors.verticalCenter: parent.verticalCenter
                    source: root.appIconSource(card.sourceIcon)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                  }

                  Column {
                    width: parent.width - parent.spacing - Style.space(38)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      text: card.sourceName || card.sourceAppId || "Aplicativo desconhecido"
                      color: card.selected ? Color.menu.selectedText : Color.menu.text
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.body
                      font.weight: Font.DemiBold
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: (card.entryType === "image" ? "Imagem" : "Texto") + " · " + root.ageText(card.capturedAt)
                      color: card.selected ? Color.menu.selectedText : Color.menu.text
                      opacity: 0.58
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }

                Item {
                  width: parent.width
                  height: parent.height - y - footer.height - parent.spacing
                  clip: true

                  Text {
                    visible: card.entryType === "text"
                    anchors.fill: parent
                    textFormat: Text.PlainText
                    text: card.previewText
                    color: card.selected ? Color.menu.selectedText : Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.title
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideRight
                    maximumLineCount: Math.max(1, Math.floor(height / (font.pixelSize * 1.25)))
                  }

                  Image {
                    id: preview
                    visible: card.entryType === "image"
                    anchors.fill: parent
                    source: card.previewImage
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                  }
                }

                Text {
                  id: footer
                  width: parent.width
                  text: card.entryType === "image"
                    ? (preview.sourceSize.width > 0 ? preview.sourceSize.width + " × " + preview.sourceSize.height + " px" : "Imagem")
                    : card.characterCount + (card.characterCount === 1 ? " caractere" : " caracteres")
                  color: card.selected ? Color.menu.selectedText : Color.menu.text
                  opacity: 0.55
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onWheel: function(event) { root.scrollHistory(event) }
                onClicked: {
                  if (root.selectedIndex === card.index) root.activateIndex(card.index)
                  else root.selectIndex(card.index)
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            visible: displayModel.count === 0
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "󰅌"
              color: Color.menu.text
              opacity: 0.7
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              text: "A área de transferência está vazia"
              color: Color.menu.text
              opacity: 0.65
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
            }
          }
        }
      }
    }
  }
}
