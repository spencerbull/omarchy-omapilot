import QtQuick
import qs.Commons
import "Presentation.js" as Presentation

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

  implicitHeight: 24
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
    anchors.verticalCenter: parent.verticalCenter
    spacing: 16

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
          ? root.accent : "#74757c"
        font.family: "JetBrains Mono"
        font.pixelSize: 10
        font.bold: false
        Accessible.role: Accessible.PageTab
        Accessible.name: text
        Accessible.checkable: true
        Accessible.checked: tabLabel.currentTab

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
      color: "#1d1e22"
    }

    Rectangle {
      id: activeSegment
      height: parent.height
      width: Math.max(24, activeTabWidth)
      x: activeTabX
      color: root.accent

      readonly property real activeTabX: {
        var item = tabRepeater.itemAt(root.currentIndex)
        return item ? item.x : 0
      }
      readonly property real activeTabWidth: {
        var item = tabRepeater.itemAt(root.currentIndex)
        return item ? item.width : 24
      }
    }
  }
}
