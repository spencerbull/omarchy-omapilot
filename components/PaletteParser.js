.pragma library

function parse(raw) {
  var values = {};
  var lines = String(raw || "").split("\n");
  var pattern = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*["'](#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?)["']/;
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(pattern);
    if (match) values[match[1]] = match[2];
  }

  function named(primary, alias) {
    return values[primary] || (alias ? values[alias] : "") || "";
  }

  var palette = {
    background: named("background", "bg"),
    darkBackground: named("dark_background", "dark_bg"),
    darkerBackground: named("darker_background", "darker_bg"),
    lighterBackground: named("lighter_background", "lighter_bg"),
    foreground: named("foreground", "fg"),
    darkForeground: named("dark_foreground", "dark_fg"),
    lightForeground: named("light_foreground", "light_fg"),
    brightForeground: named("bright_foreground", "bright_fg"),
    accent: named("accent"),
    muted: named("muted"),
    selection: named("selection"),
    selectionForeground: named("selection_foreground"),
    selectionBackground: named("selection_background"),
    red: named("red"),
    yellow: named("yellow"),
    orange: named("orange") || named("yellow"),
    green: named("green"),
    cyan: named("cyan"),
    blue: named("blue"),
    magenta: named("magenta"),
    brown: named("brown")
  };
  palette.valid = palette.background !== ""
    && palette.foreground !== ""
    && palette.accent !== ""
    && palette.muted !== ""
    && palette.red !== ""
    && palette.orange !== ""
    && palette.green !== "";
  return palette;
}

function relativeLuminance(value) {
  var hex = String(value || "").replace(/^#/, "").substring(0, 6);
  if (!/^[0-9A-Fa-f]{6}$/.test(hex)) return -1;
  var channels = [];
  for (var i = 0; i < 3; i++) {
    var channel = parseInt(hex.substring(i * 2, i * 2 + 2), 16) / 255;
    channels.push(channel <= 0.04045
      ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4));
  }
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
}

function contrastRatio(first, second) {
  var firstLuminance = relativeLuminance(first);
  var secondLuminance = relativeLuminance(second);
  if (firstLuminance < 0 || secondLuminance < 0) return 0;
  var lighter = Math.max(firstLuminance, secondLuminance);
  var darker = Math.min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

function readableSecondary(darkForeground, muted, foreground, background) {
  var candidates = [darkForeground, muted, foreground];
  for (var i = 0; i < candidates.length; i++)
    if (candidates[i] && contrastRatio(candidates[i], background) >= 4.5) return candidates[i];
  return foreground;
}
