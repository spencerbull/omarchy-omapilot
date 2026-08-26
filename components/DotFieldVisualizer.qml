import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: root

  property color accent: Color.accent
  property real level: 0.5
  property bool levelMetered: false
  property real intensity: 1
  property bool motionEnabled: true
  readonly property int columns: 46
  readonly property int rows: 7
  readonly property real boundedLevel: Math.max(0, Math.min(1, level))
  readonly property real visualLevel: levelMetered && boundedLevel > 0.025
    ? Math.min(1, Math.pow((boundedLevel - 0.025) / 0.975, 0.62) * 1.18)
    : (levelMetered ? 0 : boundedLevel * 0.78)
  readonly property real trackWidth: width * 0.84
  readonly property real columnStep: trackWidth / (columns - 1)
  readonly property real rowStep: Math.min(13, height * 0.11)
  readonly property real fieldHeight: rowStep * (rows - 1)
  readonly property real dotPadding: 5.2
  property real phase: 0

  function alphaColor(color, alpha) {
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function dotIntensity(column, row) {
    var horizontal = 1 - Math.abs(column - (columns - 1) * 0.5) / ((columns - 1) * 0.5) * 0.58
    var vertical = 1 - Math.abs(row - (rows - 1) * 0.5) / ((rows - 1) * 0.5) * 0.44
    var travelling = 0.5 + 0.5 * Math.sin(column * 0.42 - phase * 4.2 + row * 0.5)
    return Math.max(0.05, Math.min(0.95,
      (0.12 + visualLevel * 0.94) * horizontal * vertical * (0.42 + travelling * 0.58)))
  }

  Timer {
    interval: 33
    repeat: true
    running: root.motionEnabled && root.visible
    onTriggered: root.phase = (root.phase + 0.032) % (Math.PI * 200)
  }

  Item {
    id: dotSource
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: root.trackWidth + root.dotPadding
    height: root.fieldHeight + root.dotPadding
    visible: false

    Repeater {
      model: root.columns * root.rows

      delegate: Rectangle {
        required property int index
        readonly property int column: index % root.columns
        readonly property int row: Math.floor(index / root.columns)
        readonly property real strength: root.dotIntensity(column, row)
        readonly property real diameter: strength > 0.55 ? 5.2 : 4
        x: root.dotPadding * 0.5 + column * root.columnStep - diameter * 0.5
        y: root.dotPadding * 0.5 + row * root.rowStep - diameter * 0.5
        width: diameter
        height: diameter
        radius: diameter * 0.5
        color: root.alphaColor(strength > 0.55 ? Qt.lighter(root.accent, 1.3) : root.accent,
          strength)
      }
    }
  }

  MultiEffect {
    anchors.fill: dotSource
    source: dotSource
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 1
    blurMax: 12
    blurMultiplier: 0.55
    brightness: 0.42
    opacity: root.intensity * 0.66
  }

  ShaderEffectSource {
    anchors.fill: dotSource
    sourceItem: dotSource
    hideSource: false
    opacity: root.intensity
  }
}
