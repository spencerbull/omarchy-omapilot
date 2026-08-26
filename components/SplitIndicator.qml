import QtQuick
import qs.Commons

Item {
  id: root

  property color accent: Color.accent
  property real level: 0.65
  property real gap: width * 0.18
  readonly property real boundedLevel: Math.max(0, Math.min(1, level))
  readonly property real segmentWidth: Math.max(0, (width - gap) / 2)
  readonly property real segmentHeight: Math.max(
    Style.spaceReal(2), Math.min(height * (0.08 + boundedLevel * 0.08), Style.spaceReal(8)))

  implicitWidth: Style.space(64)
  implicitHeight: Style.space(16)
  Accessible.ignored: true

  Rectangle {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: root.segmentWidth
    height: root.segmentHeight
    radius: height / 2
    opacity: 0.5 + root.boundedLevel * 0.5
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: Qt.darker(root.accent, 1.55) }
      GradientStop { position: 1; color: root.accent }
    }
  }

  Rectangle {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: root.segmentWidth
    height: root.segmentHeight
    radius: height / 2
    opacity: 0.5 + root.boundedLevel * 0.5
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: root.accent }
      GradientStop { position: 1; color: Qt.darker(root.accent, 1.55) }
    }
  }
}
