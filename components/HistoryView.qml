import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "internal" as OmaPilotInternal

Item {
  id: root

  property var history: []
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool motionEnabled: true
  property bool confirmingClear: false
  readonly property bool modalInteractionActive: confirmingClear
  implicitHeight: Math.min(Style.space(360), 94 + history.length * 30)

  signal chatSelected(var chat)
  signal deleteRequested(string chatId)
  signal clearRequested()
  signal closeRequested()

  function forceInitialFocus() {
    if (list.visible && list.count > 0) list.forceActiveFocus()
    else closeHistory.forceActiveFocus()
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: 56
      Layout.leftMargin: 17
      Layout.rightMargin: 17
      spacing: 9

      PanelActionButton {
        id: closeHistory
        iconText: "󰁍"
        tooltipText: "Back to conversation"
        foreground: root.foreground
        focusable: true
        Accessible.name: tooltipText
        onClicked: root.closeRequested()
      }

      Text {
        text: "History"
        color: root.foreground
        font.family: "JetBrains Mono"
        font.pixelSize: 17
        font.bold: false
        Accessible.role: Accessible.StaticText
        Accessible.name: "Recent chats"
      }

      Item { Layout.fillWidth: true }

      Text {
        id: clearHistory
        visible: root.history.length > 0
        text: root.confirmingClear ? "Clear all?" : "Clear"
        color: root.confirmingClear
          ? Color.urgent
          : (activeFocus || clearHover.hovered ? root.foreground : Qt.darker(root.foreground, 1.35))
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.underline: clearHover.hovered || root.confirmingClear || activeFocus
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: root.confirmingClear ? "Confirm clear all chats" : "Clear all chats"

        HoverHandler {
          id: clearHover
          cursorShape: Qt.PointingHandCursor
        }

        TapHandler { onTapped: clearHistory.activate() }
        Keys.onReturnPressed: clearHistory.activate()
        Keys.onEnterPressed: clearHistory.activate()
        Keys.onSpacePressed: clearHistory.activate()

        function activate() {
          if (root.confirmingClear) {
            root.clearRequested()
            root.confirmingClear = false
          } else root.confirmingClear = true
        }
      }
    }

    ActivityFilament {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      foreground: root.foreground
      accent: root.accent
      focused: list.activeFocus || closeHistory.activeFocus
      active: false
      motionEnabled: root.motionEnabled
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      Text {
        visible: root.history.length === 0
        anchors.centerIn: parent
        width: parent.width - Style.spacing.xxl * 2
        text: "No saved chats yet.\nThe latest 30 completed answers appear here."
        color: Qt.darker(root.foreground, 1.55)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
      }

      ListView {
        id: list
        visible: root.history.length > 0
        anchors.fill: parent
        model: root.history
        spacing: 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: true
        currentIndex: count > 0 ? 0 : -1

        Keys.onPressed: function(event) { historyKeyboard.handleKey(event) }

        OmaPilotInternal.HistoryListKeyboardHandler {
          id: historyKeyboard
          list: list
          history: root.history
          confirmingClear: root.confirmingClear
          onChatSelected: function(chat) { root.chatSelected(chat) }
          onDeleteRequested: function(chatId) { root.deleteRequested(chatId) }
          onCloseRequested: root.closeRequested()
          onConfirmationCancelled: {
            root.confirmingClear = false
            clearHistory.forceActiveFocus()
          }
        }

        delegate: Item {
          id: row
          required property var modelData
          required property int index
          width: list.width
          height: 30
          Accessible.role: Accessible.ListItem
          Accessible.name: String(modelData.title || "Chat")

          readonly property bool current: index === list.currentIndex
          readonly property bool hot: current || rowHover.hovered

          Rectangle {
            anchors.fill: parent
            color: Style.hoverFillFor(root.foreground, root.accent)
            opacity: row.hot ? 1 : 0
          }

          HoverHandler {
            id: rowHover
            onHoveredChanged: if (hovered) list.currentIndex = index
          }
          TapHandler { onTapped: root.chatSelected(modelData) }

          RowLayout {
            id: rowContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 17
            anchors.rightMargin: 10
            spacing: 9

            Text {
              Layout.preferredWidth: 48
              text: String(modelData.timestamp || "")
              color: "#6f7077"
              font.family: "JetBrains Mono"
              font.pixelSize: 10
              elide: Text.ElideRight
            }

            Text {
              Layout.fillWidth: true
              text: modelData.title
              color: "#d5d5da"
              font.family: "JetBrains Mono"
              font.pixelSize: 11
              elide: Text.ElideRight
            }

            ResponseBadge {
              Layout.alignment: Qt.AlignVCenter
              responseClass: modelData.response ? String(modelData.response.class || "ANSWER") : "ANSWER"
            }

            PanelActionButton {
              Layout.alignment: Qt.AlignVCenter
              iconText: "󰆴"
              tooltipText: "Delete chat"
              foreground: root.foreground
              hoverColor: Color.urgent
              // Opacity 0 still receives taps, so non-current rows would delete
              // from empty space on pointers that never hover. Disable the
              // control until the row is current, hovered, or this button is
              // focused. List Delete remains the keyboard path.
              enabled: row.hot || activeFocus
              focusable: enabled
              opacity: enabled ? 1 : 0
              Accessible.name: tooltipText
              onClicked: root.deleteRequested(String(modelData.id))
            }
          }
        }
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 37

      Rectangle {
        anchors.fill: parent
        color: "#0c0c0f"
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: "#1d1e22"
      }

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 17
        anchors.rightMargin: 17

        Text {
          Layout.fillWidth: true
          text: root.history.length + " entries · local only"
          color: "#6f7077"
          font.family: "JetBrains Mono"
          font.pixelSize: 10
        }

        Text {
          text: "esc close"
          color: "#74757c"
          font.family: "JetBrains Mono"
          font.pixelSize: 10
        }
      }
    }
  }
}
