import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

Item {
  id: root

  property string imageUrl: ""
  property string displayName: ""
  property color statusColor: Color.muted
  property color statusTextColor: Color.popups.text
  property real avatarSize: Style.space(44)
  property bool showStatus: true
  readonly property string safeImageUrl: Model.safeAvatarUrl(imageUrl)

  implicitWidth: avatarSize
  implicitHeight: avatarSize

  BorderSurface {
    id: frame
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(root.statusColor, Style.selectedFillAlpha)
    borderSpec: Border.controlSpec("normal", root.statusColor, root.statusColor)

    Text {
      anchors.centerIn: parent
      text: Model.initials(root.displayName)
      textFormat: Text.PlainText
      color: root.statusTextColor
      font.family: Style.font.family
      font.pixelSize: Math.round(root.avatarSize * 0.3)
      font.bold: true
    }

    Image {
      id: avatarImage
      anchors.fill: parent
      anchors.margins: Style.space(2)
      source: root.safeImageUrl
      sourceSize.width: Math.round(root.avatarSize * 2)
      sourceSize.height: Math.round(root.avatarSize * 2)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      smooth: true
      visible: status === Image.Ready

      Behavior on opacity { NumberAnimation { duration: 180 } }
    }
  }

  Rectangle {
    visible: root.showStatus
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: -Style.space(2)
    anchors.bottomMargin: -Style.space(2)
    width: Style.space(12)
    height: width
    radius: width / 2
    color: root.statusColor
    border.width: Math.max(Style.spacing.hairline, Style.normalBorderWidth)
    border.color: Color.popups.background
  }
}
