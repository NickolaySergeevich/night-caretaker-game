extends SceneTree
const Main=preload("res://scripts/main.gd")
const Shift=preload("res://scripts/shift.gd")
var game:Node3D
var failures:=0
var checks:=0
class HapticRecorder extends RefCounted:
 var enabled:=true
 var intensity:=.55
 var calls:Array=[]
 var stops:=0
 func stop_all()->void:stops+=1
 func configure(value:bool,strength:float)->void:enabled=value;intensity=strength
 func pulse(device:int,event:String)->String:
  calls.append([device,event]);return "synthetic-only"
 func reconnect(_device:int)->void:pass
 func status(_device:int)->Dictionary:return {"available":false,"reason":"test-no-device"}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 checks+=1
 if ok:print("PASS ",label)
 else:failures+=1;push_error(label)
func buttons(ids:Array=[])->Array:
 var result:Array=[];result.resize(21);result.fill(0.0)
 for id in ids:result[id]=1.0
 return result
func axes(x:float=0,y:float=0,look_x:float=0,look_y:float=0)->Array:
 var result:Array=[];result.resize(10);result.fill(0.0);result[0]=x;result[1]=y;result[2]=look_x;result[3]=look_y;return result
func sample(ids:Array=[],axis:Array=[],dt:float=.016)->void:
 game.pad._dispatch_frame(game.pad.model.sample(buttons(ids),axes() if axis.is_empty() else axis,dt))
func neutral()->void:sample();sample()
func press(id:int)->void:neutral();sample([id]);sample()
func new_game()->void:
 if is_instance_valid(game):
  game.audio_scene.set_process(false)
  for voice in game.voices+game.devices:voice.stop()
  game.queue_free();await process_frame;await process_frame
 game=Main.new();game.pad_persistence_enabled=false;root.add_child(game);game.set_physics_process(false);game.set_process(false)
 game.pad.set_process(false);game.pad.model.set_profile("caretaker");game.pad.model.set_device(0);game.pad._source("gamepad")
 game.pad.haptics=HapticRecorder.new()
 await process_frame;await physics_frame
 neutral()
func run()->void:
 await new_game()
 check(game.paused and game.menu_kind=="intro","pad starts in intro with real focus")
 check(root.gui_get_focus_owner()==game.resume,"intro resume remains focused")
 game._pad_settings();neutral();press(JOY_BUTTON_B)
 check(game.menu_kind=="intro" and root.gui_get_focus_owner()==game.pad_settings_button,"intro settings Back restores the entry button rather than Start")
 game._pad_settings();await process_frame;game._pad_settings_back()
 for i in range(4):await process_frame
 check(root.gui_get_focus_owner()==game.pad_settings_button,"pending child layout cannot steal parent focus after immediate close")
 game.resume.grab_focus();press(JOY_BUTTON_A)
 check(not game.paused and game.menu_kind=="gameplay","A starts shift without mouse click")
 check(game.gameplay_control_mode=="gamepad" and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"pad start does not capture pointer")
 check(game.pad.model.context=="gameplay","pad gameplay context set")
 game.grace=-1;game._process(.5)
 check(not game.paused,"pad gameplay does not require pointer capture")
 sample([JOY_BUTTON_A]);check(game.shift.events.is_empty(),"held A after starting does not interact")
 neutral();sample([],axes(.6,0));game._physics_process(.016)
 check(absf(game.player.velocity.length()-.5*2.6)<.1,"partial stick keeps analog walking speed")
 sample([],axes(1,1));game._physics_process(.016)
 check(Vector2(game.player.velocity.x,game.player.velocity.z).length()<=2.601,"diagonal movement is capped")
 neutral();var start:float=game.player.rotation.y
 sample([],axes(0,0,.7,0),.016);var once:float=game.player.rotation.y
 for i in range(6):game._physics_process(.001)
 check(is_equal_approx(game.player.rotation.y,once) and once!=start,"one render look delta is not repeated by six physics consumers")
 var turns:Array=[]
 for hz in [30,60,120]:
  game.player.rotation.y=0;neutral()
  for i in range(hz):sample([],axes(0,0,1,0),1.0/hz)
  turns.append(game.player.rotation.y)
 check(absf(turns[0]-turns[1])<.001 and absf(turns[1]-turns[2])<.001,"look is stable at 30/60/120 samples")
 neutral();sample([JOY_BUTTON_LEFT_SHOULDER]);game._process(.016)
 check(game.goal.visible,"hold LB reveals task")
 sample();game._process(.016);check(not game.goal.visible,"release LB hides task")
 press(JOY_BUTTON_START);check(game.paused and game.menu_kind=="pause","Start opens pause")
 check(game.pad.frame.move==Vector2.ZERO and not game.pad.held("hud"),"pause clears analog and held controls")
 neutral();game._pad_settings();await process_frame;await process_frame
 check(game.menu_kind=="pad_settings" and game.pad_page.is_visible_in_tree(),"pad settings opens bounded real controls")
 check(game.pad_page.size.y<=301 and game.pad_page.size.x<=637,"settings content is bounded")
 for i in range(6):await process_frame
 var scrolls:Array=[]
 for hz in [30,60,120]:
  game.pad_page.scroll_vertical=0;game.pad_scroll_remainder=0;neutral()
  for i in range(hz):sample([],axes(0,0,0,.3),1.0/hz)
  scrolls.append(game.pad_page.scroll_vertical)
 check(scrolls.min()>30 and scrolls.max()-scrolls.min()<=1,"gentle right-stick scrolling is stable at 30/60/120 Hz")
 game.pad_scroll_remainder=.75;game._pad_menu_reset()
 check(game.pad_scroll_remainder==0,"new menu context clears fractional scroll remainder")
 neutral();press(JOY_BUTTON_B);check(game.menu_kind=="pause","B returns to pause, not gameplay")
 check(root.gui_get_focus_owner()==game.pad_settings_button,"pause settings Back restores the entry button rather than Resume")
 # Same-context UI cascade: A opens settings; B in the same sample must not close it.
 neutral();game.settings.get_child(game.settings.get_child_count()-1).grab_focus()
 sample([JOY_BUTTON_A,JOY_BUTTON_B]);await process_frame
 check(game.menu_kind=="pad_settings","A+B cannot cascade across menu-to-menu transition")
 neutral();game._pad_capture_begin("pause");game._pad_capture_sample(buttons(),axes())
 game._pad_capture_sample(buttons([JOY_BUTTON_RIGHT_STICK]),axes())
 check(game.pad.model.bindings.pause.button==JOY_BUTTON_RIGHT_STICK,"pause action can be rebound away from Start")
 game._pad_capture_begin("pause");game._pad_capture_sample(buttons(),axes())
 # Actual raw Input path through adapter, not direct menu callback.
 var raw:=InputEventJoypadButton.new();raw.device=0;raw.button_index=JOY_BUTTON_START;raw.pressed=true;Input.parse_input_event(raw);await process_frame
 check(Input.is_joy_button_pressed(0,JOY_BUTTON_START),"raw Start updates actual Input state")
 game.pad._process(.016)
 check(game.pad.model.bindings.pause.button==JOY_BUTTON_START and game.menu_kind=="pad_settings","raw Start can be rebound back instead of cancelling capture")
 raw=raw.duplicate();raw.pressed=false;Input.parse_input_event(raw);await process_frame
 game._pad_capture_begin("knock");game._pad_capture_sample(buttons(),axes());game._pad_capture_sample(buttons([JOY_BUTTON_A]),axes())
 check(game.menu_kind=="pad_remap" and game.pad.model.bindings.knock.button==JOY_BUTTON_X,"conflicting binding is rejected without corrupting controls")
 game._pad_capture_sample(buttons(),axes());game._pad_capture_sample(buttons([JOY_BUTTON_B]),axes())
 check(game.menu_kind=="pad_settings" and game.pad_capture_action.is_empty(),"B cancels remap without assigning itself")
 for i in range(8):await process_frame
 var restored:=root.gui_get_focus_owner()
 check(restored!=null and restored.name=="Remap_knock","remap returns focus to the selected binding")
 check(game.pad_page.scroll_vertical>200,"remap return scroll keeps selected binding visible")
 game._pad_settings_back();game._resume("gamepad");neutral()
 game.shift.torch=false;var calls:int=game.pad.haptics.calls.size();press(JOY_BUTTON_Y)
 check(game.pad.haptics.calls.size()==calls,"unavailable torch has no haptic")
 game.shift.torch=true;var torch_before:bool=game.shift.torch_on;press(JOY_BUTTON_Y)
 check(game.shift.torch_on!=torch_before and game.pad.haptics.calls.size()==calls+1,"acquired torch toggles and requests one soft haptic")
 game.shift.phase=Shift.Phase.INSPECT;game.shift.events.clear();press(JOY_BUTTON_X)
 check(game.shift.events.is_empty(),"invalid knock does not manufacture a sound or haptic")
 game.shift.keys=true;game.shift.phase=Shift.Phase.INVESTIGATE;game.shift.door_open=false;game.shift.time=3;game.shift.last_tap=-10
 game.player.position=Vector3(0,.05,-4.5);game.player.rotation.y=0;game.camera.rotation.x=0;game.pitch=0
 await physics_frame
 var before_knock:int=game.pad.haptics.calls.size();press(JOY_BUTTON_X)
 check(game.shift.events.size()==1 and game.shift.events[0].get("player_haptic")=="knock","valid physical door knock queues one marked sound")
 check(game.pad.haptics.calls.size()==before_knock,"knock haptic waits for sound dispatch")
 game._physics_process(.016)
 check(game.pad.haptics.calls.size()==before_knock+1,"confirmed knock requests one haptic alongside audio")
 game._physics_process(.016)
 check(game.pad.haptics.calls.size()==before_knock+1,"next physics tick does not repeat knock haptic")
 for choice in [false,true]:
  game.shift.phase=Shift.Phase.JOURNAL;game.shift.note=false;game.shift.choice=false
  game._show("Журнал","journal");neutral();press(JOY_BUTTON_B)
  check(not game.shift.note and game.menu_kind=="gameplay","B cancels journal without writing")
  game._show("Журнал","journal");neutral();game.journal.get_child(int(choice)).grab_focus();var before_journal:int=game.pad.haptics.calls.size();press(JOY_BUTTON_A)
  check(game.shift.note and game.shift.choice==choice and game.shift.phase==Shift.Phase.EXIT,"A commits selected journal choice "+str(choice))
  check(game.gameplay_control_mode=="gamepad" and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"journal returns to pad without capture")
  check(game.pad.haptics.calls.size()==before_journal+1,"one confirmed journal entry requests one interaction haptic")
 neutral();sample([],axes(0,-1));game._pad_focus_lost()
 check(game.paused and game.pad.frame.move==Vector2.ZERO and game.player.velocity==Vector3.ZERO,"focus loss safely pauses and clears velocity")
 game.pad.model.set_focused(true);neutral();check(game.paused,"focus return never resumes automatically")
 game._resume("gamepad");neutral();game.pad._connection_changed(0,false)
 check(game.paused and game.pad.model.active_device==-1,"active pad disconnect pauses")
 game.pad._connection_changed(0,true);sample([JOY_BUTTON_A]);check(game.paused,"reconnect-held A does not resume")
 neutral();press(JOY_BUTTON_A);check(not game.paused,"fresh A after neutral can resume")
 game._resume("mouse");neutral();game.pad._source("keyboard");sample([],axes(.1,0))
 game.pad._connection_changed(0,false)
 check(not game.paused,"drift inside deadzone does not claim pad use or force a disconnect pause")
 game.pad.model.set_device(0);game._resume("mouse");neutral();sample([],axes(.3,0))
 check(game.pad_controls_active and game.gameplay_control_mode=="mouse","low but meaningful analog input tracks pad activity without changing pointer ownership")
 game.pad._connection_changed(0,false)
 check(game.paused,"disconnect after analog-only use from mouse start safely pauses")
 game.pad.model.set_device(0);game.pad._source("gamepad");game._resume("gamepad");neutral()
 var saved:Dictionary=game._pad_settings_data();game.pad.model.look_speed=3.3
 check(game._import_pad_settings(saved) and is_equal_approx(game.pad.model.look_speed,float(saved.pad.look_speed)),"settings roundtrip restores profile")
 var corrupt:Dictionary=saved.duplicate(true);corrupt.pad.look_speed="oops"
 check(not game._import_pad_settings(corrupt),"corrupt settings are rejected")
 check(not game._save_pad_settings("/path-that-does-not-exist/caretaker-settings.json") and not game.paused,"unavailable storage is non-fatal to gameplay")
 game._show("Пауза","pause");game._pad_settings();await process_frame
 game.pad_message="";game.text.text="Геймпад и вибрация"
 check(not game._save_pad_settings("/path-that-does-not-exist/caretaker-settings.json") and game.text.text.contains("не сохранились"),"storage failure appears immediately on the active settings page")
 game._resume("gamepad");game.end_elapsed=.2;game.paused=false;game.audio_scene.pause(false);game._pad_focus_lost();game._pad_lost(0)
 check(not game.paused and not game.audio_scene._paused,"blur/disconnect cannot replace final fade or pause its audio")
 game._pad_action("pause");check(not game.paused,"pad Start cannot interrupt final fade")
 game._process(2);check(game.menu_kind=="end" and game.paused,"end panel follows fade with menu context")
 check(game.pad.model.context=="menu" and game.pad.frame.move==Vector2.ZERO,"end menu clears gameplay state")
 game.audio_scene.set_process(false)
 for voice in game.voices+game.devices:voice.stop()
 game.queue_free();await process_frame;await process_frame
 print("CARETaker GAMEPAD CHECKS ",checks," FAILURES ",failures,"; synthetic only, no physical vibration claim")
 quit(1 if failures else 0)
