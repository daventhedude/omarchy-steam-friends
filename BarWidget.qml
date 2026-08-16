import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.daventhedude.steam-friends"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false
  readonly property int onlineCount: panelLoader.item
    ? panelLoader.item.onlineCount
    : 0
  readonly property int inGameCount: panelLoader.item
    ? panelLoader.item.inGameCount
    : 0
  readonly property bool configured: panelLoader.item
    ? panelLoader.item.configured
    : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function refresh() {
    if (panelLoader.item) panelLoader.item.refresh()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Component {
    id: steamBarIcon

    Item {
      Text {
        anchors.centerIn: parent
        text: ""
        color: root.opened
          ? (root.bar ? root.bar.urgent : Color.urgent)
          : (root.bar ? root.bar.barForeground : Color.foreground)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering

        Behavior on color { ColorAnimation { duration: 160 } }
      }

      Rectangle {
        visible: root.configured && root.onlineCount > 0
        anchors.right: parent.right
        anchors.rightMargin: -Style.space(3)
        anchors.top: parent.top
        anchors.topMargin: -Style.space(3)
        width: Math.max(Style.space(9), badgeLabel.implicitWidth + Style.space(4))
        height: Style.space(9)
        radius: height / 2
        color: root.inGameCount > 0 ? "#90ba3c" : "#66c0f4"
        border.width: 1
        border.color: Color.bar.background

        Text {
          id: badgeLabel
          anchors.centerIn: parent
          text: root.onlineCount > 99 ? "99+" : String(root.onlineCount)
          color: "#07111b"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.space(6)
          font.bold: true
        }
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: steamBarIcon
    active: root.opened
    tooltipText: !root.configured
      ? "Set up Steam Friends"
      : (root.inGameCount > 0
        ? root.inGameCount + " playing · " + root.onlineCount + " online"
        : root.onlineCount + " friends online")

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton && panelLoader.item) panelLoader.item.openFriends()
      else if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }
}
