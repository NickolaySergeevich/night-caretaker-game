extends SceneTree
const Audio=preload("res://scripts/caretaker_audio.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var sounds:Dictionary={}
 for item in JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/manifest.json")).assets:sounds[item.id]=load("res://data/audio/"+item.path)
 var mix:=Audio.new();root.add_child(mix)
 for hz in [15,20,24,30,60,120]:
  Engine.physics_ticks_per_second=hz
  mix.configure(sounds)
  ck(mix.play_phrase([0.0,.38,.86],Vector3(0,1,-8),.4,0,1),"phrase starts at %dHz"%hz)
  await physics_frame;await physics_frame
  mix.pause(true)
  await physics_frame;await physics_frame
  for v in mix.voices+mix.devices:
   if v.playing and v.has_stream_playback():ck(v.stream_paused,"active pause holds at %dHz"%hz)
  var cursor:int=mix.voice_cursor
  for i in range(50):mix.play("switch",Vector3.ZERO)
  ck(mix.voice_cursor==cursor,"paused repeat rejects at %dHz"%hz)
  mix.pause(false)
  await physics_frame;await physics_frame
  ck(mix._phrases.has(1),"same phrase survives pause at %dHz"%hz)
  mix.configure(sounds)
  ck(mix._phrases.is_empty(),"restart clears at %dHz"%hz)
  mix.play("step_hard_01",Vector3.ZERO);mix.pause(true)
  await physics_frame;await physics_frame
  for v in mix.voices+mix.devices:
   var pb=v.get_stream_playback() if v.has_stream_playback() else null
   ck(pb==null or not pb.is_playing() or v.stream_paused,"queued pause holds at %dHz"%hz)
  mix.pause(false)
 for v in mix.voices+mix.devices:v.stop()
 await create_timer(.15).timeout
 mix.queue_free();await process_frame
 print("AUDIO RATES ",checks," checks, failures ",failures,"; actual native physics ticks, not browser")
 quit(1 if failures else 0)
