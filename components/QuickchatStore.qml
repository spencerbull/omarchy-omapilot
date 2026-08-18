pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Protocol.js" as Protocol

// One process and one ephemeral UI model for every screen. The broker is the
// only durable authority; this singleton merely normalizes its NDJSON stream
// into renderable presentation state.
Scope {
  id: root

  readonly property int protocolVersion: Protocol.protocolVersion
  readonly property string bundledBrokerPath: {
    var url = String(Qt.resolvedUrl("../runtime/bin/quickchat-broker"))
    if (url.indexOf("file://") === 0) {
      try { return decodeURIComponent(url.slice("file://".length)) }
      catch (error) { return url.slice("file://".length) }
    }
    return url
  }
  readonly property string brokerPath: Quickshell.env("QUICKCHAT_BROKER_PATH") || bundledBrokerPath
  property string state: "preparing"
  property string statusMessage: "Starting OmaPilot…"
  property string currentId: ""
  property string currentChatId: ""
  property string question: ""
  property string answerMarkdown: ""
  property var errorDetails: null
  property var images: []
  property var providers: []
  property var builtinAuthMethods: []
  property var builtinAuth: ({ phase: "idle", flowId: "", methodId: "", message: "", url: "",
    verificationUri: "", userCode: "", prompt: null })
  property var history: []
  property string provider: "builtin"
  property string model: ""
  property var pendingPermission: null
  property var permissionQueue: []
  property string transcript: ""
  property string dictationPhase: ""
  property bool initialized: false
  property bool processStarted: false
  property var queuedCommands: []
  property string stderrTail: ""
  property string configuredProvider: "builtin"
  property string configuredBuiltinModel: ""
  property string configuredCodexModel: ""
  property string configuredClaudeModel: ""
  property string configuredOpencodeModel: ""
  property bool configuredDangerousAutoApprove: false
  property bool desktopContextEnabled: true
  property bool brokerDesktopContextSupported: false
  property var latchedActiveWindow: null
  property var latchedCaptureTarget: null
  property var contextAttachments: []
  property bool brokerContextAttachmentsSupported: false
  property bool harnessRestartPending: false
  property string pendingContextRequestId: ""
  property var browserCompanionStatus: ({
    phase: "ready", relayInstalled: false, setupAvailable: false,
    chromiumConnected: false, firefoxConnected: false,
    chromiumExtensionPath: "", firefoxExtensionPath: "", message: ""
  })

  readonly property bool busy: state === "preparing" || state === "dictating" || state === "streaming" || state === "stopping"
  readonly property bool canSubmit: initialized && providers.length > 0 && !busy
  readonly property bool canRetry: state === "unavailable" && (!processStarted || providers.length === 0)
  readonly property var modelOptions: Protocol.modelOptions(providers, provider)
  readonly property var providerPolicy: Protocol.providerPolicy(providers, provider)
  readonly property bool desktopContextActive: desktopContextEnabled && brokerDesktopContextSupported
  readonly property bool contextCaptureAvailable: initialized && brokerContextAttachmentsSupported && !busy
  readonly property bool browserCompanionConnected: browserCompanionStatus.chromiumConnected === true
    || browserCompanionStatus.firefoxConnected === true
  readonly property bool browserCompanionBusy: browserCompanionStatus.phase === "installing"
    || browserCompanionStatus.phase === "removing"
  readonly property bool builtinAuthBusy: ["starting", "prompt", "info", "browser", "device_code"]
    .indexOf(String(builtinAuth.phase || "")) >= 0

  signal answerChanged()
  signal focusComposerRequested()
  signal toastRequested(string message)
  signal herdrContinued()
  signal ipcOpenRequested()
  signal ipcCloseRequested()
  signal ipcToggleRequested()
  signal ipcHistoryRequested()
  signal contextOverlayRequested(string payload)
  signal contextBrowserPickerRequested()
  signal contextAttachmentAdded()

  function routeIpc(method) {
    if (method === "open" || method === "show") ipcOpenRequested()
    else if (method === "close" || method === "hide") ipcCloseRequested()
    else if (method === "toggle") ipcToggleRequested()
    else if (method === "history") ipcHistoryRequested()
    else if (method === "newChat") { newChat(); ipcOpenRequested() }
  }

  function configure(settings) {
    var source = settings || {}
    var desiredProvider = Protocol.normalizedProvider(source.provider) || "builtin"
    var desiredBuiltinModel = String(source.builtinModel || "")
    var desiredCodexModel = String(source.codexModel || "")
    var desiredClaudeModel = String(source.claudeModel || "")
    var desiredOpencodeModel = String(source.opencodeModel || "")
    var desiredDangerousAutoApprove = source.dangerousAutoApprove === true
    var desiredDesktopContext = String(source.desktopContext || "On") !== "Off"
    var harnessChanged = desiredProvider !== configuredProvider
    var changed = harnessChanged
      || desiredBuiltinModel !== configuredBuiltinModel
      || desiredCodexModel !== configuredCodexModel
      || desiredClaudeModel !== configuredClaudeModel
      || desiredOpencodeModel !== configuredOpencodeModel
      || desiredDangerousAutoApprove !== configuredDangerousAutoApprove
      || desiredDesktopContext !== desktopContextEnabled
    if (!changed) return
    configuredProvider = desiredProvider
    configuredBuiltinModel = desiredBuiltinModel
    configuredCodexModel = desiredCodexModel
    configuredClaudeModel = desiredClaudeModel
    configuredOpencodeModel = desiredOpencodeModel
    configuredDangerousAutoApprove = desiredDangerousAutoApprove
    desktopContextEnabled = desiredDesktopContext
    if (!desktopContextEnabled) latchedActiveWindow = null
    provider = desiredProvider
    var desiredModel = desiredProvider === "claude" ? desiredClaudeModel
      : desiredProvider === "opencode" ? desiredOpencodeModel : desiredCodexModel
    if (desiredProvider === "builtin") desiredModel = desiredBuiltinModel
    model = desiredModel
    if (providers.length > 0) selectProvider(provider)
    if (harnessChanged && processStarted) restartForHarnessChange()
  }

  function restartForHarnessChange() {
    harnessRestartPending = true
    initialized = false
    providers = []
    state = "preparing"
    statusMessage = "Starting " + Protocol.providerLabel(provider) + "…"
    broker.running = false
  }

  function providerAvailable(value) {
    for (var i = 0; i < providers.length; i++) if (providers[i].value === value) return true
    return false
  }

  function selectProvider(value) {
    var desired = Protocol.normalizedProvider(value)
    if (!providerAvailable(desired)) return
    provider = desired
    var options = Protocol.modelOptions(providers, provider)
    var found = false
    for (var i = 0; i < options.length; i++) if (options[i].value === model) found = true
    if (!found) {
      var preferred = ""
      for (var p = 0; p < providers.length; p++)
        if (providers[p].value === provider) preferred = String(providers[p].defaultModel || "")
      model = preferred || (options.length > 0 ? options[0].value : "")
    }
  }

  function sendCommand(payload) {
    if (!payload || !payload.type) return
    if (!broker.running || !processStarted) {
      var queued = queuedCommands.slice()
      queued.push(payload)
      queuedCommands = queued
      if (!broker.running) broker.running = true
      return
    }
    broker.write(JSON.stringify(payload) + "\n")
  }

  function flushQueue() {
    var queued = queuedCommands
    queuedCommands = []
    for (var i = 0; i < queued.length; i++) broker.write(JSON.stringify(queued[i]) + "\n")
  }

  function initialize() {
    sendCommand(Protocol.command("initialize", {
      protocolVersion: protocolVersion,
      harness: provider,
      client: "omarchy-quickchat"
    }))
  }

  function latchDesktopContext() {
    var captureTarget = DesktopContext.captureTarget()
    if (captureTarget !== null) latchedCaptureTarget = captureTarget
    if (!desktopContextEnabled) return
    var context = DesktopContext.snapshot()
    if (context && context.activeWindow) latchedActiveWindow = context.activeWindow
  }

  function clearDesktopContextLatch() {
    latchedActiveWindow = null
    latchedCaptureTarget = null
  }

  function desktopContextForSubmit() {
    if (!desktopContextActive) return null
    var context = DesktopContext.snapshot()
    return Protocol.desktopContextWithLatchedActive(context, latchedActiveWindow)
  }

  function submit(text) {
    var prompt = String(text || "").trim()
    if (!prompt || !canSubmit) return false
    var resumeChatId = currentChatId
    currentId = "qml-" + Date.now() + "-" + Math.floor(Math.random() * 100000)
    currentChatId = ""
    question = prompt
    answerMarkdown = ""
    errorDetails = null
    images = []
    pendingPermission = null
    permissionQueue = []
    state = "preparing"
    statusMessage = "Preparing " + Protocol.providerLabel(provider) + "…"
    var context = desktopContextForSubmit()
    var attachmentSelections = []
    for (var attachmentIndex = 0; attachmentIndex < contextAttachments.length; attachmentIndex++) {
      var attachment = contextAttachments[attachmentIndex]
      attachmentSelections.push({ id: attachment.id, representationIds: attachment.selectedRepresentationIds })
    }
    var autoApprove = configuredDangerousAutoApprove
    sendCommand(Protocol.submitCommand(
      currentId, prompt, provider, model, context, autoApprove, attachmentSelections, resumeChatId))
    contextAttachments = []
    answerChanged()
    return true
  }

  function beginContextCapture() {
    if (!contextCaptureAvailable) return false
    pendingContextRequestId = "capture-" + Date.now() + "-" + Math.floor(Math.random() * 100000)
    sendCommand(Protocol.contextBeginCommand(pendingContextRequestId, latchedCaptureTarget))
    statusMessage = "Preparing context capture…"
    return true
  }

  function requestBrowserCompanionStatus() {
    sendCommand(Protocol.command("browser_companion_status"))
  }

  function installBrowserCompanion() {
    if (browserCompanionBusy) return
    sendCommand(Protocol.command("browser_companion_install"))
  }

  function uninstallBrowserCompanion() {
    if (browserCompanionBusy) return
    sendCommand(Protocol.command("browser_companion_uninstall"))
  }

  function openBrowserCompanionSettings(family) {
    var selected = family === "firefox" ? "firefox" : "chromium"
    sendCommand(Protocol.command("browser_companion_open_settings", { family: selected }))
  }

  function copyBrowserCompanionPath(family) {
    var path = family === "firefox" ? browserCompanionStatus.firefoxExtensionPath
      : browserCompanionStatus.chromiumExtensionPath
    if (String(path || "") !== "") copyText(path)
  }

  function captureContext(requestId, mode, region, anchor) {
    var values = { id: String(requestId || ""), mode: mode === "window" ? "window" : "region" }
    var normalizedRegion = Protocol.normalizedRectangle(region)
    if (normalizedRegion !== null) values.region = normalizedRegion
    if (anchor && Number.isFinite(Number(anchor.x)) && Number.isFinite(Number(anchor.y)))
      values.anchor = { x: Math.round(Number(anchor.x)), y: Math.round(Number(anchor.y)) }
    sendCommand(Protocol.command("context_capture", values))
    statusMessage = "Extracting context…"
  }

  function cancelContextCapture(requestId) {
    var id = String(requestId || "")
    if (id === "") return
    if (pendingContextRequestId === id) pendingContextRequestId = ""
    sendCommand(Protocol.command("context_cancel", { id: id }))
    statusMessage = ""
  }

  function setContextRepresentation(attachmentId, mode) {
    var values = String(mode || "").split("+")
    var next = []
    for (var i = 0; i < contextAttachments.length; i++) {
      var attachment = contextAttachments[i]
      if (String(attachment.id) === String(attachmentId)) {
        var copy = {}
        for (var key in attachment) copy[key] = attachment[key]
        copy.selectedRepresentationIds = values
        next.push(copy)
      } else next.push(attachment)
    }
    contextAttachments = next
  }

  function removeContextAttachment(attachmentId) {
    var id = String(attachmentId || "")
    var next = []
    for (var i = 0; i < contextAttachments.length; i++)
      if (String(contextAttachments[i].id) !== id) next.push(contextAttachments[i])
    contextAttachments = next
    sendCommand(Protocol.command("context_discard", { id: id }))
  }

  function clearContextAttachments() {
    var current = contextAttachments
    contextAttachments = []
    for (var i = 0; i < current.length; i++)
      sendCommand(Protocol.command("context_discard", { id: String(current[i].id || "") }))
  }

  function cancel() {
    if (dictationPhase !== "") {
      sendCommand(Protocol.command("dictation_cancel"))
      return
    }
    if (state !== "preparing" && state !== "streaming") return
    sendCommand(Protocol.command("cancel", { id: currentId }))
  }

  function respondPermission(decision, choiceId) {
    if (!pendingPermission || !currentId) return
    sendCommand(Protocol.command("permission_response", {
      id: currentId,
      permissionId: String(pendingPermission.id || ""),
      choiceId: String(choiceId || ""),
      decision: String(decision || "reject_once")
    }))
  }

  function permissionOptionsWithoutDenyOnce() {
    var options = pendingPermission && Array.isArray(pendingPermission.options) ? pendingPermission.options : []
    var result = []
    for (var i = 0; i < options.length; i++)
      if (options[i].decision !== "reject_once") result.push(options[i])
    return result
  }

  function hasPermissionDecision(decision) {
    var options = pendingPermission && Array.isArray(pendingPermission.options) ? pendingPermission.options : []
    for (var i = 0; i < options.length; i++)
      if (options[i].decision === decision) return true
    return false
  }

  function permissionChoiceId(decision) {
    var options = pendingPermission && Array.isArray(pendingPermission.options) ? pendingPermission.options : []
    for (var i = 0; i < options.length; i++)
      if (options[i].decision === decision) return String(options[i].id || "")
    return ""
  }

  function closePermission(permissionId) {
    var id = String(permissionId || "")
    var queued = []
    for (var i = 0; i < permissionQueue.length; i++)
      if (String(permissionQueue[i].id || "") !== id) queued.push(permissionQueue[i])
    permissionQueue = queued
    if (pendingPermission && String(pendingPermission.id || "") === id)
      pendingPermission = queued.length > 0 ? queued[0] : null
  }

  function newChat() {
    clearContextAttachments()
    currentId = ""
    currentChatId = ""
    question = ""
    answerMarkdown = ""
    errorDetails = null
    images = []
    pendingPermission = null
    permissionQueue = []
    transcript = ""
    state = initialized ? "composing" : "preparing"
    statusMessage = initialized ? "" : "Starting OmaPilot…"
    focusComposerRequested()
    answerChanged()
  }

  function startDictation() {
    if (!initialized || busy) return
    transcript = ""
    sendCommand(Protocol.command("dictation_start"))
  }

  function stopDictation() {
    if (state === "dictating") sendCommand(Protocol.command("dictation_stop"))
  }

  function requestHistory() { sendCommand(Protocol.command("history_list")) }
  function deleteHistory(chatId) { sendCommand(Protocol.command("history_delete", { chatId: String(chatId) })) }
  function clearHistory() { sendCommand(Protocol.command("history_clear")) }
  function copyText(text) { sendCommand(Protocol.command("copy", { text: String(text || "") })) }

  function retryBroker() {
    if (!canRetry) return
    state = "preparing"
    statusMessage = "Restarting OmaPilot…"
    errorDetails = null
    stderrTail = ""
    if (broker.running) {
      harnessRestartPending = true
      broker.running = false
    } else broker.running = true
  }

  function authenticateBuiltIn(methodId) {
    if (provider !== "builtin" || builtinAuthBusy) return
    var selected = String(methodId || "")
    if (selected === "" && builtinAuthMethods.length > 0) selected = String(builtinAuthMethods[0].value || "")
    if (selected === "") return
    builtinAuth = ({ phase: "starting", flowId: "", methodId: selected,
      message: "Starting secure authentication…", url: "", verificationUri: "", userCode: "", prompt: null })
    sendCommand(Protocol.command("auth_begin", { methodId: selected }))
  }

  function respondBuiltInAuth(value) {
    var prompt = builtinAuth.prompt
    if (!prompt || !builtinAuth.flowId) return
    sendCommand(Protocol.command("auth_response", {
      flowId: String(builtinAuth.flowId), promptId: String(prompt.id || ""), value: String(value || "")
    }))
    var next = {}
    for (var key in builtinAuth) next[key] = builtinAuth[key]
    next.prompt = null
    next.phase = "info"
    next.message = "Continuing authentication…"
    builtinAuth = next
  }

  function cancelBuiltInAuth() {
    if (!builtinAuth.flowId) return
    sendCommand(Protocol.command("auth_cancel", { flowId: String(builtinAuth.flowId) }))
  }
  function activateLink(url) {
    var value = String(url || "")
    if (Protocol.isImageLink(value)) {
      var target = Protocol.imageUrl(value)
      if (target) sendCommand(Protocol.command("load_image", { url: target }))
      return
    }
    if (Protocol.isSafeExternalUrl(value))
      sendCommand(Protocol.command("open_link", { url: value }))
  }

  function requestImage(value) {
    var image = Protocol.normalizedImage(value)
    if (image.remoteUrl) sendCommand(Protocol.command("load_image", { id: image.id, url: image.remoteUrl }))
  }

  function continueInHerdr() {
    if (!currentChatId) return
    state = "preparing"
    statusMessage = "Opening in Herdr…"
    sendCommand(Protocol.command("continue_in_herdr", { chatId: currentChatId }))
  }

  function loadChat(chat) {
    if (!chat) return
    currentChatId = String(chat.id || "")
    currentId = ""
    question = String(chat.question || "")
    answerMarkdown = String(chat.answer || chat.markdown || "")
    errorDetails = null
    images = Array.isArray(chat.images) ? chat.images : []
    provider = Protocol.normalizedProvider(chat.provider) || provider
    model = String(chat.model || "")
    pendingPermission = null
    state = "complete"
    statusMessage = ""
    answerChanged()
  }

  function applyProviders(raw) {
    var discovered = Protocol.normalizeProviders(raw)
    providers = Protocol.exactHarnessProviders(raw, configuredProvider)
    if (providers.length === 0) {
      state = "unavailable"
      var mismatched = discovered.length > 0
      statusMessage = mismatched
        ? "OmaPilot refused an unexpected harness response. Restart the selected harness and try again."
        : configuredProvider === "builtin"
          ? "Built-in (OmaPilot) needs authentication. Finish the secure setup in Settings."
          : Protocol.providerLabel(configuredProvider) + " is unavailable. Install and sign in to it, then retry or choose another harness in Settings."
      errorDetails = Protocol.normalizedError({
        unavailable: true,
        code: mismatched ? "provider_mismatch" : "provider_unavailable",
        message: statusMessage,
        retryable: !mismatched
      })
      return
    }
    provider = configuredProvider
    selectProvider(configuredProvider)
    var readyState = Protocol.providerReadyState(state, providers.length)
    if (readyState !== state) {
      state = readyState
      statusMessage = ""
      errorDetails = null
    }
  }

  function prependHistory(chat) {
    if (!chat || !chat.id) return
    var items = [chat]
    for (var i = 0; i < history.length && items.length < 30; i++) {
      if (String(history[i].id) !== String(chat.id)) items.push(history[i])
    }
    history = Protocol.normalizedHistory(items)
  }

  function applyEvent(event) {
    if (!event || !event.type) return
    var type = String(event.type)
    if (type === "ready") {
      if (!Protocol.isCompatibleEvent(event)) {
        initialized = false
        state = "unavailable"
        statusMessage = "OmaPilot protocol mismatch. Update the plugin and try again."
        errorDetails = Protocol.normalizedError({
          unavailable: true,
          code: "protocol_mismatch",
          message: statusMessage,
          retryable: false
        })
        return
      }
      initialized = true
      brokerDesktopContextSupported = Protocol.hasFeature(event.features, "desktop-context")
      brokerContextAttachmentsSupported = Protocol.hasFeature(event.features, "context-attachments")
      applyProviders(event.providers || [])
      history = Protocol.normalizedHistory(event.history || [])
      return
    }
    if (type === "providers") {
      applyProviders(event.providers || [])
      return
    }
    if (type === "auth_methods") {
      builtinAuthMethods = Protocol.normalizedAuthMethods(event.methods || [])
      return
    }
    if (type === "auth") {
      var authEvent = Protocol.normalizedAuthEvent(event)
      if (!authEvent) return
      if (authEvent.phase !== "starting" && builtinAuth.flowId
          && authEvent.flowId !== String(builtinAuth.flowId)) return
      if (!builtinAuth.flowId && authEvent.phase !== "starting" && builtinAuth.methodId
          && authEvent.methodId !== String(builtinAuth.methodId)) return
      var merged = {}
      for (var authKey in builtinAuth) merged[authKey] = builtinAuth[authKey]
      for (var eventKey in authEvent) {
        if (eventKey === "prompt" && authEvent.prompt === null && authEvent.phase !== "complete"
            && authEvent.phase !== "cancelled" && authEvent.phase !== "error") continue
        if ((eventKey === "url" || eventKey === "verificationUri" || eventKey === "userCode")
            && String(authEvent[eventKey] || "") === "") continue
        merged[eventKey] = authEvent[eventKey]
      }
      builtinAuth = merged
      if (authEvent.phase === "browser" && authEvent.url) activateLink(authEvent.url)
      else if (authEvent.phase === "device_code" && authEvent.verificationUri) activateLink(authEvent.verificationUri)
      if (authEvent.phase === "complete") toastRequested("Built-in authentication complete")
      return
    }
    if (type === "state") {
      if (event.id && currentId && String(event.id) !== currentId) return
      if (String(event.state || "") === "idle" && currentChatId !== "") {
        state = "complete"
        statusMessage = ""
        return
      }
      state = String(event.state || "") === "stopping" ? "stopping" : Protocol.normalizedState(event.state, state)
      statusMessage = String(event.message || "")
      if (state === "error" || state === "unavailable") errorDetails = Protocol.normalizedError({
        unavailable: state === "unavailable",
        code: String(event.code || "state_" + state),
        message: statusMessage,
        retryable: event.retryable === true
      })
      return
    }
    if (type === "content") {
      if (event.id && currentId && String(event.id) !== currentId) return
      answerMarkdown += String(event.delta || event.text || "")
      errorDetails = null
      state = "streaming"
      statusMessage = ""
      answerChanged()
      return
    }
    if (type === "permission") {
      var permission = Protocol.normalizedPermission(event.permission, currentId)
      if (!permission) return
      var queued = permissionQueue.slice()
      for (var permissionIndex = 0; permissionIndex < queued.length; permissionIndex++)
        if (String(queued[permissionIndex].id || "") === permission.id) return
      queued.push(permission)
      permissionQueue = queued
      if (!pendingPermission) pendingPermission = permission
      state = "streaming"
      statusMessage = "Waiting for tool approval…"
      return
    }
    if (type === "permission_closed") {
      if (String(event.id || "") !== currentId) return
      closePermission(event.permissionId)
      if (String(event.reason || "") === "expired")
        toastRequested("Tool approval expired")
      return
    }
    if (type === "image") {
      var eventId = String(event.id || "")
      var sourceUrl = String(event.image && event.image.sourceUrl || "")
      var isRemoteLoad = /^https:\/\//i.test(eventId) || /^https:\/\//i.test(sourceUrl)
      if (!isRemoteLoad && eventId && currentId && eventId !== currentId) return
      images = Protocol.mergeImageEvent(images, event, currentId)
      answerChanged()
      return
    }
    if (type === "context_ready") {
      if (String(event.id || "") !== pendingContextRequestId) return
      statusMessage = ""
      contextOverlayRequested(JSON.stringify({ id: event.id, target: event.target || {} }))
      return
    }
    if (type === "context_picker") {
      if (String(event.id || "") !== pendingContextRequestId) return
      statusMessage = "Click an element in " + String(event.browser || "the browser") + "…"
      contextBrowserPickerRequested()
      return
    }
    if (type === "context_notice") {
      if (String(event.id || "") !== pendingContextRequestId) return
      toastRequested(String(event.message || "Browser element capture is unavailable"))
      return
    }
    if (type === "context_attachment") {
      if (String(event.requestId || "") !== pendingContextRequestId) return
      pendingContextRequestId = ""
      var attachment = Protocol.normalizedContextAttachment(event.attachment)
      if (!attachment) {
        toastRequested("The captured context was invalid")
        return
      }
      var nextAttachments = contextAttachments.slice()
      if (nextAttachments.length >= 4) removeContextAttachment(nextAttachments.shift().id)
      nextAttachments.push(attachment)
      contextAttachments = nextAttachments
      statusMessage = ""
      contextAttachmentAdded()
      return
    }
    if (type === "browser_companion") {
      browserCompanionStatus = Protocol.normalizedBrowserCompanion(event)
      if (browserCompanionStatus.message !== "") toastRequested(browserCompanionStatus.message)
      return
    }
    if (type === "complete") {
      if (event.id && currentId && String(event.id) !== currentId) return
      if (event.answer !== undefined) answerMarkdown = String(event.answer)
      if (event.chat) {
        currentChatId = String(event.chat.id || currentChatId)
        question = String(event.chat.question || question)
        answerMarkdown = String(event.chat.answer || event.chat.markdown || answerMarkdown)
        if (Array.isArray(event.chat.images)) images = event.chat.images
        prependHistory(event.chat)
      } else if (event.chatId) currentChatId = String(event.chatId)
      if (event.history) history = Protocol.normalizedHistory(event.history)
      state = "complete"
      errorDetails = null
      pendingPermission = null
      permissionQueue = []
      statusMessage = ""
      answerChanged()
      return
    }
    if (type === "error") {
      if (pendingContextRequestId !== "" && String(event.id || "") === pendingContextRequestId) {
        pendingContextRequestId = ""
        statusMessage = ""
        toastRequested(String(event.message || "Context capture failed"))
        return
      }
      if (event.id && currentId && String(event.id) !== currentId) return
      if (!event.id && String(event.code || "").indexOf("image_") === 0) {
        toastRequested(String(event.message || "Could not load that image"))
        return
      }
      if (String(event.code || "").toLowerCase() === "cancelled") {
        state = "canceled"
        pendingPermission = null
        permissionQueue = []
        statusMessage = String(event.message || "Stopped")
        errorDetails = null
        answerChanged()
        return
      }
      state = event.unavailable === true ? "unavailable" : "error"
      pendingPermission = null
      permissionQueue = []
      statusMessage = String(event.message || "OmaPilot could not complete that request.")
      errorDetails = Protocol.normalizedError(event, statusMessage)
      return
    }
    if (type === "dictation") {
      var dictationState = String(event.state || "")
      transcript = String(event.text || transcript)
      if (dictationState === "recording") {
        dictationPhase = "recording"
        state = "dictating"
        statusMessage = "Listening…"
      } else if (dictationState === "transcribing") {
        dictationPhase = "transcribing"
        state = "preparing"
        statusMessage = "Transcribing…"
      } else if (dictationState === "idle" || dictationState === "complete" || dictationState === "canceled") {
        dictationPhase = ""
        state = "composing"
        statusMessage = ""
      } else if (dictationState === "unavailable" || dictationState === "error") {
        dictationPhase = ""
        state = "error"
        statusMessage = String(event.message || "Dictation is unavailable.")
        errorDetails = Protocol.normalizedError({
          code: "dictation_" + dictationState,
          message: statusMessage,
          retryable: dictationState === "unavailable",
          unavailable: dictationState === "unavailable"
        })
      }
      return
    }
    if (type === "history") {
      history = Protocol.normalizedHistory(event.items || event.history || [])
      return
    }
    if (type === "herdr") {
      var outcome = Protocol.herdrOutcome(event)
      if (!outcome) { console.warn("quickchat: unknown Herdr state " + String(event.state || "")); return }
      state = outcome.state
      statusMessage = outcome.message
      if (outcome.state === "error") errorDetails = Protocol.normalizedError({
        code: String(event.errorCode || "herdr_" + String(event.state || "failed")),
        message: statusMessage,
        retryable: true
      })
      if (outcome.toast) toastRequested(statusMessage)
      if (String(event.state || "") === "continued") herdrContinued()
      return
    }
    if (type === "copied") {
      toastRequested(event.copied === true ? "Copied" : "Could not copy")
      return
    }
    if (type === "link" && event.opened === false) {
      toastRequested("Could not open that link")
    }
  }

  IpcHandler {
    target: "io.github.spencerbull.quickchat"
    function open() { root.routeIpc("open") }
    function close() { root.routeIpc("close") }
    function show() { root.routeIpc("show") }
    function hide() { root.routeIpc("hide") }
    function toggle() { root.routeIpc("toggle") }
    function newChat() { root.routeIpc("newChat") }
    function history() { root.routeIpc("history") }
  }

  Process {
    id: broker
    command: [root.brokerPath]
    stdinEnabled: true
    running: true

    onStarted: {
      root.processStarted = true
      root.stderrTail = ""
      root.pendingPermission = null
      root.permissionQueue = []
      root.initialize()
      root.flushQueue()
    }

    onExited: function(exitCode, exitStatus) {
      root.processStarted = false
      root.initialized = false
      root.pendingPermission = null
      root.permissionQueue = []
      if (root.harnessRestartPending) {
        root.harnessRestartPending = false
        Qt.callLater(function() { broker.running = true })
        return
      }
      if (root.state !== "canceled") root.state = "unavailable"
      root.statusMessage = root.stderrTail || "OmaPilot is unavailable."
      root.errorDetails = Protocol.normalizedError({
        unavailable: true,
        code: "broker_unavailable",
        message: root.statusMessage,
        retryable: true
      })
    }

    stdout: SplitParser {
      onRead: function(line) {
        var event = Protocol.parseLine(line)
        if (event) root.applyEvent(event)
        else if (String(line || "").trim() !== "") console.warn("quickchat: invalid broker event")
      }
    }

    stderr: SplitParser {
      onRead: function(line) {
        var message = String(line || "").trim()
        if (message) root.stderrTail = message.slice(0, 240)
      }
    }
  }
}
