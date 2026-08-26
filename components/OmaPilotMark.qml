import QtQuick
import qs.Commons

Item {
  id: root

  property real size: Style.space(42)
  property color foreground: Color.popups.text
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool active: false
  property bool motionEnabled: true
  property real pulse: 0.65

  implicitWidth: size
  implicitHeight: size
  transformOrigin: Item.Center
  scale: active ? 0.975 : 1

  Behavior on scale {
    enabled: root.motionEnabled
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }

  onActiveChanged: if (!active) pulse = 0.65

  SequentialAnimation {
    running: root.active && root.visible && root.motionEnabled
    loops: Animation.Infinite
    NumberAnimation {
      target: root
      property: "pulse"
      to: 1
      duration: 620
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: root
      property: "pulse"
      to: 0.42
      duration: 740
      easing.type: Easing.InOutSine
    }
  }

  Rectangle {
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: Style.cornerRadius
    color: Style.hoverFillFor(root.foreground, root.accent)
    opacity: root.active ? 1 : 0

    Behavior on opacity {
      enabled: root.motionEnabled
      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
  }

  SplitIndicator {
    anchors.centerIn: parent
    width: root.size * 0.72
    height: root.size * 0.46
    gap: width * 0.18
    accent: root.accent
    level: root.active ? root.pulse : 0.65
  }
}
