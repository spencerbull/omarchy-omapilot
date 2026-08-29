import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Protocol.js" as Protocol
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
  // The id of the chat whose delete is armed, "" for none. One at a time, and
  // never at the same time as the clear-all confirmation.
  property string confirmingDeleteId: ""
  readonly property bool modalInteractionActive: confirmingClear || confirmingDeleteId !== ""
  // When the open question was asked, so that it cannot be answered by the
  // second half of the gesture that asked it. A double-click is one gesture:
  // the first click armed and the second, inside the platform's double-click
  // interval, confirmed — before the colour had finished changing. The same
  // window covers a stutter on a touchpad. A click that lands after the
  // interval is a click on a control that had time to turn urgent.
  property real armedAt: 0

  signal chatSelected(var chat)
  signal deleteRequested(string chatId)
  signal clearRequested()
  signal closeRequested()

  // This view is hidden, never destroyed — `visible: viewMode === "history"`
  // in the panel. So going Back or opening a chat left an armed confirmation
  // sitting here, and returning to history found a row already armed from
  // minutes ago: the next single click deleted instead of asking. A question
  // nobody is looking at is a question nobody asked.
  //
  // Clears the clear-all arm too, which had the same hole and more to lose.
  onVisibleChanged: if (!visible) root.withdrawConfirmations()

  // Called by the panel as well when it closes: this view's visibility is
  // bound to the view mode, not to the panel, so closing the panel while in
  // history does not hide it. Reopening asked the broker for the list again
  // and the answer withdrew the question, but not before the armed row had
  // shown itself urgent for however long the broker took.
  function withdrawConfirmations() {
    root.confirmingClear = false
    root.confirmingDeleteId = ""
  }

  function arm() {
    root.armedAt = Date.now()
  }

  function settled() {
    return Date.now() - root.armedAt >= Application.styleHints.mouseDoubleClickInterval
  }

  // The list can change under an open question: a completed answer is
  // prepended while history is open, and the store hands this view a new
  // array. Whatever was armed was armed against the list that is gone — the
  // row may have moved, the id may no longer be there — so the question is
  // withdrawn, both kinds. A fresh press asks it again against what is on
  // screen now.
  onHistoryChanged: root.withdrawConfirmations()

  // Deleting one chat unlinks its record, its images and its Pi session, with
  // no undo — the same irreversibility that made "Clear all" ask twice. It
  // asked, and this did not, which is the worse half of an inconsistency: the
  // cheap action was guarded and the one sitting under the pointer, on a row
  // that arms itself on hover, was not.
  //
  // Same two-step as clear-all rather than a dialog, so both destructive
  // actions in this view are answered the same way and neither steals focus.
  function requestDelete(chatId) {
    if (root.confirmingDeleteId === chatId) {
      // Inside the double-click interval the second click is the same
      // gesture as the first; it is ignored and the question stays open. The
      // keyboard pays the same toll — two Deletes inside the interval arm and
      // wait — which is the price of one rule for every way in.
      if (!root.settled()) return
      root.confirmingDeleteId = ""
      root.deleteRequested(chatId)
      return
    }
    root.confirmingClear = false
    root.confirmingDeleteId = chatId
    root.arm()
  }

  function forceInitialFocus() {
    if (list.visible && list.count > 0) list.forceActiveFocus()
    else closeHistory.forceActiveFocus()
  }

  // Two presses means two presses, on the controls as well as on the list. A
  // focused control answers Return, Enter and Space itself, and Qt emits
  // those specific signals before the generic press and accepts them by
  // default, so nothing above the control gets to see a repeat. Held past
  // the repeat delay, the first press armed and the first repeat confirmed.
  // `Keys.forwardTo` hands the event here first: a repeat of an activation
  // key is swallowed, every other key goes on as before — Delete and the
  // arrows still reach the list.
  Item {
    id: repeatGuard
    Keys.onPressed: function(event) {
      if (event.isAutoRepeat && (event.key === Qt.Key_Return
          || event.key === Qt.Key_Enter || event.key === Qt.Key_Space))
        event.accepted = true
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.spacing.md

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md

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
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
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

        Behavior on color {
          enabled: root.motionEnabled
          ColorAnimation { duration: 120 }
        }

        HoverHandler {
          id: clearHover
          cursorShape: Qt.PointingHandCursor
        }

        TapHandler { onTapped: clearHistory.activate() }
        Keys.forwardTo: [repeatGuard]
        Keys.onReturnPressed: clearHistory.activate()
        Keys.onEnterPressed: clearHistory.activate()
        Keys.onSpacePressed: clearHistory.activate()

        function activate() {
          if (root.confirmingClear) {
            if (!root.settled()) return
            root.clearRequested()
            root.confirmingClear = false
          } else {
            root.confirmingDeleteId = ""
            root.confirmingClear = true
            root.arm()
          }
        }
      }
    }

    ActivityFilament {
      Layout.fillWidth: true
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
        // No number here on purpose: the cap lives in the broker, this view
        // has no way to read it, and a literal copied across that boundary is
        // wrong the first time either side changes. It said 30 while the
        // broker kept 30, and would have gone on saying 30 afterwards.
        text: "No saved chats yet.\nCompleted answers are kept here."
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

        // An armed delete belongs to the row it is armed on. Leaving that row —
        // by arrow key, or by hovering another, which moves the cursor here too
        // — disarms it, so the confirmation can never outlive the sight of what
        // it would delete.
        onCurrentIndexChanged: root.confirmingDeleteId = ""
        // Scrolling leaves the row too, without moving the cursor: a wheel or
        // a drag can carry the armed row out of the viewport, its delegate
        // with it, and leave an open question with no urgent button anywhere
        // on screen to show for it. Any movement of the viewport withdraws
        // the question. It cannot undo an arm that was just made: with no
        // highlight item this view never scrolls on its own to follow the
        // cursor, so the viewport moves only when a wheel, a drag or a resize
        // moves it — never as a side effect of arming or of becoming current.
        onContentYChanged: root.confirmingDeleteId = ""

        Keys.onPressed: function(event) { historyKeyboard.handleKey(event) }

        OmaPilotInternal.HistoryListKeyboardHandler {
          id: historyKeyboard
          list: list
          history: root.history
          confirmingClear: root.confirmingClear
          confirmingDeleteId: root.confirmingDeleteId
          onChatSelected: function(chat) { root.chatSelected(chat) }
          // Routed through the same two-step the button uses, so Delete arms on
          // the first press and deletes on the second whichever way it came.
          // The second press carries the armed id back, so the two-step
          // confirms the chat that was armed and never the row under the
          // cursor.
          onDeleteRequested: function(chatId) { root.requestDelete(chatId) }
          onCloseRequested: root.closeRequested()
          onConfirmationCancelled: {
            if (root.confirmingDeleteId !== "") {
              root.confirmingDeleteId = ""
              return
            }
            root.confirmingClear = false
            clearHistory.forceActiveFocus()
          }
        }

        delegate: Item {
          id: row
          required property var modelData
          required property int index
          width: list.width
          height: rowContent.implicitHeight + Style.spacing.lg * 2
          Accessible.role: Accessible.ListItem
          Accessible.name: String(modelData.title || "Chat")

          readonly property bool current: index === list.currentIndex
          readonly property bool hot: current || rowHover.hovered

          Rectangle {
            anchors.fill: parent
            color: Style.hoverFillFor(root.foreground, root.accent)
            opacity: row.hot ? 1 : 0
            Behavior on opacity {
              enabled: root.motionEnabled
              NumberAnimation { duration: 120 }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: Math.max(Style.space(18), parent.height * 0.42)
            radius: 1
            color: root.accent
            opacity: row.current ? 0.95 : 0
            Behavior on opacity {
              enabled: root.motionEnabled
              NumberAnimation { duration: 140 }
            }
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
            anchors.leftMargin: Style.spacing.lg
            anchors.rightMargin: Style.spacing.xs
            spacing: Style.spacing.md

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.xxs

              Text {
                Layout.fillWidth: true
                text: modelData.title
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                text: Protocol.providerLabel(modelData.provider)
                  + (modelData.model ? " · " + modelData.model : "")
                  + (modelData.timestamp ? " · " + modelData.timestamp : "")
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              readonly property bool confirming:
                root.confirmingDeleteId === String(row.modelData.id)

              Layout.alignment: Qt.AlignVCenter
              iconText: "󰆴"
              // An instruction, not a question. Turning urgent and drawing a
              // border says the state changed; neither says what to do about
              // it. "Clear all" can afford a question because its label is
              // visible text that becomes "Clear all?" — this control has no
              // label at all, so the tooltip is the only thing that can speak,
              // and it should spend those words telling you the way out rather
              // than restating what the colour already said.
              tooltipText: confirming ? "Click again to delete" : "Delete chat"
              // Armed, the button borrows the urgent role and puts a border
              // round itself. Colour alone would be the whole signal otherwise,
              // and colour alone is not a signal for everyone.
              foreground: confirming ? Color.urgent : root.foreground
              hoverColor: Color.urgent
              bordered: confirming
              // Opacity 0 still receives taps, so non-current rows would delete
              // from empty space on pointers that never hover. Disable the
              // control until the row is current, hovered, or this button is
              // focused. List Delete remains the keyboard path.
              enabled: row.hot || activeFocus || confirming
              focusable: enabled
              opacity: enabled ? 1 : 0
              Accessible.name: confirming ? "Confirm deleting this chat" : tooltipText
              Keys.forwardTo: [repeatGuard]
              onClicked: root.requestDelete(String(row.modelData.id))
              Behavior on opacity {
                enabled: root.motionEnabled
                NumberAnimation { duration: 120 }
              }
            }
          }
        }
      }
    }
  }
}
