import QtQuick
import QtTest
import "../components/Presentation.js" as Presentation

TestCase {
  name: "OmaPilotPresentation"

  function test_heightGrowsFromMinimumAndCapsToScreen() {
    compare(Presentation.boundedPanelHeight(120, 280, 680, 900, 28), 308)
    compare(Presentation.boundedPanelHeight(460, 280, 680, 900, 28), 488)
    compare(Presentation.boundedPanelHeight(900, 280, 680, 900, 28), 680)
    compare(Presentation.boundedPanelHeight(900, 280, 680, 420, 28), 420)
  }

  function test_responseViewportHasIndependentBounds() {
    compare(Presentation.responseViewportHeight(20, 48, 420), 48)
    compare(Presentation.responseViewportHeight(240, 48, 420), 240)
    compare(Presentation.responseViewportHeight(900, 48, 420), 420)
  }

  function test_streamFollowOnlyWhenReaderIsNearBottom() {
    verify(Presentation.isNearBottom(650, 1000, 300, 56))
    verify(Presentation.isNearBottom(700, 1000, 300, 56))
    verify(!Presentation.isNearBottom(500, 1000, 300, 56))
  }

  function test_permissionNoticeStatesTheApprovalPosture() {
    verify(Presentation.permissionNotice(false).indexOf("exact approval") >= 0)
    verify(Presentation.permissionNotice(true).indexOf("auto-approved") >= 0)
  }

  function test_setupAdvancesInOrder() {
    compare(Presentation.setupStage(false, false, false, false), "authentication")
    compare(Presentation.setupStage(true, false, false, false), "voice")
    compare(Presentation.setupStage(true, true, false, false), "voice")
    compare(Presentation.setupStage(true, true, true, false), "hotkeys")
    compare(Presentation.setupStage(true, true, true, true), "complete")
    compare(Presentation.setupStage(true, false, false, true), "complete")
  }

  function test_waitingAndStreamingPhasesDoNotFakeProgress() {
    var waiting = Presentation.responsePhase("preparing", false)
    compare(waiting.label, "WAITING")
    verify(waiting.waiting)

    var firstToken = Presentation.responsePhase("streaming", true)
    compare(firstToken.label, "STREAMING")
    verify(!firstToken.waiting)

    compare(Presentation.responsePhase("complete", true).label, "ANSWER")
    compare(Presentation.responsePhase("canceled", true).tone, "urgent")
    compare(Presentation.responsePhase("error", false).tone, "urgent")
  }

  function test_responseSummariesAndFooterKeysStaySpecific() {
    compare(Presentation.responseSummary({ class: "ACTION" }), "system changed")
    compare(Presentation.responseSummary({ class: "ANSWER" }), "nothing was changed")
    compare(Presentation.responseSummary({ class: "UNSURE" }), "needs clarification")
    compare(Presentation.footerKeyHints(["enter"], "enter", "run", "close").join(","), "esc close")
    compare(Presentation.footerKeyHints([], "", "", "cancel").join(","), "esc cancel")
  }

  function test_settingsAndHistoryDismissBeforePanel() {
    compare(Presentation.escapeAction("settings", false, false, false, false), "show-chat")
    compare(Presentation.escapeAction("history", false, false, false, false), "show-chat")
    compare(Presentation.escapeAction("error", false, false, false, false), "show-chat")
    compare(Presentation.escapeAction("settings", false, true, false, false), "close-settings-popup")
    compare(Presentation.escapeAction("chat", false, false, true, true), "close-preview")
    compare(Presentation.escapeAction("chat", false, false, false, true), "cancel")
    compare(Presentation.escapeAction("chat", false, false, false, false), "close-panel")
  }

  function test_settingsTabsAreAClosedLaneSet() {
    compare(Presentation.settingsTabIds().join(","), "agent,skills,voice,servers,desktop,actions")
    compare(Presentation.normalizedSettingsTab("desktop"), "desktop")
    compare(Presentation.normalizedSettingsTab("voice"), "voice")
    compare(Presentation.normalizedSettingsTab("missing"), "agent")
    compare(Presentation.adjacentSettingsTab("agent", -1), "agent")
    compare(Presentation.adjacentSettingsTab("agent", 1), "skills")
    compare(Presentation.adjacentSettingsTab("actions", 1), "actions")
    compare(Presentation.adjacentSettingsTab("", 2), "voice")
  }
}
