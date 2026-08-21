.pragma library

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function boundedPanelHeight(naturalContentHeight, minimumContentHeight,
                            comfortableCardHeight, availableCardHeight,
                            verticalContentInset) {
  var inset = Math.max(0, finiteNumber(verticalContentInset, 0))
  var minimum = Math.max(1, finiteNumber(minimumContentHeight, 1))
  var natural = Math.max(0, finiteNumber(naturalContentHeight, 0))
  var desired = Math.max(minimum, natural) + inset
  var comfortable = Math.max(inset + 1, finiteNumber(comfortableCardHeight, desired))
  var available = finiteNumber(availableCardHeight, 0)
  var cap = available > 0 ? Math.min(comfortable, available) : comfortable
  return Math.round(Math.min(desired, cap))
}

function responseViewportHeight(naturalHeight, minimumHeight, preferredMaximum) {
  var minimum = Math.max(1, finiteNumber(minimumHeight, 1))
  var maximum = Math.max(minimum, finiteNumber(preferredMaximum, minimum))
  return Math.round(Math.max(minimum, Math.min(finiteNumber(naturalHeight, 0), maximum)))
}

function isNearBottom(contentY, contentHeight, viewportHeight, threshold) {
  var maximumY = Math.max(0,
    finiteNumber(contentHeight, 0) - finiteNumber(viewportHeight, 0))
  var distance = maximumY - Math.max(0, finiteNumber(contentY, 0))
  return distance <= Math.max(0, finiteNumber(threshold, 0))
}

function permissionNotice(dangerousAutoApprove) {
  return dangerousAutoApprove === true
    ? "Device actions are auto-approved."
    : "Device changes require an exact approval."
}

function responsePhase(state, hasAnswer) {
  var value = String(state || "")
  var contentVisible = hasAnswer === true
  if (value === "preparing")
    return { label: contentVisible ? "WORKING" : "WAITING", tone: "accent", waiting: !contentVisible }
  if (value === "streaming")
    return { label: contentVisible ? "STREAMING" : "WAITING", tone: "accent", waiting: !contentVisible }
  if (value === "stopping")
    return { label: "STOPPING", tone: "muted", waiting: false }
  if (value === "complete")
    return { label: "ANSWER", tone: "accent", waiting: false }
  if (value === "canceled")
    return { label: "CANCELED", tone: "urgent", waiting: false }
  if (value === "error")
    return { label: "ERROR", tone: "urgent", waiting: false }
  if (value === "unavailable")
    return { label: "UNAVAILABLE", tone: "urgent", waiting: false }
  return { label: "", tone: "muted", waiting: false }
}

function escapeAction(viewMode, composerPopupOpen, settingsPopupOpen,
                      previewOpen, busy) {
  if (composerPopupOpen) return "close-composer-popup"
  if (settingsPopupOpen) return "close-settings-popup"
  if (previewOpen) return "close-preview"
  if (String(viewMode || "chat") !== "chat") return "show-chat"
  if (busy) return "cancel"
  return "close-panel"
}

function settingsTabs() {
  return [
    { id: "agent", label: "Agent" },
    { id: "servers", label: "Servers" },
    { id: "desktop", label: "Desktop" },
    { id: "actions", label: "Actions" }
  ]
}

function settingsTabIds() {
  return settingsTabs().map(function(tab) { return tab.id })
}

function normalizedSettingsTab(value) {
  var id = String(value || "")
  return settingsTabIds().indexOf(id) >= 0 ? id : "agent"
}

function adjacentSettingsTab(current, delta) {
  var ids = settingsTabIds()
  var index = ids.indexOf(normalizedSettingsTab(current))
  var next = index + finiteNumber(delta, 0)
  if (next < 0) next = 0
  if (next >= ids.length) next = ids.length - 1
  return ids[next]
}
