import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory
import "I18n.js" as I18n

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
  property var nativeHistory: []
  property bool nativeHistoryValid: false
  property bool historyLoaded: false
  property bool legacyLoaded: false
  property bool initialized: false
  property double clockNow: Date.now()
  property var pasteTarget: null
  property bool contextMenuOpen: false
  property bool dragInProgress: false
  property bool displayRefreshPending: false
  property bool clearHistoryConfirmationOpen: false
  property int contextMenuIndex: -1
  property real contextMenuX: 0
  property real contextMenuY: 0

  readonly property int historyLimit: 300
  readonly property string stateRoot: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy"
  readonly property string historyPath: stateRoot + "/qick-paste-history.json"
  readonly property string legacyHistoryPath: stateRoot + "/clipboard-history.json"
  readonly property string captureScript: localPath("../scripts/capture.sh")
  readonly property string pasteScript: localPath("../scripts/paste.sh")
  readonly property string fileActionScript: localPath("../scripts/file-action.sh")
  readonly property string editScript: localPath("../scripts/edit-in-tensaku.sh")
  readonly property string removeLegacyImageScript: localPath("../scripts/remove-legacy-image.py")
  readonly property string prepareDragSourceScript: localPath("../scripts/prepare-drag-source.py")
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string pasteTargetName: appName(pasteTarget)
  readonly property string localeName: Qt.locale().name

  function tr(key, values) { return I18n.tr(localeName, key, values) }
  function count(oneKey, manyKey, value) { return I18n.count(localeName, oneKey, manyKey, value) }

  function localPath(name) {
    var value = String(Qt.resolvedUrl(name))
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function displayDirectoryPath(path) {
    var home = Quickshell.env("HOME")
    if (home && path === home) return "~"
    if (home && path.indexOf(home + "/") === 0) return "~" + path.substring(home.length)
    return path
  }

  function open(payloadJson) {
    if (dragInProgress) return
    pasteTarget = ToplevelManager.activeToplevel
    searchField.text = ""
    selectedIndex = -1
    rebuildDisplay()
    opened = true
    if (bar && typeof bar.requestPopout === "function") bar.requestPopout(hostWidget || root)
    initialPositionReset.restart()
  }

  function resetInitialPosition() {
    if (!opened || dragInProgress) return
    resultList.cancelFlick()
    resultList.forceLayout()
    resultList.positionViewAtBeginning()
    resultList.contentX = resultList.originX
  }

  function close() {
    // QDrag runs a nested event loop; keep its source window alive until it returns.
    if (dragInProgress) return
    clearHistoryConfirmationOpen = false
    closeContextMenu()
    opened = false
    selectedIndex = -1
    if (bar && bar.activePopout === (hostWidget || root) && typeof bar.releasePopout === "function")
      bar.releasePopout(hostWidget || root)
  }

  function dragMimeData(historyIndex, imagePath) {
    var entry = history[historyIndex]
    if (!entry) return ({})
    if (entry.type === "text") return ({ "text/plain": entry.text })
    var paths = entry.type === "image" ? (imagePath ? [imagePath] : []) : entry.paths
    if (!paths || !paths.length) return ({})
    return ({ "text/uri-list": paths.map(Util.fileUrl).join("\r\n") + "\r\n" })
  }

  function dragPrepareCommand(historyIndex) {
    var entry = history[historyIndex]
    if (!entry || entry.type === "text") return []
    if (entry.type === "image")
      return ["python3", prepareDragSourceScript, entry.path, entry.mime]
    return ["python3", prepareDragSourceScript, "--files", JSON.stringify(entry.paths)]
  }

  function toggle(payloadJson) {
    if (opened) close()
    else open(payloadJson || "{}")
  }

  function maybeInitialize() {
    if (initialized || !historyLoaded || !legacyLoaded) return
    initialized = true
    history = ClipboardHistory.importLegacy(loadedHistory, legacyHistory, historyLimit)
    rebuildDisplay()
    if (JSON.stringify(history) !== JSON.stringify(loadedHistory)) saveHistory()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(history.slice(0, historyLimit), null, 2) + "\n")
  }

  function addCapturedJson(raw) {
    try {
      var entry = ClipboardHistory.normalizeEntry(JSON.parse(String(raw || "").trim()))
      if (!entry) return
      entry.capturedAt = Date.now()
      var source = ToplevelManager.activeToplevel
      entry.sourceAppId = source ? String(source.appId || "") : ""
      entry.sourceName = appName(source)
      entry.sourceIcon = entry.sourceAppId
      history = ClipboardHistory.addEntry(history, entry, historyLimit)
      saveHistory()
      if (opened) rebuildDisplay()
    } catch (error) {}
  }

  function rebuildDisplay() {
    // Clearing the model destroys the delegate that owns an active QDrag.
    if (dragInProgress) {
      displayRefreshPending = true
      return
    }
    displayRefreshPending = false
    displayModel.clear()
    for (var i = 0; i < history.length; i++) {
      var entry = ClipboardHistory.normalizeEntry(history[i])
      if (!entry || !ClipboardHistory.matchesSearch(entry, searchField.text)) continue
      var linkTarget = entry.type === "text" ? ClipboardHistory.webUrl(entry.text) : ""
      if (!linkTarget && entry.linkPreview)
        linkTarget = ClipboardHistory.webUrl(entry.linkPreview.url)
      var fileTitle = ""
      var homePaths = true
      if (entry.type === "file") {
        var fileNames = []
        var home = Quickshell.env("HOME")
        for (var p = 0; p < entry.paths.length; p++) {
          var path = entry.paths[p]
          var segments = path.split("/")
          fileNames.push(segments[segments.length - 1] || segments[segments.length - 2] || "/")
          if (path !== home && path.indexOf(home + "/") !== 0) homePaths = false
        }
        fileTitle = fileNames.length === 1 ? fileNames[0] : tr("files")
      }
      displayModel.append({
        entryType: entry.type,
        previewText: entry.type === "text" ? entry.text : "",
        previewImage: entry.type === "image" ? Util.fileUrl(entry.path) : "",
        fileTitle: fileTitle,
        fileCount: entry.type === "file" ? entry.paths.length : 0,
        isDirectory: entry.type === "file" && entry.isDirectory === true,
        directoryPath: entry.type === "file" && entry.isDirectory === true
          ? displayDirectoryPath(entry.paths[0]) : "",
        homePaths: homePaths,
        isLink: entry.type === "text" && (!!entry.linkPreview || !!linkTarget),
        linkTarget: linkTarget,
        linkDescription: entry.linkPreview ? entry.linkPreview.description : "",
        linkImage: entry.linkPreview ? entry.linkPreview.image : "",
        linkUrl: entry.linkPreview ? entry.linkPreview.url : "",
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

  function updateSearch() {
    selectedIndex = -1
    rebuildDisplay()
    if (searchField.text.trim().length && displayModel.count > 0) selectIndex(0)
    resetInitialPosition()
  }

  function selectIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    selectedIndex = index
    resultList.positionViewAtIndex(index, ListView.Contain)
  }

  function openContextMenu(card, index, mouseX, mouseY) {
    if (index < 0 || index >= displayModel.count) return
    selectIndex(index)
    contextMenuIndex = index
    contextMenuOpen = true
    var point = card.mapToItem(menuLayer, mouseX, mouseY)
    contextMenuX = point.x
    contextMenuY = point.y
    Qt.callLater(function() { contextKeyCatcher.forceActiveFocus() })
  }

  function openSelectedContextMenu() {
    if (selectedIndex < 0 || selectedIndex >= displayModel.count) return false
    var card = resultList.itemAtIndex(selectedIndex)
    if (!card) return false
    openContextMenu(card, selectedIndex, card.width / 2, card.height / 2)
    return true
  }

  function closeContextMenu() {
    contextMenuOpen = false
    contextMenuIndex = -1
    if (opened) Qt.callLater(function() {
      if (opened) searchField.forceActiveFocus()
    })
  }

  function showClearHistoryConfirmation() {
    clearHistoryConfirmationOpen = true
    Qt.callLater(function() {
      if (clearHistoryConfirmationOpen) clearHistoryCancelButton.forceActiveFocus()
    })
  }

  function dismissClearHistoryConfirmation(confirmed) {
    clearHistoryConfirmationOpen = false
    if (confirmed) clearHistory()
    Qt.callLater(function() {
      if (opened && !clearHistoryConfirmationOpen) searchField.forceActiveFocus()
    })
  }

  function handleClearHistoryKey(event) {
    if (event.key === Qt.Key_Escape) {
      dismissClearHistoryConfirmation(false)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      dismissClearHistoryConfirmation(clearHistoryDeleteButton.activeFocus)
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
               || event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
      if (clearHistoryDeleteButton.activeFocus) clearHistoryCancelButton.forceActiveFocus()
      else clearHistoryDeleteButton.forceActiveFocus()
    }
    event.accepted = true
  }

  function handlePanelKey(event) {
    if (dragInProgress) return
    if (clearHistoryConfirmationOpen) {
      handleClearHistoryKey(event)
      return
    }
    if (event.key === Qt.Key_Escape) {
      close()
      event.accepted = true
    } else if (event.key === Qt.Key_Delete && event.modifiers === Qt.ShiftModifier) {
      if (history.length) showClearHistoryConfirmation()
      event.accepted = true
    } else if ((event.key === Qt.Key_Menu && event.modifiers === Qt.NoModifier)
               || (event.key === Qt.Key_F10 && event.modifiers === Qt.ShiftModifier)) {
      if (openSelectedContextMenu()) event.accepted = true
    } else if (event.key === Qt.Key_Left && event.modifiers === Qt.NoModifier) {
      moveSelection(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right && event.modifiers === Qt.NoModifier) {
      moveSelection(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Delete && selectedIndex >= 0
               && (!searchField.activeFocus || !searchField.text.length)) {
      removeIndex(selectedIndex)
      event.accepted = true
    } else if (handleFileShortcut(selectedIndex, event)) {
      event.accepted = true
    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
               && (event.modifiers & Qt.ControlModifier)
               && selectedIndex >= 0
               && !!displayModel.get(selectedIndex).linkTarget) {
      openLink(selectedIndex)
      event.accepted = true
    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && selectedIndex >= 0) {
      var row = displayModel.get(selectedIndex)
      if ((event.modifiers & Qt.ShiftModifier) && row.entryType === "text")
        pastePlainText(selectedIndex)
      else
        activateIndex(selectedIndex)
      event.accepted = true
    }
  }

  function moveSelection(delta) {
    if (displayModel.count === 0) return
    if (selectedIndex < 0) {
      selectIndex(0)
      return
    }
    selectIndex(Math.max(0, Math.min(displayModel.count - 1, selectedIndex + delta)))
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

  function activateIndex(index, plainText) {
    if (!pasteTarget || index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    if (plainText && row.entryType !== "text") return
    close()
    var command = [pasteScript, String(row.historyIndex)]
    if (plainText) command.push("--plain")
    Quickshell.execDetached(command)
  }

  function pastePlainText(index) {
    activateIndex(index, true)
  }

  function pasteFilePath(index, relativeHome) {
    if (!pasteTarget || index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    if (row.entryType !== "file" || row.fileCount !== 1 || (relativeHome && !row.homePaths)) return
    close()
    Quickshell.execDetached([pasteScript, String(row.historyIndex),
      relativeHome ? "--path-home" : "--path-absolute"])
  }

  function fileAction(index, mode) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    if (row.entryType !== "file" || row.fileCount !== 1 || (mode === "open" && row.isDirectory)) return
    close()
    Quickshell.execDetached([fileActionScript, String(row.historyIndex), mode])
  }

  function handleFileShortcut(index, event) {
    if (index < 0 || index >= displayModel.count) return false
    var row = displayModel.get(index)
    if (row.entryType !== "file") return false
    if (row.fileCount !== 1) return false
    if (event.key === Qt.Key_O && event.modifiers === Qt.ControlModifier) {
      if (row.isDirectory) return false
      fileAction(index, "open")
      return true
    }
    if (event.key === Qt.Key_O
        && event.modifiers === (Qt.ControlModifier | Qt.ShiftModifier)) {
      fileAction(index, "reveal")
      return true
    }
    if (!pasteTarget) return false
    if (event.key === Qt.Key_P && event.modifiers === Qt.ControlModifier) {
      pasteFilePath(index, false)
      return true
    }
    if (event.key === Qt.Key_P
        && event.modifiers === (Qt.ControlModifier | Qt.ShiftModifier)
        && row.homePaths) {
      pasteFilePath(index, true)
      return true
    }
    return false
  }

  function openLink(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    if (!row.linkTarget) return
    var url = row.linkTarget
    close()
    Util.execArgv(["omarchy", "launch", "browser", url])
  }

  function openInTensaku(index) {
    if (tensakuEdit.running || index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    if (row.entryType !== "image") return
    close()
    tensakuEdit.command = [editScript, String(row.historyIndex)]
    tensakuEdit.running = true
  }

  function removeIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    var entry = history[row.historyIndex]
    syncNativeHistory([entry])
    if (entry.type === "image" && !entry.imageHash)
      Quickshell.execDetached([removeLegacyImageScript, entry.path])
    history = ClipboardHistory.removeEntry(history, row.historyIndex)
    if (displayModel.count <= 1) selectedIndex = -1
    else if (selectedIndex >= displayModel.count - 1) selectedIndex = displayModel.count - 2
    else if (selectedIndex > index) selectedIndex--
    saveHistory()
    rebuildDisplay()
  }

  function clearHistory() {
    if (!history.length) return
    if (nativeHistoryValid) {
      nativeHistory = []
      nativeHistoryFile.setText("[]\n")
    }
    history = []
    selectedIndex = -1
    saveHistory()
    rebuildDisplay()
  }

  function syncNativeHistory(entries) {
    if (!nativeHistoryValid) return
    var updated = ClipboardHistory.removeNativeEntries(nativeHistory, entries)
    if (updated.length === nativeHistory.length) return
    nativeHistory = updated
    nativeHistoryFile.setText(JSON.stringify(updated, null, 2) + "\n")
  }

  function appIconSource(icon) {
    var value = String(icon || "")
    if (bar && bar.shell && bar.shell.appLibrary)
      return bar.shell.appLibrary.iconSource(value)
    return Quickshell.iconPath(value || "application-x-executable", true)
  }

  function appName(toplevel) {
    if (!toplevel) return ""
    var appId = String(toplevel.appId || "").trim()
    var normalizedId = appId.toLowerCase().replace(/\.desktop$/, "")
    var entries = DesktopEntries.applications.values || []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var entryId = String((entry && entry.id) || "").toLowerCase().replace(/\.desktop$/, "")
      if (entryId === normalizedId && entry.name) return String(entry.name)
    }
    if (appId) {
      var parts = appId.replace(/\.desktop$/i, "").split(/[.\/_-]+/)
      var fallback = parts[parts.length - 1] || appId
      return fallback.charAt(0).toUpperCase() + fallback.slice(1)
    }
    return String(toplevel.title || "")
  }

  function ageText(value) {
    return I18n.relativeTime(localeName, Number(value), clockNow)
  }

  Component.onCompleted: captureInit.running = true

  ListModel {
    id: displayModel
    dynamicRoles: true
  }

  Process {
    id: captureInit
    command: [root.captureScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addCapturedJson(text)
    }
  }

  Process {
    id: clipboardWatch
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--watch", root.captureScript]
    running: true
    stdout: SplitParser { onRead: function(data) { root.addCapturedJson(data) } }
    onExited: clipboardWatchRestart.restart()
  }

  Process {
    id: tensakuEdit
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addCapturedJson(text)
    }
  }

  Timer {
    id: clipboardWatchRestart
    interval: 1000
    onTriggered: if (!clipboardWatch.running) clipboardWatch.running = true
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.clockNow = Date.now()
  }

  Timer {
    id: initialPositionReset
    interval: 0
    onTriggered: {
      root.resetInitialPosition()
      Qt.callLater(function() {
        root.resetInitialPosition()
        if (root.opened) searchField.forceActiveFocus()
      })
    }
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.loadedHistory = ClipboardHistory.parseHistory(text())
      root.historyLoaded = true
      if (root.initialized) {
        root.history = ClipboardHistory.importLegacy(root.loadedHistory, [], root.historyLimit)
        root.rebuildDisplay()
        if (root.history.length !== root.loadedHistory.length) root.saveHistory()
      } else root.maybeInitialize()
    }
    onLoadFailed: {
      root.loadedHistory = []
      root.historyLoaded = true
      root.maybeInitialize()
    }
    onFileChanged: reload()
  }

  FileView {
    id: nativeHistoryFile
    path: root.legacyHistoryPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        if (!Array.isArray(parsed)) throw new Error("Invalid clipboard history")
        root.nativeHistory = parsed
        root.nativeHistoryValid = true
        root.legacyHistory = ClipboardHistory.parseHistory(text())
      } catch (error) {
        root.nativeHistoryValid = false
        root.legacyHistory = []
      }
      root.legacyLoaded = true
      root.maybeInitialize()
    }
    onLoadFailed: {
      root.nativeHistoryValid = false
      root.legacyHistory = []
      root.legacyLoaded = true
      root.maybeInitialize()
    }
    onFileChanged: reload()
  }

  PanelWindow {
    id: panel
    screen: root.anchorWindow ? root.anchorWindow.screen : null
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; right: true; bottom: true; left: true }
    mask: Region {
      width: root.dragInProgress ? 0 : panel.width
      height: root.dragInProgress ? 0 : panel.height
    }

    WlrLayershell.namespace: "quick-paste"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened && !root.dragInProgress
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      opacity: root.dragInProgress ? 0 : 1
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: sheet
      opacity: root.dragInProgress ? 0 : 1
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.gapsOut + Style.space(5)
      anchors.rightMargin: Style.gapsOut + Style.space(5)
      anchors.bottomMargin: Style.gapsOut
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
          root.handlePanelKey(event)
          if (!event.accepted && event.text.length
              && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            searchField.text += event.text
            searchField.forceActiveFocus()
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
            text: root.tr("clipboard")
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
          }

          Text {
            id: countLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root.count("itemOne", "itemMany", displayModel.count)
            color: Color.menu.text
            opacity: 0.55
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          width: parent.width
          height: searchField.implicitHeight + Style.space(8)

          TextField {
            id: searchField
            width: parent.width
            placeholderText: root.tr("search")
            foreground: Color.menu.text
            accent: Color.accent
            onTextChanged: root.updateSearch()
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) { root.handlePanelKey(event) }
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
              required property string fileTitle
              required property int fileCount
              required property bool isDirectory
              required property string directoryPath
              required property bool homePaths
              required property bool isLink
              required property string linkTarget
              required property string linkDescription
              required property string linkImage
              required property string linkUrl
              required property string capturedAt
              required property string sourceAppId
              required property string sourceName
              required property string sourceIcon
              required property int characterCount
              required property int historyIndex

              property string dragImagePath: ""
              property bool fileDragReady: false
              readonly property bool dragReady: entryType === "text"
                || (entryType === "image" ? !!dragImagePath : fileDragReady)

              Drag.dragType: Drag.Automatic
              Drag.supportedActions: Qt.CopyAction
              Drag.proposedAction: Qt.CopyAction
              Drag.mimeData: root.dragMimeData(historyIndex, dragImagePath)
              Drag.imageSource: entryType === "image" ? previewImage : ""
              Drag.imageSourceSize: Qt.size(96, 96)
              Drag.active: dragHandler.active && dragReady
              Drag.onDragStarted: root.dragInProgress = true
              Drag.onDragFinished: {
                Qt.callLater(function() {
                  root.dragInProgress = false
                  root.close()
                  if (root.displayRefreshPending) root.rebuildDisplay()
                })
              }

              Process {
                command: root.dragPrepareCommand(card.historyIndex)
                running: card.entryType !== "text"
                stdout: StdioCollector {
                  waitForEnd: true
                  onStreamFinished: {
                    var value = text.endsWith("\n") ? text.slice(0, -1) : text
                    if (card.entryType === "image") card.dragImagePath = value
                    else card.fileDragReady = value === "1"
                  }
                }
              }

              readonly property bool selected: root.selectedIndex === index
              readonly property real cardBorderWidth: Math.max(1, Style.space(2))
              width: Math.min(Style.space(292), resultList.width * 0.78)
              height: resultList.height
              radius: Style.cornerRadius
              color: selected ? Color.menu.selectedBackground : Util.alpha(Color.menu.text, 0.035)
              borderSpec: selected
                ? Border.flat(Color.menu.selectedText, cardBorderWidth)
                : Border.surfaceSpec("menu", "border", Util.alpha(Color.menu.border, 0.45), cardBorderWidth)
              padding: Style.space(14)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onWheel: function(event) { root.scrollHistory(event) }
                onClicked: function(mouse) {
                  if (mouse.button === Qt.RightButton) {
                    root.openContextMenu(card, card.index, mouse.x, mouse.y)
                  } else if (root.selectedIndex === card.index) {
                    root.activateIndex(card.index)
                  } else {
                    root.selectIndex(card.index)
                  }
                }
              }

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
                    width: parent.width - deleteButton.width - Style.space(30) - parent.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      text: card.sourceName || card.sourceAppId || root.tr("unknownApp")
                      color: card.selected ? Color.menu.selectedText : Color.menu.text
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.body
                      font.weight: Font.DemiBold
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: (card.entryType === "file" ? root.tr(card.fileCount > 1 ? "files" : card.isDirectory ? "folder" : "file")
                        : card.entryType === "image" ? root.tr("image") : root.tr(card.isLink ? "link" : "text"))
                        + " · " + root.ageText(card.capturedAt)
                      color: card.selected ? Color.menu.selectedText : Color.menu.text
                      opacity: 0.58
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  PanelActionButton {
                    id: deleteButton
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰅙"
                    tooltipText: root.tr("deleteHistory")
                    foreground: card.selected ? Color.menu.selectedText : Color.menu.text
                    hoverColor: Color.urgent
                    fontFamily: Style.font.menuFamily
                    onClicked: root.removeIndex(card.index)
                  }
                }

                Item {
                  width: parent.width
                  height: parent.height - y - footer.height - parent.spacing
                  clip: true

                  DragHandler {
                    id: dragHandler
                    target: null
                    enabled: card.dragReady && !root.contextMenuOpen
                  }

                  Text {
                    visible: card.entryType === "text" && !card.isLink
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

                  Column {
                    visible: card.entryType === "file"
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: Style.space(12)

                    Text {
                      width: parent.width
                      text: card.fileCount > 1 ? "󰈢" : card.isDirectory ? "󰉋" : "󰈔"
                      color: card.selected ? Color.menu.selectedText : Color.menu.text
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.displayLarge
                      horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                      width: parent.width
                      text: card.fileTitle
                      textFormat: Text.PlainText
                      color: card.selected ? Color.menu.selectedText : Color.menu.text
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.title
                      horizontalAlignment: Text.AlignHCenter
                      elide: Text.ElideMiddle
                    }
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

                  Column {
                    visible: card.isLink
                    anchors.fill: parent
                    spacing: Style.space(8)

                    Image {
                      width: parent.width
                      height: card.linkImage ? Math.max(0, parent.height - linkDescriptionText.implicitHeight - parent.spacing) : 0
                      visible: height > 0
                      source: card.linkImage
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      smooth: true
                    }

                    Text {
                      id: linkDescriptionText
                      width: parent.width
                      text: card.linkDescription || card.previewText
                      textFormat: Text.PlainText
                      color: card.selected ? Color.menu.selectedText : Color.menu.text
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.body
                      wrapMode: Text.Wrap
                      elide: Text.ElideRight
                      maximumLineCount: card.linkImage ? 2 : Math.max(1, Math.floor(parent.height / (font.pixelSize * 1.25)))
                    }
                  }
                }

                Text {
                  id: footer
                  width: parent.width
                  text: card.entryType === "file"
                    ? (card.fileCount > 1 ? "󰈢  " + root.count("fileCountOne", "fileCountMany", card.fileCount)
                      : card.isDirectory ? card.directoryPath
                      : root.count("fileOrFolderOne", "fileOrFolderMany", card.fileCount))
                    : card.entryType === "image"
                    ? (preview.sourceSize.width > 0 ? preview.sourceSize.width + " × " + preview.sourceSize.height + " px" : root.tr("image"))
                    : (card.isLink ? (card.linkUrl || card.previewText)
                      : root.count("characterOne", "characterMany", card.characterCount))
                  color: card.selected ? Color.menu.selectedText : Color.menu.text
                  opacity: 0.55
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideRight
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
              text: searchField.text.trim().length
                ? root.tr("noResults")
                : root.tr("empty")
              color: Color.menu.text
              opacity: 0.65
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
            }
          }

          Item {
            id: menuLayer
            anchors.fill: parent
            z: 20
            visible: root.contextMenuOpen || opacity > 0
            opacity: root.contextMenuOpen ? 1 : 0
            enabled: root.contextMenuOpen

            Behavior on opacity {
              NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.closeContextMenu()
            }

            BorderSurface {
              id: contextSurface
              readonly property real edgeMargin: Style.space(8)
              x: Math.max(edgeMargin,
                Math.min(root.contextMenuX, menuLayer.width - width - edgeMargin))
              y: Math.max(edgeMargin,
                Math.min(root.contextMenuY, menuLayer.height - height - edgeMargin))
              width: Math.min(Style.space(360), menuLayer.width - Style.space(16))
              height: menuColumn.implicitHeight + contentTopInset + contentBottomInset
              padding: Style.space(6)
              radius: Style.cornerRadius
              color: Color.menu.background
              borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
                Math.max(1, Style.normalBorderWidth))

              scale: root.contextMenuOpen ? 1 : 0.97
              transformOrigin: Item.TopLeft
              Behavior on scale {
                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
              }

              Item {
                id: contextKeyCatcher
                anchors.fill: parent
                focus: true
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.closeContextMenu()
                    event.accepted = true
                  } else if (root.handleFileShortcut(root.contextMenuIndex, event)) {
                    event.accepted = true
                  } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                             && (event.modifiers & Qt.ControlModifier)
                             && root.contextMenuIndex >= 0
                             && !!displayModel.get(root.contextMenuIndex).linkTarget) {
                    root.openLink(root.contextMenuIndex)
                    event.accepted = true
                  } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                             && root.pasteTarget && root.contextMenuIndex >= 0) {
                    var row = displayModel.get(root.contextMenuIndex)
                    if ((event.modifiers & Qt.ShiftModifier) && row.entryType === "text")
                      root.pastePlainText(root.contextMenuIndex)
                    else if (!(event.modifiers & Qt.ShiftModifier))
                      root.activateIndex(root.contextMenuIndex)
                    event.accepted = true
                  }
                }
              }

              Column {
                id: menuColumn
                anchors.fill: parent
                anchors.topMargin: contextSurface.contentTopInset
                anchors.rightMargin: contextSurface.contentRightInset
                anchors.bottomMargin: contextSurface.contentBottomInset
                anchors.leftMargin: contextSurface.contentLeftInset

                PasteMenuItem {
                  width: parent.width
                  iconText: "󰖟"
                  label: root.tr("openLink")
                  keymap: "Ctrl + Enter"
                  visible: root.contextMenuIndex >= 0
                    && !!displayModel.get(root.contextMenuIndex).linkTarget
                  enabled: visible
                  onChosen: root.openLink(root.contextMenuIndex)
                }

                PasteMenuItem {
                  width: parent.width
                  iconText: "󰈔"
                  label: root.tr("openFile")
                  keymap: "Ctrl + O"
                  visible: root.contextMenuIndex >= 0
                    && displayModel.get(root.contextMenuIndex).entryType === "file"
                    && displayModel.get(root.contextMenuIndex).fileCount === 1
                    && !displayModel.get(root.contextMenuIndex).isDirectory
                  onChosen: root.fileAction(root.contextMenuIndex, "open")
                }

                PasteMenuItem {
                  width: parent.width
                  iconText: "󰝰"
                  label: root.tr(root.contextMenuIndex >= 0
                    && displayModel.get(root.contextMenuIndex).isDirectory ? "revealFolder" : "revealFile")
                  keymap: "Ctrl + Shift + O"
                  visible: root.contextMenuIndex >= 0
                    && displayModel.get(root.contextMenuIndex).entryType === "file"
                    && displayModel.get(root.contextMenuIndex).fileCount === 1
                  onChosen: root.fileAction(root.contextMenuIndex, "reveal")
                }

                PasteMenuItem {
                  width: parent.width
                  iconText: "󰌷"
                  label: root.tr("pasteAbsolute")
                  keymap: "Ctrl + P"
                  visible: root.contextMenuIndex >= 0
                    && displayModel.get(root.contextMenuIndex).entryType === "file"
                    && displayModel.get(root.contextMenuIndex).fileCount === 1
                  enabled: root.pasteTarget !== null
                  onChosen: root.pasteFilePath(root.contextMenuIndex, false)
                }

                PasteMenuItem {
                  width: parent.width
                  iconText: "󰉋"
                  label: root.tr("pasteHome")
                  keymap: "Ctrl + Shift + P"
                  visible: root.contextMenuIndex >= 0
                    && displayModel.get(root.contextMenuIndex).entryType === "file"
                    && displayModel.get(root.contextMenuIndex).fileCount === 1
                  enabled: root.pasteTarget !== null && root.contextMenuIndex >= 0
                    && displayModel.get(root.contextMenuIndex).homePaths
                  onChosen: root.pasteFilePath(root.contextMenuIndex, true)
                }

                PasteMenuItem {
                  width: parent.width
                  iconText: "󰏫"
                  label: root.tr(tensakuEdit.running ? "tensakuBusy" : "openTensaku")
                  visible: root.contextMenuIndex >= 0
                    && displayModel.get(root.contextMenuIndex).entryType === "image"
                  enabled: visible && !tensakuEdit.running
                  onChosen: root.openInTensaku(root.contextMenuIndex)
                }

                PasteMenuItem {
                  width: parent.width
                  iconText: "󰆒"
                  label: root.tr("pasteIn", { app: root.pasteTargetName || root.tr("noApp") })
                  keymap: "Enter"
                  visible: root.contextMenuIndex >= 0
                    && (displayModel.get(root.contextMenuIndex).entryType !== "file"
                      || displayModel.get(root.contextMenuIndex).fileCount > 1
                      || displayModel.get(root.contextMenuIndex).isDirectory)
                  enabled: root.pasteTarget !== null
                  onChosen: root.activateIndex(root.contextMenuIndex)
                }

                PasteMenuItem {
                  width: parent.width
                  iconText: "󰉿"
                  label: root.tr("pastePlain")
                  keymap: "Shift + Enter"
                  visible: root.contextMenuIndex >= 0
                    && displayModel.get(root.contextMenuIndex).entryType === "text"
                  enabled: root.pasteTarget !== null
                    && root.contextMenuIndex >= 0
                    && displayModel.get(root.contextMenuIndex).entryType === "text"
                  onChosen: root.pastePlainText(root.contextMenuIndex)
                }
              }
            }
          }
        }
      }
    }

    FocusScope {
      anchors.fill: parent
      visible: root.clearHistoryConfirmationOpen
      z: 100
      focus: visible
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { root.handleClearHistoryKey(event) }
      Rectangle {
        anchors.fill: parent
        color: Color.menu.scrim
        MouseArea { anchors.fill: parent; onClicked: root.dismissClearHistoryConfirmation(false) }
      }
      Rectangle {
        width: Math.min(Style.space(360), sheet.width - Style.space(32))
        height: Style.space(112)
        x: sheet.x + (sheet.width - width) / 2
        y: sheet.y + (sheet.height - height) / 2
        radius: Style.cornerRadius
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: Math.max(1, Style.space(1))
        MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }
        Text {
          x: Style.space(20); y: Style.space(18)
          width: parent.width - Style.space(40)
          text: root.tr("confirmClearHistory")
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }
        Row {
          id: clearHistoryActions
          anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
          anchors.leftMargin: Style.space(16); anchors.rightMargin: Style.space(16)
          anchors.bottomMargin: Style.space(14)
          spacing: Style.space(12)
          Rectangle {
            id: clearHistoryCancelButton
            width: (clearHistoryActions.width - clearHistoryActions.spacing) / 2
            height: Style.space(34)
            focus: true
            activeFocusOnTab: true
            KeyNavigation.tab: clearHistoryDeleteButton
            KeyNavigation.backtab: clearHistoryDeleteButton
            color: "transparent"
            border.width: activeFocus ? Math.max(2, Style.space(2)) : Math.max(1, Style.space(1))
            border.color: activeFocus ? Color.accent : Color.menu.border
            Text {
              anchors.centerIn: parent; text: root.tr("cancel")
              color: Color.menu.text
              font.family: Style.font.menuFamily; font.pixelSize: Style.font.caption
            }
            MouseArea {
              anchors.fill: parent
              onPressed: clearHistoryCancelButton.forceActiveFocus()
              onClicked: root.dismissClearHistoryConfirmation(false)
            }
          }
          Rectangle {
            id: clearHistoryDeleteButton
            width: (clearHistoryActions.width - clearHistoryActions.spacing) / 2
            height: Style.space(34)
            activeFocusOnTab: true
            KeyNavigation.tab: clearHistoryCancelButton
            KeyNavigation.backtab: clearHistoryCancelButton
            color: "transparent"
            border.width: activeFocus ? Math.max(2, Style.space(2)) : Math.max(1, Style.space(1))
            border.color: activeFocus ? Color.accent : Color.urgent
            Text {
              anchors.centerIn: parent; text: root.tr("deleteAll")
              color: Color.urgent
              font.family: Style.font.menuFamily; font.pixelSize: Style.font.caption
            }
            MouseArea {
              anchors.fill: parent
              onPressed: clearHistoryDeleteButton.forceActiveFocus()
              onClicked: root.dismissClearHistoryConfirmation(true)
            }
          }
        }
      }
    }
  }

  component PasteMenuItem: Item {
    id: menuItem

    property string iconText: ""
    property string label: ""
    property string keymap: ""
    signal chosen()

    implicitHeight: Style.space(42)
    opacity: enabled ? 1 : 0.4

    Rectangle {
      anchors.fill: parent
      radius: Math.max(2, Style.cornerRadius)
      color: itemMouse.containsMouse && menuItem.enabled
        ? Style.hoverFillFor(Color.menu.text, Color.accent)
        : "transparent"
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(24)
      text: menuItem.iconText
      color: Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.icon
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(44)
      anchors.right: shortcut.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: menuItem.label
      color: Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      id: shortcut
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: menuItem.keymap
      color: Color.menu.text
      opacity: 0.55
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: itemMouse
      anchors.fill: parent
      enabled: menuItem.enabled
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: menuItem.chosen()
    }
  }
}
