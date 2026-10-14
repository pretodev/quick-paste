import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "quick-paste"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  property bool pendingOpen: false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = button
    target.hostWidget = root
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open("{}")
    else pendingOpen = true
  }

  function close() {
    pendingOpen = false
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (root.opened || pendingOpen) root.close()
    else root.open()
  }

  function closeForPopoutSwitch() {
    root.close()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    asynchronous: true
    source: Qt.resolvedUrl("ui/QuickPaste.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
      if (root.pendingOpen) {
        root.pendingOpen = false
        item.open("{}")
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰅌"
    fontSize: Style.font.icon
    tooltipText: "Quick Paste"
    active: root.opened
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
  }
}
