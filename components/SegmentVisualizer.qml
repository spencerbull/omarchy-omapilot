import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: root

  property color accent: OmaPilotPalette.accent
  property real level: 0.5
  property bool levelMetered: false
  property real intensity: 1
  property bool compact: false
  property bool motionEnabled: true
  readonly property int columns: compact ? 9 : 27
  readonly property int rows: compact ? 3 : 7
  readonly property real boundedLevel: Math.max(0, Math.min(1, level))
  readonly property real visualLevel: levelMetered && boundedLevel > 0.025
    ? Math.min(1, Math.pow((boundedLevel - 0.025) / 0.975, 0.62) * 1.18)
    : (levelMetered ? 0 : boundedLevel * 0.78)
  readonly property real trackWidth: width * (compact ? 0.9 : 0.76)
  readonly property real columnGap: compact ? 2 : Math.max(2, Style.spaceReal(3))
  readonly property real rowGap: compact ? 2
    : Math.max(2, Math.min(Style.spaceReal(4), height * 0.035))
  readonly property real segmentHeight: compact ? Math.max(2, height * 0.16)
    : Math.max(4, Math.min(Style.spaceReal(9), height * 0.085))
  readonly property real segmentWidth: Math.max(compact ? 2 : 4,
    (trackWidth - columnGap * (columns - 1)) / columns)
  readonly property real gridHeight: rows * segmentHeight + (rows - 1) * rowGap
  property real phase: 0

  function alphaColor(color, alpha) {
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function litSegments(column) {
    var distance = Math.abs(column - (columns - 1) * 0.5) / ((columns - 1) * 0.5)
    var wobble = 0.55 + 0.45 * Math.sin(phase * 6.2 + column * 0.8)
      * Math.sin(phase * 2.7 - column * 0.31)
    var activity = (1 - distance * 0.62) * (0.2 + visualLevel * 1.15) * wobble
    return Math.round(Math.max(0, Math.min(1, activity)) * rows)
  }

  Timer {
    interval: 33
    repeat: true
    running: root.motionEnabled && root.visible
    onTriggered: root.phase = (root.phase + 0.032) % (Math.PI * 200)
  }

  Item {
    id: segmentSource
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: root.trackWidth
    height: root.gridHeight + 1
    visible: false

    Repeater {
      model: root.columns

      delegate: Item {
        id: segmentColumn
        required property int index
        readonly property int activeRows: root.litSegments(index)
        x: index * (root.segmentWidth + root.columnGap)
        width: root.segmentWidth
        height: root.gridHeight

        Repeater {
          model: root.rows

          delegate: Rectangle {
            required property int index
            readonly property bool active: index < segmentColumn.activeRows
            readonly property bool peak: index === segmentColumn.activeRows - 1
            y: segmentColumn.height - (index + 1) * root.segmentHeight - index * root.rowGap
            width: segmentColumn.width
            height: root.segmentHeight
            color: !active ? root.alphaColor(root.accent, 0.13)
              : root.alphaColor(root.accent,
                peak ? 0.95 : Math.max(0.38, 0.76 - index * 0.055))
          }
        }
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: root.alphaColor(root.accent, 0.3)
    }
  }

  MultiEffect {
    anchors.fill: segmentSource
    source: segmentSource
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 1
    blurMax: 16
    blurMultiplier: 0.65
    brightness: 0.38
    opacity: root.intensity * 0.72
  }

  ShaderEffectSource {
    anchors.fill: segmentSource
    sourceItem: segmentSource
    hideSource: false
    opacity: root.intensity
  }
}
