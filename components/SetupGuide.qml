import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  required property string stage
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  readonly property bool voiceStage: stage === "voice"
  readonly property string titleText: voiceStage ? "Set up voice" : "Add global keybinds"
  readonly property string detailText: voiceStage
    ? "Enable voice and connect ElevenLabs for spoken replies. Listening uses Voxtype."
    : "Open Desktop settings, then press Install global hotkeys. Existing shortcut chords are preserved."
  readonly property string actionText: voiceStage ? "Set up voice" : "Open global keybinds"

  signal actionRequested()

  implicitHeight: 34
  color: "#0a0a0d"
  borderSpec: Border.flat("#292a2f", 1)
  radius: 0
  Accessible.role: Accessible.Grouping
  Accessible.name: titleText + ". " + detailText

  RowLayout {
    id: content
    anchors.fill: parent
    anchors.leftMargin: 10
    anchors.rightMargin: 10
    spacing: 9

    Text {
      Layout.fillWidth: true
      text: root.titleText
      color: "#d5d5da"
      font.family: "JetBrains Mono"
      font.pixelSize: 12
      elide: Text.ElideRight
    }

    Button {
      text: root.actionText
      foreground: "#58d1dc"
      background: "#0a0a0d"
      active: false
      bordered: false
      focusable: true
      Accessible.name: text
      onClicked: root.actionRequested()
    }
  }
}
