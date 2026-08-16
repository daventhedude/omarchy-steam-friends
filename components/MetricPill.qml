import QtQuick
import qs.Commons

Rectangle {
  id: root

  property string value: "0"
  property string label: "ONLINE"
  property color accent: "#66c0f4"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  implicitWidth: metricRow.implicitWidth + Style.space(16)
  implicitHeight: Style.space(28)
  radius: height / 2
  color: Qt.rgba(accent.r, accent.g, accent.b, 0.12)
  border.width: 1
  border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.36)

  Row {
    id: metricRow
    anchors.centerIn: parent
    spacing: Style.space(5)

    Text {
      text: root.value
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      color: Qt.darker(root.foreground, 1.35)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0.7
    }
  }
}
