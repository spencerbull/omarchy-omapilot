import QtQuick
import QtTest
import "../components/StateColor.js" as StateColor
import "../components/PaletteParser.js" as PaletteParser

TestCase {
  name: "OmaPilotStateColor"

  readonly property color accent: "#7aa2f7"
  readonly property color thinking: "#e09145"
  readonly property color finished: "#84a86a"
  readonly property color urgent: "#a55555"

  function phaseColor(phase) {
    return StateColor.forPhase(accent, thinking, finished, urgent, phase)
  }

  function test_eachStateUsesItsThemeRoleUnchanged() {
    compare(Qt.colorEqual(phaseColor("listening"), accent), true)
    compare(Qt.colorEqual(phaseColor("thinking"), thinking), true)
    compare(Qt.colorEqual(phaseColor("answering"), finished), true)
    compare(Qt.colorEqual(phaseColor("error"), urgent), true)
  }

  function test_themePaletteUsesNamedOrangeAndGreen() {
    var roles = PaletteParser.parse(
      'background = "#111111"\nforeground = "#eeeeee"\naccent = "#7788aa"\n'
      + 'muted = "#777777"\nred = "#cc6666"\nyellow = "#d8a657"\n'
      + 'orange = "#e1875c"\ngreen = "#a9b665"\ncolor2 = "#111111"\ncolor3 = "#222222"')
    compare(Qt.colorEqual(roles.orange, "#e1875c"), true)
    compare(Qt.colorEqual(roles.green, "#a9b665"), true)
    compare(roles.valid, true)
  }

  function test_themePaletteIgnoresAnsiRoles() {
    var roles = PaletteParser.parse(
      'color2 = "#9ece6a"\ncolor3 = "#e0af68"')
    compare(roles.orange, "")
    compare(roles.green, "")
    compare(roles.valid, false)
  }

  function test_secondaryTextFallsBackToReadableNamedRole() {
    compare(PaletteParser.readableSecondary(
      "#c0c0c0", "#808080", "#000000", "#ffffff"), "#000000")
    compare(PaletteParser.readableSecondary(
      "#a5a4a4", "#747474", "#f9f8f8", "#111a27"), "#a5a4a4")
  }

  function test_monochromeThemeDoesNotInventColour() {
    var greyAccent = "#8d8d8d"
    var greyForeground = "#ffffff"
    var greyMuted = "#5c5c5c"
    var greyUrgent = "#a4a4a4"
    var phases = ["listening", "thinking", "answering", "error"]
    for (var i = 0; i < phases.length; i++) {
      var result = StateColor.forPhase(
        greyAccent, greyForeground, greyMuted, greyUrgent, phases[i])
      var color = Qt.darker(result, 1.0)
      verify(color.hslSaturation < 0.01,
             phases[i] + " introduced colour into a monochrome theme")
    }
  }

  function test_dormantDoesNotInventAColour() {
    compare(Qt.colorEqual(phaseColor("dormant"), accent), true)
  }
}
