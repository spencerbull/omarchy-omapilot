import QtQuick

Item {
  id: root

  property string responseClass: "ANSWER"
  property string fontFamily: "JetBrains Mono"
  readonly property var colors: {
    var palettes = {
      "ACTION": { foreground: "#3fc48c", background: "#1e3329" },
      "ANSWER": { foreground: "#b8c9ff", background: "#29283d" },
      "CONFIRM": { foreground: "#f2c36b", background: "#403019" },
      "PLAN": { foreground: "#f2c36b", background: "#403019" },
      "UNSURE": { foreground: "#f2a293", background: "#422623" }
    }
    return palettes[root.responseClass] || palettes.ANSWER
  }

  implicitWidth: label.implicitWidth + 12
  implicitHeight: 18
  Accessible.role: Accessible.StaticText
  Accessible.name: root.responseClass

  Rectangle {
    anchors.fill: parent
    color: root.colors.background
    radius: 0

    Text {
      id: label
      anchors.centerIn: parent
      text: root.responseClass
      color: root.colors.foreground
      font.family: root.fontFamily
      font.pixelSize: 9
      font.bold: true
      font.letterSpacing: 0.5
    }
  }
}
