import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

CursorSurface {
  id: root

  required property var friend
  property bool selectedRow: false
  property color contentForeground: Color.foreground
  property color secondaryForeground: Util.alpha(contentForeground, 0.72)
  property color quietForeground: Util.alpha(contentForeground, 0.56)
  property var presencePalette: ({
    playing: Color.accent,
    online: contentForeground,
    busy: Color.urgent,
    urgent: Color.urgent,
    away: Color.muted,
    social: Color.accent,
    offline: Color.muted
  })
  property var presenceTextPalette: presencePalette
  property string fontFamily: Style.font.family
  property double nowMs: Date.now()

  signal activated()
  signal profileRequested()
  signal hoveredRow()

  readonly property color presenceColor: Model.stateColor(friend, presencePalette)
  readonly property color presenceTextColor: Model.stateColor(friend, presenceTextPalette)
  readonly property bool inGame: String(friend.gameName || "") !== ""
  readonly property bool offline: Number(friend.state || 0) <= 0

  width: parent ? parent.width : implicitWidth
  implicitHeight: Style.space(62)
  foreground: contentForeground
  accent: presenceColor
  hasCursor: selectedRow
  fill: Util.alpha(presenceColor,
    inGame ? Style.selectedFillAlpha : Style.hoverFillAlpha)

  Rectangle {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(Style.spacing.hairline, Style.space(2))
    height: root.inGame ? parent.height * 0.58 : parent.height * 0.34
    radius: width / 2
    color: root.presenceColor
    opacity: root.selectedRow ? 1 : 0.58

    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 120 } }
  }

  SteamAvatar {
    id: avatar
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    avatarSize: Style.space(42)
    imageUrl: String(root.friend.avatar || "")
    displayName: String(root.friend.name || "")
    statusColor: root.presenceColor
    statusTextColor: root.presenceTextColor
  }

  Column {
    id: labels
    anchors.left: avatar.right
    anchors.leftMargin: Style.space(11)
    anchors.right: stateColumn.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      width: parent.width
      text: String(root.friend.name || "Unknown friend")
      textFormat: Text.PlainText
      color: root.offline
        ? root.secondaryForeground
        : root.contentForeground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: root.inGame || Number(root.friend.state || 0) > 0
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: root.inGame
        ? "󰊗  " + String(root.friend.gameName || "")
        : (root.offline
          ? Model.relativeTime(root.friend.lastLogoff, root.nowMs)
          : Model.memberSince(root.friend.friendSince))
      textFormat: Text.PlainText
      color: root.inGame
        ? root.presenceTextColor
        : root.secondaryForeground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: root.inGame
      elide: Text.ElideRight
    }
  }

  Column {
    id: stateColumn
    anchors.right: chevron.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, Style.space(104))
    spacing: Style.space(2)

    Text {
      anchors.right: parent.right
      text: Model.stateLabel(root.friend).toUpperCase()
      textFormat: Text.PlainText
      color: root.presenceTextColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0.8
    }

    Text {
      visible: root.inGame && String(root.friend.gameId || "") !== ""
      anchors.right: parent.right
      text: "APP " + String(root.friend.gameId || "")
      textFormat: Text.PlainText
      color: root.quietForeground
      font.family: root.fontFamily
      font.pixelSize: Math.max(1, Math.round(Style.font.caption * 0.8))
    }
  }

  Text {
    id: chevron
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: "›"
    color: root.selectedRow ? root.presenceTextColor : root.quietForeground
    font.family: root.fontFamily
    font.pixelSize: Style.font.title
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hoveredRow()
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.profileRequested()
      else root.activated()
    }
  }
}
