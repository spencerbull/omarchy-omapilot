import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Protocol.js" as Protocol

BorderSurface {
  id: root

  required property var backend
  required property var attachment
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  readonly property string selectedMode: Protocol.contextRepresentationMode(attachment)
  readonly property var representationOptions: Protocol.contextRepresentationOptions(attachment)
  readonly property bool popupOpen: representationSelector.popupOpen

  implicitHeight: Style.space(86)
  color: Style.normalFillFor(foreground, accent)
  borderSpec: Border.controlSpec("normal", foreground, accent)
  radius: Style.cornerRadius

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
    anchors.margins: Style.spacing.sm
    spacing: Style.spacing.md

    Rectangle {
      Layout.preferredWidth: Style.space(92)
      Layout.fillHeight: true
      radius: Math.max(1, Style.cornerRadius - Style.spacing.xxs)
      color: Qt.darker(root.background, 1.15)
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
        id: kindPill
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Style.spacing.xxs
        // A pill wants its padding on both sides. `sm` and `xxs` were the
        // whole horizontal and vertical allowance, so 2px a side stood in for
        // padding on a shape whose radius is half its height.
        //
        // Bounded, because the thumbnail behind it clips and the combined
        // modes are long: measured against the shipped theme, "ELEMENT +
        // IMAGE" wants 112px in the 90px this leaves, and "TEXT + IMAGE"
        // wants 92px. The wider padding did not start that — "ELEMENT +
        // IMAGE" already overflowed at 94px — but it added a second label to
        // the list, so the cap belongs in the same change.
        width: Math.min(kindLabel.implicitWidth + Style.spacing.md * 2,
          parent.width - Style.spacing.xxs * 2)
        height: kindLabel.implicitHeight + Style.spacing.xxs * 2
        radius: height / 2
        color: Color.popups.background
        opacity: 0.9

        Text {
          id: kindLabel
          anchors.centerIn: parent
          // Elides inside the pill rather than under the thumbnail's clip: a
          // label cut by a clip looks like a rendering fault, and one cut by
          // an ellipsis looks like a label that ran out of room.
          width: Math.min(implicitWidth, kindPill.width - Style.spacing.md * 2)
          elide: Text.ElideRight
          text: root.selectedMode.toUpperCase().replace("+", " + ")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          // Capitals set at default tracking clump. Same 0.7 the setup
          // guide's progress label already uses for the same reason.
          font.letterSpacing: 0.7
          Accessible.role: Accessible.StaticText
          Accessible.name: root.selectedMode.toUpperCase().replace("+", " + ")
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
        color: Qt.darker(root.foreground, 1.4)
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

    Button {
      Layout.alignment: Qt.AlignVCenter
      iconText: "󰆴"
      tooltipText: "Remove context"
      foreground: root.foreground
      background: root.background
      bordered: true
      focusable: true
      horizontalPadding: Style.spacing.md
      verticalPadding: Style.spacing.md
      Accessible.name: tooltipText
      onClicked: root.backend.removeContextAttachment(root.attachment.id)
    }
  }
}
