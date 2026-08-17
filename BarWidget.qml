import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Theme.js" as Theme

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
  readonly property bool steamActionPending: panelLoader.item
    ? panelLoader.item.steamActionPending === true
    : false
  readonly property color badgeColor: root.inGameCount > 0
    ? Color.accent
    : (root.bar ? root.bar.barForeground : Color.bar.text)
  readonly property color badgeText: Theme.contrastText(
    badgeColor,
    root.bar ? root.bar.barForeground : Color.bar.text,
    Color.bar.background)

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
        color: root.opened || root.steamActionPending
          ? (root.bar ? root.bar.urgent : Color.urgent)
          : (root.bar ? root.bar.barForeground : Color.foreground)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering

        Behavior on color { ColorAnimation { duration: 160 } }

        SequentialAnimation on opacity {
          running: root.steamActionPending
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { to: 0.45; duration: 420; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutSine }
        }
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
        color: root.badgeColor
        border.width: Style.spacing.hairline
        border.color: Color.bar.background

        Text {
          id: badgeLabel
          anchors.centerIn: parent
          text: root.onlineCount > 99 ? "99+" : String(root.onlineCount)
          color: root.badgeText
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Math.max(1, Math.round(Style.font.caption * 0.62))
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
    tooltipText: root.steamActionPending
      ? "Opening Steam…"
      : (!root.configured
      ? "Set up Steam Friends"
      : (root.inGameCount > 0
        ? root.inGameCount + " playing · " + root.onlineCount + " online"
        : root.onlineCount + " friends online"))

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton && panelLoader.item) panelLoader.item.openSteam()
      else if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }
}
