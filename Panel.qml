import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

Panel {
  id: root
  moduleName: "io.github.daventhedude.steam-friends"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: Color.popups.text
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string backendPath: decodeURIComponent(
    Qt.resolvedUrl("scripts/steam-friends").toString().replace(/^file:\/\//, ""))

  property var snapshot: Model.emptySnapshot()
  property bool loading: true
  property bool receivedOutput: false
  property string activeFilter: "online"
  property string searchText: ""
  property int selectedIndex: 0
  property double nowMs: Date.now()
  property bool setupStarted: false
  property int setupPollCount: 0
  property var searchFieldItem: null
  property var friendsListItem: null

  readonly property bool configured: snapshot.configured === true
  readonly property int onlineCount: Model.safeCount(snapshot, "online")
  readonly property int inGameCount: Model.safeCount(snapshot, "inGame")
  readonly property int totalCount: Model.safeCount(snapshot, "total")
  readonly property bool showOffline: setting("showOffline", false) === true
  readonly property int browsableCount: showOffline ? totalCount : onlineCount
  readonly property int refreshIntervalSec: Math.max(30,
    Math.min(300, Number(setting("refreshIntervalSec", 60)) || 60))
  readonly property int backgroundRefreshSec: Math.max(120,
    Math.min(1800, Number(setting("backgroundRefreshSec", 300)) || 300))
  // Kept out of the public settings schema; useful to maintainers for visual
  // regression checks without ever touching a real Steam account.
  readonly property bool demoMode: setting("_demoMode", false) === true
  readonly property var visibleFriends: Model.filteredFriends(
    snapshot.friends, activeFilter, searchText, showOffline)

  function open() {
    controller.show()
    refresh()
  }

  function close() {
    if (searchFieldItem && searchFieldItem.activeFocus) searchFieldItem.focus = false
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function refresh() {
    if (snapshotProc.running) return
    receivedOutput = false
    loading = true
    snapshotProc.command = [backendPath, demoMode ? "demo" : "snapshot"]
    snapshotProc.running = true
  }

  function applySnapshot(raw) {
    var parsed = Model.parseSnapshot(raw)
    if (!parsed) return false
    snapshot = parsed
    loading = false
    receivedOutput = true
    if (configured) {
      setupStarted = false
      setupPoll.stop()
    }
    clampSelection()
    return true
  }

  function clampSelection() {
    var count = visibleFriends.length
    if (count <= 0) selectedIndex = 0
    else selectedIndex = Math.max(0, Math.min(selectedIndex, count - 1))
    Qt.callLater(function() {
      if (root.friendsListItem && count > 0)
        root.friendsListItem.positionViewAtIndex(selectedIndex, ListView.Contain)
    })
  }

  function moveSelection(delta) {
    if (visibleFriends.length === 0) return
    selectedIndex = Math.max(0, Math.min(visibleFriends.length - 1, selectedIndex + delta))
    if (friendsListItem)
      friendsListItem.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function setFilter(filter) {
    activeFilter = filter
    selectedIndex = 0
    clampSelection()
  }

  function activateSelected() {
    if (selectedIndex < 0 || selectedIndex >= visibleFriends.length) return
    messageFriend(visibleFriends[selectedIndex])
  }

  function openFriends() {
    Quickshell.execDetached(["xdg-open", "steam://open/friends"])
  }

  function messageFriend(friend) {
    if (!friend || !Model.isSteamId(friend.steamId)) return
    Quickshell.execDetached([
      "xdg-open",
      "steam://friends/message/" + String(friend.steamId)
    ])
  }

  function openProfile(friend) {
    if (!friend || !Model.isSteamId(friend.steamId)) return
    Quickshell.execDetached([
      "xdg-open",
      "https://steamcommunity.com/profiles/" + String(friend.steamId) + "/"
    ])
  }

  function beginSetup() {
    Quickshell.execDetached(["xdg-terminal-exec", backendPath, "setup"])
    setupStarted = true
    setupPollCount = 0
    setupPoll.start()
  }

  function handleShortcut(text) {
    if (text === "r" || text === "R") refresh()
    else if (text === "s" || text === "S") openFriends()
    else if (text === "/" && searchFieldItem) {
      searchFieldItem.forceActiveFocus()
      searchFieldItem.selectAll()
    }
  }

  onVisibleFriendsChanged: clampSelection()
  onDemoModeChanged: refresh()

  onOpenedChanged: {
    if (opened) {
      nowMs = Date.now()
      selectedIndex = 0
      refresh()
    } else {
      searchText = ""
    }
  }

  Component.onCompleted: refresh()

  Timer {
    interval: (root.opened ? root.refreshIntervalSec : root.backgroundRefreshSec) * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 60000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    id: setupPoll
    interval: 2000
    repeat: true
    onTriggered: {
      root.setupPollCount++
      root.refresh()
      if (root.setupPollCount >= 90) {
        root.setupStarted = false
        stop()
      }
    }
  }

  Process {
    id: snapshotProc

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySnapshot(text)
    }

    onExited: function(exitCode) {
      if (!root.receivedOutput) {
        root.loading = false
        root.snapshot = {
          ok: false,
          configured: root.configured,
          stale: false,
          error: "Steam Friends returned no usable data (exit " + exitCode + ").",
          warning: "",
          generatedAt: 0,
          self: null,
          friends: [],
          counts: { total: 0, online: 0, inGame: 0 }
        }
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(448))
    contentHeight: popup.cappedContentHeight(Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: !!root.searchFieldItem && root.searchFieldItem.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { root.handleShortcut(text) }

      Loader {
        anchors.fill: parent
        sourceComponent: !root.configured
          ? setupView
          : (root.snapshot.ok ? friendsView : errorView)
      }
    }
  }

  Component {
    id: setupView

    Item {
      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(14)

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(170)
          radius: Style.space(12)
          clip: true
          gradient: Gradient {
            GradientStop { position: 0.0; color: "#102a43" }
            GradientStop { position: 0.58; color: "#163d59" }
            GradientStop { position: 1.0; color: "#1b5b7d" }
          }

          Rectangle {
            width: Style.space(190)
            height: width
            radius: width / 2
            x: parent.width - width * 0.55
            y: -height * 0.55
            color: "#146b98"
            opacity: 0.35
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(20)
            anchors.top: parent.top
            anchors.topMargin: Style.space(18)
            text: ""
            color: "#66c0f4"
            font.family: root.fontFamily
            font.pixelSize: Style.space(38)
          }

          Column {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(20)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(20)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(18)
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: "YOUR SQUAD, ONE CLICK AWAY"
              color: "#66c0f4"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.4
            }

            Text {
              width: parent.width
              text: "Steam Friends"
              color: "#f2f7fb"
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }

            Text {
              width: parent.width
              text: "Live presence, games, avatars and native Steam actions — directly in Omarchy."
              color: "#b9d9ec"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: "SETUP TAKES ABOUT A MINUTE"
            color: Qt.darker(root.contentForeground, 1.35)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.0
          }

          Repeater {
            model: [
              ["1", "Steam account", "Your Steam ID is detected automatically."],
              ["2", "Private API key", "Stored locally with file mode 0600."],
              ["3", "Done", "The panel refreshes as soon as setup finishes."]
            ]

            Item {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(47)

              Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(28)
                height: width
                radius: width / 2
                color: Qt.rgba(0.4, 0.75, 0.96, 0.12)
                border.width: 1
                border.color: "#66c0f4"

                Text {
                  anchors.centerIn: parent
                  text: String(modelData[0])
                  color: "#66c0f4"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }

              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(40)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  text: String(modelData[1])
                  color: root.contentForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  width: parent.width
                  text: String(modelData[2])
                  color: Qt.darker(root.contentForeground, 1.55)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }
        }

        Item { Layout.fillHeight: true }

        Button {
          Layout.fillWidth: true
          text: root.setupStarted ? "Waiting for setup…" : "Open secure setup"
          iconText: root.setupStarted ? "󰔟" : "󰒓"
          foreground: root.contentForeground
          accent: "#66c0f4"
          fontFamily: root.fontFamily
          bordered: true
          active: root.setupStarted
          enabled: !root.setupStarted
          onClicked: root.beginSetup()
        }

        Text {
          Layout.fillWidth: true
          text: "The key never enters shell.json and is never printed to the shell log."
          color: Qt.darker(root.contentForeground, 1.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  Component {
    id: errorView

    Item {
      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(14)

        Item { Layout.fillHeight: true }

        Rectangle {
          Layout.alignment: Qt.AlignHCenter
          Layout.preferredWidth: Style.space(72)
          Layout.preferredHeight: Style.space(72)
          radius: width / 2
          color: Qt.rgba(0.4, 0.75, 0.96, 0.1)
          border.width: 1
          border.color: "#66c0f4"

          Text {
            anchors.centerIn: parent
            text: ""
            color: "#66c0f4"
            font.family: root.fontFamily
            font.pixelSize: Style.space(34)
          }
        }

        Text {
          Layout.fillWidth: true
          text: "Steam needs attention"
          color: root.contentForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          Layout.fillWidth: true
          Layout.maximumWidth: Style.space(340)
          Layout.alignment: Qt.AlignHCenter
          text: String(root.snapshot.error || "The Steam friends snapshot could not be loaded.")
          textFormat: Text.PlainText
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        RowLayout {
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.space(8)

          Button {
            text: "Retry"
            iconText: "󰑐"
            foreground: root.contentForeground
            accent: "#66c0f4"
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.refresh()
          }

          Button {
            text: "Reconfigure"
            iconText: "󰒓"
            foreground: root.contentForeground
            accent: "#66c0f4"
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.beginSetup()
          }
        }

        Item { Layout.fillHeight: true }
      }
    }
  }

  Component {
    id: friendsView

    Item {
      Component.onCompleted: {
        root.searchFieldItem = searchField
        root.friendsListItem = friendsList
      }
      Component.onDestruction: {
        if (root.searchFieldItem === searchField) root.searchFieldItem = null
        if (root.friendsListItem === friendsList) root.friendsListItem = null
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(10)

        Rectangle {
          id: profileHero
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(112)
          radius: Style.space(12)
          clip: true
          gradient: Gradient {
            GradientStop { position: 0.0; color: "#0d2235" }
            GradientStop { position: 0.55; color: "#12344d" }
            GradientStop { position: 1.0; color: root.inGameCount > 0 ? "#294b35" : "#145172" }
          }

          Rectangle {
            width: Style.space(190)
            height: width
            radius: width / 2
            x: parent.width - width * 0.58
            y: -height * 0.58
            color: root.inGameCount > 0 ? "#90ba3c" : "#66c0f4"
            opacity: 0.12
          }

          SteamAvatar {
            id: selfAvatar
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            avatarSize: Style.space(68)
            imageUrl: root.snapshot.self ? String(root.snapshot.self.avatar || "") : ""
            displayName: root.snapshot.self ? String(root.snapshot.self.name || "Steam") : "Steam"
            statusColor: root.snapshot.self ? Model.stateColor(root.snapshot.self) : "#66c0f4"
          }

          Column {
            anchors.left: selfAvatar.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroActions.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: root.snapshot.self ? String(root.snapshot.self.name || "Steam") : "Steam"
              textFormat: Text.PlainText
              color: "#f4f8fb"
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.inGameCount > 0
                ? Model.countText(root.inGameCount, "friend is playing", "friends are playing")
                : Model.countText(root.onlineCount, "friend online", "friends online")
              color: root.inGameCount > 0 ? "#b7dc72" : "#8ed5f6"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.snapshot.stale
                ? "Showing cached presence"
                : "Live Steam presence"
              color: "#8faabc"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: heroActions
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.top: parent.top
            anchors.topMargin: Style.space(12)
            spacing: Style.space(4)

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh · r"
              foreground: "#dbeaf2"
              hoverColor: "#66c0f4"
              fontFamily: root.fontFamily
              enabled: !root.loading
              onClicked: root.refresh()
            }

            PanelActionButton {
              iconText: "󰍉"
              tooltipText: "Open Steam Friends · s"
              foreground: "#dbeaf2"
              hoverColor: "#66c0f4"
              fontFamily: root.fontFamily
              onClicked: root.openFriends()
            }
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(13)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(12)
            spacing: Style.space(6)

            MetricPill {
              value: String(root.onlineCount)
              label: "ONLINE"
              accent: "#66c0f4"
              foreground: "#e9f3f8"
              fontFamily: root.fontFamily
            }

            MetricPill {
              visible: root.inGameCount > 0
              value: String(root.inGameCount)
              label: "PLAYING"
              accent: "#90ba3c"
              foreground: "#e9f3f8"
              fontFamily: root.fontFamily
            }
          }
        }

        Rectangle {
          visible: root.snapshot.stale || String(root.snapshot.warning || "") !== ""
          Layout.fillWidth: true
          Layout.preferredHeight: warningText.implicitHeight + Style.space(12)
          radius: Style.space(7)
          color: Qt.rgba(0.94, 0.64, 0.36, 0.10)
          border.width: 1
          border.color: Qt.rgba(0.94, 0.64, 0.36, 0.32)

          Text {
            id: warningText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰀦  " + String(root.snapshot.warning || "Steam is unreachable — cached presence is shown.")
            textFormat: Text.PlainText
            color: "#eeb37a"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Repeater {
            model: [
              { key: "online", label: "Online", count: root.onlineCount },
              { key: "game", label: "In game", count: root.inGameCount },
              { key: "all", label: "All", count: root.browsableCount }
            ]

            Button {
              required property var modelData
              Layout.fillWidth: true
              text: modelData.label + "  " + modelData.count
              foreground: root.contentForeground
              accent: modelData.key === "game" ? "#90ba3c" : "#66c0f4"
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(5)
              bordered: true
              active: root.activeFilter === modelData.key
              onClicked: root.setFilter(String(modelData.key))
            }
          }
        }

        TextField {
          id: searchField
          Layout.fillWidth: true
          placeholderText: "Search friends or games…   /"
          foreground: root.contentForeground
          accent: "#66c0f4"
          font.family: root.fontFamily
          horizontalPadding: Style.space(11)
          verticalPadding: Style.space(6)
          onTextChanged: {
            root.searchText = text
            root.selectedIndex = 0
          }
          onAccepted: {
            focus = false
            keyCatcher.forceActiveFocus()
          }
          Keys.onEscapePressed: function(event) {
            if (text !== "") text = ""
            else {
              focus = false
              keyCatcher.forceActiveFocus()
            }
            event.accepted = true
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.minimumHeight: Style.space(110)

          ListView {
            id: friendsList
            anchors.fill: parent
            clip: true
            spacing: Style.space(4)
            model: root.visibleFriends
            currentIndex: root.selectedIndex
            boundsBehavior: Flickable.StopAtBounds

            delegate: FriendRow {
              required property var modelData
              required property int index
              width: ListView.view.width
              friend: modelData
              selectedRow: index === root.selectedIndex
              contentForeground: root.contentForeground
              fontFamily: root.fontFamily
              nowMs: root.nowMs
              onHoveredRow: root.selectedIndex = index
              onActivated: root.messageFriend(modelData)
              onProfileRequested: root.openProfile(modelData)
            }

            displaced: Transition {
              NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic }
            }

            Behavior on opacity { NumberAnimation { duration: 150 } }
          }

          Column {
            visible: root.visibleFriends.length === 0
            anchors.centerIn: parent
            spacing: Style.space(7)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.searchText !== "" ? "󰍉" : "󰊕"
              color: Qt.darker(root.contentForeground, 1.65)
              font.family: root.fontFamily
              font.pixelSize: Style.space(28)
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.searchText !== ""
                ? "No matching friends"
                : (root.activeFilter === "game" ? "Nobody is playing right now" : "Nobody is online right now")
              color: Qt.darker(root.contentForeground, 1.45)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Rectangle {
            visible: root.loading
            anchors.top: parent.top
            anchors.left: parent.left
            width: parent.width
            height: Style.space(2)
            radius: height / 2
            color: "#66c0f4"

            SequentialAnimation on opacity {
              running: root.loading
              loops: Animation.Infinite
              NumberAnimation { from: 0.2; to: 1.0; duration: 520; easing.type: Easing.InOutSine }
              NumberAnimation { from: 1.0; to: 0.2; duration: 520; easing.type: Easing.InOutSine }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: "ENTER CHAT  ·  RIGHT-CLICK PROFILE"
            color: Qt.darker(root.contentForeground, 1.75)
            font.family: root.fontFamily
            font.pixelSize: Style.space(8)
            font.bold: true
            font.letterSpacing: 0.7
          }

          Text {
            text: "R REFRESH  ·  S STEAM"
            color: Qt.darker(root.contentForeground, 1.75)
            font.family: root.fontFamily
            font.pixelSize: Style.space(8)
            font.bold: true
            font.letterSpacing: 0.7
          }
        }
      }
    }
  }
}
