import QtQuick
import qs.Commons
import qs.Ui
import "QuickActions.js" as ActionCatalog

Item {
  id: root

  property var actions: ActionCatalog.defaultActions(true, true)
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string workInAppShortcutText: ""
  signal actionRequested(string actionId, string prompt)

  implicitHeight: actions.length > 0 ? actionFlow.implicitHeight : 0
  visible: actions.length > 0

  Flow {
    id: actionFlow
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.sm

    Repeater {
      model: root.actions

      delegate: Button {
        required property var modelData
        width: root.actions.length > 1
          ? Math.floor((actionFlow.width - actionFlow.spacing) / 2)
          : actionFlow.width
        iconText: String(modelData.icon || "")
        text: String(modelData.label || "")
        tooltipText: text + (String(modelData.id || "") === "work-in-app"
          && root.workInAppShortcutText !== ""
          ? " (" + root.workInAppShortcutText + ")" : "")
        foreground: root.foreground
        background: root.background
        accent: root.accent
        fontFamily: root.fontFamily
        bordered: false
        focusable: true
        leftAlign: true
        Accessible.name: tooltipText
        onClicked: root.actionRequested(
          String(modelData.id || ""), String(modelData.prompt || ""))
      }
    }
  }
}
