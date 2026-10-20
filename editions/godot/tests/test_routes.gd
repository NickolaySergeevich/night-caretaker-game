extends SceneTree
const Main=preload("res://scripts/main.gd")
const Shift=preload("res://scripts/shift.gd")
var game:Node3D
var failures:=0
func _initialize()->void:
 call_deferred("run")
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
 else:print("PASS ",label)
func key(pressed:bool)->void:
 var e:=InputEventKey.new();e.physical_keycode=KEY_W;e.pressed=pressed;Input.parse_input_event(e)
func walk(x:float,z:float)->void:
 var point:=Vector3(x,0,z)
 for frame in range(400):
  var delta:Vector3=point-game.player.position;delta.y=0
  if delta.length()<.10:
   key(false)
   return
  game.player.rotation.y=atan2(-delta.x,-delta.z)
  key(true)
  await physics_frame
 key(false)
 for idx in range(game.player.get_slide_collision_count()):
  var collision:KinematicCollision3D=game.player.get_slide_collision(idx)
  print("COLLIDER ",collision.get_position()," normal ",collision.get_normal()," parent ",collision.get_collider().get_parent().position," rotation ",collision.get_collider().get_parent().rotation)
 check(false,"walk stuck at %s toward %s"%[game.player.position,point])
 quit(1)
func look(point:Vector3)->void:
 var delta:Vector3=point-game.camera.global_position
 game.player.rotation.y=atan2(-delta.x,-delta.z)
 # Match the real input path: the pad callback restores camera pitch from state.
 game.pitch=atan2(delta.y,Vector2(delta.x,delta.z).length())
 game.camera.rotation.x=game.pitch
func act(id:String,point:Vector3)->void:
 look(point)
 await physics_frame
 check(game.target()==id,"target "+id+" at "+str(game.player.position))
 if game.target()==id:game._interact()
 for i in range(35):await physics_frame
func run()->void:
 Engine.time_scale=8
 Engine.physics_ticks_per_second=480
 game=Main.new();root.add_child(game)
 await physics_frame
 game._resume()
 await walk(-.8,8)
 await act("keys",Vector3(-2,1.25,7.8))
 for i in [0,2,1,3]:
  var side:float=-1 if i<2 else 1
  var z:float=3 if i%2==0 else -1
  await walk(0,z)
  await walk(side*2.4,z)
  if i==0:
   await walk(-3,3.1);await act("printer",Vector3(-4,1.24,3.9))
  elif i==2:
   await walk(3.3,3.1);await act("projector",Vector3(4.45,1.18,3.95))
  else:await walk(side*3.2,z)
  await walk(side*2.4,z)
  await walk(side*2.5,z+.9)
  await act("switch_%d"%i,Vector3(side*1.78,1.3,z+.84))
  await walk(side*2.4,z)
  await walk(side*.5,z)
  await act("door_%d"%i,Vector3(side*1.6,1.3,z))
  await walk(0,z)
 check(game.shift.room_locked.all(func(v):return v),"all four physical room routes")
 await walk(0,-7)
 await walk(3.35,-7)
 await walk(3.35,-12.6)
 await walk(3.35,-7)
 await walk(.5,-7)
 await act("hall_switch",Vector3(1.5,1.3,-6.24))
 await walk(0,-4.7)
 await act("hall_door",Vector3(0,1.3,-6))
 check(game.shift.ordinary_complete(),"hall inspected and secured")
 await walk(0,7.2)
 check(game.shift.phase==Shift.Phase.CLASS_RECHECK,"physical return triggers recheck")
 await walk(0,3);await walk(.5,3);await act("door_2",Vector3(1.6,1.3,3))
 await walk(2.4,3);await walk(3.3,3.1);await act("projector",Vector3(4.45,1.18,3.95))
 await walk(2.4,3);await walk(.5,3);await act("door_2",Vector3(1.6,1.3,3));await walk(0,3)
 await walk(0,-1);await walk(-.5,-1);await act("door_1",Vector3(-1.6,1.3,-1))
 await walk(-2.4,-1);await walk(-3.2,.35);await walk(-2.4,-1)
 await walk(-.5,-1);await act("door_1",Vector3(-1.6,1.3,-1));await walk(0,-1)
 check(game.shift.phase==Shift.Phase.FUSE,"library physical route triggers outage")
 await walk(.5,-1);await act("door_3",Vector3(1.6,1.3,-1));await walk(2.4,-1)
 await walk(5.65,-1);await act("fuse",Vector3(6.91,1.4,-1))
 await walk(2.4,-1);await walk(.5,-1);await act("door_3",Vector3(1.6,1.3,-1));await walk(0,-1)
 check(game.shift.phase==Shift.Phase.INVESTIGATE,"fuse physical route triggers knock")
 await walk(0,-4.5);await act("hall_door",Vector3(0,1.3,-6));await walk(0,-5.4)
 look(Vector3(0,1.7,-8))
 for i in range(120):await physics_frame
 check(game.shift.phase==Shift.Phase.JOURNAL,"hall physical inspection")
 await walk(0,6);await walk(-.8,8);await act("journal",Vector3(-2,1.25,7.8))
 check(game.menu_kind=="journal" and not game.shift.note,"journal waits for choice")
 game._resume()
 check(not game.shift.note,"journal cancel preserves state")
 game._interact();game._write_journal(true)
 check(game.shift.choice and game.shift.note,"journal chosen entry")
 await walk(0,9);await act("exit",Vector3(0,1.3,9.9))
 check(game.shift.phase==Shift.Phase.END,"full physics route complete")
 var final_slot:int=(game.audio_scene.voice_cursor-1+16)%16
 var final_voice:AudioStreamPlayer3D=game.voices[final_slot]
 check(game.audio_scene._voice_ids[final_slot]=="door_close" and final_voice.global_position.is_equal_approx(Vector3(0,1.3,9.9)),"final audio voice is the actual exit door")
 check(final_voice.playing and not final_voice.stream_paused,"actual final door sound playing and not paused")
 print("PHYSICAL ROUTE FAILURES: ",failures)
 # Let the audio server consume stop commands before the headless process exits.
 for voice in game.voices+game.devices:voice.stop()
 await create_timer(.15,true,false,true).timeout
 game.queue_free();await process_frame;await process_frame;quit(1 if failures else 0)
