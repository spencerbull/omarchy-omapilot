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

  implicitHeight: Style.space(34)
  color: Style.normalFillFor(foreground, accent)
  borderSpec: Border.controlSpec("normal", foreground, accent)
  radius: Style.cornerRadius
  Accessible.role: Accessible.Grouping
  Accessible.name: titleText + ". " + detailText

  RowLayout {
    id: content
    anchors.fill: parent
    anchors.leftMargin: root.contentLeftInset + Style.spacing.xl
    anchors.rightMargin: root.contentRightInset + Style.spacing.xl
    spacing: Style.space(9)

    Text {
      Layout.fillWidth: true
      text: root.titleText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Button {
      text: root.actionText
      foreground: root.accent
      background: root.background
      fontFamily: root.fontFamily
      active: false
      bordered: false
      focusable: true
      Accessible.name: text
      onClicked: root.actionRequested()
    }
  }
}
