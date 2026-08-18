.pragma library

// UI-facing Quickchat protocol, version 1. The broker owns harness details,
// policy, persistence, URL opening, clipboard writes, and Herdr control. QML
// only sends typed commands and renders normalized events.

var protocolVersion = 2
var validStates = [
  "idle", "composing", "preparing", "dictating", "streaming",
  "complete", "canceled", "error", "unavailable", "history"
]

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
    if (["text", "secret", "select", "manual_code"].indexOf(kind) >= 0) {
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

function submitCommand(id, question, provider, model, desktopContext, dangerousAutoApprove, contextAttachments) {
  var payload = command("submit", {
    id: String(id || ""),
    question: String(question || ""),
    provider: normalizedProvider(provider) || "builtin"
  })
  var selectedModel = String(model || "").trim()
  if (selectedModel !== "") payload.model = selectedModel
  var context = normalizedDesktopContext(desktopContext)
  if (context !== null) payload.desktopContext = context
  var attachments = normalizedContextSelections(contextAttachments)
  if (attachments.length > 0) payload.contextAttachments = attachments
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
  if (player !== "") result.player = player
  if (title !== "") result.title = title
  if (artist !== "") result.artist = artist
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
  if (activeWindow === null && apps.length === 0 && workspaces.length === 0 && media.length === 0) return null
  var result = { version: 1, apps: apps, workspaces: workspaces, media: media }
  if (activeWindow !== null) result.activeWindow = activeWindow
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

function normalizedProvider(value) {
  var provider = String(value || "").toLowerCase()
  return ["builtin", "codex", "claude", "opencode"].indexOf(provider) >= 0 ? provider : ""
}

function harnessOptions() {
  return ["builtin", "codex", "claude", "opencode"].map(function(value) {
    return { value: value, label: providerLabel(value) }
  })
}

function providerLabel(value) {
  var provider = normalizedProvider(value)
  if (provider === "builtin") return "Built-in (OmaPilot)"
  if (provider === "codex") return "Codex"
  if (provider === "claude") return "Claude"
  if (provider === "opencode") return "OpenCode"
  return String(value || "")
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
  return String(url || "").indexOf("quickchat-image:") === 0
}

function imageUrl(url) {
  if (!isImageLink(url)) return ""
  try { return decodeURIComponent(String(url).slice("quickchat-image:".length)) }
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
      return "[Image: " + (alt || "remote image") + " — click to load](quickchat-image:" + encodeURIComponent(target) + ")"
    })
  value = value.replace(/!\[([^\]]*)\]\[([^\]]+)\]/g,
    function(_, alt, id) {
      var target = definitions[String(id || "").toLowerCase()] || ""
      if (!/^https:\/\//i.test(target)) return "Image blocked: " + (alt || "unnamed image")
      return "[Image: " + (alt || "remote image") + " — click to load](quickchat-image:" + encodeURIComponent(target) + ")"
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
  // forms we understand into broker-owned quickchat-image links, remove the
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
      images: Array.isArray(row.images) ? row.images : [],
      resumable: row.resumable === true || (row.session && row.session.resumable === true)
    })
  }
  return result
}
