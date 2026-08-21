import QtQuick
import QtQuick.Window
import Quickshell
import "components" as OmaPilot

ShellRoot {
  id: root
  property bool failed: false
  property int stage: 0

  function fail(message) {
    failed = true
    console.error("omapilot server save probe failed: " + message)
  }

  QtObject {
    id: backend
    property string state: "composing"
    property string provider: "builtin"
    property var providers: [{ value: "builtin" }]
    property var modelOptions: []
    property var builtinAuthMethods: []
    property var builtinAuth: ({ phase: "idle", prompt: null })
    property bool builtinAuthBusy: false
    property var browserCompanionStatus: ({
      phase: "ready", relayInstalled: false, setupAvailable: false,
      chromiumConnected: false, firefoxConnected: false,
      chromiumExtensionPath: "", firefoxExtensionPath: "", message: ""
    })
    property bool browserCompanionConnected: false
    property bool browserCompanionBusy: false
    property var voxtypeOsd: ({ available: false, enabled: true, message: "" })
    property var customProviders: []
    property var customProviderSaved: null
    property string customProviderError: ""
    property var customProviderTest: null
    property string customProviderTestError: ""
  }

  Window {
    width: 900
    height: 900
    visible: true

    OmaPilot.SettingsView {
      id: view
      anchors.fill: parent
      backend: backend
    }
  }

  Timer {
    id: probeTimer
    interval: 80
    running: true
    repeat: true
    onTriggered: {
      if (root.stage === 0) {
        view.serverFormExpanded = true
        view.serverSavePending = true
        view.serverPendingId = "local-qwen"
        view.serverPendingName = "Local Qwen"
        backend.customProviderSaved = { id: "other", name: "Other" }
      } else if (root.stage === 1) {
        if (!view.serverFormExpanded || !view.serverSavePending || view.serverFormNotice !== "")
          root.fail("an unrelated acknowledgement completed the save")
        backend.customProviderSaved = { id: "local-qwen", name: "Local Qwen" }
      } else if (root.stage === 2) {
        if (view.serverFormExpanded || view.serverSavePending
            || view.serverFormNotice !== "Saved Local Qwen.")
          root.fail("a matching acknowledgement did not complete the save")
        view.serverFormExpanded = true
        view.serverSavePending = true
        view.serverPendingId = "bad-id"
        view.serverPendingName = "Bad server"
        view.serverFormNotice = ""
        backend.customProviderError = "Use a short lowercase id"
      } else if (root.stage === 3) {
        if (!view.serverFormExpanded || view.serverSavePending
            || view.serverFormError !== "Use a short lowercase id")
          root.fail("a rejection did not keep the form open with its reason")
        view.editServer({
          id: "keyed-server",
          name: "Keyed server",
          baseUrl: "https://keyed.example/v1",
          api: "openai-completions",
          models: [{ id: "secure-model", name: "Secure Model", contextWindow: 262144 }],
          requiresAuth: true
        })
      } else if (root.stage === 4) {
        if (view.serverDraftKey !== ""
            || view.serverTestUrl !== "https://keyed.example/v1"
            || view.serverTestModels.length !== 1
            || String(view.serverTestModels[0].id || "") !== "secure-model"
            || String(view.serverTestModels[0].name || "") !== "Secure Model"
            || Number(view.serverTestModels[0].contextWindow || 0) !== 262144)
          root.fail("editing a keyed server discarded its verified models or required its stored key")
        view.serverDraftKey = "replacement"
        view.refreshServerTestValidity()
        if (view.serverTestModels.length !== 0)
          root.fail("entering a replacement key did not invalidate the prior server test")
        view.serverDraftKey = ""
        view.refreshServerTestValidity()
        if (view.serverTestModels.length !== 1 || view.serverTestUrl !== "https://keyed.example/v1"
            || Number(view.serverTestModels[0].contextWindow || 0) !== 262144)
          root.fail("clearing a replacement key did not restore the existing credential path")
        view.serverRemoveConfirmId = "keyed-server"
        view.browserRemoveConfirmation = true
        view.selectTab("agent")
      } else if (root.stage === 5) {
        if (view.selectedTab !== "agent"
            || view.serverRemoveConfirmId !== ""
            || view.browserRemoveConfirmation)
          root.fail("switching tabs left a hidden confirmation armed")
        if (!root.failed) console.log("OMAPILOT_SERVER_SAVE_PROBE_OK")
        probeTimer.stop()
        Qt.quit()
      }
      root.stage += 1
    }
  }
}
