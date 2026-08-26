import QtQuick
import qs.Commons
import "Presentation.js" as Presentation

Item {
  id: root

  property string current: "agent"
  property var tabs: Presentation.settingsTabs()
  property color foreground: OmaPilotPalette.popups.text
  property color accent: OmaPilotPalette.accent
  property string fontFamily: Style.font.family
  property bool motionEnabled: true
  readonly property int currentIndex: {
    var ids = Presentation.settingsTabIds()
    var index = ids.indexOf(Presentation.normalizedSettingsTab(root.current))
    return index < 0 ? 0 : index
  }

  signal selected(string id)

  implicitHeight: Style.space(24)
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
    spacing: Style.space(16)

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
          ? root.accent : OmaPilotPalette.darkForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
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
    height: Style.spacing.hairline

    Rectangle {
      anchors.fill: parent
      color: OmaPilotPalette.normalBorder(root.foreground)
    }

    Rectangle {
      id: activeSegment
      height: parent.height
      width: Math.max(Style.space(24), activeTabWidth)
      x: activeTabX
      color: root.accent

      readonly property real activeTabX: {
        var item = tabRepeater.itemAt(root.currentIndex)
        return item ? item.x : 0
      }
      readonly property real activeTabWidth: {
        var item = tabRepeater.itemAt(root.currentIndex)
        return item ? item.width : Style.space(24)
      }
    }
  }
}
