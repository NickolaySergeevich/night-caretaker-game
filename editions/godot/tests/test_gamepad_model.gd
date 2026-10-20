extends SceneTree
const Model = preload("../common/gamepad_model.gd")
const Support = preload("../common/gamepad_support.gd")
const Haptics = preload("../common/gamepad_haptics.gd")
var checks := 0
var failures := 0
var clicks := 0
var edge_count := 0

func check(condition: bool, message: String) -> void:
 checks += 1
 if not condition:
  failures += 1
  printerr("FAIL: " + message)

func pad_buttons() -> Array:
 var values: Array = []
 values.resize(Model.BUTTON_COUNT)
 values.fill(0.0)
 return values

func pad_axes() -> Array:
 var values: Array = []
 values.resize(Model.AXIS_COUNT)
 values.fill(0.0)
 return values

func fresh(profile: String = "deeper", context: String = "gameplay"):
 var model = Model.new(profile)
 model.set_device(3)
 model.set_context(context)
 model.sample(pad_buttons(), pad_axes(), 1.0 / 60.0)
 return model

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 var m = fresh()
 check(m.armed, "initial neutral snapshot arms")
 check(m.bindings.dig.axis == JOY_AXIS_TRIGGER_RIGHT, "trigger uses Godot axis enum")
 check(Model.radial(Vector2(0.1, 0.1), 0.2) == Vector2.ZERO, "radial deadzone rejects drift")
 check(Model.radial(Vector2(0.0, 0.2), 0.2) == Vector2.ZERO, "deadzone boundary")
 check(is_equal_approx(Model.radial(Vector2(0.0, 0.6), 0.2).length(), 0.5), "analog magnitude preserved")
 check(Model.radial(Vector2(1.0, 1.0), 0.2).length() <= 1.000001, "diagonal speed capped")
 check(Model.radial(Vector2(NAN, 0), 0.2) == Vector2.ZERO, "nonfinite axis safe")
 var b := pad_buttons()
 var a := pad_axes()
 a[JOY_AXIS_LEFT_Y] = -0.6
 var f: Dictionary = m.sample(b, a, 1.0 / 60)
 check(is_equal_approx(f.move.y, -0.5), "forward sign and analog speed")
 a = pad_axes()
 a[JOY_AXIS_RIGHT_X] = 1
 var at30: Dictionary = m.sample(b, a, 1.0 / 30)
 var at60: Dictionary = m.sample(b, a, 1.0 / 60)
 check(is_equal_approx(at30.look.x, at60.look.x * 2), "look uses delta, not frame count")
 a[JOY_AXIS_RIGHT_Y] = 1
 var normal: Dictionary = m.sample(b, a, 0.01)
 m.invert_y = true
 check(is_equal_approx(m.sample(b, a, 0.01).look.y, -normal.look.y), "Y invert only look")
 a = pad_axes()
 b[JOY_BUTTON_A] = 1
 check(m.sample(b, a, 0.01).pressed == ["interact"], "single action edge")
 check(m.sample(b, a, 0.01).pressed.is_empty(), "hold does not repeat interaction")
 b[JOY_BUTTON_A] = 0
 check(m.sample(b, a, 0.01).released == ["interact"], "action release")
 b[JOY_BUTTON_LEFT_SHOULDER] = 1
 check(m.sample(b, a, 0.01).held.hud, "HUD hold")
 b[JOY_BUTTON_LEFT_SHOULDER] = 0
 check(not m.sample(b, a, 0.01).held.hud, "HUD immediately released")
 a[JOY_AXIS_TRIGGER_RIGHT] = 0.54
 check(not m.sample(b, a, 0.01).held.dig, "trigger below threshold")
 a[JOY_AXIS_TRIGGER_RIGHT] = 0.56
 check(m.sample(b, a, 0.01).held.dig, "trigger above threshold")
 a[JOY_AXIS_TRIGGER_RIGHT] = 0.5
 check(m.sample(b, a, 0.01).held.dig, "trigger hysteresis prevents threshold chatter")
 a[JOY_AXIS_TRIGGER_RIGHT] = 0.44
 check(not m.sample(b, a, 0.01).held.dig, "trigger releases below hysteresis threshold")
 a[JOY_AXIS_TRIGGER_RIGHT] = 0.56
 m.sample(b, a, 0.01)
 m.set_context("menu")
 check(m.sample(b, a, 0.01).held.is_empty(), "menu clears held digging")
 m.set_context("gameplay")
 check(m.sample(b, a, 0.01).pressed.is_empty() and not m.armed, "held trigger cannot resume after menu")
 a = pad_axes()
 m.sample(b, a, 0.01)
 check(m.armed, "neutral arms after menu")
 m.suspend()
 a[JOY_AXIS_LEFT_X] = 0.19
 a[JOY_AXIS_LEFT_Y] = 0.19
 check(m.sample(b, a, 0.01).move == Vector2.ZERO and not m.armed, "neutral gate uses circular deadzone, not per-axis square")
 a = pad_axes()
 m.sample(b, a, 0.01)
 m.set_focused(false)
 b[JOY_BUTTON_A] = 1
 check(m.sample(b, a, 0.01).pressed.is_empty(), "focus out suppresses action")
 m.set_focused(true)
 check(m.sample(b, a, 0.01).pressed.is_empty() and not m.armed, "focus in requires neutral")
 b[JOY_BUTTON_A] = 0
 m.sample(b, a, 0.01)
 m.set_device(-1)
 check(m.sample(b, a, 0.01).held.is_empty(), "disconnect clears held")
 m.set_device(3)
 b[JOY_BUTTON_A] = 1
 check(m.sample(b, a, 0.01).pressed.is_empty(), "reused device requires neutral")
 m = fresh("office", "menu")
 b = pad_buttons()
 b[JOY_BUTTON_A] = 1
 check(m.sample(b, a, 0.01).ui == ["ui_accept"], "menu A accepts")
 check(m.sample(b, a, 0.01).ui.is_empty(), "menu A never autorepeats")
 b = pad_buttons()
 b[JOY_BUTTON_DPAD_DOWN] = 1
 check(m.sample(b, a, 0.01).ui == ["ui_down"], "menu dpad direction")
 for i in range(3): check(m.sample(b, a, 0.1).ui.is_empty(), "no premature repeat %d" % i)
 check(m.sample(b, a, 0.03).ui == ["ui_down"], "delayed menu repeat")
 b = pad_buttons()
 m.sample(b, a, 0.01)
 a[JOY_AXIS_RIGHT_Y] = 1
 f = m.sample(b, a, 0.01)
 check(f.scroll > 0 and f.ui.is_empty(), "right stick scroll does not steal focus")
 a = pad_axes()
 a[JOY_AXIS_LEFT_X] = 1
 check(m.sample(b, a, 0.01).ui == ["ui_right"], "left stick menu navigation")
 m = fresh("office")
 check(m.rebind("notebook", {"button": JOY_BUTTON_RIGHT_STICK}).ok, "valid rebinding")
 check(not m.rebind("notebook", {"button": JOY_BUTTON_A}).ok, "conflict rejected")
 check(not m.rebind("notebook", {"axis": JOY_AXIS_LEFT_X, "sign": 1}).ok, "movement axis protected")
 check(not m.rebind("notebook", {"button": 999}).ok, "out of range button rejected")
 check(not m.rebind("missing", {"button": 3}).ok, "unknown action rejected")
 check(m.binding_label("notebook") == "R3", "prompt follows binding")
 var saved: Dictionary = m.export_settings()
 var m2 = fresh("office")
 check(m2.import_settings(saved), "settings direct roundtrip")
 check(m2.bindings == m.bindings, "settings maintain bindings")
 var json_saved: Variant = JSON.parse_string(JSON.stringify(saved))
 check(m2.import_settings(json_saved), "JSON settings roundtrip")
 var before: Dictionary = m2.export_settings()
 saved.bindings.interact = {"button": 777}
 check(not m2.import_settings(saved), "corrupt settings rejected")
 check(m2.export_settings() == before, "settings validation transactional")
 for profile in ["caretaker", "office", "deeper"]:
  var pm = fresh(profile)
  for action in Model.COMMON:
   check(pm.bindings[action] == Model.COMMON[action], "%s shared %s binding" % [profile, action])
 var original := InputMap.action_get_events("ui_accept").duplicate()
 var support = Support.new()
 root.add_child(support)
 await process_frame
 check(InputMap.action_get_events("ui_accept") == original, "adapter does not overwrite keyboard InputMap")
 check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "adapter never captures mouse")
 var container := VBoxContainer.new()
 root.add_child(container)
 var first := Button.new()
 first.text = "First"
 var second := Button.new()
 second.text = "Second"
 container.add_child(first)
 container.add_child(second)
 first.pressed.connect(func(): clicks += 1)
 first.grab_focus()
 await process_frame
 Support.push_ui(root, "ui_accept")
 await process_frame
 check(clicks == 1, "one synthetic UI action produces one button activation")
 Support.push_ui(root, "ui_down")
 await process_frame
 check(root.gui_get_focus_owner() == second, "menu focus travels without mouse")
 var sub := SubViewport.new()
 sub.size = Vector2i(800, 600)
 sub.gui_disable_input = false
 root.add_child(sub)
 var sub_button := Button.new()
 sub_button.text = "Mail action"
 sub.add_child(sub_button)
 sub_button.pressed.connect(func(): clicks += 1)
 sub_button.grab_focus()
 await process_frame
 var outer_focus_before := root.gui_get_focus_owner()
 Support.push_ui(sub, "ui_accept")
 await process_frame
 check(clicks == 2, "SubViewport accepts isolated gamepad UI action")
 check(root.gui_get_focus_owner() == outer_focus_before, "SubViewport action does not change outer focus")
 var slider := HSlider.new()
 slider.min_value = 0.0
 slider.max_value = 1.0
 slider.step = 0.1
 slider.value = 0.5
 slider.custom_minimum_size.x = 200
 container.add_child(slider)
 slider.grab_focus()
 await process_frame
 Support.push_ui(root, "ui_right")
 await process_frame
 check(is_equal_approx(slider.value, 0.6), "gamepad changes settings slider")
 var toggle := CheckButton.new()
 toggle.text = "Vibration"
 container.add_child(toggle)
 toggle.grab_focus()
 await process_frame
 Support.push_ui(root, "ui_accept")
 await process_frame
 check(toggle.button_pressed, "gamepad toggles vibration checkbox")
 first.disabled = true
 first.grab_focus()
 await process_frame
 var old_clicks := clicks
 Support.push_ui(root, "ui_accept")
 await process_frame
 check(clicks == old_clicks, "disabled button is not activated")
 check(support.rumble("interact") == "inactive", "keyboard session never vibrates a nearby idle pad")
 # A slow render frame can contain several physics ticks. Rotation is a delta,
 # movement/hold is a state, and action is an edge: do not consume them alike.
 support.set_process(false)
 support.action_pressed.connect(func(_action): edge_count += 1)
 support._dispatch_frame({"move": Vector2(0.5, 0), "look": Vector2(0.01, 0.02), "scroll": 0.0, "held": {"hud": true}, "pressed": ["interact"], "released": [], "ui": []})
 var accumulated_look := Vector2.ZERO
 for physics_tick in range(6):
  accumulated_look += support.take_look()
  check(support.frame.move == Vector2(0.5, 0) and support.held("hud"), "physics %d retains movement and holds" % physics_tick)
 check(accumulated_look == Vector2(0.01, 0.02), "six physics ticks do not multiply one look delta")
 check(edge_count == 1, "six physics ticks do not repeat one interact edge")
 support._dispatch_frame({"move": Vector2(0.5, 0), "look": Vector2(0.01, 0.02), "scroll": 0.0, "held": {"hud": true}, "pressed": [], "released": [], "ui": []})
 check(support.take_look() == Vector2(0.01, 0.02), "next render frame supplies a fresh look delta")
 check(edge_count == 1, "held interact does not create another edge on next render")
 var haptics = Haptics.new()
 haptics.setup()
 check(not haptics.status(0).available, "headless/native is not called WEB haptics PASS")
 haptics.configure(false, 0.5)
 check(haptics.pulse(0, "test") == "disabled", "vibration disabled")
 support.queue_free()
 container.queue_free()
 sub.queue_free()
 await process_frame
 print("GAMEPAD_MODEL: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
