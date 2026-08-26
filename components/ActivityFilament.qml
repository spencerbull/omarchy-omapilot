import QtQuick
import QtQuick.Effects
import qs.Commons

// A single hairline that replaces the composer's border.
//
// The old panel expressed focus and activity with a box: a bordered surface
// whose stroke changed colour, plus a runner travelling its perimeter. Both
// read as an application window sitting on the desktop. This is the same
// information as one line of light, and it shares its vocabulary with the voice
// node's filament so the panel and the ambient layer look like one product.
Item {
  id: root

  property color accent: OmaPilotPalette.accent
  property color foreground: OmaPilotPalette.popups.text
  property bool focused: false
  property bool active: false
  property bool motionEnabled: true

  implicitHeight: 1

  // Resting rail. Barely there, so the composer reads as text on the panel
  // rather than as a control with a chrome edge.
  Rectangle {
    id: rail
    anchors.fill: parent
    color: root.focused ? root.accent : OmaPilotPalette.muted
    opacity: root.active ? 0.2 : (root.focused ? 0.7 : 0.28)
    Behavior on opacity {
      enabled: root.motionEnabled
      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    Behavior on color {
      enabled: root.motionEnabled
      ColorAnimation { duration: 160 }
    }
  }

  // The sweep, shown only while a response is in flight. Flattened from the
  // response card's perimeter runner: same short bright segment, same easing,
  // travelling a line instead of a rectangle.
  Item {
    id: sweepSource
    anchors.fill: parent
    visible: false

    Rectangle {
      id: sweep
      width: Math.max(Style.space(60), parent.width * 0.16)
      height: parent.height
      color: root.accent
    }

    SequentialAnimation {
      running: root.active && root.motionEnabled && root.width > 0
      loops: Animation.Infinite
      NumberAnimation {
        target: sweep; property: "x"; from: 0
        to: Math.max(0, sweepSource.width - sweep.width)
        duration: 1150; easing.type: Easing.InOutSine
      }
      NumberAnimation {
        target: sweep; property: "x"
        to: 0; duration: 1150; easing.type: Easing.InOutSine
      }
    }
  }

  MultiEffect {
    anchors.fill: sweepSource
    source: sweepSource
    visible: root.active
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 1
    blurMax: 16
    blurMultiplier: 0.8
    brightness: 0.45
    colorization: 1
    colorizationColor: root.accent
    opacity: root.active ? 1 : 0
    Behavior on opacity {
      enabled: root.motionEnabled
      NumberAnimation { duration: 180 }
    }
  }
}
