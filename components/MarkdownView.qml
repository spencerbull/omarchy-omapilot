import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Protocol.js" as Protocol

Item {
  id: root

  property string markdown: ""
  property var images: []
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  readonly property var blocks: Protocol.markdownBlocks(markdown)

  signal linkActivated(string url)
  signal imageLoadRequested(var image)
  signal imagePreviewRequested(string source, string alt)
  signal copyRequested(string text)

  implicitHeight: content.implicitHeight

  Column {
    id: content
    width: parent.width
    spacing: Style.spacing.lg

    Repeater {
      model: root.blocks

      delegate: Loader {
        required property var modelData
        width: content.width
        sourceComponent: modelData.kind === "code" ? codeBlock : markdownBlock
        onLoaded: item.block = modelData
      }
    }

    Repeater {
      model: root.images

      delegate: BorderSurface {
        id: imageCard
        required property var modelData
        readonly property var normalized: Protocol.normalizedImage(modelData)
        readonly property bool localImageFailed: normalized.state === "ready" && responseImage.status === Image.Error
        readonly property bool displayReady: normalized.state === "ready" && !localImageFailed
        width: content.width
        height: displayReady ? Math.min(Style.space(320), Math.max(Style.space(140), responseImage.implicitHeight)) : Style.space(82)
        color: Style.normalFillFor(root.foreground, root.accent)
        borderSpec: Border.controlSpec(imageHover.hovered ? "hover-cursor" : "normal", root.foreground, root.accent)
        radius: Style.cornerRadius
        clip: true

        HoverHandler { id: imageHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: {
            if (imageCard.displayReady)
              root.imagePreviewRequested(imageCard.normalized.source, imageCard.normalized.alt)
            else if (imageCard.normalized.remoteUrl !== ""
                && (imageCard.normalized.state === "placeholder" || imageCard.normalized.state === "error" || imageCard.localImageFailed))
              root.imageLoadRequested(imageCard.normalized)
          }
        }

        Image {
          id: responseImage
          visible: imageCard.normalized.state === "ready"
          anchors.fill: parent
          anchors.margins: Style.spacing.sm
          source: visible ? imageCard.normalized.source : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          cache: false
          Accessible.name: imageCard.normalized.alt
        }

        Column {
          visible: !imageCard.displayReady
          anchors.centerIn: parent
          width: parent.width - Style.spacing.xxl * 2
          spacing: Style.spacing.xs

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: imageCard.localImageFailed && imageCard.normalized.remoteUrl !== "" ? "Image expired — click to reload"
              : imageCard.localImageFailed ? "Image expired"
              : imageCard.normalized.state === "loading" ? "Loading image…"
              : imageCard.normalized.state === "expired" ? "Image expired"
              : imageCard.normalized.state === "error" ? "Image could not be loaded — retry"
              : "Remote image — click to load"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }

          Text {
            visible: text !== ""
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: imageCard.normalized.host || imageCard.normalized.alt
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }
        }
      }
    }
  }

  Component {
    id: markdownBlock

    TextEdit {
      property var block: ({ kind: "markdown", text: "" })
      width: content.width
      height: implicitHeight
      text: block.text
      textFormat: Text.MarkdownText
      readOnly: true
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      wrapMode: Text.Wrap
      selectByMouse: true
      onLinkActivated: function(link) { root.linkActivated(String(link)) }
      Accessible.role: Accessible.StaticText
      Accessible.name: block.text
    }
  }

  Component {
    id: codeBlock

    BorderSurface {
      property var block: ({ kind: "code", language: "", text: "" })
      width: content.width
      height: codeHeader.height + codeFlick.height + contentTopInset + contentBottomInset
      color: Style.normalFillFor(root.foreground, root.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
      radius: Style.cornerRadius

      Row {
        id: codeHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: parent.contentLeftInset + Style.spacing.lg
        anchors.rightMargin: parent.contentRightInset + Style.spacing.sm
        anchors.topMargin: parent.contentTopInset + Style.spacing.xs
        height: Style.spacing.controlHeight

        Text {
          width: parent.width - copyCode.width
          anchors.verticalCenter: parent.verticalCenter
          text: block.language || "code"
          color: Qt.darker(root.foreground, 1.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          elide: Text.ElideRight
        }

        PanelActionButton {
          id: copyCode
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰆏"
          tooltipText: "Copy code"
          foreground: root.foreground
          focusable: true
          Accessible.name: tooltipText
          onClicked: root.copyRequested(block.text)
        }
      }

      Flickable {
        id: codeFlick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: codeHeader.bottom
        anchors.leftMargin: parent.contentLeftInset + Style.spacing.lg
        anchors.rightMargin: parent.contentRightInset + Style.spacing.lg
        height: Math.min(Style.space(240), Math.max(Style.space(40), codeText.implicitHeight + Style.spacing.lg))
        contentWidth: Math.max(width, codeText.implicitWidth)
        contentHeight: codeText.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        TextEdit {
          id: codeText
          width: Math.max(codeFlick.width, implicitWidth)
          readOnly: true
          selectByMouse: true
          text: block.text
          color: root.foreground
          selectionColor: Style.selectionFillFor(root.foreground, root.accent)
          selectedTextColor: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: TextEdit.NoWrap
          Accessible.name: (block.language || "Code") + " block"
        }
      }
    }
  }
}
