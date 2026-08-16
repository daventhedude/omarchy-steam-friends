import QtQuick
import qs.Commons

// A compact, data-driven presence visualization. The outer arc is everyone
// online; the inner arc is the subset currently playing. It replaces a purely
// decorative hero blob with useful ambient information while staying quiet
// enough to sit behind the primary controls.
Item {
  id: root

  property int online: 0
  property int playing: 0
  property int total: 0
  property color foreground: Color.popups.text
  property color onlineColor: foreground
  property color playingColor: Color.accent

  readonly property real onlineRatio: total > 0 ? Math.min(1, online / total) : 0
  readonly property real playingRatio: total > 0 ? Math.min(1, playing / total) : 0

  property real animatedOnlineRatio: onlineRatio
  property real animatedPlayingRatio: playingRatio

  Behavior on animatedOnlineRatio {
    NumberAnimation { duration: 520; easing.type: Easing.OutCubic }
  }
  Behavior on animatedPlayingRatio {
    NumberAnimation { duration: 620; easing.type: Easing.OutCubic }
  }

  onAnimatedOnlineRatioChanged: orbit.requestPaint()
  onAnimatedPlayingRatioChanged: orbit.requestPaint()
  onForegroundChanged: orbit.requestPaint()
  onOnlineColorChanged: orbit.requestPaint()
  onPlayingColorChanged: orbit.requestPaint()
  onWidthChanged: orbit.requestPaint()
  onHeightChanged: orbit.requestPaint()

  Canvas {
    id: orbit
    anchors.fill: parent

    function drawArc(context, radius, width, color, progress) {
      var start = -Math.PI / 2
      context.beginPath()
      context.arc(root.width / 2, root.height / 2, radius, start,
        start + Math.PI * 2 * Math.max(0.002, progress), false)
      context.lineWidth = width
      context.lineCap = "round"
      context.strokeStyle = color
      context.stroke()
    }

    onPaint: {
      var context = getContext("2d")
      context.reset()
      context.clearRect(0, 0, width, height)

      var outerRadius = Math.max(2, Math.min(width, height) * 0.40)
      var innerRadius = Math.max(2, outerRadius - Style.spaceReal(12))
      var lineWidth = Math.max(1, Style.spaceReal(2))

      drawArc(context, outerRadius, lineWidth,
        Util.alpha(root.foreground, 0.10), 1)
      drawArc(context, innerRadius, lineWidth,
        Util.alpha(root.foreground, 0.07), 1)
      drawArc(context, outerRadius, lineWidth,
        Util.alpha(root.onlineColor, 0.72), root.animatedOnlineRatio)
      drawArc(context, innerRadius, lineWidth,
        Util.alpha(root.playingColor, 0.92), root.animatedPlayingRatio)
    }
  }
}
