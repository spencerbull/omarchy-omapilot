import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "StateColor.js" as StateColor

// The voice node: light bleeding up from the bottom edge of the focused output.
//
// This surface is deliberately inert. It has no input region and never accepts
// keyboard focus, because voice must not move focus out of whatever the user is
// typing in — if talking to OmaPilot steals the caret, the whole premise dies.
// Everything actionable lives on a hotkey or in the console.
//
// Purely presentational: the owner supplies `phase` and `transcript`.
Item {
  id: root

  // dormant | listening | thinking | answering | error
  property string phase: "dormant"
  property string transcript: ""
  // How to finish. Rendered under the caption while listening.
  property string hint: ""
  property var targetScreen: null
  property bool motionEnabled: true

  readonly property bool lit: phase !== "dormant"
  // Each state gets its own hue, derived from the theme accent so it still
  // belongs to the palette. See StateColor.js for why the states rotate rather
  // than using absolute "success green" style colours.
  readonly property color lightColor: StateColor.forPhase(Color.accent, Color.urgent, phase)

  // One driver for the whole node. This is an honest breath on a fixed rhythm,
  // not an audio level: the broker reports recording/transcribing/idle with no
  // amplitude, so a VU meter would be a lie in pixels.
  property real level: 0
  property real presence: lit ? 1 : 0
  // A second, much slower cycle keeps the active listening/thinking surface
  // from feeling like a static lamp. It changes atmosphere only; it still
  // makes no claim about audio.
  property real tide: 0.35
  // The brightest part of the full-width gradient wanders by only a few percent.
  // That slight asymmetry is what keeps the edge from feeling mechanically looped.
  property real drift: 0
  readonly property bool atmosphereActive: motionEnabled
    && (phase === "listening" || phase === "thinking")

  function settleAtmosphere() {
    if (!atmosphereActive) {
      tide = 0.4
      drift = 0
    }
    if (!motionEnabled) level = 0.5
  }

  Behavior on presence {
    enabled: root.motionEnabled
    NumberAnimation { duration: root.lit ? 260 : 420; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    running: root.phase === "listening" && root.motionEnabled
    loops: Animation.Infinite
    NumberAnimation { target: root; property: "level"; to: 1; duration: 820; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "level"; to: 0.34; duration: 980; easing.type: Easing.InOutSine }
  }
  SequentialAnimation {
    id: tideAnimation
    running: root.atmosphereActive
    loops: Animation.Infinite
    NumberAnimation {
      target: root; property: "tide"; to: 1
      duration: root.phase === "thinking" ? 2700 : 3900
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: root; property: "tide"; to: 0.18
      duration: root.phase === "thinking" ? 3400 : 4700
      easing.type: Easing.InOutSine
    }
  }
  SequentialAnimation {
    id: driftAnimation
    running: root.atmosphereActive
    loops: Animation.Infinite
    NumberAnimation {
      target: root; property: "drift"; to: 1
      duration: root.phase === "thinking" ? 4700 : 6300
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: root; property: "drift"; to: -1
      duration: root.phase === "thinking" ? 5600 : 7100
      easing.type: Easing.InOutSine
    }
  }
  // Thinking holds a low steady presence and lets the travelling filament carry
  // the motion, so listening and thinking never read as the same state.
  NumberAnimation {
    id: levelSettleAnimation
    running: root.motionEnabled && root.lit && root.phase !== "listening"
    target: root
    property: "level"
    to: root.phase === "thinking" ? 0.42 : (root.phase === "error" ? 0.9 : 0.62)
    duration: 300
    easing.type: Easing.OutCubic
  }
  onPhaseChanged: settleAtmosphere()
  onMotionEnabledChanged: settleAtmosphere()
  onAtmosphereActiveChanged: settleAtmosphere()

  PanelWindow {
    id: surface
    screen: root.targetScreen
    color: "transparent"
    anchors { bottom: true; left: true; right: true }
    implicitHeight: Style.space(240)
    // Stay mapped through the fade, then release the surface rather than
    // leaving a permanently mapped overlay on the output.
    visible: root.lit || root.presence > 0.001
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omapilot-node"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // The shadow half of "shadow glow": a whisper of theme background rising
    // from the edge. It seats the light in something instead of letting it
    // float, and keeps the transcript legible over bright windows. Kept weak on
    // purpose — this must never read as a panel over the user's work.
    Rectangle {
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: Style.space(190)
      opacity: root.presence
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.0) }
        GradientStop { position: 0.55; color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.30) }
        GradientStop { position: 1.0; color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.62) }
      }
    }

    // The ember spans the complete output. Its transparent horizontal gradient
    // keeps the corners quiet without leaving the lower screen visibly unlit;
    // the body stays sunk below the edge so only its bloom reaches the desktop.
    Item {
      id: emberSource
      visible: false
      anchors { left: parent.left; right: parent.right }
      height: Style.space(64)
      y: parent.height - Style.space(14) - root.tide * Style.space(2)
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.10) }
          GradientStop { position: 0.18 + root.drift * 0.025; color: Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.48) }
          GradientStop { position: 0.50 + root.drift * 0.055; color: root.lightColor }
          GradientStop { position: 0.82 + root.drift * 0.025; color: Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.48) }
          GradientStop { position: 1.0; color: Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.10) }
        }
      }
    }

    // Two blooms, not one. A single wide blur spreads the energy until the light
    // reads as fog; a wide halo under a tight core reads as an actual source.
    MultiEffect {
      anchors.fill: emberSource
      source: emberSource
      autoPaddingEnabled: true
      blurEnabled: true
      blur: 1
      blurMax: 64
      blurMultiplier: 3.2
      brightness: 0.26
      colorization: 1
      colorizationColor: root.lightColor
      opacity: root.presence * (0.24 + root.level * 0.22 + root.tide * 0.06)
      scale: 1 + root.level * 0.035 + root.tide * 0.018
      transformOrigin: Item.Bottom
    }

    MultiEffect {
      anchors.fill: emberSource
      source: emberSource
      autoPaddingEnabled: true
      blurEnabled: true
      blur: 1
      blurMax: 44
      blurMultiplier: 1.5
      brightness: 0.42
      colorization: 1
      colorizationColor: root.lightColor
      opacity: root.presence * (0.14 + root.level * 0.16 + root.tide * 0.04)
      scale: 1 + root.level * 0.022 + root.tide * 0.012
      transformOrigin: Item.Bottom
    }

    // The filament: the crisp edge that makes the glow read as deliberate
    // rather than as a rendering artifact.
    Item {
      id: filamentSource
      visible: false
      width: parent.width * 0.46
      height: Math.max(2, Style.space(2))
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - height

      Rectangle {
        anchors.fill: parent
        radius: height / 2
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.28; color: root.lightColor }
          GradientStop { position: 0.72; color: root.lightColor }
          GradientStop { position: 1.0; color: "transparent" }
        }
        opacity: root.phase === "thinking" ? 0.22 : 0.85
        Behavior on opacity {
          enabled: root.motionEnabled
          NumberAnimation { duration: 240 }
        }
      }

      // Thinking: one short bright runner sweeping the filament. Same
      // vocabulary as the response perimeter runner, flattened to a line, so
      // the surfaces read as one product.
      Rectangle {
        id: runner
        visible: root.phase === "thinking" && root.motionEnabled
        width: parent.width * 0.18
        height: parent.height
        radius: height / 2
        color: root.lightColor
        SequentialAnimation {
          running: runner.visible
          loops: Animation.Infinite
          NumberAnimation {
            target: runner; property: "x"; from: 0
            to: filamentSource.width - runner.width
            duration: 1150; easing.type: Easing.InOutSine
          }
          NumberAnimation {
            target: runner; property: "x"
            to: 0; duration: 1150; easing.type: Easing.InOutSine
          }
        }
      }
    }

    MultiEffect {
      anchors.fill: filamentSource
      source: filamentSource
      autoPaddingEnabled: true
      blurEnabled: true
      blur: 1
      blurMax: 28
      blurMultiplier: 0.9
      brightness: 0.5
      colorization: 0.9
      colorizationColor: root.lightColor
      opacity: root.presence
    }

    // The filament itself, unblurred, on top: one hairline of real light. It
    // fades at both ends too — a hard-terminated line is the one element that
    // would give the whole edge a visible boundary.
    Rectangle {
      width: filamentSource.width
      height: 1
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - 1
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.3; color: root.lightColor }
        GradientStop { position: 0.7; color: root.lightColor }
        GradientStop { position: 1.0; color: "transparent" }
      }
      opacity: root.presence * (root.phase === "thinking" ? 0.35 : 0.55 + root.level * 0.3)
    }

    // ---- the ribbon. Present while the node is listening or thinking, so the
    // surface reads as alive rather than as a static gradient. It is abstract by
    // design: see VoiceWave for why this is not a level meter.
    VoiceWave {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(10)
      width: parent.width * 0.72
      height: Style.space(66)
      accent: root.lightColor
      level: root.level
      motionEnabled: root.motionEnabled
      visible: root.phase === "listening" || root.phase === "thinking"
      intensity: root.presence * (root.phase === "thinking" ? 0.6 : 1)
    }

    // ---- caption. Voice mode's only text.
    //
    // Legibility here has to survive both a white browser and a black terminal
    // without introducing a box, which would undo the ambient premise. Real
    // backdrop blur is unavailable: it needs a Hyprland layer rule, and
    // OmaPilot does not write the user's compositor config.
    //
    // So the backing is a "plate" — two stacked feathered passes sized to the
    // text. Density accumulates at the centre faster than a rim accumulates at
    // the edge, so it stays legible on white while effectively vanishing on
    // dark. The containment appears only where it is needed, with no theme
    // branch and no mode switch.
    Item {
      id: caption
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(68)
      width: Math.min(parent.width * 0.52, Style.space(660))
      height: captionColumn.implicitHeight + Style.space(26)
      opacity: captionText.text === "" && hintText.text === "" ? 0 : root.presence
      Behavior on opacity {
        enabled: root.motionEnabled
        NumberAnimation { duration: 180 }
      }

      Item {
        id: plateSource
        visible: false
        anchors.centerIn: parent
        width: Math.min(parent.width, Math.max(captionText.implicitWidth, hintText.implicitWidth) + Style.space(72))
        height: captionColumn.implicitHeight + Style.space(20)
        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: Color.background
        }
      }
      MultiEffect {
        anchors.fill: plateSource
        source: plateSource
        autoPaddingEnabled: true
        blurEnabled: true
        blur: 1
        blurMax: 32
        blurMultiplier: 1.15
        // Translucent on purpose: the desktop should stay faintly present, or
        // the plate stops being ambient and becomes a redaction bar.
        opacity: 0.56
      }
      MultiEffect {
        anchors.fill: plateSource
        source: plateSource
        autoPaddingEnabled: true
        blurEnabled: true
        blur: 1
        blurMax: 22
        blurMultiplier: 0.5
        opacity: 0.46
      }

      // Transcript above, how-to-finish below, stacked so the plate backs both.
      Column {
        id: captionColumn
        anchors.centerIn: parent
        width: parent.width
        spacing: Style.spacing.xxs
        // Hidden because the MultiEffect below paints the glyphs plus their
        // halo; drawing both would double the stroke weight.
        visible: false

        Text {
          id: captionText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          maximumLineCount: 2
          wrapMode: Text.WordWrap
          text: root.transcript
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          id: hintText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: root.hint
          color: Qt.darker(Color.foreground, 1.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      // A dark halo shaped like the glyphs themselves. This is what buys
      // contrast on bright backgrounds while adding no geometry of its own.
      MultiEffect {
        anchors.fill: captionColumn
        source: captionColumn
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowBlur: 1
        shadowScale: 1
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
        shadowColor: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
        shadowOpacity: 0.72
      }
    }
  }
}
