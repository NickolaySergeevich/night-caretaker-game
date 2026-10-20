extends SceneTree
const Main=preload("res://scripts/main.gd")
const Shift=preload("res://scripts/shift.gd")
var failures:=0
var game:Node3D
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
 else:print("PASS ",label)
func send_key(key:int)->void:
 var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=true
 Input.parse_input_event(event);await process_frame
 event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
func run()->void:
 game=Main.new();root.add_child(game)
 await process_frame
 check(root.gui_get_focus_owner()==game.resume,"start button receives focus")
 await send_key(KEY_ENTER)
 check(not game.paused,"Enter starts shift")
 await send_key(KEY_P)
 check(game.paused and root.gui_get_focus_owner()==game.resume,"P opens focused pause")
 await send_key(KEY_TAB)
 check(root.gui_get_focus_owner() is HSlider,"Tab reaches settings")
 var slider:HSlider=root.gui_get_focus_owner()
 var value:=slider.value
 await send_key(KEY_LEFT)
 check(slider.value<value,"keyboard changes slider value")
 await send_key(KEY_ESCAPE)
 check(game.paused and game.menu_kind=="pause","Escape does not toggle the game menu")
 await send_key(KEY_P)
 check(not game.paused,"P resumes")
 var position:Vector3=game.player.position
 await send_key(KEY_ESCAPE)
 check(game.paused and game.menu_kind=="pointer" and not game.panel.visible,"Escape frees pointer without menu")
 await physics_frame
 check(game.player.position==position,"pointer release safely freezes movement")
 var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
 game._unhandled_input(click)
 check(not game.paused and not game.panel.visible,"click recaptures without an interaction")
 game.shift.keys=true;game.shift.phase=Shift.Phase.JOURNAL
 game._show("Журнал", "journal")
 await process_frame
 check(root.gui_get_focus_owner()==game.journal.get_child(0),"journal focuses first entry")
 await send_key(KEY_DOWN)
 check(root.gui_get_focus_owner()==game.journal.get_child(1),"Down chooses second entry")
 await send_key(KEY_ENTER)
 check(game.shift.choice and game.shift.note and game.shift.phase==Shift.Phase.EXIT,"Enter commits selected journal entry")
 for voice in game.voices+game.devices:voice.stop()
 await create_timer(.15,true,false,true).timeout
 game.queue_free();await process_frame;await process_frame
 print("UI FAILURES ",failures);quit(1 if failures else 0)
