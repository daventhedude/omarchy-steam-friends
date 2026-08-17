import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Theme.js" as Theme
import "components"

Panel {
  id: root
  moduleName: "io.github.daventhedude.steam-friends"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color surfaceBackground: Color.popups.background
  readonly property color contentForeground: Color.popups.text
  readonly property color accentColor: Color.accent
  readonly property color urgentColor: Color.urgent
  readonly property color secondaryText: Theme.readableMuted(
    contentForeground, surfaceBackground, 5.5)
  readonly property color quietText: Theme.readableMuted(
    contentForeground, surfaceBackground, 4.5)
  readonly property color accentGraphic: Theme.ensureContrast(
    accentColor, contentForeground, surfaceBackground, 3.0)
  readonly property color accentText: Theme.ensureContrast(
    accentColor, contentForeground, surfaceBackground, 4.5)
  readonly property color urgentGraphic: Theme.ensureContrast(
    urgentColor, contentForeground, surfaceBackground, 3.0)
  readonly property color urgentText: Theme.ensureContrast(
    urgentColor, contentForeground, surfaceBackground, 4.5)
  readonly property color mutedGraphic: Theme.ensureContrast(
    Color.muted, quietText, surfaceBackground, 3.0)
  readonly property var presencePalette: ({
    playing: accentGraphic,
    online: contentForeground,
    busy: urgentGraphic,
    urgent: urgentGraphic,
    away: mutedGraphic,
    social: accentGraphic,
    offline: mutedGraphic
  })
  readonly property var presenceTextPalette: ({
    playing: accentText,
    online: contentForeground,
    busy: urgentText,
    urgent: urgentText,
    away: secondaryText,
    social: accentText,
    offline: secondaryText
  })
  readonly property color heroStart: Theme.mix(
    surfaceBackground, contentForeground, 0.04)
  readonly property color heroMiddle: Theme.mix(
    surfaceBackground, accentColor, 0.10)
  readonly property color heroEnd: Theme.mix(
    surfaceBackground,
    inGameCount > 0 ? accentColor : contentForeground,
    inGameCount > 0 ? 0.20 : 0.08)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string backendPath: decodeURIComponent(
    Qt.resolvedUrl("scripts/steam-friends").toString().replace(/^file:\/\//, ""))

  property var snapshot: Model.emptySnapshot()
  property bool loading: true
  property bool receivedOutput: false
  property bool initialized: false
  property string activeFilter: "online"
  property string searchText: ""
  property int selectedIndex: 0
  property double nowMs: Date.now()
  property bool setupStarted: false
  property int setupPollCount: 0
  property var searchFieldItem: null
  property var friendsListItem: null
  property string steamActionMessage: ""
  property string steamActionSuccessMessage: ""
  property bool steamActionFailure: false

  readonly property bool steamActionPending: steamActionProc.running

  readonly property bool configured: snapshot.configured === true
  readonly property int onlineCount: Model.safeCount(snapshot, "online")
  readonly property int inGameCount: Model.safeCount(snapshot, "inGame")
  readonly property int totalCount: Model.safeCount(snapshot, "total")
  readonly property bool showOffline: setting("showOffline", false) === true
  readonly property int browsableCount: showOffline ? totalCount : onlineCount
  readonly property int refreshIntervalSec: Math.max(60,
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
    initialized = true
    if (configured) {
      setupStarted = false
      setupPoll.stop()
    }
    clampSelection()
    restorePanelFocus()
    return true
  }

  function restorePanelFocus() {
    if (!opened || (searchFieldItem && searchFieldItem.activeFocus)) return
    Qt.callLater(function() {
      if (root.opened && (!root.searchFieldItem || !root.searchFieldItem.activeFocus))
        keyCatcher.forceActiveFocus()
    })
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

  function activateCurrent() {
    if (!initialized) return
    if (!configured) {
      if (!setupStarted) beginSetup()
      return
    }
    if (!snapshot.ok) {
      refresh()
      return
    }
    activateSelected()
  }

  function launchSteamAction(actionArguments, pendingMessage, successMessage) {
    if (steamActionProc.running) {
      steamActionMessage = "Steam is already opening — duplicate action blocked."
      steamActionFailure = false
      return false
    }

    actionFeedbackTimer.stop()
    steamActionMessage = pendingMessage
    steamActionSuccessMessage = successMessage
    steamActionFailure = false
    steamActionProc.command = [backendPath, "steam-action"].concat(actionArguments)
    steamActionProc.running = true
    return true
  }

  function openFriends() {
    return launchSteamAction(
      ["friends"],
      "Opening Steam Friends… Steam may take a moment to start.",
      "Steam Friends opened."
    )
  }

  function messageFriend(friend) {
    if (!friend || !Model.isSteamId(friend.steamId)) return false
    var displayName = String(friend.name || "friend")
    return launchSteamAction(
      ["chat", String(friend.steamId)],
      "Opening chat with " + displayName + "… Steam may take a moment to start.",
      "Chat sent to Steam."
    )
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
      restorePanelFocus()
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
    id: actionFeedbackTimer
    interval: 3500
    repeat: false
    onTriggered: {
      if (!root.steamActionPending) root.steamActionMessage = ""
    }
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
        root.initialized = true
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
      root.restorePanelFocus()
    }
  }

  Process {
    id: steamActionProc

    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.steamActionMessage = root.steamActionSuccessMessage
        root.steamActionFailure = false
      } else if (exitCode === 75) {
        root.steamActionMessage = "Steam is still starting — duplicate action blocked safely."
        root.steamActionFailure = false
      } else if (exitCode === 69) {
        root.steamActionMessage = "Steam could not be opened because a required system command is missing."
        root.steamActionFailure = true
      } else {
        root.steamActionMessage = "Steam could not be opened. Try again after checking the Steam installation."
        root.steamActionFailure = true
      }
      actionFeedbackTimer.restart()
      root.restorePanelFocus()
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
      onActivateRequested: root.activateCurrent()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { root.handleShortcut(text) }

      Loader {
        anchors.fill: parent
        sourceComponent: !root.initialized
          ? loadingView
          : (!root.configured
          ? setupView
          : (root.snapshot.ok ? friendsView : errorView))
      }
    }
  }

  Component {
    id: loadingView

    Item {
      ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width, Style.space(320))
        spacing: Style.space(10)

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: ""
          color: root.accentText
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge
        }

        Text {
          Layout.fillWidth: true
          text: "Loading Steam presence…"
          color: root.contentForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          Layout.fillWidth: true
          text: "The first secure refresh can take a few seconds."
          color: root.secondaryText
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  Component {
    id: setupView

    Item {
      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(14)

        BorderSurface {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(170)
          radius: Style.cornerRadius
          clip: true
          borderSpec: Border.controlSpec("normal", root.contentForeground, root.accentColor)
          gradient: Gradient {
            GradientStop { position: 0.0; color: root.heroStart }
            GradientStop { position: 0.58; color: root.heroMiddle }
            GradientStop { position: 1.0; color: Theme.mix(root.surfaceBackground, root.accentColor, 0.18) }
          }

          PresenceOrbit {
            width: Style.space(190)
            height: width
            x: parent.width - width * 0.55
            y: -height * 0.55
            online: 4
            playing: 2
            total: 8
            foreground: root.contentForeground
            onlineColor: root.contentForeground
            playingColor: root.accentGraphic
            opacity: 0.58
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(20)
            anchors.top: parent.top
            anchors.topMargin: Style.space(18)
            text: ""
            color: root.accentText
            font.family: root.fontFamily
            font.pixelSize: Math.round(Style.font.displayLarge * 1.35)
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
              color: root.accentText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.4
            }

            Text {
              width: parent.width
              text: "Steam Friends"
              color: root.contentForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }

            Text {
              width: parent.width
              text: "Live presence, games, avatars and native Steam actions — directly in Omarchy."
              color: root.secondaryText
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
            color: root.secondaryText
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

              BorderSurface {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(28)
                height: width
                radius: width / 2
                color: Style.normalFillFor(root.accentGraphic, root.accentGraphic)
                borderSpec: Border.controlSpec("normal", root.accentGraphic, root.accentGraphic)

                Text {
                  anchors.centerIn: parent
                  text: String(modelData[0])
                  color: root.accentText
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
                  color: root.secondaryText
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
          accent: root.accentGraphic
          fontFamily: root.fontFamily
          bordered: true
          active: root.setupStarted
          enabled: !root.setupStarted
          onClicked: root.beginSetup()
        }

        Text {
          Layout.fillWidth: true
          text: "The key never enters shell.json and is never printed to the shell log."
          color: root.secondaryText
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

        BorderSurface {
          Layout.alignment: Qt.AlignHCenter
          Layout.preferredWidth: Style.space(72)
          Layout.preferredHeight: Style.space(72)
          radius: width / 2
          color: Style.normalFillFor(root.urgentGraphic, root.urgentGraphic)
          borderSpec: Border.controlSpec("normal", root.urgentGraphic, root.urgentGraphic)

          Text {
            anchors.centerIn: parent
            text: ""
            color: root.urgentText
            font.family: root.fontFamily
            font.pixelSize: Math.round(Style.font.displayLarge * 1.2)
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
          color: root.secondaryText
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
            accent: root.accentGraphic
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.refresh()
          }

          Button {
            text: "Reconfigure"
            iconText: "󰒓"
            foreground: root.contentForeground
            accent: root.accentGraphic
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
        root.restorePanelFocus()
      }
      Component.onDestruction: {
        if (root.searchFieldItem === searchField) root.searchFieldItem = null
        if (root.friendsListItem === friendsList) root.friendsListItem = null
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(10)

        BorderSurface {
          id: profileHero
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(112)
          radius: Style.cornerRadius
          clip: true
          borderSpec: Border.controlSpec("normal", root.contentForeground, root.accentColor)
          gradient: Gradient {
            GradientStop { position: 0.0; color: root.heroStart }
            GradientStop { position: 0.55; color: root.heroMiddle }
            GradientStop { position: 1.0; color: root.heroEnd }
          }

          PresenceOrbit {
            width: Style.space(190)
            height: width
            x: parent.width - width * 0.58
            y: -height * 0.58
            online: root.onlineCount
            playing: root.inGameCount
            total: root.totalCount
            foreground: root.contentForeground
            onlineColor: root.contentForeground
            playingColor: root.accentGraphic
            opacity: 0.72
          }

          SteamAvatar {
            id: selfAvatar
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            avatarSize: Style.space(68)
            imageUrl: root.snapshot.self ? String(root.snapshot.self.avatar || "") : ""
            displayName: root.snapshot.self ? String(root.snapshot.self.name || "Steam") : "Steam"
            statusColor: root.snapshot.self
              ? Model.stateColor(root.snapshot.self, root.presencePalette)
              : root.accentGraphic
            statusTextColor: root.snapshot.self
              ? Model.stateColor(root.snapshot.self, root.presenceTextPalette)
              : root.accentText
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
              color: root.contentForeground
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
              color: root.inGameCount > 0 ? root.accentText : root.contentForeground
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
              color: root.secondaryText
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
              foreground: root.contentForeground
              hoverColor: root.accentGraphic
              fontFamily: root.fontFamily
              enabled: !root.loading
              onClicked: root.refresh()
            }

            PanelActionButton {
              iconText: "󰍉"
              tooltipText: "Open Steam Friends · s"
              foreground: root.contentForeground
              hoverColor: root.accentGraphic
              fontFamily: root.fontFamily
              enabled: !root.steamActionPending
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
              accent: root.contentForeground
              accentText: root.contentForeground
              foreground: root.contentForeground
              secondaryForeground: root.secondaryText
              fontFamily: root.fontFamily
            }

            MetricPill {
              visible: root.inGameCount > 0
              value: String(root.inGameCount)
              label: "PLAYING"
              accent: root.accentGraphic
              accentText: root.accentText
              foreground: root.contentForeground
              secondaryForeground: root.secondaryText
              fontFamily: root.fontFamily
            }
          }
        }

        BorderSurface {
          visible: root.snapshot.stale || String(root.snapshot.warning || "") !== ""
          Layout.fillWidth: true
          Layout.preferredHeight: warningText.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.urgentGraphic, root.urgentGraphic)
          borderSpec: Border.controlSpec("normal", root.urgentGraphic, root.urgentGraphic)

          Text {
            id: warningText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰀦  " + String(root.snapshot.warning || "Steam is unreachable — cached presence is shown.")
            textFormat: Text.PlainText
            color: root.urgentText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        BorderSurface {
          visible: root.steamActionMessage !== ""
          Layout.fillWidth: true
          Layout.preferredHeight: actionMessageText.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: Style.normalFillFor(
            root.steamActionFailure ? root.urgentGraphic : root.accentGraphic,
            root.steamActionFailure ? root.urgentGraphic : root.accentGraphic)
          borderSpec: Border.controlSpec(
            "normal",
            root.steamActionFailure ? root.urgentGraphic : root.accentGraphic,
            root.steamActionFailure ? root.urgentGraphic : root.accentGraphic)

          Text {
            id: actionMessageText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: (root.steamActionPending ? "󰔟  " : (root.steamActionFailure ? "󰅙  " : "󰄬  "))
              + root.steamActionMessage
            textFormat: Text.PlainText
            color: root.steamActionFailure ? root.urgentText : root.accentText
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
              accent: modelData.key === "game" ? root.accentGraphic : root.contentForeground
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
          accent: root.accentGraphic
          font.family: root.fontFamily
          horizontalPadding: Style.space(11)
          verticalPadding: Style.space(6)
          onTextChanged: {
            root.searchText = text
            root.selectedIndex = 0
          }
          onAccepted: {
            root.activateCurrent()
            focus = false
            root.restorePanelFocus()
          }
          Keys.onEscapePressed: function(event) {
            text = ""
            focus = false
            root.restorePanelFocus()
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
              secondaryForeground: root.secondaryText
              quietForeground: root.quietText
              presencePalette: root.presencePalette
              presenceTextPalette: root.presenceTextPalette
              fontFamily: root.fontFamily
              nowMs: root.nowMs
              enabled: !root.steamActionPending
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
              color: root.quietText
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.searchText !== ""
                ? "No matching friends"
                : (root.activeFilter === "game" ? "Nobody is playing right now" : "Nobody is online right now")
              color: root.secondaryText
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
            color: root.accentGraphic

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
            text: root.steamActionPending
              ? "OPENING STEAM  ·  DUPLICATE INPUT LOCKED"
              : "ENTER CHAT  ·  RIGHT-CLICK PROFILE"
            color: root.quietText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.7
          }

          Text {
            text: "R REFRESH  ·  S STEAM"
            color: root.quietText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.7
          }
        }
      }
    }
  }
}
