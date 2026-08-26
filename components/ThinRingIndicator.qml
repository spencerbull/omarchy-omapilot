import QtQuick
import qs.Commons

Item {
  id: root

  property color accent: OmaPilotPalette.accent
  property real level: 0.65
  readonly property real boundedLevel: Math.max(0, Math.min(1, level))
  readonly property real strokeWidth: Math.max(Style.spacing.hairline, width * (2 / 64))
  readonly property real markerWidth: width * (18 / 64)
  readonly property real markerOverhang: width * (6 / 64)

  implicitWidth: Style.space(24)
  implicitHeight: implicitWidth
  Accessible.ignored: true

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: "transparent"
    border.width: root.strokeWidth
    border.color: root.accent
    opacity: 0.55 + root.boundedLevel * 0.45
  }

  Rectangle {
    x: root.width - root.markerWidth + root.markerOverhang
    anchors.verticalCenter: parent.verticalCenter
    width: root.markerWidth
    height: root.strokeWidth
    radius: height / 2
    color: root.accent
    opacity: 0.65 + root.boundedLevel * 0.35
  }
}
