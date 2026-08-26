import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  property string label: ""
  property string description: ""
  property string accessibleName: label
  property bool checked: false
  property color foreground: OmaPilotPalette.popups.text
  property color accent: OmaPilotPalette.accent
  property string fontFamily: Style.font.family
  readonly property color mutedForeground: OmaPilotPalette.darkForeground

  signal clicked()

  implicitWidth: content.implicitWidth
  implicitHeight: content.implicitHeight
  activeFocusOnTab: true
  Accessible.role: Accessible.CheckBox
  Accessible.name: accessibleName
  Accessible.description: description
  Accessible.checkable: true
  Accessible.checked: checked
  Accessible.focusable: true
  Accessible.onPressAction: root.trigger()

  function trigger() {
    if (root.enabled) root.clicked()
  }

  Keys.onReturnPressed: root.trigger()
  Keys.onEnterPressed: root.trigger()
  Keys.onSpacePressed: root.trigger()

  RowLayout {
    id: content
    anchors.fill: parent
    spacing: Style.spacing.md

    ColumnLayout {
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      visible: root.label !== "" || root.description !== ""
      spacing: Style.spacing.xs

      Text {
        Layout.fillWidth: true
        visible: root.label !== ""
        text: root.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
        Accessible.ignored: true
      }

      Text {
        Layout.fillWidth: true
        visible: root.description !== ""
        text: root.description
        color: root.mutedForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
        Accessible.ignored: true
      }
    }

    RowLayout {
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.spacing.sm

      Text {
        Layout.alignment: Qt.AlignVCenter
        text: root.checked ? "On" : "Off"
        color: root.mutedForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Accessible.ignored: true
      }

      ToggleSwitch {
        Layout.alignment: Qt.AlignVCenter
        checked: root.checked
        trackHeight: Style.space(16)
        cursorPad: Style.spacing.xxs
        cursorRing: true
        interactive: false
        hasCursor: root.activeFocus || pointer.containsMouse
        foreground: root.foreground
        accent: root.accent
      }
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      root.forceActiveFocus()
      root.trigger()
    }
  }
}
