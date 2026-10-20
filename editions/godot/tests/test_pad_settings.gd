extends SceneTree
const UI = preload("res://scripts/pad_settings.gd")
const Model = preload("res://common/gamepad_model.gd")
class HapticStub extends RefCounted:
 var enabled := true
 var intensity := 0.55
 var stops := 0
 var pulses: Array = []
 var capability := {"available": true, "reason": "api-present-unverified-hardware", "lastResult": "not-tested"}
 func stop_all() -> void: stops += 1
 func configure(value: bool, strength: float) -> void:
  enabled = value
  intensity = strength
 func pulse(device: int, event: String) -> String:
  pulses.append([device, event])
  capability.lastResult = "requested"
  return "requested"
 func status(_device: int) -> Dictionary: return capability
class PadStub extends Node:
 var model = Model.new("caretaker")
 var haptics = HapticStub.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool, title: String) -> void:
 checks += 1
 if not value:
  failures.append(title)
  printerr("FAIL: " + title)
func _initialize() -> void: call_deferred("run")
func frames(count := 3) -> void:
 for _i in range(count): await process_frame
func ui_action(action: String) -> void:
 var event := InputEventAction.new()
 event.action = action
 event.pressed = true
 root.push_input(event, true)
 event = event.duplicate()
 event.pressed = false
 root.push_input(event, true)
func run() -> void:
 root.size = Vector2i(1280, 720)
 var pad := PadStub.new()
 root.add_child(pad)
 pad.model.active_device = 7
 var events := {"saved": 0, "back": 0, "remap": []}
 var save := func() -> void: events.saved += 1
 var back := func() -> void: events.back += 1
 var remap := func(action: String) -> void: events.remap.append(action)
 var detached := UI.build(pad, Callable(), Callable(), Callable())
 check(detached is ScrollContainer, "detached build returns scroll")
 detached.free()
 await frames()
 var wrapper := VBoxContainer.new()
 wrapper.size = Vector2(1200, 650)
 root.add_child(wrapper)
 var screen: ScrollContainer = UI.build(pad, back, save, remap)
 wrapper.add_child(screen)
 await frames(5)
 check(screen.size.x <= 636.1 and screen.size.y <= 300.1, "bounded even in large VBox: " + str(screen.size))
 var controls: Array[Control] = []
 var sliders: Array[HSlider] = []
 for node in screen.find_children("*", "Control", true, false):
  if node.focus_mode == Control.FOCUS_ALL:
   controls.append(node)
  if node is HSlider: sliders.append(node)
 check(controls.size() == 15, "all 15 editable/action controls focusable")
 check(sliders.size() == 4, "four sliders")
 check(root.gui_get_focus_owner() == sliders[0], "initial focus is move deadzone")
 var expected_keys := ["move_deadzone", "look_deadzone", "look_speed"]
 var expected_values := [0.31, 0.29, 3.8]
 for i in 3:
  sliders[i].value = expected_values[i]
  check(is_equal_approx(float(pad.model.get(expected_keys[i])), expected_values[i]), "independent slider callback " + expected_keys[i])
 check(events.saved == 3, "one save per numeric change")
 for i in 2:
  check(is_equal_approx(sliders[i].min_value, 0.05) and is_equal_approx(sliders[i].max_value, 0.4), "deadzone bounds " + str(i))
 check(is_equal_approx(sliders[2].min_value, 0.5) and is_equal_approx(sliders[2].max_value, 5.0), "look speed bounds")
 var invert: CheckBox = screen.find_child("InvertY", true, false)
 invert.button_pressed = true
 check(pad.model.invert_y and events.saved == 4, "invert callback saves")
 var vibration: CheckBox = screen.find_child("Vibration", true, false)
 var previous_stops: int = pad.haptics.stops
 vibration.button_pressed = false
 check(not pad.haptics.enabled and pad.haptics.stops > previous_stops, "vibration off configures and stops")
 sliders[3].value = 0.0
 check(pad.haptics.intensity == 0.0, "zero vibration")
 check(UI._haptics_status(pad).contains("выключена"), "off has honest status")
 vibration.button_pressed = true
 check(UI._haptics_status(pad).contains("0%"), "zero has honest status")
 sliders[3].value = 55.0
 var test: Button = screen.find_child("TestVibration", true, false)
 test.pressed.emit()
 check(pad.haptics.pulses == [[7, "test"]], "test pulse uses active device")
 pad.haptics.capability.lastResult = "api-complete"
 check(UI._haptics_status(pad).contains("не подтверждает"), "API completion is not physical proof")
 pad.haptics.capability.lastResult = "rejected:Error"
 check(UI._haptics_status(pad).contains("отклонил"), "rejection is not success")
 pad.haptics.capability = {"available": false, "reason": "haptics-unavailable"}
 check(UI._haptics_status(pad).contains("недоступна"), "unsupported haptics truthful")
 pad.model.active_device = -1
 check(UI._haptics_status(pad).contains("не обнаружен"), "missing controller truthful")
 pad.model.active_device = 7
 for action in UI.ACTIONS:
  var button: Button = screen.find_child("Remap_" + action, true, false)
  check(button.text.contains(pad.model.binding_label(action)), "binding comes from model " + action)
  button.pressed.emit()
 check(events.remap == UI.ACTIONS, "six independent remap callbacks")
 check(events.back == 0, "remap did not call back")
 pad.model.rebind("torch", {"button": JOY_BUTTON_RIGHT_STICK})
 await create_timer(0.30).timeout
 check(screen.find_child("Remap_torch", true, false).text.contains("R3"), "live remap refresh")
 pad.model.move_axes = Vector2i(6, 7)
 pad.model.look_axes = Vector2i(8, 9)
 pad.model.look_exponent = 2.8
 pad.model.trigger_threshold = 0.8
 var reset: Button = screen.find_child("ResetPadSettings", true, false)
 var saved_before: int = events.saved
 reset.pressed.emit()
 check(events.saved == saved_before + 1, "reset saves exactly once")
 check(pad.model.active_device == 7, "reset preserves active device")
 check(pad.model.profile == "caretaker", "reset caretaker profile")
 check(pad.model.bindings.torch.button == JOY_BUTTON_Y, "reset binding")
 check(pad.model.move_axes == Vector2i(0, 1) and pad.model.look_axes == Vector2i(2, 3), "reset axes")
 check(is_equal_approx(pad.model.move_deadzone, 0.20) and is_equal_approx(pad.model.look_deadzone, 0.16), "reset deadzones")
 check(is_equal_approx(pad.model.look_exponent, 1.5) and is_equal_approx(pad.model.look_speed, 2.4) and is_equal_approx(pad.model.trigger_threshold, 0.55), "reset numeric defaults")
 check(not pad.model.invert_y and not invert.button_pressed, "reset inversion model and UI")
 check(pad.haptics.enabled and is_equal_approx(pad.haptics.intensity, 0.55) and vibration.button_pressed and sliders[3].value == 55, "reset haptics model and UI")
 for direction in [controls, controls.duplicate()]:
  if direction != controls: direction.reverse()
  for control in direction:
   control.grab_focus()
   await frames()
   var row: Control = control.get_parent() if control is HSlider else control
   var viewport_rect := screen.get_global_rect().grow(1.0)
   check(viewport_rect.encloses(row.get_global_rect()), "focus row visible " + str(control.name) + " " + str(row.get_global_rect()))
 # Explicit reverse traversal rather than relying on object/list comparison.
 var reversed := controls.duplicate()
 reversed.reverse()
 for control in reversed:
  control.grab_focus()
  await frames()
  var row: Control = control.get_parent() if control is HSlider else control
  check(screen.get_global_rect().grow(1.0).encloses(row.get_global_rect()), "bottom-up visible " + str(control.name))
 sliders[0].grab_focus()
 await frames()
 ui_action("ui_up")
 await frames()
 check(root.gui_get_focus_owner() == controls[-1], "up from first wraps to back")
 ui_action("ui_down")
 await frames()
 check(root.gui_get_focus_owner() == sliders[0], "down from back wraps to first")
 var old_value: float = sliders[0].value
 ui_action("ui_right")
 await frames()
 check(sliders[0].value > old_value, "right changes slider rather than focus")
 screen.find_child("BackFromPadSettings", true, false).pressed.emit()
 check(events.back == 1, "back callback")
 # Pending deferred visibility calls must not throw after freeing the screen.
 controls[-1].grab_focus()
 screen.free()
 await frames()
 var hidden: ScrollContainer = UI.build(pad, Callable(), Callable(), Callable())
 hidden.hide()
 wrapper.add_child(hidden)
 await frames()
 check(root.gui_get_focus_owner() == null, "hidden build does not steal focus")
 hidden.free()
 # Detached invalid callbacks remain safe when explicitly invoked.
 var invalid: ScrollContainer = UI.build(pad, Callable(), Callable(), Callable())
 invalid.find_child("BackFromPadSettings", true, false).pressed.emit()
 invalid.find_child("Remap_interact", true, false).pressed.emit()
 invalid.find_child("ResetPadSettings", true, false).pressed.emit()
 invalid.free()
 wrapper.free()
 pad.free()
 await frames()
 print("PAD_SETTINGS_SMOKE: %d checks, %d failures" % [checks, failures.size()])
 quit(1 if not failures.is_empty() else 0)
