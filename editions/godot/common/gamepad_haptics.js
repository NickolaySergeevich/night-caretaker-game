/* Isolated WEB bridge. No networking, storage, permissions, fullscreen or pointer lock. */
(function (root, factory) {
  "use strict";
  if (typeof module === "object" && module.exports) module.exports = { createBridge: factory };
  else if (!root.RinGamepadHaptics) root.RinGamepadHaptics = factory(root);
})(typeof globalThis !== "undefined" ? globalThis : this, function createBridge(env) {
  "use strict";
  const state = new Map();
  let enabled = true, intensity = 0.55, disposed = false;
  const subscriptions = [];
  const finite = (x, fallback = 0) => Number.isFinite(Number(x)) ? Number(x) : fallback;
  const unit = (x) => Math.min(1, Math.max(0, finite(x)));
  const now = () => env.performance && env.performance.now ? env.performance.now() : Date.now();
  function entry(index) {
    if (!state.has(index)) state.set(index, { lastResult: "not-tested", generation: 0, lastTime: -Infinity, failure: "", actuator: null });
    return state.get(index);
  }
  function padAt(index) {
    if (!Number.isInteger(index) || index < 0) return { reason: "no-controller" };
    if (env.isSecureContext === false) return { reason: "insecure-context" };
    if (!env.navigator || typeof env.navigator.getGamepads !== "function") return { reason: "api-unavailable" };
    try {
      const pads = env.navigator.getGamepads();
      const pad = pads && pads[index];
      return pad && pad.connected !== false ? { pad } : { reason: "no-controller" };
    } catch (error) {
      return { reason: error && error.name === "SecurityError" ? "permissions-policy-blocked" : "api-error" };
    }
  }
  function actuatorFor(pad) {
    const candidates = [pad.vibrationActuator, ...Array.from(pad.hapticActuators || [])].filter(Boolean);
    for (const actuator of candidates) {
      const hasEffects = actuator.effects != null;
      const effects = hasEffects ? Array.from(actuator.effects) : [];
      if (typeof actuator.playEffect === "function" && (!hasEffects || effects.includes("dual-rumble"))) {
        return { actuator, mode: "dual-rumble" };
      }
    }
    for (const actuator of candidates) {
      if (typeof actuator.pulse === "function") return { actuator, mode: "pulse" };
    }
    return { reason: "haptics-unavailable" };
  }
  function capability(index) {
    const found = padAt(index);
    if (!found.pad) return { available: false, reason: found.reason, mode: "none" };
    const actuator = actuatorFor(found.pad);
    if (!actuator.actuator) return { available: false, reason: actuator.reason, mode: "none" };
    const saved = entry(index);
    if (saved.failure) return { available: false, reason: saved.failure, mode: actuator.mode };
    return { available: true, reason: "api-present-unverified-hardware", mode: actuator.mode };
  }
  function activeDocument() {
    return !env.document || (!env.document.hidden && (typeof env.document.hasFocus !== "function" || env.document.hasFocus()));
  }
  function play(index, weak, strong, duration) {
    if (disposed) return "disposed";
    if (!enabled || intensity <= 0) return "disabled";
    if (!activeDocument()) return "unfocused";
    if (!Number.isFinite(Number(duration)) || Number(duration) <= 0) return "invalid-duration";
    const cap = capability(index);
    if (!cap.available) return cap.reason;
    const found = padAt(index);
    if (!found.pad) return found.reason;
    const foundActuator = actuatorFor(found.pad);
    const actuator = foundActuator.actuator;
    if (!actuator) return foundActuator.reason;
    const s = entry(index);
    const time = now();
    if (time - s.lastTime < 90) return "rate-limited";
    weak = unit(weak) * intensity;
    strong = unit(strong) * intensity;
    if (weak === 0 && strong === 0) return "zero-intensity";
    const milliseconds = Math.min(300, Math.max(1, finite(duration)));
    s.actuator = actuator;
    s.lastTime = time;
    s.lastResult = "requested";
    const generation = ++s.generation;
    const fail = (error) => {
      if (s.generation !== generation) return;
      const name = error && error.name ? String(error.name) : "Error";
      s.lastResult = "rejected:" + name;
      if (name === "NotSupportedError") s.failure = "haptics-rejected";
      if (name === "SecurityError") s.failure = "permissions-policy-blocked";
    };
    try {
      const result = foundActuator.mode === "dual-rumble"
        ? actuator.playEffect("dual-rumble", { duration: milliseconds, startDelay: 0, weakMagnitude: weak, strongMagnitude: strong })
        : actuator.pulse(Math.max(weak, strong), milliseconds);
      Promise.resolve(result).then((outcome) => {
        if (s.generation !== generation) return;
        s.lastResult = outcome === "complete" || outcome === true ? "api-complete"
          : outcome === "preempted" ? "preempted" : outcome === false ? "not-completed" : "unknown-result";
      }, fail);
    } catch (error) { fail(error); }
    return s.lastResult;
  }
  function stop(index) {
    const s = state.get(index);
    if (!s) return;
    ++s.generation; // A late play promise must not resurrect old status.
    s.lastResult = "stopped";
    const actuator = s.actuator;
    s.actuator = null;
    if (!actuator) return;
    try {
      let result;
      if (typeof actuator.reset === "function") result = actuator.reset();
      else if (typeof actuator.playEffect === "function") result = actuator.playEffect("dual-rumble", { duration: 1, startDelay: 0, weakMagnitude: 0, strongMagnitude: 0 });
      else if (typeof actuator.pulse === "function") result = actuator.pulse(0, 1);
      Promise.resolve(result).catch(() => {}); // Hardware/OS may already be disconnected.
    } catch (_) { /* Original effects are always bounded to <=300 ms. */ }
  }
  function stopAll() { for (const index of state.keys()) stop(index); }
  function reconnect(index) {
    stop(index);
    state.delete(index); // Reused index must not inherit a previous controller's failure.
  }
  function configure(nextEnabled, nextIntensity) {
    const changed = enabled !== Boolean(nextEnabled) || intensity !== unit(nextIntensity);
    enabled = Boolean(nextEnabled);
    intensity = unit(nextIntensity);
    if (changed) stopAll();
  }
  function statusJSON(index) {
    const s = entry(index);
    return JSON.stringify({ ...capability(index), enabled, intensity, lastResult: s.lastResult });
  }
  function listen(target, type, callback) {
    if (!target || typeof target.addEventListener !== "function") return;
    target.addEventListener(type, callback);
    subscriptions.push([target, type, callback]);
  }
  listen(env, "blur", stopAll);
  listen(env, "pagehide", stopAll);
  listen(env.document, "visibilitychange", () => { if (env.document.hidden) stopAll(); });
  listen(env, "gamepaddisconnected", (event) => reconnect(event.gamepad.index));
  listen(env, "gamepadconnected", (event) => reconnect(event.gamepad.index));
  function dispose() {
    stopAll();
    disposed = true;
    for (const [target, type, callback] of subscriptions) target.removeEventListener(type, callback);
    subscriptions.length = 0;
  }
  return { version: 1, configure, play, stop, stopAll, reconnect, statusJSON, dispose };
});

