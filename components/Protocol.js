.pragma library

// UI-facing OmaPilot protocol, version 1. The broker owns harness details,
// policy, persistence, URL opening, clipboard writes, and Herdr control. QML
// only sends typed commands and renders normalized events.

var protocolVersion = 2
var validStates = [
  "idle", "composing", "preparing", "dictating", "streaming",
  "complete", "canceled", "error", "unavailable", "history"
]

function providerReadyState(currentState, providerCount) {
  var current = String(currentState || "")
  if (Number(providerCount || 0) > 0 && ["preparing", "unavailable"].indexOf(current) >= 0)
    return "composing"
  return current
}

function historyContinuationBlocked(requiredProvider, configuredProvider, providers) {
  var required = normalizedProvider(requiredProvider)
  if (required === "") return false
  if (normalizedProvider(configuredProvider) !== required) return true
  var rows = Array.isArray(providers) ? providers : []
  for (var i = 0; i < rows.length; i++)
    if (String(rows[i] && rows[i].value || "") === required) return false
  return true
}

function command(type, values) {
  var result = { type: String(type || "") }
  var source = values || {}
  for (var key in source) result[key] = source[key]
  return result
}

function normalizedAuthMethods(raw) {
  var source = Array.isArray(raw) ? raw : []
  var result = []
  for (var i = 0; i < source.length && result.length < 32; i++) {
    var method = source[i] && typeof source[i] === "object" ? source[i] : {}
    var id = String(method.id || "")
    var providerId = String(method.providerId || "")
    var authType = String(method.authType || "")
    if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}::(?:api_key|oauth)$/.test(id)
        || !/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/.test(providerId)
        || ["api_key", "oauth"].indexOf(authType) < 0) continue
    result.push({
      value: id,
      label: safeContextText(method.label, 120) || providerId,
      description: safeContextText(method.description, 240),
      providerId: providerId,
      authType: authType
    })
  }
  return result
}

function normalizedAuthEvent(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var phase = String(source.phase || "")
  if (["starting", "prompt", "info", "browser", "device_code", "complete", "cancelled", "error"].indexOf(phase) < 0) return null
  var result = {
    phase: phase,
    flowId: String(source.flowId || ""),
    methodId: String(source.methodId || ""),
    message: safeContextText(source.message || source.instructions, 500),
    url: isSafeExternalUrl(source.url) ? String(source.url) : "",
    verificationUri: isSafeExternalUrl(source.verificationUri) ? String(source.verificationUri) : "",
    userCode: safeContextText(source.userCode, 120),
    prompt: null
  }
  var prompt = source.prompt && typeof source.prompt === "object" ? source.prompt : null
  if (prompt !== null) {
    var kind = String(prompt.kind || "")
    if (["text", "secret", "select"].indexOf(kind) >= 0) {
      var options = []
      var rawOptions = Array.isArray(prompt.options) ? prompt.options : []
      for (var i = 0; i < rawOptions.length && options.length < 32; i++) {
        var option = rawOptions[i] && typeof rawOptions[i] === "object" ? rawOptions[i] : {}
        var optionId = safeContextText(option.id, 160)
        if (!optionId) continue
        options.push({ value: optionId, label: safeContextText(option.label, 120) || optionId,
          description: safeContextText(option.description, 240) })
      }
      result.prompt = { id: String(prompt.id || ""), kind: kind,
        message: safeContextText(prompt.message, 500), placeholder: safeContextText(prompt.placeholder, 500), options: options }
    }
  }
  return result
}

function submitCommand(id, question, provider, model, desktopContext, dangerousAutoApprove, contextAttachments, resumeChatId, webHandoffProvider) {
  var payload = command("submit", {
    id: String(id || ""),
    question: String(question || ""),
    provider: normalizedProvider(provider) || "builtin"
  })
  var previousChat = String(resumeChatId || "")
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(previousChat))
    payload.resumeChatId = previousChat
  var selectedModel = String(model || "").trim()
  if (selectedModel !== "") payload.model = selectedModel
  var context = normalizedDesktopContext(desktopContext)
  if (context !== null) payload.desktopContext = context
  var attachments = normalizedContextSelections(contextAttachments)
  if (attachments.length > 0) payload.contextAttachments = attachments
  var handoffProvider = normalizedWebHandoffProvider(webHandoffProvider)
  if (handoffProvider !== "") payload.webHandoffProvider = handoffProvider
  if (dangerousAutoApprove === true) payload.dangerousAutoApprove = true
  return payload
}

function contextBeginCommand(id, captureTarget) {
  var payload = command("context_begin", { id: String(id || "") })
  var target = normalizedCaptureTarget(captureTarget)
  if (target !== null) payload.target = target
  return payload
}

function normalizedRectangle(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var x = Math.round(Number(source.x)); var y = Math.round(Number(source.y))
  var width = Math.round(Number(source.width)); var height = Math.round(Number(source.height))
  if (![x, y, width, height].every(Number.isFinite) || width < 1 || height < 1
      || width > 12000 || height > 12000 || width * height > 16000000) return null
  return { x: x, y: y, width: width, height: height }
}

function normalizedCaptureTarget(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var result = {}
  var appId = safeContextText(source.appId, 160)
  var title = safeContextText(source.title, 240)
  var bounds = normalizedRectangle(source.bounds)
  if (appId !== "") result.appId = appId
  if (title !== "") result.title = title
  if (bounds !== null) result.bounds = bounds
  return Object.keys(result).length > 0 ? result : null
}

function normalizedContextSelections(raw) {
  var source = Array.isArray(raw) ? raw : []
  var result = []
  var ids = {}
  for (var i = 0; i < source.length && result.length < 4; i++) {
    var item = source[i] && typeof source[i] === "object" ? source[i] : {}
    var id = String(item.id || "")
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id) || ids[id]) continue
    var values = Array.isArray(item.representationIds) ? item.representationIds : []
    var representations = []
    for (var j = 0; j < values.length && representations.length < 2; j++) {
      var value = String(values[j] || "")
      if (["text", "element", "image"].indexOf(value) < 0 || representations.indexOf(value) >= 0) continue
      representations.push(value)
    }
    if (representations.length === 0) continue
    ids[id] = true
    result.push({ id: id, representationIds: representations })
  }
  return result
}

function normalizedContextAttachment(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var id = String(source.id || "")
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) return null
  var representations = []
  var rawRepresentations = Array.isArray(source.representations) ? source.representations : []
  for (var i = 0; i < rawRepresentations.length && representations.length < 3; i++) {
    var value = rawRepresentations[i] && typeof rawRepresentations[i] === "object" ? rawRepresentations[i] : {}
    var kind = String(value.kind || value.id || "")
    if (["text", "element", "image"].indexOf(kind) < 0) continue
    representations.push({
      id: kind,
      kind: kind,
      label: safeContextText(value.label, 40) || (kind === "image" ? "Screenshot" : kind === "element" ? "Element" : "Text"),
      preview: safeContextText(value.preview, 320),
      confidence: Math.max(0, Math.min(1, Number(value.confidence) || 0))
    })
  }
  if (representations.length === 0) return null
  var available = representations.map(function(value) { return value.id })
  var selected = []
  var rawSelected = Array.isArray(source.selectedRepresentationIds) ? source.selectedRepresentationIds : []
  for (var j = 0; j < rawSelected.length && selected.length < 2; j++) {
    var selectedId = String(rawSelected[j] || "")
    if (available.indexOf(selectedId) >= 0 && selected.indexOf(selectedId) < 0) selected.push(selectedId)
  }
  if (selected.length === 0) selected.push(available[0])
  var origin = source.origin && typeof source.origin === "object" ? source.origin : {}
  return {
    version: 1,
    id: id,
    title: safeContextText(source.title, 160) || "Context capture",
    origin: {
      appId: safeContextText(origin.appId, 160),
      windowTitle: safeContextText(origin.windowTitle, 240)
    },
    previewImage: normalizedImage(source.previewImage),
    representations: representations,
    selectedRepresentationIds: selected
  }
}

function normalizedBrowserCompanion(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var phase = ["ready", "installing", "removing", "failed"].indexOf(String(source.phase || "")) >= 0
    ? String(source.phase) : "ready"
  return {
    phase: phase,
    relayInstalled: source.relayInstalled === true,
    setupAvailable: source.setupAvailable === true,
    chromiumConnected: source.chromiumConnected === true,
    firefoxConnected: source.firefoxConnected === true,
    chromiumExtensionPath: safeContextText(source.chromiumExtensionPath, 4096),
    firefoxExtensionPath: safeContextText(source.firefoxExtensionPath, 4096),
    message: safeContextText(source.message, 240)
  }
}

function contextRepresentationOptions(attachment) {
  var source = attachment && attachment.representations && attachment.representations.length !== undefined
    ? attachment.representations : []
  var options = source.map(function(value) { return { value: value.id, label: value.label } })
  var available = source.map(function(value) { return value.id })
  if (available.indexOf("text") >= 0 && available.indexOf("image") >= 0)
    options.push({ value: "text+image", label: "Text + screenshot" })
  if (available.indexOf("element") >= 0 && available.indexOf("image") >= 0)
    options.push({ value: "element+image", label: "Element + screenshot" })
  return options
}

function contextRepresentationMode(attachment) {
  var values = attachment && attachment.selectedRepresentationIds
      && attachment.selectedRepresentationIds.length !== undefined
    ? attachment.selectedRepresentationIds : []
  return values.join("+")
}

function safeContextText(value, limit) {
  return String(value || "")
    .replace(/[\u0000-\u001f\u007f-\u009f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, limit)
}

function isShellAppId(value) {
  var appId = safeContextText(value, 160).toLowerCase()
  return appId.indexOf("quickshell") >= 0 || appId.indexOf("omarchy-shell") >= 0
}

function normalizedDesktopWindow(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var result = {}
  var appId = safeContextText(source.appId, 160)
  var title = safeContextText(source.title, 240)
  var monitor = safeContextText(source.monitor, 120)
  var workspace = Number(source.workspace)
  if (appId !== "") result.appId = appId
  if (title !== "") result.title = title
  if (Number.isFinite(workspace) && Math.floor(workspace) === workspace
      && workspace >= -100000 && workspace <= 100000) result.workspace = workspace
  if (monitor !== "") result.monitor = monitor
  return Object.keys(result).length > 0 ? result : null
}

function normalizedDesktopApp(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var appId = safeContextText(source.appId, 160)
  if (appId === "") return null
  var workspaces = []
  var sourceWorkspaces = Array.isArray(source.workspaces) ? source.workspaces : []
  for (var i = 0; i < sourceWorkspaces.length && workspaces.length < 12; i++) {
    var workspace = Number(sourceWorkspaces[i])
    if (!Number.isFinite(workspace) || Math.floor(workspace) !== workspace
        || workspace < -100000 || workspace > 100000 || workspaces.indexOf(workspace) >= 0) continue
    workspaces.push(workspace)
  }
  workspaces.sort(function(left, right) { return left - right })
  var windowCount = Math.floor(Number(source.windowCount))
  return {
    appId: appId,
    workspaces: workspaces,
    windowCount: Number.isFinite(windowCount) && windowCount > 0 && windowCount <= 64 ? windowCount : 1
  }
}

function normalizedDesktopMedia(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var result = {}
  var player = safeContextText(source.player, 160)
  var title = safeContextText(source.title, 240)
  var artist = safeContextText(source.artist, 200)
  var status = String(source.status || "").toLowerCase()
  if (player !== "") result.player = player
  if (title !== "") result.title = title
  if (artist !== "") result.artist = artist
  if (["playing", "paused", "stopped"].indexOf(status) >= 0) result.status = status
  return Object.keys(result).length > 0 ? result : null
}

function normalizedDesktopContext(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var activeWindow = normalizedDesktopWindow(source.activeWindow)
  if (activeWindow !== null && activeWindow.appId && isShellAppId(activeWindow.appId)) activeWindow = null
  var appMap = {}
  var workspaceMap = {}
  var sourceWindows = Array.isArray(source.windows) ? source.windows : []
  for (var i = 0; i < sourceWindows.length; i++) {
    var window = normalizedDesktopWindow(sourceWindows[i])
    if (window === null) continue
    if (window.appId && isShellAppId(window.appId)) continue
    if (window.workspace !== undefined) workspaceMap[String(window.workspace)] = window.workspace
    if (!window.appId) continue
    var appKey = String(window.appId).toLowerCase()
    if (!appMap[appKey]) appMap[appKey] = { appId: window.appId, workspaces: [], windowCount: 0 }
    appMap[appKey].windowCount += 1
    if (window.workspace !== undefined && appMap[appKey].workspaces.indexOf(window.workspace) < 0)
      appMap[appKey].workspaces.push(window.workspace)
  }
  var sourceApps = Array.isArray(source.apps) ? source.apps : []
  for (var a = 0; a < sourceApps.length; a++) {
    var app = normalizedDesktopApp(sourceApps[a])
    if (app === null) continue
    if (isShellAppId(app.appId)) continue
    var key = app.appId.toLowerCase()
    if (!appMap[key]) appMap[key] = app
    for (var aw = 0; aw < app.workspaces.length; aw++) workspaceMap[String(app.workspaces[aw])] = app.workspaces[aw]
  }
  var sourceWorkspaceIds = Array.isArray(source.workspaces) ? source.workspaces : []
  for (var sw = 0; sw < sourceWorkspaceIds.length; sw++) {
    var workspaceId = Number(sourceWorkspaceIds[sw])
    if (Number.isFinite(workspaceId) && Math.floor(workspaceId) === workspaceId
        && workspaceId >= -100000 && workspaceId <= 100000) workspaceMap[String(workspaceId)] = workspaceId
  }
  var activeWorkspace = Number(source.activeWorkspace)
  if (!Number.isFinite(activeWorkspace) || Math.floor(activeWorkspace) !== activeWorkspace
      || activeWorkspace < -100000 || activeWorkspace > 100000) activeWorkspace = undefined
  else workspaceMap[String(activeWorkspace)] = activeWorkspace
  var focusedMonitor = safeContextText(source.focusedMonitor, 120)
  var apps = []
  var appKeys = Object.keys(appMap).sort()
  for (var k = 0; k < appKeys.length && apps.length < 12; k++) apps.push(normalizedDesktopApp(appMap[appKeys[k]]))
  var workspaces = []
  var workspaceKeys = Object.keys(workspaceMap)
  for (var w = 0; w < workspaceKeys.length; w++) workspaces.push(workspaceMap[workspaceKeys[w]])
  workspaces.sort(function(left, right) { return left - right })
  workspaces = workspaces.slice(0, 12)
  var media = []
  var sourceMedia = Array.isArray(source.media) ? source.media : []
  for (var j = 0; j < sourceMedia.length && media.length < 4; j++) {
    var player = normalizedDesktopMedia(sourceMedia[j])
    if (player !== null) media.push(player)
  }
  if (activeWindow === null && activeWorkspace === undefined && focusedMonitor === ""
      && apps.length === 0 && workspaces.length === 0 && media.length === 0) return null
  var result = { version: 1, apps: apps, workspaces: workspaces, media: media }
  if (activeWindow !== null) result.activeWindow = activeWindow
  if (activeWorkspace !== undefined) result.activeWorkspace = activeWorkspace
  if (focusedMonitor !== "") result.focusedMonitor = focusedMonitor
  return result
}

function desktopContextWithLatchedActive(raw, latchedActiveWindow) {
  var context = normalizedDesktopContext(raw)
  var latched = normalizedDesktopWindow(latchedActiveWindow)
  if (context === null) {
    if (latched === null) return null
    context = { version: 1, apps: [], workspaces: [], media: [] }
  }
  if (!context.activeWindow && latched !== null) context.activeWindow = latched
  return normalizedDesktopContext(context)
}

function hasFeature(features, feature) {
  var values = Array.isArray(features) ? features : []
  return values.indexOf(String(feature || "")) >= 0
}

function normalizedCapabilities(raw) {
  var source = Array.isArray(raw) ? raw : []
  var validIds = ["email", "calendar", "files", "projects", "messages", "meetings"]
  var validStates = ["ready", "needs_configuration", "missing_connector", "needs_setup", "degraded", "disabled"]
  var validRisks = ["inspect", "prepare", "local_action", "external_write", "destructive", "setup"]
  var result = []
  var seen = {}
  for (var i = 0; i < source.length && result.length < validIds.length; i++) {
    var item = source[i] && typeof source[i] === "object" ? source[i] : {}
    var id = String(item.id || "")
    if (validIds.indexOf(id) < 0 || seen[id]) continue
    var state = String(item.state || "degraded")
    if (validStates.indexOf(state) < 0) state = "degraded"
    var rawOperations = Array.isArray(item.operations) ? item.operations : []
    var operations = []
    for (var j = 0; j < rawOperations.length && operations.length < 16; j++) {
      var operation = rawOperations[j] && typeof rawOperations[j] === "object" ? rawOperations[j] : {}
      var risk = String(operation.risk || "inspect")
      if (validRisks.indexOf(risk) < 0) risk = "inspect"
      var operationId = safeContextText(operation.id, 80)
      if (operationId === "") continue
      operations.push({ id: operationId,
        label: safeContextText(operation.label, 120) || operationId,
        risk: risk,
        available: operation.available === true })
    }
    var configuration = item.configuration && typeof item.configuration === "object" ? item.configuration : {}
    seen[id] = true
    result.push({
      id: id,
      label: safeContextText(item.label, 80) || id,
      description: safeContextText(item.description, 240),
      connector: safeContextText(item.connector, 80),
      state: state,
      status: safeContextText(item.status, 240),
      enabled: item.enabled !== false,
      operations: operations,
      filesRoot: safeContextText(configuration.filesRoot, 4096),
      setupHint: safeContextText(item.setupHint, 300)
    })
  }
  return result
}

function capabilityFilesRoot(capabilities) {
  var rows = Array.isArray(capabilities) ? capabilities : []
  for (var i = 0; i < rows.length; i++)
    if (String(rows[i] && rows[i].id || "") === "files") return String(rows[i].filesRoot || "")
  return ""
}

function capabilityOperationsLabel(capability) {
  var operations = capability && Array.isArray(capability.operations) ? capability.operations : []
  var labels = []
  for (var i = 0; i < operations.length; i++) labels.push(String(operations[i].label || ""))
  return labels.filter(function(value) { return value !== "" }).join("  ·  ")
}

function parseLine(line) {
  try {
    var value = JSON.parse(String(line || ""))
    return value && typeof value === "object" && !Array.isArray(value) ? value : null
  } catch (error) {
    return null
  }
}

function isCompatibleEvent(event) {
  return event && Number(event.protocolVersion) === protocolVersion
}

function normalizedState(value, fallback) {
  var state = String(value || "")
  return validStates.indexOf(state) >= 0 ? state : (fallback || "idle")
}

function normalizedError(raw, fallbackMessage) {
  var value = raw && typeof raw === "object" ? raw : {}
  var unavailable = value.unavailable === true
  var message = String(value.message || fallbackMessage
    || (unavailable ? "OmaPilot is unavailable." : "OmaPilot could not complete that request."))
  return {
    title: unavailable ? "OmaPilot unavailable" : "Request failed",
    message: message.slice(0, 2000),
    code: String(value.code || (unavailable ? "unavailable" : "unknown_error")).slice(0, 120),
    retryable: value.retryable === true,
    unavailable: unavailable
  }
}

function errorDiagnosticText(raw) {
  var error = normalizedError(raw)
  return error.title + "\n" + error.message + "\nCode: " + error.code
    + "\nRetryable: " + (error.retryable ? "yes" : "no")
}

// User-registered OpenAI-compatible endpoints. QML never constructs the
// models.json entry itself; it only renders what the broker reports and sends
// back opaque, already-validated field values.
function normalizedVoxtypeOsd(event) {
  var source = event && typeof event === "object" ? event : {}
  return {
    available: source.available === true,
    enabled: source.enabled !== false,
    message: String(source.message || "")
  }
}

function normalizedCustomProviders(input) {
  var source = Array.isArray(input) ? input : []
  var result = []
  for (var i = 0; i < source.length && i < 32; i++) {
    var entry = source[i]
    if (!entry || typeof entry !== "object") continue
    var id = String(entry.id || "")
    if (id === "") continue
    var models = Array.isArray(entry.models) ? entry.models : []
    var normalizedModels = []
    for (var m = 0; m < models.length && m < 200; m++) {
      var rawModel = models[m]
      var modelId = String(rawModel && typeof rawModel === "object" ? rawModel.id : rawModel || "").trim()
      if (modelId === "") continue
      var modelName = String(rawModel && typeof rawModel === "object" ? rawModel.name || modelId : modelId).trim()
      var contextWindow = Number(rawModel && typeof rawModel === "object" ? rawModel.contextWindow : 0)
      normalizedModels.push({
        id: modelId,
        name: modelName || modelId,
        contextWindow: isFinite(contextWindow) && contextWindow > 0 ? Math.floor(contextWindow) : 128000
      })
    }
    result.push({
      id: id,
      name: String(entry.name || id),
      baseUrl: String(entry.baseUrl || ""),
      api: String(entry.api || ""),
      apiLabel: String(entry.api || "") === "openai-responses" ? "/responses" : "/chat/completions",
      models: normalizedModels,
      requiresAuth: entry.requiresAuth === true
    })
  }
  return result
}

// Model option ids are provider-prefixed ("<provider>::<model>"), so their
// presence is a truthful live-availability signal for keyed and no-auth servers.
function customProviderModelCount(modelOptions, providerId) {
  var options = Array.isArray(modelOptions) ? modelOptions : []
  var prefix = String(providerId || "") + "::"
  var count = 0
  for (var i = 0; i < options.length; i++) {
    var value = String(options[i] && options[i].value || options[i] || "")
    if (value.indexOf(prefix) === 0) count++
  }
  return count
}

function customProviderCommand(id, name, baseUrl, api, modelIds, apiKey) {
  var models = []
  var source = Array.isArray(modelIds) ? modelIds : []
  for (var i = 0; i < source.length && i < 200; i++) {
    var entry = source[i]
    var value = String(entry && typeof entry === "object" ? entry.id : entry || "").trim()
    if (value === "") continue
    var model = { id: value }
    if (entry && typeof entry === "object") {
      var modelName = String(entry.name || "").trim()
      var contextWindow = Number(entry.contextWindow || 0)
      if (modelName !== "") model.name = modelName
      if (isFinite(contextWindow) && contextWindow > 0) model.contextWindow = Math.floor(contextWindow)
    }
    models.push(model)
  }
  var payload = {
    id: String(id || "").trim().toLowerCase(),
    name: String(name || "").trim(),
    baseUrl: String(baseUrl || "").trim(),
    api: api === "openai-completions" ? "openai-completions" : "openai-responses",
    models: models
  }
  // Omitted entirely when blank, so editing a server without retyping its key
  // leaves the stored credential untouched.
  var key = String(apiKey || "").trim()
  if (key !== "") payload.apiKey = key
  return command("custom_provider_add", payload)
}

function customProviderTestCommand(baseUrl, apiKey) {
  var payload = { baseUrl: String(baseUrl || "").trim() }
  var key = String(apiKey || "").trim()
  if (key !== "") payload.apiKey = key
  return command("custom_provider_test", payload)
}

function normalizedTtsProvider(value) {
  var provider = String(value || "").toLowerCase()
  return ["kokoro", "elevenlabs", "openai"].indexOf(provider) >= 0 ? provider : ""
}

function normalizedVoiceVisualizer(value) {
  var visualizer = String(value || "").toLowerCase()
  return ["segments", "spectrum", "dots", "line"]
    .indexOf(visualizer) >= 0 ? visualizer : ""
}

function voiceVisualizerOptions() {
  return [
    { value: "segments", label: "Segments" },
    { value: "spectrum", label: "Mirrored spectrum" },
    { value: "dots", label: "Dot field" },
    { value: "line", label: "Animated line" }
  ]
}

function normalizedThinkingVisualizer(value) {
  var visualizer = String(value || "").toLowerCase()
  return ["scanner", "bumper"].indexOf(visualizer) >= 0 ? visualizer : ""
}

function thinkingVisualizerOptions() {
  return [
    { value: "scanner", label: "Luminous scanner" },
    { value: "bumper", label: "Bumper sweep" }
  ]
}

function ttsProviderOptions() {
  return [
    { value: "elevenlabs", label: "ElevenLabs" },
    { value: "kokoro", label: "Kokoro (local)" },
    { value: "openai", label: "OpenAI" }
  ]
}

function elevenLabsDefaultVoiceId() {
  return "wyWA56cQNU2KqUW4eCsI"
}

function emptyVoiceStatus() {
  return {
    dictation: { available: false, message: "" },
    tts: [
      { id: "kokoro", name: "Kokoro", kind: "local", available: false, configured: false, message: "", models: [], voices: [] },
      { id: "elevenlabs", name: "ElevenLabs", kind: "cloud", available: false, configured: false, message: "",
        models: [], voices: [{ id: elevenLabsDefaultVoiceId(), name: "Clyde" }] },
      { id: "openai", name: "OpenAI", kind: "cloud", available: false, configured: false, message: "", models: [], voices: [] }
    ]
  }
}

function normalizedVoiceOption(raw, kind) {
  var source = raw && typeof raw === "object" ? raw : { id: raw }
  var id = String(source.id || "").trim()
  if (id === "" || id.length > 128) return null
  var name = String(source.name || id).trim().slice(0, 64) || id
  var result = { id: id, name: name, value: id, label: name }
  if (kind === "voice" && Array.isArray(source.models)) {
    var models = []
    for (var i = 0; i < source.models.length && models.length < 8; i++) {
      var model = String(source.models[i] || "").trim()
      if (model !== "") models.push(model)
    }
    if (models.length > 0) result.models = models
  }
  return result
}

function normalizedVoiceStatus(event) {
  var source = event && typeof event === "object" ? event : {}
  var fallback = emptyVoiceStatus()
  var dictation = source.dictation && typeof source.dictation === "object" ? source.dictation : {}
  var result = {
    dictation: {
      available: dictation.available === true,
      message: String(dictation.message || "")
    },
    tts: []
  }
  var rows = Array.isArray(source.tts) ? source.tts : []
  for (var i = 0; i < rows.length && result.tts.length < 8; i++) {
    var entry = rows[i]
    if (!entry || typeof entry !== "object") continue
    var id = normalizedTtsProvider(entry.id)
    if (id === "") continue
    var models = []
    var voices = []
    var rawModels = Array.isArray(entry.models) ? entry.models : []
    for (var m = 0; m < rawModels.length && models.length < 32; m++) {
      var model = normalizedVoiceOption(rawModels[m], "model")
      if (model) models.push(model)
    }
    var rawVoices = Array.isArray(entry.voices) ? entry.voices : []
    for (var v = 0; v < rawVoices.length && voices.length < 100; v++) {
      var voice = normalizedVoiceOption(rawVoices[v], "voice")
      if (voice) voices.push(voice)
    }
    result.tts.push({
      id: id,
      name: String(entry.name || id),
      kind: entry.kind === "local" ? "local" : "cloud",
      available: entry.available === true,
      configured: entry.configured === true,
      message: String(entry.message || ""),
      models: models,
      voices: voices
    })
  }
  if (result.tts.length === 0) result.tts = fallback.tts
  return result
}

function ttsProviderStatus(status, provider) {
  var id = normalizedTtsProvider(provider) || "elevenlabs"
  var rows = status && Array.isArray(status.tts) ? status.tts : []
  for (var i = 0; i < rows.length; i++)
    if (String(rows[i] && rows[i].id || "") === id) return rows[i]
  return { id: id, name: id, kind: id === "kokoro" ? "local" : "cloud", available: false, configured: false, message: "", models: [], voices: [] }
}

function ttsModelOptions(catalog) {
  var models = catalog && Array.isArray(catalog.models) ? catalog.models : []
  var options = []
  for (var i = 0; i < models.length; i++) {
    options.push({
      value: String(models[i].value || models[i].id || ""),
      label: String(models[i].label || models[i].name || models[i].id || "")
    })
  }
  return options.length > 0 ? options : [{ value: "", label: "No models yet" }]
}

function ttsVoiceOptions(catalog, model) {
  var voices = catalog && Array.isArray(catalog.voices) ? catalog.voices : []
  var selected = String(model || "")
  var options = []
  for (var i = 0; i < voices.length; i++) {
    var voice = voices[i]
    var models = Array.isArray(voice.models) ? voice.models : []
    if (selected !== "" && models.length > 0 && models.indexOf(selected) < 0) continue
    options.push({
      value: String(voice.value || voice.id || ""),
      label: String(voice.label || voice.name || voice.id || "")
    })
  }
  return options.length > 0 ? options : [{ value: "", label: "No voices yet" }]
}

function ttsDefaultModel(catalog) {
  var options = ttsModelOptions(catalog)
  return options[0] && options[0].value ? options[0].value : ""
}

function ttsDefaultVoice(catalog, model) {
  var options = ttsVoiceOptions(catalog, model)
  if (catalog && catalog.id === "elevenlabs") {
    var preferred = elevenLabsDefaultVoiceId()
    for (var i = 0; i < options.length; i++)
      if (options[i].value === preferred) return preferred
    return preferred
  }
  return options[0] && options[0].value ? options[0].value : ""
}

function ttsModelAvailable(catalog, model) {
  var selected = String(model || "")
  if (selected === "") return false
  var options = ttsModelOptions(catalog)
  for (var i = 0; i < options.length; i++)
    if (options[i].value === selected) return true
  return false
}

function ttsVoiceAvailable(catalog, model, voice) {
  var selected = String(voice || "")
  if (selected === "") return false
  var options = ttsVoiceOptions(catalog, model)
  for (var i = 0; i < options.length; i++)
    if (options[i].value === selected) return true
  return false
}

function ttsKeySetCommand(provider, apiKey) {
  return command("tts_key_set", {
    provider: normalizedTtsProvider(provider) || "openai",
    apiKey: String(apiKey || "").trim()
  })
}

function ttsKeyClearCommand(provider) {
  return command("tts_key_clear", { provider: normalizedTtsProvider(provider) || "openai" })
}

function ttsKeyTestCommand(provider, apiKey) {
  return command("tts_key_test", {
    provider: normalizedTtsProvider(provider) || "openai",
    apiKey: String(apiKey || "").trim()
  })
}

function ttsSpeakCommand(id, provider, model, voice, text) {
  var payload = {
    id: String(id || ""),
    provider: normalizedTtsProvider(provider) || "elevenlabs",
    text: String(text || "").slice(0, 8000)
  }
  var selectedModel = String(model || "").trim()
  var selectedVoice = String(voice || "").trim()
  if (selectedModel !== "") payload.model = selectedModel
  if (selectedVoice !== "") payload.voice = selectedVoice
  return command("tts_speak", payload)
}

function ttsStopCommand() {
  return command("tts_stop")
}

function normalizedTtsLevel(event) {
  if (!event || String(event.type || "") !== "tts_level") return null
  var level = Number(event.level)
  if (!Number.isFinite(level)) return null
  return Math.max(0, Math.min(1, level))
}

function normalizedDictationLevel(event) {
  if (!event || String(event.type || "") !== "dictation_level") return null
  var level = Number(event.level)
  if (!Number.isFinite(level)) return null
  return {
    metered: event.metered === true,
    level: Math.max(0, Math.min(1, level))
  }
}

function normalizedProvider(value) {
  var provider = String(value || "").toLowerCase()
  return ["builtin", "codex", "opencode"].indexOf(provider) >= 0 ? provider : ""
}

function normalizedWebHandoffProvider(value) {
  var provider = String(value || "").toLowerCase()
  return ["duckduckgo", "google", "chatgpt", "claude", "grok"].indexOf(provider) >= 0 ? provider : ""
}

function webHandoffProviderOptions() {
  return ["duckduckgo", "google", "chatgpt", "claude", "grok"].map(function(value) {
    return { value: value, label: webHandoffProviderLabel(value) }
  })
}

function webHandoffProviderLabel(value) {
  var provider = normalizedWebHandoffProvider(value)
  if (provider === "duckduckgo") return "DuckDuckGo"
  if (provider === "google") return "Google"
  if (provider === "chatgpt") return "ChatGPT Search"
  if (provider === "claude") return "Claude"
  if (provider === "grok") return "Grok"
  return String(value || "")
}

function harnessOptions() {
  return ["builtin", "codex", "opencode"].map(function(value) {
    return { value: value, label: providerLabel(value) }
  })
}

function providerLabel(value) {
  var provider = normalizedProvider(value)
  if (provider === "builtin") return "Built-in (OmaPilot)"
  if (provider === "codex") return "Codex"
  if (provider === "opencode") return "OpenCode"
  return String(value || "")
}

function providerShortLabel(value) {
  var provider = normalizedProvider(value)
  if (provider === "builtin") return "OmaPilot"
  if (provider === "codex") return "Codex"
  if (provider === "opencode") return "OpenCode"
  return providerLabel(value)
}

function normalizeProviders(input) {
  var source = Array.isArray(input) ? input : []
  var result = []
  for (var i = 0; i < source.length; i++) {
    var raw = source[i]
    var id = normalizedProvider(raw && typeof raw === "object" ? raw.id : raw)
    if (!id || (raw && typeof raw === "object" && raw.ready === false)) continue
    var models = raw && typeof raw === "object" && Array.isArray(raw.models) ? raw.models : []
    var normalizedModels = []
    for (var j = 0; j < models.length; j++) {
      var model = models[j]
      var modelId = String(model && typeof model === "object" ? model.id || model.value || "" : model)
      if (!modelId) continue
      normalizedModels.push({
        value: modelId,
        label: String(model && typeof model === "object" ? model.label || model.name || modelId : modelId)
      })
    }
    result.push({
      value: id,
      label: String(raw && typeof raw === "object" ? raw.label || raw.name || providerLabel(id) : providerLabel(id)),
      models: normalizedModels,
      defaultModel: String(raw && typeof raw === "object" ? raw.defaultModel || "" : ""),
      policy: normalizedProviderPolicy(raw && typeof raw === "object" ? raw.policy : null)
    })
  }
  return result
}

function exactHarnessProviders(input, harness) {
  var expected = normalizedProvider(harness)
  var rows = normalizeProviders(input)
  return expected && rows.length === 1 && rows[0].value === expected ? rows : []
}

function normalizedProviderPolicy(raw) {
  var value = raw && typeof raw === "object" ? raw : {}
  var tools = value.tools === "device-approval" ? "device-approval" : "blocked"
  var web = ["approved-command", "search", "blocked"].indexOf(value.web) >= 0
    ? String(value.web) : "blocked"
  return { tools: tools, web: web, hostReads: value.hostReads === true }
}

function providerPolicy(providers, provider) {
  var rows = Array.isArray(providers) ? providers : []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].value === provider) return rows[i].policy
  }
  return normalizedProviderPolicy(null)
}

function providerPolicyDescription(provider, rawPolicy) {
  var label = providerLabel(provider) || "This harness"
  var policy = normalizedProviderPolicy(rawPolicy)
  if (policy.tools !== "device-approval") return label + " tool policy is unavailable."
  var skillsClause = " It can load relevant installed skills automatically."
  if (policy.hostReads) {
    return policy.web === "approved-command"
      ? label + " uses device tools when useful. It may read user-readable files; network access and broader commands require Allow once." + skillsClause
      : label + " uses device tools when useful. It may read user-readable files; broader commands require Allow once." + skillsClause
  }
  return label + " can use safe local tools" + (policy.web === "search" ? " and web search" : "")
    + ". Host files and device changes require Allow once." + skillsClause
}

function modelOptions(providers, provider) {
  var rows = Array.isArray(providers) ? providers : []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].value === provider) return rows[i].models || []
  }
  return []
}

function normalizedPermission(raw, currentRequestId) {
  var value = raw && typeof raw === "object" ? raw : {}
  var id = String(value.id || "")
  var requestId = String(value.requestId || "")
  var kind = String(value.kind || "")
  if (!id || requestId !== String(currentRequestId || "") || kind !== "execute") return null
  return {
    id: id,
    requestId: requestId,
    title: String(value.title || "Tool request").slice(0, 120),
    kind: kind,
    authority: "device",
    detail: String(value.detail || "").slice(0, 3000),
    options: normalizedPermissionOptions(value.options)
  }
}

function normalizedPermissionOptions(raw) {
  var values = Array.isArray(raw) ? raw : []
  var supported = ["allow_once", "allow_session", "allow_always", "reject_once", "reject_always"]
  var result = []
  for (var i = 0; i < values.length; i++) {
    var decision = String(values[i] && values[i].decision || "")
    if (supported.indexOf(decision) < 0) continue
    var id = String(values[i] && values[i].id || "")
    if (!/^option-[0-9]{1,3}$/.test(id)) continue
    result.push({ id: id, decision: decision, label: String(values[i].label || "").slice(0, 48) })
  }
  return result
}

function isSafeExternalUrl(url) {
  var value = String(url || "").trim()
  return /^(https?:\/\/|mailto:)/i.test(value)
}

function isImageLink(url) {
  return String(url || "").indexOf("omapilot-image:") === 0
}

function imageUrl(url) {
  if (!isImageLink(url)) return ""
  try { return decodeURIComponent(String(url).slice("omapilot-image:".length)) }
  catch (error) { return "" }
}

function sanitizeMarkdown(markdown) {
  var value = String(markdown || "")
  var definitions = {}
  var imageReferences = {}
  var imageReferenceMatcher = /!\[[^\]]*\]\[([^\]]+)\]/g
  var imageReference
  while ((imageReference = imageReferenceMatcher.exec(value)) !== null)
    imageReferences[String(imageReference[1] || "").toLowerCase()] = true
  var definitionMatcher = /^\s*\[([^\]]+)\]:\s*(\S+)(?:\s+["'(][^\n]*["')])?\s*$/gmi
  var definition
  while ((definition = definitionMatcher.exec(value)) !== null)
    definitions[String(definition[1] || "").toLowerCase()] = String(definition[2] || "")
  // Qt Markdown may resolve images on its own. Replace image syntax with an
  // inert custom link so the broker can validate and fetch only after click.
  value = value.replace(/!\[([^\]]*)\]\(([^\s\)]+)(?:\s+["'][^"']*["'])?\)/g,
    function(_, alt, url) {
      var target = String(url || "")
      if (!/^https:\/\//i.test(target)) return "Image blocked: " + (alt || "unnamed image")
      return "[Image: " + (alt || "remote image") + " — click to load](omapilot-image:" + encodeURIComponent(target) + ")"
    })
  value = value.replace(/!\[([^\]]*)\]\[([^\]]+)\]/g,
    function(_, alt, id) {
      var target = definitions[String(id || "").toLowerCase()] || ""
      if (!/^https:\/\//i.test(target)) return "Image blocked: " + (alt || "unnamed image")
      return "[Image: " + (alt || "remote image") + " — click to load](omapilot-image:" + encodeURIComponent(target) + ")"
    })
  value = value.replace(definitionMatcher, function(line, id) {
    return imageReferences[String(id || "").toLowerCase()] ? "" : line
  })
  // Raw HTML images bypass Markdown's image syntax entirely; never let their
  // src reach Text.MarkdownText.
  value = value.replace(/<img\b[^>]*>/gi, "Image blocked: embedded HTML image")
  // Text.MarkdownText does not execute script, but stripping active/embed
  // HTML keeps the rendered subset explicit and deterministic.
  value = value.replace(/<\/?(?:script|iframe|object|embed|style|link|meta)[^>]*>/gi, "")
  // CommonMark has several image forms (inline, full/collapsed/shortcut
  // references, nested labels, and escaped label text). After converting the
  // forms we understand into broker-owned omapilot-image links, remove the
  // image opener itself from every remaining form. Encoding the exclamation
  // mark is deliberately structural: Markdown parses the entity as display
  // text only, so Text.MarkdownText never receives an image token or URL to
  // resolve on its own.
  value = value.replace(/!\[/g, "&#33;[")
  return value
}

function markdownBlocks(markdown) {
  var value = String(markdown || "")
  var result = []
  var matcher = /```([^\n`]*)\n([\s\S]*?)```/g
  var cursor = 0
  var match
  while ((match = matcher.exec(value)) !== null) {
    if (match.index > cursor)
      result.push({ kind: "markdown", text: sanitizeMarkdown(value.slice(cursor, match.index)) })
    result.push({ kind: "code", language: String(match[1] || "").trim(), text: String(match[2] || "").replace(/\n$/, "") })
    cursor = matcher.lastIndex
  }
  if (cursor < value.length)
    result.push({ kind: "markdown", text: sanitizeMarkdown(value.slice(cursor)) })
  if (result.length === 0) result.push({ kind: "markdown", text: sanitizeMarkdown(value) })
  return result
}

function normalizedImage(raw) {
  var value = raw && typeof raw === "object" ? raw : {}
  var state = String(value.state || (value.source || value.localUrl || value.url ? "ready" : "placeholder"))
  if (["placeholder", "loading", "ready", "error", "expired"].indexOf(state) < 0) state = "placeholder"
  return {
    id: String(value.id || ""),
    state: state,
    source: String(value.source || value.localUrl || ""),
    remoteUrl: String(value.remoteUrl || value.sourceUrl || value.url || ""),
    alt: String(value.alt || "AI response image"),
    host: String(value.host || ""),
    error: String(value.error || "")
  }
}

function mergeImageEvent(images, event, currentRequestId) {
  var source = Array.isArray(images) ? images : []
  var raw = event && event.image ? event.image : event
  var incoming = normalizedImage(raw)
  var eventId = String(event && event.id || "")
  var remoteKey = incoming.remoteUrl || (/^https:\/\//i.test(eventId) ? eventId : "")
  var result = []
  var replaced = false
  for (var i = 0; i < source.length; i++) {
    var existing = normalizedImage(source[i])
    if (!replaced && remoteKey && existing.remoteUrl === remoteKey) {
      result.push(incoming)
      replaced = true
    } else result.push(source[i])
  }
  if (!replaced && (eventId === "" || eventId === String(currentRequestId || "") || remoteKey))
    result.push(incoming)
  return result
}

function herdrOutcome(event) {
  var value = event || {}
  var state = String(value.state || "")
  if (state === "opening") return { state: "preparing", message: String(value.message || "Opening in Herdr…"), toast: false }
  if (state === "continued") return {
    state: "complete",
    message: value.mode === "native" ? "Continued native session in Herdr" : "Continued from transcript in Herdr",
    toast: true
  }
  if (state === "unavailable" || state === "failed")
    return { state: "error", message: String(value.message || "Could not continue in Herdr."), toast: false }
  return null
}

function normalizedHistory(input) {
  var source = Array.isArray(input) ? input : []
  var result = []
  for (var i = 0; i < source.length && result.length < 30; i++) {
    var row = source[i] || {}
    if (!row.id) continue
    result.push({
      id: String(row.id),
      title: String(row.title || row.question || "Untitled question"),
      question: String(row.question || ""),
      answer: String(row.answer || row.markdown || ""),
      provider: normalizedProvider(row.provider) || "builtin",
      model: String(row.model || ""),
      timestamp: String(row.createdAt || row.timestamp || ""),
      response: normalizedResponseOutcome(row.response),
      images: Array.isArray(row.images) ? row.images : [],
      resumable: row.resumable === true || (row.session && row.session.resumable === true)
    })
  }
  return result
}

function normalizedResponseOutcome(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var responseClass = String(source.class || "ANSWER")
  if (["ACTION", "ANSWER", "CONFIRM", "PLAN", "UNSURE"].indexOf(responseClass) < 0)
    responseClass = "ANSWER"
  var receipt = source.receipt && typeof source.receipt === "object" ? source.receipt : null
  var command = receipt ? safeContextText(receipt.command, 32000) : ""
  var exitCode = receipt ? Number(receipt.exitCode) : NaN
  var durationMs = receipt ? Math.round(Number(receipt.durationMs)) : NaN
  var validReceipt = command !== "" && exitCode === 0 && Number.isInteger(durationMs)
    && durationMs >= 0 && durationMs <= 180000
  if (responseClass === "ACTION" && !validReceipt) responseClass = "ANSWER"
  return {
    class: responseClass,
    receipt: responseClass === "ACTION" && validReceipt
      ? { command: command, exitCode: 0, durationMs: durationMs } : null
  }
}
