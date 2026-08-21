import QtQuick
import QtQuick.Effects
import qs.Commons
import "Presentation.js" as Presentation

// Quiet text tabs with the same filament language as the composer.
// A faint full-width rail, plus a short accent glow that sits under the
// current label. The group is one Tab stop; h / l / Left / Right move
// between tabs without walking every label.
Item {
  id: root

  property string current: "agent"
  property var tabs: Presentation.settingsTabs()
  property color foreground: Color.popups.text
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool motionEnabled: true
  readonly property int currentIndex: {
    var ids = Presentation.settingsTabIds()
    var index = ids.indexOf(Presentation.normalizedSettingsTab(root.current))
    return index < 0 ? 0 : index
  }

  signal selected(string id)

  implicitHeight: tabRow.implicitHeight + Style.spacing.sm + rail.height
  implicitWidth: tabRow.implicitWidth
  activeFocusOnTab: true
  Accessible.role: Accessible.PageTabList
  Accessible.name: "Settings sections"
  Accessible.focusable: true

  function selectByDelta(delta) {
    root.selected(Presentation.adjacentSettingsTab(root.current, delta))
  }

  Keys.onPressed: function(event) {
    var unmodified = event.modifiers === Qt.NoModifier
      || event.modifiers === Qt.KeypadModifier
    if (!unmodified) return
    if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
      root.selectByDelta(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
      root.selectByDelta(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Home) {
      root.selected(Presentation.settingsTabIds()[0])
      event.accepted = true
    } else if (event.key === Qt.Key_End) {
      var ids = Presentation.settingsTabIds()
      root.selected(ids[ids.length - 1])
      event.accepted = true
    }
  }

  Row {
    id: tabRow
    spacing: Style.spacing.xl

    Repeater {
      id: tabRepeater
      model: root.tabs

      delegate: Text {
        id: tabLabel
        required property var modelData
        required property int index
        readonly property string tabId: String(modelData.id || "")
        readonly property bool currentTab: tabId === Presentation.normalizedSettingsTab(root.current)

        text: String(modelData.label || "")
        color: tabLabel.currentTab || tabHover.hovered || (root.activeFocus && index === root.currentIndex)
          ? root.foreground : Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: tabLabel.currentTab
        opacity: tabLabel.currentTab ? 1 : 0.86
        Accessible.role: Accessible.PageTab
        Accessible.name: text
        Accessible.checkable: true
        Accessible.checked: tabLabel.currentTab

        Behavior on color {
          enabled: root.motionEnabled
          ColorAnimation { duration: 140 }
        }

        HoverHandler {
          id: tabHover
          cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
          onTapped: root.selected(tabLabel.tabId)
        }
      }
    }
  }

  Item {
    id: rail
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1

    Rectangle {
      anchors.fill: parent
      color: root.activeFocus ? root.accent : Qt.darker(root.foreground, 1.9)
      opacity: root.activeFocus ? 0.55 : 0.28
      Behavior on opacity {
        enabled: root.motionEnabled
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
      Behavior on color {
        enabled: root.motionEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: glowSource
      anchors.fill: parent
      visible: false

      Rectangle {
        id: glowSegment
        height: parent.height
        width: Math.max(Style.space(24), activeTabWidth)
        x: activeTabX
        color: root.accent

        readonly property real activeTabX: {
          var _w = tabRow.width + tabRepeater.count
          var item = tabRepeater.itemAt(root.currentIndex)
          return item ? item.x : _w * 0
        }
        readonly property real activeTabWidth: {
          var _w = tabRow.width + tabRepeater.count
          var item = tabRepeater.itemAt(root.currentIndex)
          return item ? item.width : Math.max(Style.space(24), _w * 0 + Style.space(36))
        }

        Behavior on x {
          enabled: root.motionEnabled
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on width {
          enabled: root.motionEnabled
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
      }
    }

    MultiEffect {
      anchors.fill: glowSource
      source: glowSource
      autoPaddingEnabled: true
      blurEnabled: true
      blur: 1
      blurMax: 16
      blurMultiplier: 0.8
      brightness: 0.45
      colorization: 1
      colorizationColor: root.accent
    }

    Rectangle {
      height: parent.height
      width: glowSegment.width
      x: glowSegment.x
      color: root.accent
      opacity: 0.9
    }
  }
}
