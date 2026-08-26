pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "PaletteParser.js" as PaletteParser

QtObject {
  id: root

  property bool ready: false
  property string themeName: ""
  property string sourcePath: ""
  property string requestedPalettePath: ""
  property string paletteSource: ""

  property color background: "transparent"
  property color darkBackground: background
  property color darkerBackground: darkBackground
  property color lighterBackground: background
  property color foreground: "transparent"
  property color darkForeground: foreground
  property color lightForeground: foreground
  property color brightForeground: foreground
  property color accent: "transparent"
  property color muted: foreground
  property color selection: foreground
  property color selectionForeground: background
  property color selectionBackground: accent
  property color red: "transparent"
  property color yellow: "transparent"
  property color orange: yellow
  property color green: "transparent"
  property color cyan: accent
  property color blue: accent
  property color magenta: accent
  property color brown: muted

  readonly property color urgent: red
  readonly property color thinking: orange
  readonly property color finished: green

  readonly property string home: Quickshell.env("HOME")
  readonly property string themeNamePath:
    home + "/.local/state/omarchy/current/theme.name"
  readonly property string userThemePath:
    home + "/.config/omarchy/themes/" + themeName + "/colors.toml"
  readonly property string systemThemePath:
    "/usr/share/omarchy/themes/" + themeName + "/colors.toml"
  readonly property string stagedThemePath:
    home + "/.local/state/omarchy/current/theme/colors.toml"

  readonly property QtObject popups: QtObject {
    property color background: root.background
    property color text: root.foreground
    property color border: root.accent
  }
  readonly property QtObject bar: QtObject {
    property color background: root.background
    property color text: root.foreground
    property color active: root.accent
  }
  readonly property QtObject menu: QtObject {
    property color scrim: root.alpha(root.background, 0.5)
  }
  readonly property QtObject tooltip: QtObject {
    property color background: root.background
    property color text: root.foreground
    property color border: root.accent
  }

  function alpha(value, opacity) {
    return Qt.rgba(value.r, value.g, value.b, opacity)
  }

  function normalFill(value) { return alpha(value, 0.04) }
  function hoverFill(value) { return alpha(value, 0.08) }
  function selectedFill(value) { return alpha(value, 0.18) }
  function pressedFill(value) { return alpha(value, 0.22) }
  function focusFill(value) { return alpha(value, 0.08) }
  function selectionFill(value) { return alpha(value, 0.35) }
  function normalBorder(value) { return alpha(value, 0.4) }
  function hoverBorder(value) { return alpha(value, 0.25) }
  function focusBorder(value) { return alpha(value, 0.25) }
  function controlFill(focused, hot, value) {
    return focused ? focusFill(value) : (hot ? hoverFill(value) : normalFill(value))
  }

  function selectTheme(raw) {
    var name = String(raw || "").replace(/^\s+|\s+$/g, "")
    if (!/^[A-Za-z0-9._-]+$/.test(name)) return
    themeName = name
    loadPalette(userThemePath, "user")
  }

  function loadPalette(path, source) {
    var samePath = requestedPalettePath === path
    requestedPalettePath = path
    paletteSource = source
    if (samePath) paletteFile.reload()
    else paletteFile.path = path
  }

  function applyPalette(raw) {
    var next = PaletteParser.parse(raw)
    if (!next.valid) {
      useNextSource()
      return
    }
    background = next.background
    darkBackground = next.darkBackground || next.background
    darkerBackground = next.darkerBackground || next.darkBackground || next.background
    lighterBackground = next.lighterBackground || next.background
    foreground = next.foreground
    darkForeground = PaletteParser.readableSecondary(
      next.darkForeground, next.muted, next.foreground, next.background)
    lightForeground = next.lightForeground || next.foreground
    brightForeground = next.brightForeground || next.foreground
    accent = next.accent
    muted = next.muted
    selection = next.selection || next.foreground
    selectionForeground = next.selectionForeground || next.background
    selectionBackground = next.selectionBackground || next.accent
    red = next.red
    yellow = next.yellow || next.orange
    orange = next.orange
    green = next.green
    cyan = next.cyan || next.accent
    blue = next.blue || next.accent
    magenta = next.magenta || next.accent
    brown = next.brown || next.muted
    sourcePath = requestedPalettePath
    ready = true
  }

  function useNextSource() {
    if (paletteSource === "user") {
      Qt.callLater(function() { root.loadPalette(root.systemThemePath, "system") })
      return
    }
    if (paletteSource === "system") {
      Qt.callLater(function() { root.loadPalette(root.stagedThemePath, "staged") })
    }
  }

  property FileView themeMarker: FileView {
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: root.selectTheme(text())
    onFileChanged: reload()
    onLoadFailed: root.loadPalette(root.stagedThemePath, "staged")
  }

  property FileView paletteFile: FileView {
    watchChanges: true
    printErrors: false
    onLoaded: root.applyPalette(text())
    onFileChanged: reload()
    onLoadFailed: root.useNextSource()
  }
}
