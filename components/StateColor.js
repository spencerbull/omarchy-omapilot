.pragma library

/**
 * Resolve each phase directly from Omarchy's foundational theme roles.
 *
 * phase: dormant | listening | thinking | answering | error
 */
function forPhase(accent, thinking, finished, urgent, phase) {
  if (phase === "error") return urgent;
  if (phase === "thinking") return thinking;
  if (phase === "answering") return finished;
  return accent;
}
