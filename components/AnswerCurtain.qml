import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "StateColor.js" as StateColor
import "." as OmaPilot

// The answer curtain: slides down from the top of the focused output, under the
// Omarchy bar, holds the response, then leaves.
//
// Unfocused and click-through outside the answer viewport, so an answer can
// arrive while the user keeps typing. `ExclusionMode.Normal` with a zero zone
// means it respects the bar's reserved strip but reserves nothing itself, so no
// window ever reflows.
//
// The slide is ours rather than the compositor's: Omarchy pins layersIn and
// layersOut to a global fade, so the surface stays static and the card animates
// its own y.
Item {
  id: root

  property bool shown: false
  property string question: ""
  property string markdown: ""
  property var images: []
  property string provenance: ""
  property bool failed: false
  property var targetScreen: null
  property bool motionEnabled: true
  property color finishedColor: OmaPilotPalette.finished

  // A delivered answer is its own state, so the curtain does not reuse the
  // listening colour.
  readonly property color lightColor:
    StateColor.forPhase(OmaPilotPalette.accent, OmaPilotPalette.muted, finishedColor, OmaPilotPalette.urgent,
                        failed ? "error" : "answering")

  signal linkActivated(string url)

  onShownChanged: if (shown) answerScroll.contentY = 0

  PanelWindow {
    id: surface
    screen: root.targetScreen
    color: "transparent"
    anchors { top: true; left: true; right: true }
    implicitHeight: Style.space(520)
    // Keep the surface mapped while the exit animation plays out.
    visible: root.shown || card.slid > 0.001
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    // Preserve the ambient surface's click-through behavior outside the card.
    // Keeping this region stable also lets streaming content become scrollable
    // without remapping the input mask.
    mask: Region {
      item: card
    }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omapilot-curtain"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
      id: card
      // 0 = fully retracted above the edge, 1 = docked.
      property real slid: root.shown ? 1 : 0
      Behavior on slid {
        enabled: root.motionEnabled
        NumberAnimation {
          duration: root.shown ? 300 : 220
          easing.type: root.shown ? Easing.OutQuint : Easing.OutCubic
        }
      }

      width: Math.min(parent.width - Style.space(96), Style.space(940))
      readonly property real naturalBodyHeight:
        provenanceRow.height + body.spacing + answerContent.implicitHeight
      height: Math.min(surface.height - Style.space(24),
                       naturalBodyHeight + Style.space(52))
      anchors.horizontalCenter: parent.horizontalCenter
      y: -height * (1 - card.slid) + Style.space(14) * card.slid
      opacity: card.slid

      BorderSurface {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: OmaPilotPalette.popups.background
        borderSpec: Border.flat(OmaPilotPalette.popups.border, Math.max(1, Style.normalBorderWidth))
      }

      // An edge-lit seam along the top: brightest at the centre, gone by the
      // corners. A flat bar of colour would read as a progress indicator; the
      // gradient reads as the same light the node emits, arriving from above.
      Rectangle {
        width: parent.width - Style.spacing.xxs
        height: Style.spacing.hairline
        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.spacing.hairline
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.5; color: Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.85) }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }

      // The card's own bloom, cast downward, so the curtain looks lit by the
      // same source as the node rather than pasted onto the desktop.
      Item {
        id: glowSource
        visible: false
        width: parent.width * 0.7
        height: Style.space(4)
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - Style.spacing.xxs
        Rectangle { anchors.fill: parent; radius: height / 2; color: root.lightColor }
      }
      MultiEffect {
        anchors.fill: glowSource
        source: glowSource
        autoPaddingEnabled: true
        blurEnabled: true
        blur: 1
        blurMax: 40
        blurMultiplier: 1.6
        brightness: 0.35
        colorization: 1
        colorizationColor: root.lightColor
        opacity: 0.5 * card.slid
        z: -1
      }

      Column {
        id: body
        anchors {
          left: parent.left; right: parent.right; top: parent.top
          leftMargin: Style.space(30); rightMargin: Style.space(30)
          topMargin: Style.space(24)
        }
        height: Math.max(0, parent.height - Style.space(52))
        spacing: Style.spacing.xxl

        // Provenance row: what was asked, and who answered. Nothing else — no
        // logo, no gear, no buttons. Restraint is the point.
        Item {
          id: provenanceRow
          width: parent.width
          height: Math.max(askText.implicitHeight, whoText.implicitHeight)
          Text {
            id: askText
            anchors.left: parent.left
            anchors.right: whoText.left
            anchors.rightMargin: Style.spacing.xxl
            elide: Text.ElideRight
            text: root.question
            color: OmaPilotPalette.darkForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            id: whoText
            anchors.right: parent.right
            text: root.provenance
            color: root.failed ? OmaPilotPalette.urgent : OmaPilotPalette.darkForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        Flickable {
          id: answerScroll
          objectName: "answerCurtainScroll"
          width: parent.width
          height: Math.max(0, body.height - provenanceRow.height - body.spacing)
          contentWidth: width
          contentHeight: answerContent.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          OmaPilot.MarkdownView {
            id: answerContent
            width: answerScroll.width
            markdown: root.markdown
            images: root.images
            foreground: OmaPilotPalette.popups.text
            background: OmaPilotPalette.popups.background
            accent: root.lightColor
            fontFamily: Style.font.family
            onLinkActivated: function(url) { root.linkActivated(url) }
          }
        }
      }
    }
  }
}
