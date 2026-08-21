// OmaPilot ambient design mock — voice node + response curtain.
//
// Standalone on purpose: this runs outside the Omarchy shell process so the
// concept can be judged on a real desktop before any production QML moves.
// It therefore reads the live Omarchy palette off disk instead of importing
// qs.Commons, and owns its own layer-shell surfaces exactly the way the
// production overlay entrypoint would.
//
//   run:    quickshell -p design/voice-node-mock.qml
//   drive:  qs -p design/voice-node-mock.qml ipc call node state listening
//           states: dormant | listening | thinking | answering | error
//
// Two surfaces, no window chrome, no focus theft:
//   * voice node   — bottom edge, click-through, keyboardFocus None. Light
//                    bleeding up from the screen edge. Never a widget.
//   * curtain      — top edge, slides down under the omarchy bar, holds the
//                    answer, then leaves.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root

  // ---------------------------------------------------------------- palette
  // Same beacon trick the user's other Quickshell configs use: colors.toml
  // gets a fresh inode on every omarchy theme swap, theme.name is rewritten
  // in place, so watch theme.name and reload colors.toml from it.
  readonly property string themeDir: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"
  readonly property string colorsPath: themeDir + "/colors.toml"
  readonly property string themeNamePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"

  property color background: "#101315"
  property color foreground: "#cacccc"
  property color accent: "#7aa2f7"
  property color urgent: "#a55555"
  property color muted: "#707880"

  readonly property string mono: "JetBrainsMono Nerd Font"

  // The one colour the whole ambient layer is built from. Voice is accent;
  // failure is urgent. Nothing else gets its own hue.
  readonly property color lightColor: phase === "error" ? urgent : accent

  function parseColors(text) {
    const re = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/
    const lines = String(text || "").split("\n")
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(re)
      if (!m) continue
      if (m[1] === "background") root.background = m[2]
      else if (m[1] === "foreground") root.foreground = m[2]
      else if (m[1] === "color4") root.accent = m[2]
      else if (m[1] === "color1") root.urgent = m[2]
      else if (m[1] === "color8") root.muted = m[2]
    }
  }

  FileView {
    id: paletteFile
    path: root.colorsPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.parseColors(paletteFile.text())
  }
  FileView {
    id: themeMarker
    path: root.themeNamePath
    watchChanges: true
    onFileChanged: { reload(); paletteFile.reload() }
  }

  // ------------------------------------------------------------------ state
  // dormant | listening | thinking | answering | error
  property string phase: "dormant"
  property string transcript: ""
  // halo | bed | plate | capsule — see the caption block in the voice node.
  property string captionStyle: "plate"
  // Test harness only, never shipped: see the contrast probe in the node.
  property bool probeOn: false
  property bool motionEnabled: true
  property string answer: ""
  // off | prompt | permission — the console's lane.
  property string console_: "off"
  property string draft: ""
  property int permissionChoice: 0

  // The output Hyprland has focused — where the user actually is. Every
  // surface follows it, so the light appears on the screen being worked on
  // rather than on a fixed output. Hyprland reports nothing briefly at
  // startup, so fall back rather than render nowhere.
  readonly property string focusedScreenName:
    Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
  readonly property var activeScreen: {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name || "") === root.focusedScreenName) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  readonly property bool nodeLit: phase !== "dormant"
  readonly property bool curtainUp: phase === "answering" || phase === "error"
  onPhaseChanged: node.settleAtmosphere()
  onMotionEnabledChanged: node.settleAtmosphere()

  // Auto-dismiss, scaled to how much there is to read rather than a flat
  // timeout — a fixed 8s eats a long answer mid-sentence. Roughly 240ms per
  // word over a floor, clamped so a one-liner still lingers and an essay does
  // not camp on the desktop forever.
  readonly property int dismissDelay: {
    var words = String(answer || "").split(/\s+/).filter(function(w) { return w !== "" }).length
    return Math.max(6000, Math.min(40000, 4500 + words * 240))
  }

  Timer {
    id: dismissTimer
    interval: root.dismissDelay
    repeat: false
    // Only runs once the answer has settled. Production also holds it while
    // the curtain is grabbed; the node and curtain are click-through
    // (`mask: Region {}`), so there is no hover to pause on — that is the
    // deliberate cost of never intercepting a click.
    running: root.phase === "answering"
    onTriggered: root.phase = "dormant"
  }


  IpcHandler {
    target: "node"
    function state(value: string): string {
      const allowed = ["dormant", "listening", "thinking", "answering", "error"]
      if (allowed.indexOf(value) === -1) return "unknown state: " + value
      root.phase = value
      return value
    }
    function say(text: string): string { root.transcript = text; return "ok" }
    function caption(style: string): string {
      if (["halo", "bed", "plate", "capsule"].indexOf(style) === -1) return "unknown caption style: " + style
      root.captionStyle = style
      return style
    }
    function answer(text: string): string { root.answer = text; return "ok" }
    function probe(value: string): string { root.probeOn = value === "on"; return root.probeOn ? "on" : "off" }
    function motion(value: string): string {
      root.motionEnabled = value !== "off"
      return root.motionEnabled ? "on" : "off"
    }
    function lane(value: string): string {
      if (["off", "prompt", "permission"].indexOf(value) === -1) return "unknown lane: " + value
      root.console_ = value
      return value
    }
    function draft(text: string): string { root.draft = text; return "ok" }
    function where(): string {
      return "hyprland=" + root.focusedScreenName
        + " resolved=" + (root.activeScreen ? root.activeScreen.name : "none")
        + " dismissMs=" + root.dismissDelay
    }
    function choice(index: string): string { root.permissionChoice = parseInt(index) || 0; return "ok" }
  }

  // ============================================================ voice node
  PanelWindow {
    id: node
    screen: root.activeScreen
    color: "transparent"
    anchors { bottom: true; left: true; right: true }
    implicitHeight: 240
    // Stay mapped through the fade, then release the surface rather than
    // leaving a permanently-mapped overlay on the output.
    visible: root.nodeLit || node.presence > 0.001
    // Never displace a window and never take a click. The node is a light
    // source, not a control: everything actionable stays on the keyboard.
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omapilot-voice-node"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // One driver for the whole node. `level` is an honest breath, not a fake
    // VU meter — the broker exposes no audio amplitude, so pretending to
    // visualise one would be a lie in pixels.
    property real level: 0
    property real presence: root.nodeLit ? 1 : 0
    property real tide: 0.35
    property real drift: 0
    readonly property bool atmosphereActive: root.motionEnabled
      && (root.phase === "listening" || root.phase === "thinking")

    function settleAtmosphere() {
      if (!atmosphereActive) {
        tide = 0.4
        drift = 0
      }
      if (!root.motionEnabled) level = 0.5
    }

    Behavior on presence {
      enabled: root.motionEnabled
      NumberAnimation { duration: root.nodeLit ? 260 : 420; easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
      running: root.phase === "listening" && root.motionEnabled
      loops: Animation.Infinite
      NumberAnimation { target: node; property: "level"; to: 1; duration: 820; easing.type: Easing.InOutSine }
      NumberAnimation { target: node; property: "level"; to: 0.34; duration: 980; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
      running: node.atmosphereActive
      loops: Animation.Infinite
      NumberAnimation { target: node; property: "tide"; to: 1; duration: root.phase === "thinking" ? 2700 : 3900; easing.type: Easing.InOutSine }
      NumberAnimation { target: node; property: "tide"; to: 0.18; duration: root.phase === "thinking" ? 3400 : 4700; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
      running: node.atmosphereActive
      loops: Animation.Infinite
      NumberAnimation { target: node; property: "drift"; to: 1; duration: root.phase === "thinking" ? 4700 : 6300; easing.type: Easing.InOutSine }
      NumberAnimation { target: node; property: "drift"; to: -1; duration: root.phase === "thinking" ? 5600 : 7100; easing.type: Easing.InOutSine }
    }
    // Thinking holds a low, steady presence; the travelling filament carries
    // the motion instead, so the two states never read the same.
    NumberAnimation {
      running: root.motionEnabled && root.nodeLit && root.phase !== "listening"
      target: node
      property: "level"
      to: root.phase === "thinking" ? 0.42 : (root.phase === "error" ? 0.9 : 0.62)
      duration: 300
      easing.type: Easing.OutCubic
    }
    onAtmosphereActiveChanged: settleAtmosphere()

    // ---- contrast probe. Not part of the design: a bright band drawn *under*
    // everything so caption legibility over a white browser can be judged
    // without moving any of the user's windows. `ipc call node probe on`.
    Rectangle {
      visible: root.probeOn
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: 150
      color: "#f2f2f0"
    }

    // ---- the shadow half of "shadow glow". A whisper of the theme background
    // rising from the edge. It does two jobs: it seats the light in something
    // instead of letting it float, and it guarantees the transcript stays
    // legible over a white browser or a bright terminal. Deliberately weak —
    // this must never read as a panel or a scrim over the user's work.
    Rectangle {
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: 190
      opacity: node.presence
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.0) }
        GradientStop { position: 0.55; color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.30) }
        GradientStop { position: 1.0; color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.62) }
      }
    }

    // ---- the ember: a transparent full-width body sitting mostly below the
    // screen edge, so the complete lower edge stays alive without becoming a bar.
    Item {
      id: emberSource
      visible: false
      anchors { left: parent.left; right: parent.right }
      height: 64
      // Sink the body under the edge; only its top rim clears it, so what
      // reaches the desktop is bloom rather than the shape itself.
      y: parent.height - 14 - node.tide * 2
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.10) }
          GradientStop { position: 0.18 + node.drift * 0.025; color: Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.48) }
          GradientStop { position: 0.50 + node.drift * 0.055; color: root.lightColor }
          GradientStop { position: 0.82 + node.drift * 0.025; color: Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.48) }
          GradientStop { position: 1.0; color: Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.10) }
        }
      }
    }

    // Two blooms, not one. A single wide blur spreads the energy until the
    // light reads as fog; layering a wide halo under a tight core is what
    // makes it read as an actual light source at the screen edge.
    MultiEffect {
      id: emberHalo
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
      opacity: node.presence * (0.24 + node.level * 0.22 + node.tide * 0.06)
      scale: 1 + node.level * 0.035 + node.tide * 0.018
      transformOrigin: Item.Bottom
    }

    MultiEffect {
      id: emberCore
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
      opacity: node.presence * (0.14 + node.level * 0.16 + node.tide * 0.04)
      scale: 1 + node.level * 0.022 + node.tide * 0.012
      transformOrigin: Item.Bottom
    }

    // ---- the filament: the crisp edge that makes the glow read as
    // deliberate rather than as a rendering artifact.
    Item {
      id: filamentSource
      visible: false
      width: parent.width * 0.46
      height: 2
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - 2

      Rectangle {
        anchors.fill: parent
        radius: 1
        color: root.lightColor
        opacity: root.phase === "thinking" ? 0.22 : 0.85
        Behavior on opacity { NumberAnimation { duration: 240 } }
      }

      // Thinking: one short bright runner sweeping the filament. Same
      // vocabulary as the existing response perimeter runner, flattened to a
      // line, so the two surfaces feel like one product.
      Rectangle {
        id: runner
        visible: root.phase === "thinking"
        width: parent.width * 0.18
        height: parent.height
        radius: 1
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
      opacity: node.presence
    }

    // The filament itself, unblurred, on top — one hairline of real light.
    Rectangle {
      width: filamentSource.width
      height: 1
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - 1
      radius: 0.5
      color: root.lightColor
      opacity: node.presence * (root.phase === "thinking" ? 0.35 : 0.55 + node.level * 0.3)
    }

    // ---- live transcript, set just above the edge. Voice mode's only text.
    //
    // The hard part is legibility over arbitrary content — a white browser and
    // a black terminal are both one keystroke away — without introducing a box,
    // which would undo the whole ambient premise. Real backdrop blur is off the
    // table: compositor blur is disabled on this machine and turning it on for
    // our namespace would mean writing to the user's Hyprland config, which
    // OmaPilot is not allowed to do.
    //
    // So: shapeless containment only. Three variants, switchable live via
    // `ipc call node caption <halo|bed|capsule>`, all of which stay transparent.
    Item {
      id: caption
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 68
      width: Math.min(parent.width * 0.52, 660)
      height: transcriptText.implicitHeight + 26
      opacity: transcriptText.text === "" ? 0 : node.presence
      Behavior on opacity { NumberAnimation { duration: 180 } }

      // (bed) A heavily feathered ellipse of shade, wider than the text and
      // with no discernible edge. It gives the words something to sit on
      // without ever resolving into a shape the eye can name.
      Item {
        id: bedSource
        visible: false
        anchors.centerIn: parent
        width: parent.width * 0.96
        height: parent.height * 0.82
        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: root.background
        }
      }
      MultiEffect {
        visible: root.captionStyle === "bed"
        anchors.fill: bedSource
        source: bedSource
        autoPaddingEnabled: true
        blurEnabled: true
        blur: 1
        blurMax: 64
        blurMultiplier: 1.5
        opacity: 0.72
      }

      // (plate) The one that should win. Same idea as `bed`, but sized to the
      // text rather than the slot and pushed to near-full opacity, so it owns
      // the local contrast the way the capsule does — while a wide blur keeps
      // every edge below the threshold where the eye reads "box". Legibility
      // from the capsule, shapelessness from the bed.
      Item {
        id: plateSource
        visible: false
        anchors.centerIn: parent
        width: Math.min(parent.width, transcriptText.implicitWidth + 72)
        height: transcriptText.implicitHeight + 20
        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: root.background
        }
      }
      MultiEffect {
        visible: root.captionStyle === "plate"
        anchors.fill: plateSource
        source: plateSource
        autoPaddingEnabled: true
        blurEnabled: true
        blur: 1
        blurMax: 32
        blurMultiplier: 1.15
        // Two stacked passes of the same soft plate build density at the centre
        // faster than they build a visible rim at the edge. Kept translucent
        // on purpose: the desktop should still be faintly present through it,
        // or the plate stops being ambient and becomes a redaction bar.
        opacity: 0.56
      }
      MultiEffect {
        visible: root.captionStyle === "plate"
        anchors.fill: plateSource
        source: plateSource
        autoPaddingEnabled: true
        blurEnabled: true
        blur: 1
        blurMax: 22
        blurMultiplier: 0.5
        opacity: 0.46
      }

      // (capsule) The same pill, but only lightly softened and carrying a
      // barely-there rim. Closest to a conventional control; included so the
      // comparison is honest rather than rigged.
      Rectangle {
        visible: root.captionStyle === "capsule"
        anchors.centerIn: parent
        width: transcriptText.implicitWidth + 40
        height: transcriptText.implicitHeight + 18
        radius: height / 2
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55)
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
      }

      Text {
        id: transcriptText
        anchors.centerIn: parent
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 2
        wrapMode: Text.WordWrap
        text: root.phase === "listening" ? root.transcript : ""
        color: root.foreground
        font.family: root.mono
        font.pixelSize: 16
        // Hidden because the MultiEffect below paints the glyphs plus their
        // halo; drawing both would double the stroke weight.
        visible: false
      }

      // (all variants) A dark halo shaped like the glyphs themselves. This is
      // the piece that actually buys contrast: it hugs each letter, so it
      // survives a white background while adding no geometry of its own.
      MultiEffect {
        anchors.fill: transcriptText
        source: transcriptText
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowBlur: 1
        shadowScale: 1
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
        shadowColor: Qt.rgba(root.background.r, root.background.g, root.background.b, 1)
        shadowOpacity: root.captionStyle === "halo" ? 0.95
          : (root.captionStyle === "plate" ? 0.72 : 0.75)
      }
    }
  }

  // ========================================================= answer curtain
  PanelWindow {
    id: curtain
    screen: root.activeScreen
    color: "transparent"
    anchors { top: true; left: true; right: true }
    implicitHeight: 460
    // Normal + zero zone: respect the omarchy bar's reserved strip so the
    // curtain slides in *under* the bar instead of over it, and reserve
    // nothing of its own so no window ever reflows.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    // Keep the surface mapped while the exit animation plays out.
    visible: root.curtainUp || card.slid > 0.001
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omapilot-curtain"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
      id: card
      // 0 = fully retracted above the edge, 1 = docked.
      property real slid: root.curtainUp ? 1 : 0
      Behavior on slid {
        NumberAnimation {
          duration: root.curtainUp ? 300 : 220
          easing.type: root.curtainUp ? Easing.OutQuint : Easing.OutCubic
        }
      }

      width: Math.min(parent.width - 96, 940)
      height: body.implicitHeight + 52
      anchors.horizontalCenter: parent.horizontalCenter
      y: -height * (1 - card.slid) + 14 * card.slid
      opacity: card.slid

      Rectangle {
        anchors.fill: parent
        radius: 10
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.97)
        border.width: 1
        border.color: Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.28)
      }

      // An edge-lit seam along the top: brightest at the centre, gone by the
      // corners. A flat bar of colour reads as a progress indicator; a
      // gradient reads as the same light the node emits, arriving from above.
      Rectangle {
        width: parent.width - 2
        height: 1
        anchors.horizontalCenter: parent.horizontalCenter
        y: 1
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.5; color: Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.85) }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }

      // The card's own bloom, cast downward. Without it the curtain looks
      // pasted onto the desktop instead of lit by the same source.
      Item {
        id: curtainGlowSource
        visible: false
        width: parent.width * 0.7
        height: 4
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 2
        Rectangle { anchors.fill: parent; radius: 2; color: root.lightColor }
      }
      MultiEffect {
        anchors.fill: curtainGlowSource
        source: curtainGlowSource
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
          leftMargin: 30; rightMargin: 30; topMargin: 24
        }
        spacing: 14

        // Provenance row: what was asked, and who answered. Nothing else.
        Item {
          width: parent.width
          height: Math.max(ask.implicitHeight, who.implicitHeight)
          Text {
            id: ask
            anchors.left: parent.left
            anchors.right: who.left
            anchors.rightMargin: 16
            elide: Text.ElideRight
            text: root.transcript
            color: root.muted
            font.family: root.mono
            font.pixelSize: 12
          }
          Text {
            id: who
            anchors.right: parent.right
            text: root.phase === "error" ? "could not answer" : "built-in · voice"
            color: root.phase === "error" ? root.urgent : root.muted
            font.family: root.mono
            font.pixelSize: 12
            opacity: 0.8
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.answer
          color: root.foreground
          font.family: root.mono
          font.pixelSize: 15
          lineHeight: 1.45
          lineHeightMode: Text.ProportionalHeight
        }
      }
    }
  }

  // ================================================================= console
  // The deliberate lane. Unlike the node and the curtain this surface is meant
  // to take focus — typing, choices, settings, history, permissions, and
  // built-in auth all need it. In production it is
  // `WlrKeyboardFocus.Exclusive` while open; the mock deliberately uses `None`
  // and is driven over IPC so demonstrating it cannot swallow the user's
  // keystrokes mid-session.
  PanelWindow {
    id: consoleWindow
    screen: root.activeScreen
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    visible: root.console_ !== "off" || consoleCard.shown > 0.001
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omapilot-console"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Because the console does take focus, a scrim is the honest signal that
    // the desktop is no longer listening to the keyboard. The ambient surfaces
    // never get one.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55)
      opacity: consoleCard.shown
    }

    Item {
      id: consoleCard
      property real shown: root.console_ !== "off" ? 1 : 0
      Behavior on shown {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }

      width: Math.min(parent.width - 120, 720)
      height: consoleBody.implicitHeight + 44
      anchors.horizontalCenter: parent.horizontalCenter
      // Seated above centre: the eye lands here, and the node stays visible
      // below so the two surfaces read as one system.
      y: parent.height * 0.32 + (1 - consoleCard.shown) * 10
      opacity: consoleCard.shown
      scale: 0.99 + consoleCard.shown * 0.01

      Rectangle {
        anchors.fill: parent
        radius: 12
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.98)
        border.width: 1
        border.color: root.console_ === "permission"
          ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.45)
          : Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.30)
      }

      Column {
        id: consoleBody
        anchors {
          left: parent.left; right: parent.right; top: parent.top
          leftMargin: 26; rightMargin: 26; topMargin: 22
        }
        spacing: 16

        // ---- prompt lane: one line, no toolbar. The typed path exists for
        // precision, not for feature parity with the old composer.
        Row {
          visible: root.console_ === "prompt"
          width: parent.width
          spacing: 10
          Text {
            text: "\u203a"
            color: root.lightColor
            font.family: root.mono
            font.pixelSize: 19
          }
          Text {
            width: consoleBody.width - 30
            text: root.draft === "" ? "Ask, or describe what to do" : root.draft
            color: root.draft === "" ? root.muted : root.foreground
            font.family: root.mono
            font.pixelSize: 19
            elide: Text.ElideRight
          }
        }

        // ---- permission lane. Deliberately plain and deliberately verbose:
        // this is the one surface where looking exciting would be a defect.
        Column {
          visible: root.console_ === "permission"
          width: parent.width
          spacing: 12
          Text {
            text: "Allow this exact command?"
            color: root.foreground
            font.family: root.mono
            font.pixelSize: 16
            font.bold: true
          }
          Rectangle {
            width: parent.width
            height: cmd.implicitHeight + 20
            radius: 6
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            Text {
              id: cmd
              anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                        leftMargin: 12; rightMargin: 12 }
              text: "powerprofilesctl set power-saver"
              color: root.foreground
              font.family: root.mono
              font.pixelSize: 14
              wrapMode: Text.WrapAnywhere
            }
          }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Approving runs this once with your full device and network authority, outside the sandbox."
            color: root.muted
            font.family: root.mono
            font.pixelSize: 12
          }
          Row {
            spacing: 10
            Repeater {
              model: ["Allow once", "Reject once"]
              delegate: Rectangle {
                required property string modelData
                required property int index
                readonly property bool active: root.permissionChoice === index
                width: label.implicitWidth + 28
                height: 32
                radius: 6
                color: active
                  ? Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.18)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                border.width: 1
                border.color: active
                  ? Qt.rgba(root.lightColor.r, root.lightColor.g, root.lightColor.b, 0.65)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                Text {
                  id: label
                  anchors.centerIn: parent
                  text: modelData
                  color: root.foreground
                  font.family: root.mono
                  font.pixelSize: 13
                }
              }
            }
          }
        }

        // ---- one hint row, shared. Provenance left, keys right.
        Item {
          width: parent.width
          height: 16
          Text {
            anchors.left: parent.left
            text: "built-in \u00b7 pi"
            color: root.muted
            font.family: root.mono
            font.pixelSize: 11
          }
          Text {
            anchors.right: parent.right
            text: root.console_ === "permission"
              ? "\u2190 \u2192 choose \u00b7 enter confirm \u00b7 esc reject"
              : "enter send \u00b7 tab history \u00b7 esc dismiss"
            color: root.muted
            font.family: root.mono
            font.pixelSize: 11
          }
        }
      }
    }
  }
}
