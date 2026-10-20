extends SceneTree
const Audio = preload("res://scripts/caretaker_audio.gd")
const Shift = preload("res://scripts/shift.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var sounds:Dictionary={}
 for item in JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/manifest.json")).assets:sounds[item.id]=load("res://data/audio/"+item.path)
 var mix:=Audio.new();root.add_child(mix);mix.configure(sounds)
 for hz in [15,20,24,30,60,120]:
  mix.configure(sounds)
  for i in range(16):mix.play("step_hard_01",Vector3.ZERO)
  ck(mix.play_phrase([0.0,.38,.86],Vector3(0,1,-8),0,0,1),"reply survives saturated footsteps at %dHz"%hz)
  mix.play("chair",Vector3(1,1,0));mix.play("paper",Vector3(-1,1,0));mix.play("pipe_tick",Vector3(0,1,-12))
  ck(mix._voice_ids.has("chair") and mix._voice_ids.has("paper") and mix._voice_ids.has("pipe_tick"),"important cues survive at %dHz"%hz)
  ck(mix._phrases.has(1),"story cues cannot replace reply")
  for i in range(hz):
   mix.play("step_hard_01",Vector3.ZERO)
   mix._advance_voices(1.0/hz)
   ck(mix._phrases.has(1),"repeated steps never steal answer")
  mix.pause(true)
  var starts:int=mix.phrase_starts;var cursor:int=mix.voice_cursor
  for i in range(hz):
   mix.play("switch",Vector3.ZERO)
   mix.play_phrase([0.0,.38,.86],Vector3.ZERO,0,0,2)
  ck(mix.voice_cursor==cursor and mix.phrase_starts==starts,"menu rejects new voices")
  mix.pause(false)
  mix.stop_devices();cursor=mix.voice_cursor
  mix.play("paper",Vector3.ZERO)
  ck(mix.voice_cursor==cursor and not mix.play_phrase([0.0],Vector3.ZERO,0,0,2),"end menu rejects new voices but retains old tails")
  mix.configure(sounds)
  ck(mix._phrases.is_empty() and mix._slot_tokens.is_empty() and mix._deferred_starts.is_empty(),"restart clears state")
  # User knock cadence already limited in simulation, do not alter its pattern.
  var state:=Shift.new();state.phase=Shift.Phase.INVESTIGATE;state.door_open=false
  var taps:=0
  for i in range(hz):
   state.time=float(i)/hz;state.knock(Vector3(0,1,-5),true)
   taps+=state.events.size();state.events.clear()
  ck(taps<=13,"repeated knock bounded at %dHz"%hz)
 mix.configure(sounds)
 for i in range(16):mix.play("knock_reply_01",Vector3.ZERO)
 mix.play("paper",Vector3.ZERO);mix.play("step_hard_01",Vector3.ZERO)
 ck(mix.dropped_voices==2,"full answer pool is protected, no unbounded spill")
 mix.configure(sounds)
 mix.play("step_hard_01",Vector3.ZERO);mix.pause(true)
 await physics_frame;await physics_frame
 for v in mix.voices+mix.devices:
  var pb=v.get_stream_playback() if v.has_stream_playback() else null
  ck(pb==null or not pb.is_playing() or v.stream_paused,"immediate queued pause holds all starts")
 mix.pause(false);await physics_frame;await physics_frame
 mix.pause(true);await physics_frame
 for v in mix.voices+mix.devices:
  if v.has_stream_playback() and v.playing:ck(v.stream_paused,"active focus pause reaches playback")
 mix.pause(false)
 for id in ["door_open","door_close","dev_printer","dev_projector","knock_reply_01","chair","paper"]:
  ck(mix._sounds[id].data==sounds[id].data,"expressive source preserved: "+id)
 for id in ["step_hard_01","step_hall_01"]:ck(mix._web_spatial_info(id,Vector3.ZERO).is_empty(),"no double browser step filter")
 ck(mix._web_spatial_info("knock_reply_01",Vector3(0,1,-8)).has("spatial"),"hall knock keeps spatial adapter")
 for v in mix.voices+mix.devices:v.stop()
 await create_timer(.15).timeout
 mix.queue_free();await process_frame
 print("SOFT AUDIO ",checks," checks, failures ",failures)
 quit(1 if failures else 0)
