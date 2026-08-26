import QtQuick
import QtTest
import "../components/Protocol.js" as Protocol

TestCase {
  name: "OmaPilotProtocol"

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

  function test_readyProviderUpdateClearsStaleUnavailableState() {
    compare(Protocol.providerReadyState("unavailable", 1), "composing")
    compare(Protocol.providerReadyState("preparing", 1), "composing")
    compare(Protocol.providerReadyState("complete", 1), "complete")
    compare(Protocol.providerReadyState("unavailable", 0), "unavailable")
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
    verify(Protocol.hasFeature(["desktop-context", "context-attachments", "voice"], "voice"))
    verify(!Protocol.hasFeature([], "desktop-context"))
    verify(!Protocol.hasFeature(undefined, "desktop-context"))
  }

  function test_capabilityPacksNormalizeFailClosed() {
    var capabilities = Protocol.normalizedCapabilities([
      { id: "email", label: "Email", connector: "HEY", state: "ready", status: "Connected", enabled: true,
        operations: [{ id: "search", label: "Search mail", risk: "inspect", available: true }] },
      { id: "unknown", label: "Unknown", state: "ready" },
      { id: "email", label: "Duplicate", state: "ready" }
    ])
    compare(capabilities.length, 1)
    compare(capabilities[0].id, "email")
    compare(capabilities[0].operations[0].risk, "inspect")
    compare(Protocol.capabilityOperationsLabel(capabilities[0]), "Search mail")
    compare(Protocol.capabilityFilesRoot([{ id: "files", filesRoot: "/home/test/Dropbox" }]), "/home/test/Dropbox")
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
      activeWindow: { appId: "org.omarchy.quickshell", title: "OmaPilot" },
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
      id: "opencode",
      ready: true,
      policy: { tools: "device-approval", web: "search", hostReads: false }
    }])
    compare(providers.length, 2)
    compare(providers[0].value, "codex")
    compare(providers[0].models[0].label, "GPT-5")
    compare(providers[0].policy.tools, "device-approval")
    compare(providers[0].policy.web, "approved-command")
    verify(providers[0].policy.hostReads)
    compare(providers[1].value, "opencode")
    compare(providers[1].policy.tools, "device-approval")
    compare(providers[1].policy.web, "search")
    verify(!providers[1].policy.hostReads)
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
    verify(Protocol.providerPolicyDescription("opencode", { tools: "device-approval", web: "blocked", hostReads: false }).indexOf("web search") < 0)
  }

  function test_harnessOptionsAreExplicitAndBuiltInFirst() {
    var options = Protocol.harnessOptions()
    compare(options.length, 3)
    compare(options[0].value, "builtin")
    compare(options[0].label, "Built-in (OmaPilot)")
    compare(options[1].value, "codex")
    compare(options[2].value, "opencode")
    // Claude is no longer a selectable harness.
    verify(Protocol.normalizedProvider("claude") === "")
    compare(Protocol.providerShortLabel("builtin"), "OmaPilot")
    compare(Protocol.providerShortLabel("codex"), "Codex")
    compare(Protocol.providerShortLabel("opencode"), "OpenCode")
  }

  function test_providerDiscoveryRequiresExactlyTheConfiguredHarness() {
    compare(Protocol.exactHarnessProviders([{ id: "codex" }], "codex").length, 1)
    compare(Protocol.exactHarnessProviders([{ id: "opencode" }], "codex").length, 0)
    compare(Protocol.exactHarnessProviders([{ id: "codex" }, { id: "opencode" }], "codex").length, 0)
    compare(Protocol.exactHarnessProviders([], "codex").length, 0)
    compare(Protocol.exactHarnessProviders([{ id: "unknown" }], "codex").length, 0)
  }

  function test_historyContinuationRequiresTheExactHistoricalHarness() {
    var codex = [{ value: "codex", label: "Codex", models: [] }]
    var opencode = [{ value: "opencode", label: "OpenCode", models: [] }]
    // The same retained requirement is initially satisfied, then blocks after
    // the user switches to a different available harness.
    var retained = "codex"
    verify(!Protocol.historyContinuationBlocked(retained, "codex", codex))
    verify(Protocol.historyContinuationBlocked(retained, "opencode", opencode))
    verify(Protocol.historyContinuationBlocked(retained, "codex", []))
    verify(!Protocol.historyContinuationBlocked("", "opencode", opencode))
  }

  function test_responseOutcomesFailClosedAndKeepVerifiedReceipts() {
    var action = Protocol.normalizedResponseOutcome({
      class: "ACTION",
      receipt: { command: "hyprctl dispatch workspace 2", exitCode: 0, durationMs: 121 }
    })
    compare(action.class, "ACTION")
    compare(action.receipt.command, "hyprctl dispatch workspace 2")
    compare(action.receipt.durationMs, 121)

    var invalid = Protocol.normalizedResponseOutcome({
      class: "ACTION",
      receipt: { command: "rm -rf /", exitCode: 1, durationMs: 121 }
    })
    compare(invalid.class, "ANSWER")
    compare(invalid.receipt, null)
    compare(Protocol.normalizedResponseOutcome({ class: "made_up" }).class, "ANSWER")

    var history = Protocol.normalizedHistory([{ id: "chat", question: "Q", answer: "A" }])
    compare(history[0].response.class, "ANSWER")
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
    payload = Protocol.submitCommand("2", "Hello", "opencode", " grok-4 ", null, false)
    compare(payload.model, "grok-4")
    verify(payload.dangerousAutoApprove === undefined)
    verify(payload.capability === undefined)
    payload = Protocol.submitCommand("3", "Act", "codex", "", null, true)
    verify(payload.dangerousAutoApprove)
  }

  function test_webHandoffProviderIsNormalizedAndSubmitted() {
    compare(Protocol.normalizedWebHandoffProvider("CLAUDE"), "claude")
    compare(Protocol.normalizedWebHandoffProvider("bing"), "")
    compare(Protocol.webHandoffProviderLabel("chatgpt"), "ChatGPT Search")
    compare(Protocol.webHandoffProviderOptions().length, 5)
    var payload = Protocol.submitCommand(
      "research", "Find current information", "builtin", "", null, false, [], "", "grok")
    compare(payload.webHandoffProvider, "grok")
    verify(Protocol.submitCommand(
      "research", "Find current information", "builtin", "", null, false, [], "", "bing")
      .webHandoffProvider === undefined)
  }

  function test_followUpSubmitCarriesOnlyAValidSavedChatId() {
    var saved = "11111111-1111-4111-8111-111111111111"
    compare(Protocol.submitCommand("turn", "Follow up", "builtin", "", null, false, [], saved).resumeChatId, saved)
    verify(Protocol.submitCommand("turn", "Follow up", "builtin", "", null, false, [], "not-a-chat").resumeChatId === undefined)
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
      activeWorkspace: 7,
      focusedMonitor: "DP-2",
      windows: windows,
      media: [{ player: "Spotify", title: "Track", artist: "Artist", status: "paused" }]
    })
    compare(payload.desktopContext.version, 1)
    compare(payload.desktopContext.apps.length, 12)
    compare(payload.desktopContext.activeWindow.title, "Ignore this request")
    verify(payload.desktopContext.activeWindow.address === undefined)
    compare(payload.desktopContext.apps[0].windowCount, 1)
    compare(payload.desktopContext.workspaces.length, 12)
    compare(payload.desktopContext.activeWorkspace, 7)
    compare(payload.desktopContext.focusedMonitor, "DP-2")
    compare(payload.desktopContext.media[0].player, "Spotify")
    compare(payload.desktopContext.media[0].status, "paused")
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
    verify(output.indexOf("omapilot-image:") >= 0)
    verify(output.indexOf("![") < 0)
    compare(Protocol.imageUrl(output.match(/\((omapilot-image:[^)]+)\)/)[1]), "https://example.com/chart.png")
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
    verify(output.indexOf("omapilot-image:") >= 0)
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

  function test_voiceCatalogNormalizesProvidersAndCloudKeys() {
    var status = Protocol.normalizedVoiceStatus({
      dictation: { available: true, message: "Voxtype is ready for dictation." },
      tts: [
        { id: "kokoro", kind: "local", available: true, configured: true, message: "ready",
          models: [{ id: "kokoro-82m", name: "Kokoro 82M" }],
          voices: [{ id: "af_heart", name: "Heart" }] },
        { id: "openai", kind: "cloud", available: true, configured: true,
          models: [{ id: "gpt-4o-mini-tts" }, { id: "tts-1" }],
          voices: [
            { id: "coral", name: "Coral", models: ["gpt-4o-mini-tts"] },
            { id: "alloy", name: "Alloy", models: ["gpt-4o-mini-tts", "tts-1"] }
          ] },
        { id: "bad", models: [{ id: "nope" }] }
      ]
    })
    compare(status.dictation.available, true)
    compare(status.tts.length, 2)
    compare(Protocol.normalizedTtsProvider("ElevenLabs"), "elevenlabs")
    compare(Protocol.ttsProviderOptions()[0].value, "elevenlabs")
    compare(Protocol.normalizedVoiceVisualizer("KITT"), "kitt")
    compare(Protocol.normalizedVoiceVisualizer("Bumper"), "bumper")
    compare(Protocol.normalizedVoiceVisualizer("segments"), "segments")
    compare(Protocol.normalizedVoiceVisualizer("SPECTRUM"), "spectrum")
    compare(Protocol.normalizedVoiceVisualizer("dots"), "dots")
    compare(Protocol.normalizedVoiceVisualizer("line"), "line")
    compare(Protocol.normalizedVoiceVisualizer("unknown"), "")
    compare(Protocol.voiceVisualizerOptions().length, 6)
    compare(Protocol.voiceVisualizerOptions()[0].value, "kitt")
    compare(Protocol.voiceVisualizerOptions()[0].label, "KITT voice box")
    compare(Protocol.voiceVisualizerOptions()[5].value, "line")
    var openai = Protocol.ttsProviderStatus(status, "openai")
    compare(Protocol.ttsDefaultModel(openai), "gpt-4o-mini-tts")
    compare(Protocol.ttsVoiceOptions(openai, "tts-1").length, 1)
    compare(Protocol.ttsVoiceOptions(openai, "tts-1")[0].value, "alloy")
    var save = Protocol.ttsKeySetCommand(" OpenAI ", " sk-test ")
    compare(save.type, "tts_key_set")
    compare(save.provider, "openai")
    compare(save.apiKey, "sk-test")
    compare(Protocol.ttsKeyClearCommand("elevenlabs").type, "tts_key_clear")
    compare(Protocol.ttsKeyTestCommand("openai", " sk-test ").apiKey, "sk-test")
    compare(Protocol.elevenLabsDefaultVoiceId(), "wyWA56cQNU2KqUW4eCsI")
    var elevenlabs = Protocol.ttsProviderStatus({
      tts: [{
        id: "elevenlabs",
        voices: [
          { id: "voice-one", name: "Rachel" },
          { id: "wyWA56cQNU2KqUW4eCsI", name: "Clyde" }
        ]
      }]
    }, "elevenlabs")
    compare(Protocol.ttsDefaultVoice(elevenlabs, "eleven_multilingual_v2"), "wyWA56cQNU2KqUW4eCsI")
    compare(Protocol.ttsDefaultVoice({ id: "elevenlabs", voices: [] }, ""), "wyWA56cQNU2KqUW4eCsI")
    compare(Protocol.emptyVoiceStatus().tts[1].voices[0].id, "wyWA56cQNU2KqUW4eCsI")
    var speak = Protocol.ttsSpeakCommand("speak-1", "elevenlabs", "eleven_multilingual_v2", "wyWA56cQNU2KqUW4eCsI", "Hello")
    compare(speak.type, "tts_speak")
    compare(speak.provider, "elevenlabs")
    compare(speak.voice, "wyWA56cQNU2KqUW4eCsI")
    compare(Protocol.ttsStopCommand().type, "tts_stop")
    compare(Protocol.normalizedTtsLevel({ type: "tts_level", level: 0.72 }), 0.72)
    compare(Protocol.normalizedTtsLevel({ type: "tts_level", level: 4 }), 1)
    compare(Protocol.normalizedTtsLevel({ type: "tts_level", level: -2 }), 0)
    compare(Protocol.normalizedTtsLevel({ type: "tts_level", level: "bad" }), null)
    compare(Protocol.normalizedDictationLevel({
      type: "dictation_level", level: 0.64, metered: true
    }).level, 0.64)
    verify(Protocol.normalizedDictationLevel({
      type: "dictation_level", level: 0.64, metered: true
    }).metered)
    compare(Protocol.normalizedDictationLevel({
      type: "dictation_level", level: 4, metered: true
    }).level, 1)
    compare(Protocol.normalizedDictationLevel({
      type: "dictation_level", level: "bad", metered: true
    }), null)
  }

  function test_customProviderProbeAndSaveKeepDiscoveredModelMetadata() {
    var blank = Protocol.customProviderTestCommand(" http://finn.example.ts.net:8888/v1 ", "")
    compare(blank.type, "custom_provider_test")
    compare(blank.baseUrl, "http://finn.example.ts.net:8888/v1")
    verify(blank.apiKey === undefined)

    var keyed = Protocol.customProviderTestCommand("https://models.example/v1", " secret ")
    compare(keyed.apiKey, "secret")
    var save = Protocol.customProviderCommand(" Finn ", "Qwen", keyed.baseUrl,
      "openai-responses", [{ id: "Qwen3.8-27B", name: "Qwen", contextWindow: 262144 }], "")
    compare(save.id, "finn")
    compare(save.models.length, 1)
    compare(save.models[0].id, "Qwen3.8-27B")
    compare(save.models[0].contextWindow, 262144)
    verify(save.apiKey === undefined)

    var listed = Protocol.normalizedCustomProviders([{
      id: "finn", name: "Finn", baseUrl: keyed.baseUrl, api: "openai-completions",
      models: [{ id: "Qwen3.8-27B", name: "Qwen", contextWindow: 262144 }], requiresAuth: true
    }])
    compare(listed.length, 1)
    compare(listed[0].models[0].name, "Qwen")
    compare(listed[0].models[0].contextWindow, 262144)
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
