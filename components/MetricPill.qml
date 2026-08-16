import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property string value: "0"
  property string label: "ONLINE"
  property color accent: Color.accent
  property color accentText: accent
  property color foreground: Color.popups.text
  property color secondaryForeground: Util.alpha(foreground, 0.76)
  property string fontFamily: Style.font.family

  implicitWidth: metricRow.implicitWidth + Style.space(16)
  implicitHeight: Style.space(28)
  radius: height / 2
  color: Util.alpha(accent, Style.hoverFillAlpha)
  borderSpec: Border.controlSpec("normal", accent, accent)

  Row {
    id: metricRow
    anchors.centerIn: parent
    spacing: Style.space(5)

    Text {
      text: root.value
      color: root.accentText
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      color: root.secondaryForeground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0.7
    }
  }
}
