extends RefCounted
## Pure state machine. Godot-normalized button/axis numbers, not browser raw indices.
## Does not modify InputMap or synthesize keyboard/mouse events.

const VERSION := 1
const BUTTON_COUNT := 21
const AXIS_COUNT := 10
const COMMON := {
 "interact": {"button": JOY_BUTTON_A},
 "back": {"button": JOY_BUTTON_B},
 "torch": {"button": JOY_BUTTON_Y},
 "hud": {"button": JOY_BUTTON_LEFT_SHOULDER},
 "pause": {"button": JOY_BUTTON_START},
}
const PROFILES := {
 "caretaker": {"knock": {"button": JOY_BUTTON_X}},
 "office": {"notebook": {"button": JOY_BUTTON_X}, "inventory": {"button": JOY_BUTTON_RIGHT_SHOULDER}, "sprint": {"button": JOY_BUTTON_LEFT_STICK}},
 "deeper": {"jump": {"button": JOY_BUTTON_X}, "dig": {"axis": JOY_AXIS_TRIGGER_RIGHT, "sign": 1}, "lighter": {"button": JOY_BUTTON_RIGHT_SHOULDER}, "battery": {"button": JOY_BUTTON_DPAD_LEFT}, "upgrade": {"button": JOY_BUTTON_DPAD_UP}},
}
const BUTTON_LABELS := {
 JOY_BUTTON_A: "A / Cross (нижняя)", JOY_BUTTON_B: "B / Circle (правая)",
 JOY_BUTTON_X: "X / Square (левая)", JOY_BUTTON_Y: "Y / Triangle (верхняя)",
 JOY_BUTTON_LEFT_SHOULDER: "LB / L1", JOY_BUTTON_RIGHT_SHOULDER: "RB / R1",
 JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
 JOY_BUTTON_START: "Start / Options", JOY_BUTTON_BACK: "Back / Share",
 JOY_BUTTON_DPAD_UP: "Крестовина ↑", JOY_BUTTON_DPAD_DOWN: "Крестовина ↓",
 JOY_BUTTON_DPAD_LEFT: "Крестовина ←", JOY_BUTTON_DPAD_RIGHT: "Крестовина →",
}
var profile := "caretaker"
var bindings: Dictionary = {}
var move_axes := Vector2i(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
var look_axes := Vector2i(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
var move_deadzone := 0.20
var look_deadzone := 0.16
var look_exponent := 1.5
var look_speed := 2.4 # radians per second; independent of mouse sensitivity
var invert_y := false
var trigger_threshold := 0.55
var context := "menu"
var focused := true
var active_device := -1
var armed := false
var _held: Dictionary = {}
var _ui_held: Dictionary = {}
var _repeat_direction := ""
var _repeat_remaining := 0.0

func _init(game_profile: String = "caretaker") -> void:
 set_profile(game_profile)

func set_profile(game_profile: String) -> void:
 profile = game_profile if PROFILES.has(game_profile) else "caretaker"
 bindings = COMMON.duplicate(true)
 bindings.merge(PROFILES[profile].duplicate(true))
 suspend()

func suspend() -> void:
 armed = false
 _held.clear()
 _ui_held.clear()
 _repeat_direction = ""
 _repeat_remaining = 0.0

func set_device(device: int) -> void:
 if device != active_device:
  active_device = device
  suspend()

func set_context(value: String) -> void:
 var next := "gameplay" if value == "gameplay" else "menu"
 if context != next:
  context = next
  suspend() # A closing a menu cannot also interact, jump or confirm twice.

func set_focused(value: bool) -> void:
 if focused != value:
  focused = value
  suspend()

static func radial(raw: Vector2, deadzone: float, exponent: float = 1.0) -> Vector2:
 if not raw.is_finite():
  return Vector2.ZERO
 var magnitude := raw.length()
 var dz := clampf(deadzone, 0.0, 0.8)
 if magnitude <= dz + 0.000001:
  return Vector2.ZERO
 var scaled := clampf((magnitude - dz) / (1.0 - dz), 0.0, 1.0)
 return raw.normalized() * pow(scaled, clampf(exponent, 0.5, 3.0))

static func _value(values: Array, index: int) -> float:
 if index < 0 or index >= values.size():
  return 0.0
 var value := float(values[index])
 return value if is_finite(value) else 0.0

func _neutral(buttons: Array, axes: Array) -> bool:
 for value in buttons:
  if float(value) > 0.25:
   return false
 # Only configured axes and bindings participate. Unused raw axes can rest at -1.
 if Vector2(_value(axes, move_axes.x), _value(axes, move_axes.y)).length() > move_deadzone + 0.000001:
  return false
 if Vector2(_value(axes, look_axes.x), _value(axes, look_axes.y)).length() > look_deadzone + 0.000001:
  return false
 for binding in bindings.values():
  if binding.has("axis") and _value(axes, int(binding.axis)) * float(binding.get("sign", 1)) > 0.25:
   return false
 return true

func _binding_pressed(binding: Dictionary, buttons: Array, axes: Array, previously_held: bool = false) -> bool:
 if binding.has("button"):
  return _value(buttons, int(binding.button)) > 0.5
 var threshold := maxf(0.05, trigger_threshold - 0.10) if previously_held else trigger_threshold
 return _value(axes, int(binding.get("axis", -1))) * float(binding.get("sign", 1)) >= threshold

func sample(buttons: Array, axes: Array, delta: float) -> Dictionary:
 var frame := {"move": Vector2.ZERO, "look": Vector2.ZERO, "scroll": 0.0, "held": {}, "pressed": [], "released": [], "ui": []}
 if not focused or active_device < 0:
  return frame
 if not armed:
  if _neutral(buttons, axes):
   armed = true
  return frame
 var movement := radial(Vector2(_value(axes, move_axes.x), _value(axes, move_axes.y)), move_deadzone)
 var look := radial(Vector2(_value(axes, look_axes.x), _value(axes, look_axes.y)), look_deadzone, look_exponent)
 var dt := clampf(delta, 0.0, 0.1) if is_finite(delta) else 0.0
 if context == "gameplay":
  frame.move = movement
  frame.look = Vector2(look.x, -look.y if invert_y else look.y) * look_speed * dt
  for action in bindings:
   var pressed := _binding_pressed(bindings[action], buttons, axes, bool(_held.get(action, false)))
   frame.held[action] = pressed
   if pressed and not _held.get(action, false):
    frame.pressed.append(action)
   elif not pressed and _held.get(action, false):
    frame.released.append(action)
  _held = frame.held.duplicate()
  return frame
 # Menu layout is intentionally independent of gameplay rebinding.
 var ui := {
  "ui_accept": _value(buttons, JOY_BUTTON_A) > 0.5,
  "ui_cancel": _value(buttons, JOY_BUTTON_B) > 0.5,
  "pause": _value(buttons, JOY_BUTTON_START) > 0.5,
  "ui_focus_prev": _value(buttons, JOY_BUTTON_LEFT_SHOULDER) > 0.5,
  "ui_focus_next": _value(buttons, JOY_BUTTON_RIGHT_SHOULDER) > 0.5,
 }
 for action in ui:
  if ui[action] and not _ui_held.get(action, false):
   frame.ui.append(action)
 _ui_held = ui
 var direction := ""
 if _value(buttons, JOY_BUTTON_DPAD_UP) > 0.5: direction = "ui_up"
 elif _value(buttons, JOY_BUTTON_DPAD_DOWN) > 0.5: direction = "ui_down"
 elif _value(buttons, JOY_BUTTON_DPAD_LEFT) > 0.5: direction = "ui_left"
 elif _value(buttons, JOY_BUTTON_DPAD_RIGHT) > 0.5: direction = "ui_right"
 elif movement.length() >= 0.55:
  if absf(movement.x) > absf(movement.y): direction = "ui_right" if movement.x > 0 else "ui_left"
  else: direction = "ui_down" if movement.y > 0 else "ui_up"
 if direction != _repeat_direction:
  _repeat_direction = direction
  _repeat_remaining = 0.32
  if not direction.is_empty(): frame.ui.append(direction)
 elif not direction.is_empty():
  _repeat_remaining -= dt
  if _repeat_remaining <= 0.0:
   frame.ui.append(direction)
   _repeat_remaining = 0.11
 frame.scroll = look.y * 560.0 * dt # Text scroll is separate from focus navigation.
 return frame

func binding_label(action: String) -> String:
 var binding: Dictionary = bindings.get(action, {})
 if binding.has("button"):
  return BUTTON_LABELS.get(int(binding.button), "Кнопка %d" % (int(binding.button) + 1))
 if binding.has("axis"):
  if int(binding.axis) == JOY_AXIS_TRIGGER_RIGHT: return "RT / R2"
  if int(binding.axis) == JOY_AXIS_TRIGGER_LEFT: return "LT / L2"
  return "Ось %d %s" % [int(binding.axis), "+" if int(binding.get("sign", 1)) > 0 else "−"]
 return "Не назначено"

func rebind(action: String, binding: Dictionary) -> Dictionary:
 if not bindings.has(action): return {"ok": false, "reason": "unknown-action"}
 var canonical := binding.duplicate()
 if binding.size() == 1 and binding.has("button"):
  if not _integer_number(binding.button) or int(binding.button) < 0 or int(binding.button) >= BUTTON_COUNT:
   return {"ok": false, "reason": "invalid-button"}
  canonical.button = int(binding.button)
 elif binding.has("axis") and binding.has("sign") and binding.size() == 2:
  if not _integer_number(binding.axis) or not _integer_number(binding.sign) or int(binding.axis) < 0 or int(binding.axis) >= AXIS_COUNT or int(binding.sign) not in [-1, 1]:
   return {"ok": false, "reason": "invalid-axis"}
  if int(binding.axis) in [move_axes.x, move_axes.y, look_axes.x, look_axes.y]:
   return {"ok": false, "reason": "reserved-stick-axis"}
  canonical.axis = int(binding.axis)
  canonical.sign = int(binding.sign)
 else: return {"ok": false, "reason": "invalid-binding"}
 for other in bindings:
  if other != action and bindings[other] == canonical:
   return {"ok": false, "reason": "conflict", "action": other}
 bindings[action] = canonical
 suspend()
 return {"ok": true}

static func _integer_number(value: Variant) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func export_settings() -> Dictionary:
 return {"version": VERSION, "profile": profile, "bindings": bindings.duplicate(true), "move_deadzone": move_deadzone, "look_deadzone": look_deadzone, "look_speed": look_speed, "invert_y": invert_y}

func import_settings(settings: Dictionary) -> bool:
 if settings.get("version") != VERSION or settings.get("profile") != profile: return false
 # Transactional validation supports swaps and rejects corrupt/conflicting saves.
 var candidate = get_script().new(profile)
 var saved: Variant = settings.get("bindings", {})
 if not saved is Dictionary or saved.size() != bindings.size(): return false
 candidate.bindings = {}
 for action in bindings: candidate.bindings[action] = {"button": -1}
 for action in bindings:
  if not saved.get(action) is Dictionary or not candidate.rebind(action, saved[action]).ok: return false
 for key in ["move_deadzone", "look_deadzone", "look_speed"]:
  var value: Variant = settings.get(key)
  if not (value is int or value is float) or not is_finite(float(value)): return false
 if not settings.get("invert_y") is bool: return false
 bindings = candidate.bindings.duplicate(true)
 move_deadzone = clampf(float(settings.move_deadzone), 0.05, 0.40)
 look_deadzone = clampf(float(settings.look_deadzone), 0.05, 0.40)
 look_speed = clampf(float(settings.look_speed), 0.5, 5.0)
 invert_y = settings.invert_y
 suspend()
 return true

