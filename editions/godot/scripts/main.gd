extends Node3D
const GamepadSupport = preload("res://common/gamepad_support.gd")
const PadSettings = preload("res://scripts/pad_settings.gd")
const PAD_SETTINGS_PATH = "user://caretaker-pad-settings.json"
const Shift = preload("res://scripts/shift.gd")
const Building = preload("res://scripts/building.gd")
const CONTROLS = "WASD — идти     Мышь — смотреть\nE / ЛКМ — действие     F — фонарь\nR / ПКМ — постучать     Tab — памятка\nP — меню     Esc — освободить мышь"
var pad:Node
var gameplay_control_mode := "mouse"
var pad_controls_active := false
var pad_ui_blocked := false
var pad_scroll_remainder := 0.0
var pad_page:Control
var pad_settings_button:Button
var pad_return_kind := "intro"
var pad_capture_action := ""
var pad_capture_ready := false
var pad_message := ""
var pad_settings_focus := ""
var pad_persistence_enabled := true
var shift := Shift.new()
var building: Node3D
var player: CharacterBody3D
var camera: Camera3D
var lamp: SpotLight3D
var spill: SpotLight3D
var panel: PanelContainer
var text: Label
var resume: Button
var settings: VBoxContainer
var journal: VBoxContainer
var hint: Label
var goal: Label
var paused := true
var menu_kind := "intro"
var pitch := 0.0
var sensitivity := .002
var capture_pending := false
var grace := 0
var foot_distance := 0.0
var step_index := 0
var voices: Array[AudioStreamPlayer3D] = []
var devices: Array[AudioStreamPlayer3D] = []
var sounds: Dictionary = {}
var audio_scene:Node3D
var end_fade:ColorRect
var end_elapsed := -1.0
func _ready() -> void:
 building = Building.new()
 add_child(building)
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color(.008,.014,.016)
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color(.17,.24,.28)
 env.ambient_light_energy = .10
 env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 var world := WorldEnvironment.new()
 world.environment = env
 add_child(world)
 player = CharacterBody3D.new()
 player.position = Vector3(0,.05,8.8)
 add_child(player)
 var col := CollisionShape3D.new()
 var capsule := CapsuleShape3D.new()
 capsule.radius = .23
 capsule.height = 1.75
 col.shape = capsule
 col.position.y = .875
 player.add_child(col)
 _player_shadow()
 camera = Camera3D.new()
 camera.position.y = 1.7
 camera.fov = 70
 camera.near = .10
 camera.far = 60.0
 player.add_child(camera)
 lamp = SpotLight3D.new()
 lamp.position = Vector3(.12,-.12,0)
 lamp.spot_angle = 19
 lamp.spot_range = 22
 lamp.light_energy = 1.8
 lamp.light_specular = .15
 lamp.spot_angle_attenuation = .65
 lamp.shadow_enabled = true
 lamp.shadow_caster_mask = 1
 lamp.light_color = Color(.85,.91,1)
 camera.add_child(lamp)
 spill = SpotLight3D.new()
 spill.position = lamp.position
 spill.spot_angle = 42
 spill.spot_range = 12
 spill.light_energy = .16
 spill.light_specular = .1
 spill.shadow_enabled = true
 spill.shadow_caster_mask = 1
 camera.add_child(spill)
 lamp.visible=false
 spill.visible=false
 _audio()
 _ui()
 _setup_pad()
 building.sync(shift,10)
 _show("НОЧНОЙ СМОТРИТЕЛЬ\nПервая смена\n\n" + _controls(), "intro")
func _player_shadow()->void:
 # A single merged shadow-only body follows the player; the camera-mounted
 # torch excludes its layer, while room/projector lights can be interrupted.
 var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 for part in [Vector4(0,1.12,.19,.74),Vector4(0,1.66,.13,.30),Vector4(-.10,.40,.075,.73),Vector4(.10,.40,.075,.73),Vector4(-.23,1.11,.07,.60),Vector4(.23,1.11,.07,.60)]:
  var mesh:=CapsuleMesh.new();mesh.radius=part.z;mesh.height=part.w;mesh.radial_segments=12;mesh.rings=4
  surface.append_from(mesh,0,Transform3D(Basis.IDENTITY,Vector3(part.x,part.y,.055)))
 var body:=MeshInstance3D.new();body.name="PlayerShadow";body.mesh=surface.commit();body.layers=2
 body.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
 player.add_child(body)
func _ui() -> void:
 var canvas := CanvasLayer.new()
 add_child(canvas)
 var root := Control.new()
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.mouse_filter = Control.MOUSE_FILTER_IGNORE
 canvas.add_child(root)
 hint = Label.new()
 hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
 hint.offset_left = -300
 hint.offset_right = 300
 hint.offset_top = -60
 hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 hint.add_theme_font_size_override("font_size",20)
 root.add_child(hint)
 goal = Label.new()
 goal.position = Vector2(28,28)
 goal.add_theme_font_size_override("font_size",20)
 root.add_child(goal)
 var dot := Label.new()
 dot.text = "·"
 dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 root.add_child(dot)
 panel = PanelContainer.new()
 root.add_child(panel)
 panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 panel.offset_left = -350
 panel.offset_right = 350
 panel.offset_top = -260
 panel.offset_bottom = 260
 var skin := StyleBoxFlat.new()
 skin.bg_color = Color(.035,.048,.052,.97)
 skin.border_color = Color(.34,.36,.29)
 skin.set_border_width_all(1)
 skin.content_margin_left = 32
 skin.content_margin_right = 32
 skin.content_margin_top = 28
 skin.content_margin_bottom = 28
 panel.add_theme_stylebox_override("panel",skin)
 end_fade=ColorRect.new();end_fade.color=Color(0,0,0,0);end_fade.mouse_filter=Control.MOUSE_FILTER_IGNORE
 end_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(end_fade);root.move_child(end_fade,panel.get_index())
 var box := VBoxContainer.new()
 box.add_theme_constant_override("separation",18)
 panel.add_child(box)
 text = Label.new()
 text.add_theme_font_size_override("font_size",20)
 text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 text.size_flags_vertical = Control.SIZE_EXPAND_FILL
 box.add_child(text)
 journal = VBoxContainer.new()
 journal.add_theme_constant_override("separation",12)
 box.add_child(journal)
 for i in range(2):
  var entry := Button.new()
  entry.text = "Посторонних не обнаружено" if i == 0 else "Источник не установлен"
  entry.custom_minimum_size.y = 44
  entry.pressed.connect(_write_journal.bind(i == 1))
  journal.add_child(entry)
 settings = VBoxContainer.new()
 box.add_child(settings)
 var volume_label := Label.new()
 volume_label.text = "Громкость"
 settings.add_child(volume_label)
 var volume := HSlider.new()
 volume.min_value = 0
 volume.max_value = 100
 volume.value = 75
 volume.step = 5
 volume.custom_minimum_size.y = 28
 volume.value_changed.connect(func(v:float): AudioServer.set_bus_volume_db(0,linear_to_db(v / 100.0)))
 settings.add_child(volume)
 AudioServer.set_bus_volume_db(0,linear_to_db(.75))
 var mouse_label := Label.new()
 mouse_label.text = "Чувствительность мыши"
 settings.add_child(mouse_label)
 var mouse := HSlider.new()
 mouse.min_value = .5
 mouse.max_value = 3
 mouse.step = .1
 mouse.value = 1
 mouse.custom_minimum_size.y = 28
 mouse.value_changed.connect(func(v:float): sensitivity = .002 * v)
 settings.add_child(mouse)
 pad_settings_button=Button.new();pad_settings_button.name="PadSettingsEntry";pad_settings_button.text="Геймпад и вибрация";pad_settings_button.custom_minimum_size.y=36
 pad_settings_button.pressed.connect(_pad_settings);settings.add_child(pad_settings_button)
 resume = Button.new()
 resume.custom_minimum_size.y = 44
 resume.pressed.connect(_resume_button)
 box.add_child(resume)
func _show(message:String,kind:String = "pause") -> void:
 paused = true
 menu_kind = kind
 _pad_menu_reset()
 if is_instance_valid(pad_page):pad_page.hide();pad_page.queue_free();pad_page=null
 resume.show()
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 panel.show()
 text.text = message
 journal.visible = kind == "journal"
 settings.visible = kind == "pause" or kind == "intro"
 resume.text = "Начать смену" if kind == "intro" else ("Начать заново" if kind == "end" else ("Не записывать пока" if kind == "journal" else "Продолжить"))
 if kind == "journal":journal.get_child(int(shift.choice)).grab_focus()
 else:resume.grab_focus()
 audio_scene.pause(kind != "end")
 if kind == "end":audio_scene.stop_devices()
func _resume_button()->void:
 if menu_kind=="pad_remap":_pad_capture_cancel()
 elif menu_kind=="pad_settings":_pad_settings_back()
 else:_resume()
func _resume(source:String="") -> void:
 if shift.phase == Shift.Phase.END:
  _pad_stop()
  get_tree().reload_current_scene()
  return
 paused = false
 menu_kind = "gameplay"
 panel.hide()
 hint.text = ""
 capture_pending = true
 grace = Time.get_ticks_msec() + 400
 gameplay_control_mode="gamepad" if source=="gamepad" or (source.is_empty() and is_instance_valid(pad) and pad.last_source=="gamepad") else "mouse"
 pad_controls_active=gameplay_control_mode=="gamepad"
 Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if gameplay_control_mode=="mouse" else Input.MOUSE_MODE_VISIBLE
 if is_instance_valid(pad):pad.set_context("gameplay");pad.model.suspend();pad._clear_frame()
 audio_scene.pause(false)
func _release_pointer() -> void:
 # Esc belongs to the browser. Freeze safely without opening the game menu.
 paused = true
 menu_kind = "pointer"
 _pad_menu_reset()
 panel.hide()
 hint.text = "Мышь свободна. Щёлкните по игре, чтобы продолжить. P — меню"
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 audio_scene.pause(true)
func _write_journal(choice:bool) -> void:
 if shift.phase!=Shift.Phase.JOURNAL or shift.note or not shift.keys:return
 shift.choice = choice
 shift.interact("journal",player.position)
 if not shift.note:return
 _resume()
 if is_instance_valid(pad):pad.rumble("interact")
func _notification(what:int) -> void:
 if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(panel):_pad_focus_lost()
func _process(_dt:float) -> void:
 if end_elapsed>=0:
  end_elapsed+=_dt
  end_fade.color.a=clampf(end_elapsed/1.67,0,1)
  if end_elapsed>=1.8 and menu_kind!="end":
   _show("Смена закончена\n\n" + ("Источник не установлен." if shift.choice else "Посторонних не обнаружено."), "end")
 goal.visible = not paused and end_elapsed<0 and (Input.is_physical_key_pressed(KEY_TAB) or (is_instance_valid(pad) and pad.held("hud")))
 goal.text = shift.short_goal()
 if OS.has_feature("web") and gameplay_control_mode=="mouse" and not paused and end_elapsed<0 and Time.get_ticks_msec() > grace and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
  _release_pointer()
func _input(event:InputEvent)->void:
 if not pad_capture_action.is_empty() and event is InputEventKey and event.pressed:
  if event.physical_keycode==KEY_ESCAPE or event.keycode==KEY_ESCAPE:_pad_capture_cancel()
  get_viewport().set_input_as_handled()
func _unhandled_input(event:InputEvent) -> void:
 if end_elapsed>=0 and menu_kind!="end":return
 if event is InputEventKey and event.pressed and not event.echo:
  var key:int = event.physical_keycode if event.physical_keycode else event.keycode
  if key == KEY_ESCAPE:
   if not paused:_release_pointer()
   return
  if key == KEY_P:
   if not paused:_show("Пауза\n\n" + _controls())
   elif menu_kind == "pause" or menu_kind == "journal":_resume()
   elif menu_kind == "pointer":_show("Пауза\n\n" + _controls())
   return
  if paused:return
  if key == KEY_F:_toggle_torch()
  if key == KEY_K or key == KEY_R:_knock()
  if key == KEY_E:_interact()
 if event is InputEventMouseButton and event.pressed and paused and menu_kind == "pointer" and event.button_index == MOUSE_BUTTON_LEFT:
  _resume()
  return
 if event is InputEventMouseButton and event.pressed and not paused:
  if gameplay_control_mode=="gamepad":
   gameplay_control_mode="mouse";Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;capture_pending=true;grace=Time.get_ticks_msec()+400
  if event.button_index == MOUSE_BUTTON_LEFT:_interact()
  if event.button_index == MOUSE_BUTTON_RIGHT:_knock()
 if event is InputEventMouseMotion and not paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
  if capture_pending:
   capture_pending = false
   return
  _apply_mouse_motion(event)
func _apply_mouse_motion(event:InputEventMouseMotion)->void:
 # Captured aiming must not change with canvas stretch / embed resolution.
 var motion:Vector2 = event.screen_relative
 player.rotate_y(-motion.x * sensitivity)
 pitch = clampf(pitch - motion.y * sensitivity,-1.4,1.4)
 camera.rotation.x = pitch
func _knock() -> void:
 var before:int=shift.events.size()
 shift.knock(player.position,_focused(Vector3(0,1.3,-6),2.1))
 _tag_player_haptic(before)
func _interact() -> void:
 var id := target()
 if id == "journal":_show("Журнал смены\n\nЧто записать?", "journal")
 else:
  var before:int=shift.events.size()
  shift.interact(id,player.position)
  _tag_player_haptic(before)
func _focused(p:Vector3,radius:float) -> bool:
 var delta := p - camera.global_position
 if Vector2(delta.x,delta.z).length() > radius or delta.length() < .01:return false
 if (-camera.global_basis.z).dot(delta.normalized()) < .86:return false
 var query := PhysicsRayQueryParameters3D.create(camera.global_position,p)
 query.exclude = [player.get_rid()]
 var hit := get_world_3d().direct_space_state.intersect_ray(query)
 return hit.is_empty() or hit.position.distance_to(p) < .35
func target() -> String:
 if shift.phase == Shift.Phase.END:return ""
 if not shift.keys:return "keys" if _focused(Vector3(-2,1.25,7.8),2.3) else ""
 if shift.printer_on and _focused(Vector3(-4,1.24,3.9),1.7):return "printer"
 if shift.projector_on and _focused(Vector3(4.45,1.18,3.95),1.7):return "projector"
 if shift.phase == Shift.Phase.FUSE and not shift.fuse_repaired and _focused(Vector3(6.91,1.4,-1),1.7):return "fuse"
 for i in range(4):
  var x:float = -1.6 if i < 2 else 1.6
  var z:float = 3.0 if i % 2 == 0 else -1.0
  if shift.room_open[i] and _focused(Vector3(x + (-.18 if i < 2 else .18),1.3,z + .84),1.4):return "switch_%d" % i
  if _focused(Vector3(x,1.3,z),1.55):return "door_%d" % i
 if shift.phase == Shift.Phase.DARKEN and _focused(Vector3(1.5,1.3,-6.24),1.7):return "hall_switch"
 if _focused(Vector3(0,1.3,-6),2.1):return "hall_door"
 if shift.phase == Shift.Phase.JOURNAL and _focused(Vector3(-2,1.25,7.8),2.3):return "journal"
 if shift.phase == Shift.Phase.EXIT and _focused(Vector3(0,1.3,9.9),1.9):return "exit"
 return ""
func _physics_process(dt:float) -> void:
 if paused or end_elapsed>=0:
  if menu_kind != "pointer":hint.text = ""
  return
 building.sync(shift,dt)
 lamp.visible = shift.torch_on
 spill.visible = shift.torch_on
 var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
 var input_move:=Vector2(direction.x,direction.z)
 if is_instance_valid(pad):input_move+=pad.frame.move
 input_move=input_move.limit_length(1.0)
 var move := player.basis * Vector3(input_move.x,0,input_move.y) * 2.6
 player.velocity.x = move.x
 player.velocity.z = move.z
 if not player.is_on_floor():player.velocity.y -= 18 * dt
 var old := player.position
 player.move_and_slide()
 foot_distance += player.position.distance_to(old)
 if player.is_on_floor() and foot_distance > .78:
  foot_distance = fmod(foot_distance,.78)
  step_index = (step_index + 1) % 3
  _play(("step_hall_" if player.position.z < -6 else "step_hard_") + "%02d" % (step_index + 1),player.position)
 shift.step(dt,player.position,_focused(Vector3(0,1.7,-8),4.0))
 for event in shift.events:
  audio_scene.handle_event(event,shift.time)
  if event.has("player_haptic") and is_instance_valid(pad):pad.rumble(event.player_haptic)
 shift.events.clear()
 _update_devices(dt)
 hint.text = (pad.model.binding_label("interact") if is_instance_valid(pad) and pad.last_source=="gamepad" else "E") if not target().is_empty() else ""
 if shift.phase == Shift.Phase.END:
  end_elapsed=0.0
  _pad_stop()
  Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
  audio_scene.stop_devices()
func _audio() -> void:
 var manifest:Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/manifest.json"))
 for item in manifest.assets:sounds[item.id] = load("res://data/audio/" + str(item.path))
 audio_scene=preload("res://scripts/caretaker_audio.gd").new();add_child(audio_scene);audio_scene.configure(sounds)
 audio_scene.update_devices(shift,player.position,.00001)
 voices=audio_scene.voices;devices=audio_scene.devices
func _update_devices(dt:float) -> void:
 audio_scene.update_devices(shift,player.position,dt)
func _play(id:String,position_:Vector3) -> void:
 audio_scene.play(id,position_)

func _setup_pad()->void:
 pad=GamepadSupport.new();pad.configure("caretaker");add_child(pad)
 pad.action_pressed.connect(_pad_action);pad.menu_action.connect(_pad_menu)
 pad.frame_ready.connect(_pad_frame);pad.source_changed.connect(_pad_source)
 pad.focus_lost.connect(_pad_focus_lost);pad.device_lost.connect(_pad_lost)
 _load_pad_settings()
func _pad_stop()->void:
 if not is_instance_valid(pad):return
 pad.haptics.stop_all();pad.model.suspend();pad._clear_frame()
 if is_instance_valid(player):player.velocity=Vector3.ZERO
func _exit_tree()->void:_pad_stop()
func _pad_menu_reset()->void:
 pad_scroll_remainder=0.0
 if not is_instance_valid(pad):return
 pad.set_context("menu");_pad_stop();pad_ui_blocked=true
func _controls()->String:
 if not is_instance_valid(pad) or pad.last_source!="gamepad":return CONTROLS
 return "Левый стик — идти; правый — смотреть\n"+pad.model.binding_label("interact")+" — действие\n"+pad.model.binding_label("torch")+" — фонарь\n"+pad.model.binding_label("knock")+" — постучать\n"+pad.model.binding_label("hud")+" — памятка, удерживать\n"+pad.model.binding_label("pause")+" — меню"
func _pad_source(source:String)->void:
 if source in ["keyboard","mouse"]:pad_controls_active=false
 if menu_kind=="intro":text.text="НОЧНОЙ СМОТРИТЕЛЬ\nПервая смена\n\n"+_controls()
 elif menu_kind=="pause":text.text="Пауза\n\n"+_controls()
 elif menu_kind=="pointer" and source=="gamepad":hint.text="Мышь свободна. A / Cross или Start — продолжить с геймпадом. P — меню"
func _toggle_torch()->void:
 if not shift.torch or end_elapsed>=0:return
 shift.torch_on=not shift.torch_on;_play("switch",camera.global_position)
 if is_instance_valid(pad):pad.rumble("switch")
func _tag_player_haptic(first:int)->void:
 # Only events caused by this actual player action, never ambient/reply cues.
 for i in range(first,shift.events.size()):
  var name_:String=shift.events[i].get("name","")
  if name_.begins_with("knock_player_"):shift.events[i]["player_haptic"]="knock";return
  if name_ in ["switch","breaker"]:shift.events[i]["player_haptic"]="switch";return
  if name_ in ["keys","door_open","door_close","lock","unlock"]:shift.events[i]["player_haptic"]="interact";return
func _pad_action(action:String)->void:
 if paused or end_elapsed>=0:return
 gameplay_control_mode="gamepad";Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 match action:
  "interact":_interact()
  "torch":_toggle_torch()
  "knock":_knock()
  "pause","back":_show("Пауза\n\n"+_controls())
func _pad_menu(action:String)->void:
 if not paused or pad_ui_blocked or (end_elapsed>=0 and menu_kind!="end"):return
 if not pad_capture_action.is_empty():
  if action=="ui_cancel":_pad_capture_cancel()
  return
 if menu_kind=="pointer":
  if action in ["ui_accept","pause"]:_resume("gamepad")
  elif action=="ui_cancel":_show("Пауза\n\n"+_controls())
  return
 if action in ["ui_cancel","pause"]:
  if menu_kind=="pad_settings":_pad_settings_back()
  elif menu_kind in ["pause","journal"]:_resume("gamepad")
  elif menu_kind=="intro" and action=="pause":_resume("gamepad")
  return
 if get_viewport().gui_get_focus_owner()==null:resume.grab_focus()
 GamepadSupport.push_ui(get_viewport(),action)
func _pad_frame(frame:Dictionary)->void:
 if not pad_capture_action.is_empty():
  var buttons:Array=[];var axes:Array=[]
  if pad.model.active_device>=0:
   for i in range(pad.model.BUTTON_COUNT):buttons.append(1.0 if Input.is_joy_button_pressed(pad.model.active_device,i) else 0.0)
   for i in range(pad.model.AXIS_COUNT):axes.append(Input.get_joy_axis(pad.model.active_device,i))
  _pad_capture_sample(buttons,axes);return
 if pad_ui_blocked and pad.model.armed:pad_ui_blocked=false
 if paused:
  if is_instance_valid(pad_page) and pad_page is ScrollContainer:
   pad_scroll_remainder+=float(frame.scroll)
   var pixels:=int(pad_scroll_remainder)
   pad_scroll_remainder-=pixels
   if pixels!=0:
    var before:int=pad_page.scroll_vertical
    pad_page.scroll_vertical+=pixels
    if pad_page.scroll_vertical!=before+pixels:pad_scroll_remainder=0.0
  return
 if end_elapsed>=0:pad.take_look();return
 var look:Vector2=pad.take_look()
 if not frame.move.is_zero_approx() or not look.is_zero_approx() or bool(frame.held.get("hud",false)):pad_controls_active=true
 player.rotate_y(-look.x);pitch=clampf(pitch-look.y,-1.4,1.4);camera.rotation.x=pitch
func _pad_focus_lost()->void:
 _pad_stop()
 if end_elapsed>=0:return # Preserve end-of-shift fade and final audio tail.
 if not pad_capture_action.is_empty():pad_capture_action="";pad_capture_ready=false;_show("Пауза\n\n"+_controls())
 elif not paused:_show("Пауза\n\n"+_controls())
func _pad_lost(_device:int)->void:
 _pad_stop()
 if end_elapsed>=0:return
 if gameplay_control_mode=="gamepad" or pad_controls_active or not pad_capture_action.is_empty():
  pad_capture_action="";pad_capture_ready=false
  _show("Геймпад отключён\n\nМожно подключить его снова или продолжить клавиатурой.\n\n"+CONTROLS)
func _pad_settings()->void:
 if menu_kind not in ["pad_settings","pad_remap"]:pad_return_kind=menu_kind
 _show("Геймпад и вибрация\n"+pad_message,"pad_settings")
 resume.hide()
 pad_page=PadSettings.build(pad,_pad_settings_back,_save_pad_settings,_pad_capture_begin)
 var box:VBoxContainer=text.get_parent();box.add_child(pad_page);box.move_child(pad_page,resume.get_index())
 _pad_first_focus.call_deferred()
func _pad_first_focus()->void:
 if not is_instance_valid(pad_page):return
 var page:=pad_page
 var target:Control
 if not pad_settings_focus.is_empty():
  var previous:=page.find_child(pad_settings_focus,true,false)
  if previous is Control and previous.is_visible_in_tree():target=previous
 if target==null:
  for control in page.find_children("*","Control",true,false):
   if control.focus_mode==Control.FOCUS_ALL and control.is_visible_in_tree():target=control;break
 if target==null:return
 target.grab_focus()
 # The replaced ScrollContainer has not completed its first container layout
 # when deferred focus runs. Wait for layout before keeping the restored row
 # visible; do not steal focus after another menu or a user's navigation.
 for i in range(2):await get_tree().process_frame
 if is_instance_valid(page) and page==pad_page and is_instance_valid(target) and get_viewport().gui_get_focus_owner()==target:
  page.ensure_control_visible(target.get_parent() if target is HSlider else target)
func _pad_settings_back()->void:
 pad_message=""
 _show(("НОЧНОЙ СМОТРИТЕЛЬ\nПервая смена\n\n" if pad_return_kind=="intro" else "Пауза\n\n")+_controls(),"intro" if pad_return_kind=="intro" else "pause")
 if is_instance_valid(pad_settings_button):pad_settings_button.grab_focus()
func _pad_capture_begin(action:String)->void:
 pad_settings_focus="Remap_"+action
 _show("Назначить: "+str(PadSettings.ACTION_NAMES.get(action,action))+"\n\nОтпустите все кнопки и стики. Затем нажмите новую кнопку или курок.\nB / Circle или Esc — отмена. Home / Share остаются системе.","pad_remap")
 resume.text="Отмена";pad_capture_action=action;pad_capture_ready=false
func _pad_capture_cancel()->void:
 pad_capture_action="";pad_capture_ready=false;_pad_settings()
func _pad_capture_sample(buttons:Array,axes:Array)->void:
 if pad_capture_action.is_empty():return
 if not pad_capture_ready:
  pad_capture_ready=pad.model._neutral(buttons,axes) and pad.model._value(axes,JOY_AXIS_TRIGGER_LEFT)<=.25 and pad.model._value(axes,JOY_AXIS_TRIGGER_RIGHT)<=.25;return
 if pad.model._value(buttons,JOY_BUTTON_B)>.5:_pad_capture_cancel();return
 var binding:Dictionary={}
 for i in range(buttons.size()):
  if buttons[i]>.5:
   if i in [JOY_BUTTON_GUIDE,JOY_BUTTON_BACK]:text.text="Home / Share остаются системе. Отпустите кнопку и выберите другую.";pad_capture_ready=false;return
   binding={"button":i};break
 if binding.is_empty():
  for axis in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:
   if pad.model._value(axes,axis)>.55:binding={"axis":axis,"sign":1};break
 if binding.is_empty():return
 var result:Dictionary=pad.model.rebind(pad_capture_action,binding)
 if not result.ok:
  text.text="Кнопка уже занята другим действием. Отпустите её и выберите другую.\nB / Esc — отмена.";pad_capture_ready=false;return
 pad_message="Назначено: "+pad.model.binding_label(pad_capture_action)
 _save_pad_settings();_pad_capture_cancel()
func _pad_settings_data()->Dictionary:
 return {"version":1,"pad":pad.model.export_settings(),"vibration":pad.haptics.enabled,"strength":pad.haptics.intensity}
func _import_pad_settings(data:Variant)->bool:
 if not data is Dictionary or data.get("version")!=1 or not data.get("pad") is Dictionary or not data.get("vibration") is bool:return false
 var strength:Variant=data.get("strength")
 if not(strength is int or strength is float) or not is_finite(float(strength)):return false
 if not pad.model.import_settings(data.pad):return false
 pad.haptics.configure(data.vibration,clampf(float(strength),0,1));return true
func _pad_save_status(message:String)->void:
 pad_message=message
 if menu_kind=="pad_settings":text.text="Геймпад и вибрация\n"+pad_message
func _save_pad_settings(path:String=PAD_SETTINGS_PATH)->bool:
 if path==PAD_SETTINGS_PATH and not pad_persistence_enabled:return false
 var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
 if file==null:_pad_save_status("Настройки не сохранились, но работают в этой сессии.");return false
 file.store_string(JSON.stringify(_pad_settings_data()));file.close()
 var error:=DirAccess.rename_absolute(path+".tmp",path)
 if error!=OK:_pad_save_status("Настройки не сохранились, но работают в этой сессии.")
 if error==OK:_pad_save_status("Настройки сохранены.")
 return error==OK
func _load_pad_settings()->void:
 if pad_persistence_enabled and FileAccess.file_exists(PAD_SETTINGS_PATH):_import_pad_settings(JSON.parse_string(FileAccess.get_file_as_string(PAD_SETTINGS_PATH)))
