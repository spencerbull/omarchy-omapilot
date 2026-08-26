import QtQuick
import Quickshell
import Quickshell.Io
import "components" as OmaPilot

ShellRoot {
  id: root
  property int attempts: 0
  property string lastSignature: ""
  readonly property bool watchChanges:
    Quickshell.env("OMAPILOT_PALETTE_WATCH") === "1"

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: console.log("OMAPILOT_PALETTE_DIRECT_FILE_OK bytes=" + text().length)
    onLoadFailed: console.error("omapilot palette runtime probe failed: direct theme file load failed")
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      root.attempts += 1
      if (OmaPilot.OmaPilotPalette.ready) {
        if (OmaPilot.OmaPilotPalette.foreground.a === 0
            || OmaPilot.OmaPilotPalette.background.a === 0
            || OmaPilot.OmaPilotPalette.accent.a === 0
            || Qt.colorEqual(OmaPilot.OmaPilotPalette.darkForeground,
              OmaPilot.OmaPilotPalette.background)) {
          console.error("omapilot palette runtime probe failed: palette colors are not readable")
          Qt.quit()
          return
        }
        var signature = OmaPilot.OmaPilotPalette.themeName
          + "|" + OmaPilot.OmaPilotPalette.sourcePath
          + "|" + OmaPilot.OmaPilotPalette.background
          + "|" + OmaPilot.OmaPilotPalette.foreground
          + "|" + OmaPilot.OmaPilotPalette.darkForeground
          + "|" + OmaPilot.OmaPilotPalette.accent
        if (signature === root.lastSignature) return
        root.lastSignature = signature
        console.log("OMAPILOT_PALETTE_RUNTIME_PROBE_OK"
          + " theme=" + OmaPilot.OmaPilotPalette.themeName
          + " source=" + OmaPilot.OmaPilotPalette.sourcePath
          + " background=" + OmaPilot.OmaPilotPalette.background
          + " foreground=" + OmaPilot.OmaPilotPalette.foreground
          + " secondary=" + OmaPilot.OmaPilotPalette.darkForeground
          + " accent=" + OmaPilot.OmaPilotPalette.accent)
        if (!root.watchChanges) Qt.quit()
      } else if (root.attempts >= 40) {
        console.error("omapilot palette runtime probe failed: palette did not become ready"
          + " theme=" + OmaPilot.OmaPilotPalette.themeName
          + " requested=" + OmaPilot.OmaPilotPalette.requestedPalettePath
          + " source=" + OmaPilot.OmaPilotPalette.paletteSource)
        Qt.quit()
      }
    }
  }
}
