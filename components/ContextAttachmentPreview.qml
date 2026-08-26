import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Protocol.js" as Protocol

BorderSurface {
  id: root

  required property var backend
  required property var attachment
  property color foreground: OmaPilotPalette.popups.text
  property color background: OmaPilotPalette.popups.background
  property color accent: OmaPilotPalette.accent
  property string fontFamily: Style.font.family

  readonly property string selectedMode: Protocol.contextRepresentationMode(attachment)
  readonly property var representationOptions: Protocol.contextRepresentationOptions(attachment)
  readonly property bool popupOpen: representationSelector.popupOpen

  implicitHeight: Style.space(92)
  color: OmaPilotPalette.normalFill(foreground)
  borderSpec: Border.flat(OmaPilotPalette.normalBorder(foreground), Style.normalBorderWidth)
  radius: Style.cornerRadius
  padding: Style.spacing.md

  function selectedPreview() {
    var values = attachment && attachment.representations && attachment.representations.length !== undefined
      ? attachment.representations : []
    var ids = attachment && attachment.selectedRepresentationIds
        && attachment.selectedRepresentationIds.length !== undefined
      ? attachment.selectedRepresentationIds : []
    for (var i = 0; i < values.length; i++)
      if (ids.indexOf(values[i].id) >= 0 && String(values[i].preview || "") !== "") return String(values[i].preview)
    return ids.indexOf("image") >= 0 ? "Visual appearance and layout will be shared." : "Selected context will be shared."
  }

  function closePopup() { representationSelector.close() }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: root.contentLeftInset
    anchors.rightMargin: root.contentRightInset
    anchors.topMargin: root.contentTopInset
    anchors.bottomMargin: root.contentBottomInset
    spacing: Style.spacing.md

    Rectangle {
      Layout.preferredWidth: Style.space(80)
      Layout.fillHeight: true
      radius: Math.max(1, Style.cornerRadius - Style.spacing.xxs)
      color: OmaPilotPalette.normalFill(root.foreground)
      clip: true

      Image {
        anchors.fill: parent
        source: root.attachment && root.attachment.previewImage
          ? String(root.attachment.previewImage.source || root.attachment.previewImage.localUrl || "") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
      }

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Style.spacing.xxs
        width: kindLabel.implicitWidth + Style.spacing.md * 2
        height: kindLabel.implicitHeight + Style.spacing.xxs * 2
        radius: height / 2
        color: root.background

        Text {
          id: kindLabel
          anchors.centerIn: parent
          text: root.selectedMode.toUpperCase().replace("+", " + ")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.spacing.xxs

      Text {
        Layout.fillWidth: true
        text: String(root.attachment && root.attachment.title || "Context capture")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        Layout.fillWidth: true
        Layout.fillHeight: true
        text: root.selectedPreview()
        color: OmaPilotPalette.darkForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        maximumLineCount: 2
        elide: Text.ElideRight
        wrapMode: Text.Wrap
      }
    }

    Dropdown {
      id: representationSelector
      Layout.preferredWidth: Style.space(150)
      Layout.alignment: Qt.AlignVCenter
      showLabel: false
      rowHeight: Style.space(34)
      options: root.representationOptions
      value: root.selectedMode
      foreground: root.foreground
      background: root.background
      onChanged: function(value) { root.backend.setContextRepresentation(root.attachment.id, value) }
    }

    PanelActionButton {
      Layout.alignment: Qt.AlignVCenter
      iconText: "󰆴"
      tooltipText: "Remove context"
      foreground: root.foreground
      hoverColor: OmaPilotPalette.urgent
      size: Style.space(34)
      bordered: true
      focusable: true
      Accessible.name: tooltipText
      onClicked: root.backend.removeContextAttachment(root.attachment.id)
    }
  }
}
