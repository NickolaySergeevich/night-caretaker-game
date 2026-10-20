extends SceneTree
## Native injection tests for the GDScript failure paths. No actual JS or WASM.
const Audio = preload("res://scripts/caretaker_audio.gd")
class FailedBridge:
 extends Audio
 var response = null
 func _web_call(_method: String, _arguments: Array = []):
  return response
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var sounds := {}
 for i in range(1,4): sounds["knock_reply_%02d" % i] = load("res://data/audio/knock_reply_%02d.wav" % i)
 for response in [null, false, {"ok": true}]:
  var mix := FailedBridge.new()
  root.add_child(mix)
  mix.configure(sounds)
  check(not mix.web_sample_active, "native configure does not claim browser Sample support")
  mix.web_sample_active = true # Inject only the boundary, never a native Sample driver.
  mix.response = response
  check(mix.play_phrase([0.0,.38,.86], Vector3.ZERO, 0, 0, 1), "failed Sample registration still has an explicit playable Stream fallback")
  var record: Dictionary = mix._phrases[1]
  var voice: AudioStreamPlayer3D = mix.voices[record.slot]
  check(not record.web_sample, "non-true register response is not counted as a Sample start")
  check(voice.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "failed registration cannot leave the voice in Sample mode")
  check(mix.web_audio_failures == 1 and mix.web_audio_status.begins_with("Stream fallback:"), "failed registration is observable in counter/status")
  check(voice.has_stream_playback(), "fallback is registered before pause rather than leaking a queued start")
  mix.pause(true)
  check(voice.stream_paused, "immediate pause reaches the fallback voice")
  mix.pause(false)
  mix.cancel_phrase(1)
  check(mix.web_audio_failures == 1, "fallback cancellation uses native PCM path, not missing Sample metadata")
  for player in mix.voices + mix.devices: player.stop()
  mix.queue_free()
  await process_frame

 for response in [null, false, {}, {"ok": false}, {"ok": {}}, {"ok": true}, {"ok": true,"keep": "1","frontier": 123}, {"ok": true,"keep": 100,"frontier": 123}, {"keep": 1,"frontier": 123}]:
  var mix := FailedBridge.new()
  root.add_child(mix); mix.configure(sounds)
  mix.play_phrase([0.0,.38,.86], Vector3.ZERO, 0, 0, 1)
  var record: Dictionary = mix._phrases[1]
  var slot: int = record.slot
  mix.web_sample_active = true
  record["web_sample"] = true # Simulate a previously accepted WEB node disappearing.
  mix.response = response
  mix.cancel_phrase(1)
  check(mix.phrase_cancels == 0, "absent/malformed cancel response never counts as success")
  check(mix.web_audio_failures == 1, "cancel failure has a diagnostic counter")
  check(not mix._busy[slot] and not mix.voices[slot].playing and not mix._phrases.has(1), "cancel failure stops/releases voice rather than playing future attacks")
  mix.queue_free(); await process_frame
 await create_timer(.20, true, false, true).timeout
 await process_frame
 print("WEB AUDIO BOUNDARY ", checks, " checks, failures ", failures, "; native failure injection only, not actual JS/WASM")
 quit(1 if failures else 0)
