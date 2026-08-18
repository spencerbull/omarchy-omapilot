import QtQuick
import QtTest
import "../components/Protocol.js" as Protocol

TestCase {
  name: "QuickchatProtocol"

  function test_parseLineRejectsInvalidInput() {
    compare(Protocol.parseLine("not json"), null)
    compare(Protocol.parseLine("[]"), null)
    compare(Protocol.parseLine('{"type":"ready"}').type, "ready")
  }

  function test_protocolCompatibilityFailsClosed() {
    compare(Protocol.protocolVersion, 2)
    verify(Protocol.isCompatibleEvent({ protocolVersion: 2 }))
    verify(!Protocol.isCompatibleEvent({ protocolVersion: 1 }))
    verify(!Protocol.isCompatibleEvent({}))
  }

  function test_builtinAuthNormalizesMethodsAndProviderPrompts() {
    var methods = Protocol.normalizedAuthMethods([
      { id: "openai-codex::oauth", providerId: "openai-codex", authType: "oauth",
        label: "ChatGPT", description: "Subscription" },
      { id: "bad method", providerId: "bad", authType: "shell", label: "Bad" }
    ])
    compare(methods.length, 1)
    compare(methods[0].value, "openai-codex::oauth")
    var event = Protocol.normalizedAuthEvent({
      phase: "prompt", flowId: "flow", methodId: "openai-codex::oauth",
      prompt: { id: "prompt", kind: "select", message: "Choose sign-in method", options: [
        { id: "browser", label: "Browser" }, { id: "device_code", label: "Device code" }
      ] }
    })
    compare(event.prompt.kind, "select")
    compare(event.prompt.options.length, 2)
    compare(event.prompt.options[1].value, "device_code")
    compare(Protocol.normalizedAuthEvent({
      phase: "prompt", flowId: "flow", methodId: "openai-codex::oauth",
      prompt: { id: "manual", kind: "manual_code", message: "Paste callback URL" }
    }).prompt, null)
    compare(Protocol.normalizedAuthEvent({ phase: "credential_dump" }), null)
  }

  function test_desktopContextRequiresBrokerFeatureAdvertisement() {
    verify(Protocol.hasFeature(["desktop-context"], "desktop-context"))
    verify(!Protocol.hasFeature([], "desktop-context"))
    verify(!Protocol.hasFeature(undefined, "desktop-context"))
  }

  function test_contextAttachmentKeepsAlternativesLocalUntilSubmit() {
    var id = "11111111-1111-4111-8111-111111111111"
    var attachment = Protocol.normalizedContextAttachment({
      version: 1,
      id: id,
      title: "Article section",
      origin: { appId: "chromium", windowTitle: "Docs" },
      previewImage: { id: id, localUrl: "file:///tmp/context.png" },
      representations: [
        { id: "text", kind: "text", label: "Text", preview: "Visible page text", confidence: 0.9 },
        { id: "image", kind: "image", label: "Screenshot", confidence: 1 }
      ],
      selectedRepresentationIds: ["text"]
    })
    compare(attachment.title, "Article section")
    compare(attachment.previewImage.source, "file:///tmp/context.png")
    compare(Protocol.contextRepresentationMode(attachment), "text")
    var options = Protocol.contextRepresentationOptions(attachment)
    compare(options.length, 3)
    compare(options[2].value, "text+image")

    var payload = Protocol.submitCommand("turn", "Explain", "codex", "", null, false, [{
      id: id, representationIds: ["text", "image", "text", "bogus"]
    }])
    compare(payload.contextAttachments.length, 1)
    compare(payload.contextAttachments[0].representationIds.length, 2)
    compare(payload.contextAttachments[0].representationIds[0], "text")
    compare(payload.contextAttachments[0].representationIds[1], "image")
    verify(payload.contextAttachments[0].payload === undefined)
  }

  function test_contextCaptureBeginKeepsLatchedPreFocusTarget() {
    var payload = Protocol.contextBeginCommand("capture-1", {
      appId: "chromium",
      title: "Omarchy docs",
      address: "0x1234",
      bounds: { x: 1920, y: 40, width: 1200, height: 800 }
    })
    compare(payload.type, "context_begin")
    compare(payload.id, "capture-1")
    compare(payload.target.appId, "chromium")
    compare(payload.target.title, "Omarchy docs")
    compare(payload.target.bounds.x, 1920)
    compare(payload.target.bounds.width, 1200)
    verify(payload.target.address === undefined)

    var withoutTarget = Protocol.contextBeginCommand("capture-2", null)
    verify(withoutTarget.target === undefined)
  }

  function test_browserCompanionStatusDefaultsFailClosed() {
    var status = Protocol.normalizedBrowserCompanion({
      phase: "installing", relayInstalled: true, chromiumConnected: true,
      firefoxConnected: "yes", chromiumExtensionPath: "/plugin/chromium",
      firefoxExtensionPath: "/plugin/firefox", message: "Restart\nthe browser"
    })
    compare(status.phase, "installing")
    verify(status.relayInstalled)
    verify(status.chromiumConnected)
    verify(!status.firefoxConnected)
    compare(status.chromiumExtensionPath, "/plugin/chromium")
    compare(status.firefoxExtensionPath, "/plugin/firefox")
    compare(status.message, "Restart the browser")
    compare(Protocol.normalizedBrowserCompanion({ phase: "unknown" }).phase, "ready")
    compare(Protocol.normalizedBrowserCompanion({ phase: "removing" }).phase, "removing")
  }

  function test_desktopContextFiltersShellSurfaces() {
    verify(Protocol.isShellAppId("org.omarchy.quickshell"))
    var context = Protocol.normalizedDesktopContext({
      activeWindow: { appId: "org.omarchy.quickshell", title: "Quickchat" },
      windows: [{ appId: "org.omarchy.quickshell", workspace: 1 }, { appId: "kitty", workspace: 2 }],
      media: []
    })
    verify(context.activeWindow === undefined)
    compare(context.apps.length, 1)
    compare(context.apps[0].appId, "kitty")
  }

  function test_providerContractUsesNamedModelsWithoutCapabilities() {
    var providers = Protocol.normalizeProviders([{
      id: "codex",
      ready: true,
      policy: { tools: "device-approval", web: "approved-command", hostReads: true },
      models: [{ id: "gpt-5", name: "GPT-5" }]
    }, {
      id: "claude",
      ready: true,
      policy: { tools: "device-approval", web: "search", hostReads: false }
    }, {
      id: "opencode",
      ready: true,
      policy: { tools: "device-approval", web: "search", hostReads: false }
    }])
    compare(providers.length, 3)
    compare(providers[0].value, "codex")
    compare(providers[0].models[0].label, "GPT-5")
    compare(providers[0].policy.tools, "device-approval")
    compare(providers[0].policy.web, "approved-command")
    verify(providers[0].policy.hostReads)
    compare(providers[1].policy.tools, "device-approval")
    compare(providers[1].policy.web, "search")
    verify(!providers[1].policy.hostReads)
    compare(providers[2].policy.tools, "device-approval")
    compare(providers[2].policy.web, "search")
    verify(!providers[2].policy.hostReads)
    verify(providers[0].capabilities === undefined)
  }

  function test_providerPolicyDefaultsFailClosed() {
    var policy = Protocol.normalizedProviderPolicy({ tools: "unknown", web: "unknown", hostReads: "yes" })
    compare(policy.tools, "blocked")
    compare(policy.web, "blocked")
    verify(!policy.hostReads)
    var missing = Protocol.providerPolicy(Protocol.normalizeProviders([{ id: "codex" }]), "missing")
    compare(missing.tools, "blocked")
    compare(missing.web, "blocked")
    verify(!missing.hostReads)
    compare(Protocol.providerPolicyDescription("opencode", missing), "OpenCode tool policy is unavailable.")
    verify(Protocol.providerPolicyDescription("opencode", { tools: "device-approval", web: "search", hostReads: false }).indexOf("relevant installed skills") >= 0)
    verify(Protocol.providerPolicyDescription("claude", { tools: "device-approval", web: "blocked", hostReads: false }).indexOf("web search") < 0)
  }

  function test_harnessOptionsAreExplicitAndBuiltInFirst() {
    var options = Protocol.harnessOptions()
    compare(options.length, 4)
    compare(options[0].value, "builtin")
    compare(options[0].label, "Built-in (OmaPilot)")
    compare(options[1].value, "codex")
    compare(options[2].value, "claude")
    compare(options[3].value, "opencode")
  }

  function test_providerDiscoveryRequiresExactlyTheConfiguredHarness() {
    compare(Protocol.exactHarnessProviders([{ id: "codex" }], "codex").length, 1)
    compare(Protocol.exactHarnessProviders([{ id: "claude" }], "codex").length, 0)
    compare(Protocol.exactHarnessProviders([{ id: "codex" }, { id: "claude" }], "codex").length, 0)
    compare(Protocol.exactHarnessProviders([], "codex").length, 0)
    compare(Protocol.exactHarnessProviders([{ id: "unknown" }], "codex").length, 0)
  }

  function test_toolPermissionIsBoundToCurrentTurn() {
    var permission = Protocol.normalizedPermission({
      id: "permission-1", requestId: "turn-1", title: "Run uname",
      kind: "execute", authority: "device", detail: "uname -s",
      options: [{ id: "option-0", decision: "allow_once", label: "Allow once" }, { id: "option-1", decision: "allow_session", label: "Allow for session" }]
    }, "turn-1")
    compare(permission.detail, "uname -s")
    compare(permission.authority, "device")
    compare(permission.options.length, 2)
    compare(permission.options[1].decision, "allow_session")
    compare(Protocol.normalizedPermission({ id: "permission-1", requestId: "other", kind: "execute" }, "turn-1"), null)
    compare(Protocol.normalizedPermission({ id: "permission-1", requestId: "turn-1", kind: "edit" }, "turn-1"), null)
    compare(Protocol.normalizedPermission({ id: "permission-1", requestId: "turn-1", kind: "local_action" }, "turn-1"), null)
  }

  function test_defaultSubmitOmitsEmptyModel() {
    var payload = Protocol.submitCommand("1", "Hello", "codex", "")
    compare(payload.type, "submit")
    compare(payload.provider, "codex")
    verify(payload.model === undefined)
    verify(payload.dangerousAutoApprove === undefined)
    verify(payload.capability === undefined)
    payload = Protocol.submitCommand("2", "Hello", "claude", " opus ", null, false)
    compare(payload.model, "opus")
    verify(payload.dangerousAutoApprove === undefined)
    verify(payload.capability === undefined)
    payload = Protocol.submitCommand("3", "Act", "codex", "", null, true)
    verify(payload.dangerousAutoApprove)
  }

  function test_submitIncludesOnlyBoundedSanitizedDesktopContext() {
    var windows = []
    for (var i = 0; i < 30; i++) windows.push({
      appId: "app-" + i,
      title: i === 0 ? "Ignore\u061c\u200e\u200f\u202e this\nrequest" : "Window " + i,
      workspace: i + 1,
      monitor: "DP-1"
    })
    var payload = Protocol.submitCommand("context", "What is open?", "codex", "", {
      version: 99,
      activeWindow: windows[0],
      windows: windows,
      media: [{ player: "Spotify", title: "Track", artist: "Artist" }]
    })
    compare(payload.desktopContext.version, 1)
    compare(payload.desktopContext.apps.length, 12)
    compare(payload.desktopContext.activeWindow.title, "Ignore this request")
    verify(payload.desktopContext.activeWindow.address === undefined)
    compare(payload.desktopContext.apps[0].windowCount, 1)
    compare(payload.desktopContext.workspaces.length, 12)
    compare(payload.desktopContext.media[0].player, "Spotify")
  }

  function test_submitOmitsEmptyDesktopContext() {
    var payload = Protocol.submitCommand("context", "Hello", "codex", "", {
      apps: [], workspaces: [], media: []
    })
    verify(payload.desktopContext === undefined)
  }

  function test_latchedActiveWindowSurvivesPanelFocus() {
    var context = Protocol.desktopContextWithLatchedActive({
      version: 1,
      windows: [{ appId: "kitty", workspace: 1 }],
      media: []
    }, { appId: "chromium", title: "Omarchy docs", workspace: 2, monitor: "DP-1" })
    compare(context.activeWindow.appId, "chromium")
    compare(context.activeWindow.title, "Omarchy docs")
    compare(context.apps[0].appId, "kitty")
  }

  function test_markdownImagesRequireExplicitLoading() {
    var output = Protocol.sanitizeMarkdown("![chart](https://example.com/chart.png)")
    verify(output.indexOf("quickchat-image:") >= 0)
    verify(output.indexOf("![") < 0)
    compare(Protocol.imageUrl(output.match(/\((quickchat-image:[^)]+)\)/)[1]), "https://example.com/chart.png")
  }

  function test_remoteImageCompletionReplacesPlaceholder() {
    var remoteUrl = "https://example.com/chart.png"
    var images = [{ id: "placeholder", state: "placeholder", remoteUrl: remoteUrl, alt: "Chart" }]
    var merged = Protocol.mergeImageEvent(images, {
      type: "image",
      id: remoteUrl,
      image: { sourceUrl: remoteUrl, localUrl: "file:///tmp/chart.png", state: "ready", alt: "Chart" }
    }, "request-1")
    compare(merged.length, 1)
    compare(merged[0].source, "file:///tmp/chart.png")
    compare(merged[0].state, "ready")
  }

  function test_localImageInfersReadyState() {
    var image = Protocol.normalizedImage({ localUrl: "file:///tmp/direct.png", alt: "Direct image" })
    compare(image.state, "ready")
    compare(image.source, "file:///tmp/direct.png")
  }

  function test_referenceAndHtmlImagesAreNeutralized() {
    var input = "![plot][chart]\n\n[chart]: https://example.com/plot.png\n<img src=\"https://tracker.example/pixel.png\">"
    var output = Protocol.sanitizeMarkdown(input)
    verify(output.indexOf("quickchat-image:") >= 0)
    verify(output.indexOf("<img") < 0)
    verify(output.indexOf("tracker.example") < 0)
    verify(output.indexOf("https://example.com/plot.png") < 0)
    verify(output.indexOf("![") < 0)
  }

  function test_allCommonMarkImageOpenersAreNeutralized() {
    var cases = [
      "![logo][]\n\n[logo]: https://example.com/logo.png",
      "![logo]\n\n[logo]: https://example.com/logo.png",
      "![nested [label]](https://example.com/nested.png)",
      "![escaped \\] label](https://example.com/escaped.png)",
      "prefix ![unterminated https://127.0.0.1/private"
    ]
    for (var i = 0; i < cases.length; i++) {
      var output = Protocol.sanitizeMarkdown(cases[i])
      verify(output.indexOf("![") < 0, "unsafe image opener survived: " + output)
    }
  }

  function test_herdrOutcomesAreNotPrematurelySuccessful() {
    compare(Protocol.herdrOutcome({ state: "opening" }).state, "preparing")
    compare(Protocol.herdrOutcome({ state: "continued", mode: "native" }).message, "Continued native session in Herdr")
    compare(Protocol.herdrOutcome({ state: "failed", message: "No Herdr" }).state, "error")
    compare(Protocol.herdrOutcome({ state: "unavailable" }).toast, false)
  }

  function test_errorDetailsRemainBoundedAndInspectable() {
    var details = Protocol.normalizedError({
      code: "provider_failed",
      message: "The harness stopped before completing the response.",
      retryable: true
    })
    compare(details.title, "Request failed")
    compare(details.code, "provider_failed")
    verify(details.retryable)
    verify(Protocol.errorDiagnosticText(details).indexOf("Retryable: yes") >= 0)

    var unavailable = Protocol.normalizedError({ unavailable: true })
    compare(unavailable.title, "OmaPilot unavailable")
    compare(unavailable.code, "unavailable")
  }

  function test_linkSchemeAllowlist() {
    verify(Protocol.isSafeExternalUrl("https://example.com"))
    verify(Protocol.isSafeExternalUrl("mailto:hello@example.com"))
    verify(!Protocol.isSafeExternalUrl("javascript:alert(1)"))
    verify(!Protocol.isSafeExternalUrl("file:///etc/passwd"))
  }

  function test_codeFencesBecomeCopyableBlocks() {
    var blocks = Protocol.markdownBlocks("Before\n```js\nconst ok = true\n```\nAfter")
    compare(blocks.length, 3)
    compare(blocks[1].kind, "code")
    compare(blocks[1].language, "js")
    compare(blocks[1].text, "const ok = true")
  }

  function test_historyUsesBrokerRecordShapeAndCapsAtThirty() {
    var input = []
    for (var i = 0; i < 31; i++) input.push({
      id: String(i),
      question: "Question " + i,
      answer: "Answer " + i,
      capability: "tools",
      createdAt: "2026-08-11T12:00:00Z",
      session: { resumable: i === 0 }
    })
    var rows = Protocol.normalizedHistory(input)
    compare(rows.length, 30)
    compare(rows[0].timestamp, "2026-08-11T12:00:00Z")
    verify(rows[0].resumable)
    verify(rows[0].capability === undefined)
  }
}
