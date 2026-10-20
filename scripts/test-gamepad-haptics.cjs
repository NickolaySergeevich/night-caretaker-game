"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createBridge } = require("../godot/common/gamepad_haptics.js");
function target() {
  const listeners = new Map();
  return { addEventListener(type, cb) { if (!listeners.has(type)) listeners.set(type, new Set()); listeners.get(type).add(cb); },
    removeEventListener(type, cb) { listeners.get(type)?.delete(cb); },
    emit(type, data = {}) { for (const cb of listeners.get(type) || []) cb(data); }, listeners };
}
function fixture(actuator = null) {
  let time = 1000;
  const pads = actuator ? [{ connected: true, vibrationActuator: actuator }] : [];
  const env = Object.assign(target(), { isSecureContext: true, navigator: { getGamepads: () => pads },
    document: Object.assign(target(), { hidden: false, hasFocus: () => true }), performance: { now: () => time } });
  const api = createBridge(env);
  return { api, env, pads, advance(ms = 300) { time += ms; }, status(i = 0) { return JSON.parse(api.statusJSON(i)); } };
}
const settle = () => new Promise(resolve => setImmediate(resolve));
test("missing API, no controller, insecure and permissions policy fail safely", () => {
  const f = fixture();
  assert.equal(f.api.play(0, 1, 1, 100), "no-controller");
  assert.equal(f.status().available, false);
  f.env.navigator = {};
  assert.equal(f.api.play(0, 1, 1, 100), "api-unavailable");
  f.env.isSecureContext = false;
  assert.equal(f.api.play(0, 1, 1, 100), "insecure-context");
  f.env.isSecureContext = true;
  f.env.navigator.getGamepads = () => { throw Object.assign(new Error(), { name: "SecurityError" }); };
  assert.equal(f.api.play(0, 1, 1, 100), "permissions-policy-blocked");
});
test("dual rumble clamps magnitude/duration, respects intensity and reports API not hardware", async () => {
  const calls = [];
  const f = fixture({ effects: ["dual-rumble"], playEffect(...args) { calls.push(args); return Promise.resolve("complete"); } });
  assert.equal(f.status().reason, "api-present-unverified-hardware");
  assert.equal(f.api.play(0, 8, -2, 9000), "requested");
  assert.deepEqual(calls[0], ["dual-rumble", { duration: 300, startDelay: 0, weakMagnitude: 0.55, strongMagnitude: 0 }]);
  await settle();
  assert.equal(f.status().lastResult, "api-complete");
  assert.equal(f.api.play(0, 1, 1, 20), "rate-limited");
  f.advance();
  assert.equal(f.api.play(0, 1, 1, 0), "invalid-duration");
  assert.equal(f.api.play(0, 1, 1, Infinity), "invalid-duration");
  assert.equal(f.api.play(0, NaN, NaN, 100), "zero-intensity");
});
test("explicit unsupported effects are not attempted", () => {
  let calls = 0;
  const f = fixture({ effects: ["trigger-rumble"], playEffect() { calls++; } });
  assert.equal(f.api.play(0, 1, 1, 100), "haptics-unavailable");
  assert.equal(calls, 0);
});
test("legacy effects-absent dual API and pulse fallback", async () => {
  let calls = 0;
  const f = fixture({ playEffect() { calls++; return Promise.resolve("preempted"); } });
  f.api.play(0, 1, 1, 100);
  await settle();
  assert.equal(calls, 1);
  assert.equal(f.status().lastResult, "preempted");
  const pulseCalls = [];
  f.pads[0] = { connected: true, hapticActuators: [{ pulse(...args) { pulseCalls.push(args); return Promise.resolve(true); } }] };
  f.api.reconnect(0);
  assert.equal(f.status().mode, "pulse");
  f.api.play(0, 0.4, 0.8, 120);
  await settle();
  assert.deepEqual(pulseCalls[0], [0.8 * 0.55, 120]);
  assert.equal(f.status().lastResult, "api-complete");
});
test("promise rejection is caught and unsupported haptics do not flood calls", async () => {
  let calls = 0;
  const f = fixture({ playEffect() { calls++; return Promise.reject(Object.assign(new Error(), { name: "NotSupportedError" })); } });
  f.api.play(0, 1, 1, 100);
  await settle();
  assert.equal(f.status().lastResult, "rejected:NotSupportedError");
  f.advance();
  assert.equal(f.api.play(0, 1, 1, 100), "haptics-rejected");
  assert.equal(calls, 1);
  f.pads[0] = { connected: true, vibrationActuator: { playEffect() { return Promise.resolve("complete"); } } };
  f.env.emit("gamepadconnected", { gamepad: { index: 0 } });
  assert.equal(f.api.play(0, 1, 1, 100), "requested");
  await settle();
  assert.equal(f.status().lastResult, "api-complete");
});
test("synchronous error is contained", () => {
  const f = fixture({ playEffect() { throw Object.assign(new Error(), { name: "NotSupportedError" }); } });
  assert.equal(f.api.play(0, 1, 1, 100), "rejected:NotSupportedError");
});
test("disable, zero intensity, hidden, blur and pagehide stop without fresh rumble", async () => {
  let plays = 0, resets = 0;
  const f = fixture({ playEffect() { plays++; return Promise.resolve("complete"); }, reset() { resets++; return Promise.resolve("complete"); } });
  f.api.configure(false, 1);
  assert.equal(f.api.play(0, 1, 1, 100), "disabled");
  f.api.configure(true, 0);
  assert.equal(f.api.play(0, 1, 1, 100), "disabled");
  f.api.configure(true, 0.5);
  for (const event of ["blur", "pagehide", "visibilitychange"]) {
    f.advance();
    f.env.document.hidden = false;
    f.api.play(0, 1, 1, 100);
    if (event === "visibilitychange") { f.env.document.hidden = true; f.env.document.emit(event); }
    else f.env.emit(event);
  }
  assert.equal(plays, 3);
  assert.equal(resets, 3);
  assert.equal(f.api.play(0, 1, 1, 100), "unfocused");
  await settle();
  assert.equal(f.status().lastResult, "stopped");
});
test("stopping before a late promise cannot resurrect requested state", async () => {
  let resolve;
  const f = fixture({ playEffect() { return new Promise(r => { resolve = r; }); }, reset() { return Promise.resolve("complete"); } });
  f.api.play(0, 1, 1, 100);
  f.api.stopAll();
  resolve("complete");
  await settle();
  assert.equal(f.status().lastResult, "stopped");
});
test("disconnect preserves other indices and reconnect clears old failure/status", async () => {
  const f = fixture({ playEffect() { return Promise.resolve("complete"); }, reset() { return Promise.reject(new Error()); } });
  f.pads[2] = f.pads[0];
  f.pads[0] = null;
  assert.equal(f.api.play(0, 1, 1, 100), "no-controller");
  assert.equal(f.api.play(2, 1, 1, 100), "requested");
  f.pads[2] = null;
  f.env.emit("gamepaddisconnected", { gamepad: { index: 2 } });
  await settle();
  assert.equal(f.status(2).lastResult, "not-tested");
  assert.equal(f.status(2).available, false);
});
test("dispose removes listeners and blocks effects", () => {
  const f = fixture({ playEffect() {} });
  f.api.dispose();
  assert.equal(f.api.play(0, 1, 1, 100), "disposed");
  for (const callbacks of [...f.env.listeners.values(), ...f.env.document.listeners.values()]) assert.equal(callbacks.size, 0);
});
test("bridge has no host integration, pointer/fullscreen, networking or phone-vibration calls", () => {
  const source = require("node:fs").readFileSync(require.resolve("../godot/common/gamepad_haptics.js"), "utf8");
  for (const forbidden of [/\bfetch\s*\(/, /XMLHttpRequest/, /requestFullscreen\s*\(/, /requestPointerLock\s*\(/, /navigator\.vibrate\s*\(/, /localStorage/, /\beval\s*\(/]) assert.equal(forbidden.test(source), false);
});
test("browser setup is idempotent across scene reload; stop does not dispose singleton", async () => {
  const vm = require("node:vm");
  const source = require("node:fs").readFileSync(require.resolve("../godot/common/gamepad_haptics.js"), "utf8");
  let plays = 0, resets = 0;
  const f = fixture({ playEffect() { plays++; return Promise.resolve("complete"); }, reset() { resets++; return Promise.resolve("complete"); } });
  f.api.dispose();
  const context = vm.createContext(f.env);
  vm.runInContext(source, context);
  const first = f.env.RinGamepadHaptics;
  first.play(0, 1, 1, 100);
  first.stopAll();
  const listenersBefore = [...f.env.listeners.values()].map(x => x.size);
  vm.runInContext(source, context);
  assert.equal(f.env.RinGamepadHaptics, first);
  assert.deepEqual([...f.env.listeners.values()].map(x => x.size), listenersBefore);
  f.advance();
  assert.equal(first.play(0, 1, 1, 100), "requested");
  await settle();
  assert.equal(plays, 2);
  assert.equal(resets, 1);
  assert.equal(JSON.parse(first.statusJSON(0)).lastResult, "api-complete");
});
