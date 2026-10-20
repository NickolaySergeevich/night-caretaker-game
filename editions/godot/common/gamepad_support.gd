extends Node
## Add once to a game's root. Host owns gameplay, pause, mouse capture, settings UI.
## Copy this entire common/ directory together; no autoload or project settings needed.
const Model = preload("gamepad_model.gd")
const Haptics = preload("gamepad_haptics.gd")
signal action_pressed(action: String)
signal menu_action(action: String)
signal source_changed(source: String)
signal device_lost(device: int)
signal focus_lost
signal frame_ready(frame: Dictionary)
var model = Model.new()
var haptics = Haptics.new()
var last_source := "keyboard"
var frame: Dictionary = {"move": Vector2.ZERO, "look": Vector2.ZERO, "scroll": 0.0, "held": {}, "pressed": [], "released": [], "ui": []}

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 process_priority = -100 # Poll before the host's normal _process.
 Input.joy_connection_changed.connect(_connection_changed)
 haptics.setup()
 var devices := Input.get_connected_joypads()
 if not devices.is_empty(): model.set_device(devices[0])

func _exit_tree() -> void:
 haptics.stop_all()

func configure(profile: String) -> void:
 model.set_profile(profile)

func set_context(context: String) -> void:
 if model.context != context:
  haptics.stop_all()
  model.set_context(context)
  _clear_frame()

func _clear_frame() -> void:
 frame = {"move": Vector2.ZERO, "look": Vector2.ZERO, "scroll": 0.0, "held": {}, "pressed": [], "released": [], "ui": []}

func held(action: String) -> bool:
 return bool(frame.held.get(action, false))

func take_look() -> Vector2:
 # Extra guard against multiple physics ticks consuming one render-sampled delta.
 var result: Vector2 = frame.look
 frame.look = Vector2.ZERO
 return result

func rumble(event: String) -> String:
 if last_source != "gamepad" or not model.focused or model.context != "gameplay": return "inactive"
 return haptics.pulse(model.active_device, event)

func _source(value: String) -> void:
 if last_source != value:
  last_source = value
  source_changed.emit(value)

func _input(event: InputEvent) -> void:
 if event is InputEventJoypadButton or event is InputEventJoypadMotion:
  if not model.focused:
   get_viewport().set_input_as_handled()
   return
  var meaningful: bool = (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4)
  if meaningful:
   # Only a deliberate button press can switch away from an active pad.
   if model.active_device < 0 or (event is InputEventJoypadButton and event.pressed and event.device != model.active_device):
    haptics.stop_all()
    model.set_device(event.device)
   if event.device == model.active_device: _source("gamepad")
  # One routing owner: prevent built-in ui_* mappings from confirming twice.
  get_viewport().set_input_as_handled()
 elif event is InputEventKey and event.pressed and not event.echo:
  _source("keyboard")
 elif event is InputEventMouseButton and event.pressed:
  _source("mouse")
 elif event is InputEventMouseMotion and event.screen_relative.length() > 2.0:
  _source("mouse")

func _process(delta: float) -> void:
 var buttons: Array = []
 var axes: Array = []
 if model.active_device >= 0 and model.focused:
  for button in range(Model.BUTTON_COUNT): buttons.append(1.0 if Input.is_joy_button_pressed(model.active_device, button) else 0.0)
  for axis in range(Model.AXIS_COUNT): axes.append(Input.get_joy_axis(model.active_device, axis))
 _dispatch_frame(model.sample(buttons, axes, delta))

func _dispatch_frame(snapshot: Dictionary) -> void:
 frame = snapshot
 # A callback may change context; do not dispatch stale actions after that.
 var before: String = model.context
 for action in frame.pressed:
  action_pressed.emit(action)
  if model.context != before: break
 for action in frame.ui:
  menu_action.emit(action)
  if model.context != before: break
 frame_ready.emit(frame)

func _connection_changed(device: int, connected: bool) -> void:
 if connected:
  haptics.reconnect(device)
  if model.active_device < 0: model.set_device(device)
 elif device == model.active_device:
  haptics.stop_all()
  model.set_device(-1)
  _clear_frame()
  device_lost.emit(device) # Host pauses only if this was its gameplay control mode.

func _notification(what: int) -> void:
 if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
  model.set_focused(false)
  _clear_frame()
  haptics.stop_all()
  focus_lost.emit()
 elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
  model.set_focused(true) # Never auto-resume or reacquire pointer lock.

static func push_ui(viewport: Viewport, action: String) -> void:
 if action not in ["ui_accept", "ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]: return
 var event := InputEventAction.new()
 event.action = action
 event.pressed = true
 event.strength = 1.0
 viewport.push_input(event, true)
 event = event.duplicate()
 event.pressed = false
 event.strength = 0.0
 viewport.push_input(event, true)
