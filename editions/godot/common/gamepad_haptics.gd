extends RefCounted
## WEB only. A successful API promise is not physical-hardware verification.
const JS_PATH := "res://common/gamepad_haptics.js"
const PRESETS := {
 "interact": Vector3(0.18, 0.06, 45),
 "switch": Vector3(0.12, 0.03, 35),
 "knock": Vector3(0.28, 0.18, 80),
 "dig": Vector3(0.22, 0.12, 65),
 "break": Vector3(0.34, 0.24, 95),
 "blocked": Vector3(0.10, 0.04, 35),
 "land": Vector3(0.20, 0.32, 100),
 "hurt": Vector3(0.30, 0.50, 140),
 "test": Vector3(0.30, 0.25, 120),
}
var enabled := true
var intensity := 0.55
var _bridge: JavaScriptObject
var _cooldowns: Dictionary = {}

func setup(js_path: String = JS_PATH) -> void:
 if not OS.has_feature("web"): return
 var file := FileAccess.open(js_path, FileAccess.READ)
 if file == null: return
 JavaScriptBridge.eval(file.get_as_text(), true)
 _bridge = JavaScriptBridge.get_interface("RinGamepadHaptics")
 configure(enabled, intensity)

func configure(value: bool, strength: float) -> void:
 enabled = value
 intensity = clampf(strength, 0.0, 1.0) if is_finite(strength) else 0.0
 if _bridge != null: _bridge.configure(enabled, intensity)

func pulse(device: int, event: String) -> String:
 if not enabled or intensity <= 0.0: return "disabled"
 if not PRESETS.has(event): return "unknown-event"
 if _bridge == null: return "web-bridge-unavailable"
 var now := Time.get_ticks_msec()
 var key := "%d:%s" % [device, event]
 # Do not buzz every physics frame or use ambient/controller-discovery rumble.
 var cooldown := 250 if event in ["dig", "blocked"] else 90
 if now - int(_cooldowns.get(key, -10000)) < cooldown: return "rate-limited"
 _cooldowns[key] = now
 var preset: Vector3 = PRESETS[event]
 return str(_bridge.play(device, preset.x, preset.y, preset.z))

func status(device: int) -> Dictionary:
 if _bridge == null: return {"available": false, "reason": "web-bridge-unavailable", "lastResult": "not-tested"}
 var parsed: Variant = JSON.parse_string(str(_bridge.statusJSON(device)))
 return parsed if parsed is Dictionary else {"available": false, "reason": "invalid-status"}

func stop_all() -> void:
 if _bridge != null: _bridge.stopAll()

func reconnect(device: int) -> void:
 _cooldowns.clear()
 if _bridge != null: _bridge.reconnect(device)
