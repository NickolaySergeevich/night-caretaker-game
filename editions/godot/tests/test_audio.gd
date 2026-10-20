extends SceneTree
## Configuration/math tests only. Neither headless playback nor non-zero PCM
## proves that the browser mix is audible, natural, or comfortable to a listener.
const Audio = preload("res://scripts/caretaker_audio.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
 checks += 1
 if not condition:
  failures += 1
  push_error(label)

func _initialize() -> void:
 call_deferred("run")

func sample() -> AudioStreamWAV:
 var stream := AudioStreamWAV.new()
 stream.format = AudioStreamWAV.FORMAT_16_BITS
 stream.mix_rate = 48000
 var data := PackedByteArray()
 data.resize(48000 * 2)
 stream.data = data
 return stream

func wav_peak_and_rms(path: String) -> Vector2:
 var bytes := FileAccess.get_file_as_bytes(path)
 check(bytes.size() >= 44, "source WAV exists: " + path)
 if bytes.size() < 44: return Vector2.ZERO
 check(bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WAVE", "RIFF PCM fixture")
 var offset := 12
 while offset + 8 <= bytes.size():
  var length := int(bytes.decode_u32(offset + 4))
  if bytes.slice(offset, offset + 4).get_string_from_ascii() == "data":
   var end := mini(offset + 8 + length, bytes.size())
   var peak := 0.0
   var sum_squares := 0.0
   var count := 0
   for position in range(offset + 8, end - 1, 2):
    var value := float(bytes.decode_s16(position)) / 32768.0
    peak = maxf(peak, absf(value))
    sum_squares += value * value
    count += 1
   return Vector2(peak, sqrt(sum_squares / maxf(count, 1)))
  offset += 8 + length + (length % 2)
 check(false, "source WAV has a data chunk")
 return Vector2.ZERO

func run() -> void:
 var bus_count := AudioServer.bus_count
 var sound := sample()
 var sound_map := {}
 for id in ["dev_printer", "dev_projector", "amb_vent", "amb_electric", "knock_reply_01", "knock_reply_02", "knock_reply_03", "knock_player_01", "switch", "door_open", "door_close", "chair", "paper", "step_hard_01"]:
  sound_map[id] = sound
 var mix := Audio.new()
 root.add_child(mix)
 mix.configure(sound_map)
 check(mix.voices.size() == 16, "bounded one-shot pool")
 check(mix.devices.size() == 2 and mix.get_child_count() == 18, "only two local loops; no global ambience")
 check(AudioServer.bus_count == bus_count, "no audio buses added")
 for player in mix.voices + mix.devices:
  check(player.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "positional Web voice forces Stream")
  check(player.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED and player.max_distance == 0.0, "no accidental double attenuation")
  check(player.panning_strength == 1.0 and player.bus == &"Master", "position and existing master bus preserved")
 check(mix.devices[0].position == Vector3(-4, 1.08, 3.9), "printer origin")
 check(mix.devices[1].position == Vector3(4.45, 1.18, 3.95), "projector origin")
 check(mix.devices[0].stream != sound and sound.loop_mode == AudioStreamWAV.LOOP_DISABLED, "loop configuration does not mutate supplied sounds")
 check(mix.devices[1].stream.loop_end == 48000, "device loop uses exact frame count")

 var near_gain: float = Audio.gain_for("knock_reply_01", 0.0)
 var far_gain: float = Audio.gain_for("knock_reply_01", 13.0)
 var closed_gain: float = Audio.gain_for("knock_reply_01", 13.0, 1)
 check(is_equal_approx(near_gain, 0.90), "reply near field has bounded gain, not an unlimited boost")
 check(is_equal_approx(far_gain, 1.20 / 2.04), "13 m reply retains explicit original distance curve")
 check(far_gain / near_gain > 0.65 and far_gain / near_gain < 0.66, "13 m retains 65% of capped near gain")
 check(closed_gain / far_gain > 0.87, "closed hall door preserves quiet answer")
 check(Audio.gain_for("switch", 0.0) <= 0.32, "household click is lower than reply, not an accent")
 check(Audio.gain_for("knock_reply_01", NAN) == 0.0, "nonfinite distance is silent")
 for distance in [0.0, 1.0, 5.0, 13.0, 25.0]:
  check(Audio.gain_for("knock_reply_01", distance) <= near_gain, "no gain peak with distance")
 print("REPLY GAIN: near=", near_gain, " at_13m=", far_gain, " closed=", closed_gain,
  " ratio_db=", linear_to_db(far_gain / near_gain), " (gain-model evidence, not listening)")
 # These are scalar bounds from the unmodified mono source, before stereo pan,
 # not a recording of the engine output. Include the current 75% master value.
 for variant in range(1, 4):
  var id := "knock_reply_%02d" % variant
  var stats := wav_peak_and_rms("res://data/audio/" + id + ".wav")
  var far_peak: float = stats.x * far_gain * 0.75
  var far_rms: float = stats.y * far_gain * 0.75
  check(far_rms > 0.002, "13 m source/gain bound is not near digital silence")
  check(far_peak < 0.10 and stats.x * near_gain * 0.75 < 0.12, "quiet source peak bounds; no near-field sting gain")
  print(id, " modeled_13m_peak_dbfs=", linear_to_db(far_peak), " modeled_13m_rms_dbfs=", linear_to_db(far_rms))

 var state := {"room_open": [true, true, true, true], "door_open": true, "printer_on": true, "projector_on": true}
 var listener := Vector3(0, 1.7, -5.2)
 mix.update_devices(state, listener, 0.02)
 mix.play("knock_reply_01", Vector3(0, 1, 7.8))
 var reply: AudioStreamPlayer3D = mix.voices[0]
 check(reply.global_position == Vector3(0, 1, 7.8), "reply retains remote post origin")
 check(is_equal_approx(db_to_linear(reply.volume_db), far_gain), "actual voice receives 13 m curve without cutoff")
 mix.play("door_open", Vector3(0, 1, -6))
 var old_door := mix.voice_cursor - 1
 var old_gain: float = mix._voice_gains[old_door]
 mix.play("door_close", Vector3(0, 1, -6))
 check(mix._busy[old_door] and is_equal_approx(mix._voice_gains[old_door], old_gain), "door reversal does not hard-cut the earlier sound")
 mix.update_devices(state, listener, 0.06)
 check(is_equal_approx(mix._voice_gains[old_door], old_gain * 0.5), "reversed door has short quiet crossfade")
 mix.update_devices(state, listener, 0.07)
 check(not mix._busy[old_door], "old door voice releases after fade")

 state.door_open = false
 mix.play("knock_reply_01", Vector3(0, 1, -8))
 var hall_slot := (mix.voice_cursor - 1 + 16) % 16
 var before: float = mix._voice_gains[hall_slot]
 mix.update_devices(state, listener, 0.01)
 var after: float = mix._voice_gains[hall_slot]
 check(after < before and after > Audio.gain_for("knock_reply_01", 2.8, 1), "door occlusion eases rather than jumps")
 state.room_open[2] = false
 mix.update_devices(state, Vector3(4.2, 1.7, -1), 0.02)
 check(mix._closed_doors(Vector3(4.45, 1.18, 3.95), Vector3(4.2, 1.7, -1)) == 1, "utility room is not mistaken for inside the classroom")

 for i in range(60): mix.update_devices(state, listener, 0.02)
 var running_gain: float = mix._device_gains[1]
 state.projector_on = false
 mix.update_devices(state, listener, 0.02)
 check(mix._device_gains[1] < running_gain and mix._device_gains[1] > 0.0, "unplugging leaves a quiet fan tail")
 # AudioStreamPlayer3D creates its queued playback on a physics tick. An idle
 # player's stream_paused getter is false even after its setter is called.
 await physics_frame
 await physics_frame
 mix.pause(true)
 var frozen_gain: float = mix._device_gains[1]
 var cursor: int = mix.voice_cursor
 mix.update_devices(state, listener, 0.2)
 mix.play("switch", Vector3.ZERO)
 check(mix._device_gains[1] == frozen_gain and mix.voice_cursor == cursor, "pause freezes envelopes and rejects new one-shots")
 for player in mix.voices + mix.devices:
  if player.has_stream_playback(): check(player.stream_paused, "pause reaches active streams")
 mix.pause(false)
 mix.stop_devices()
 check(is_equal_approx(mix._device_gains[1], frozen_gain), "end does not hard-cut the fan")
 mix._process(0.4)
 check(is_equal_approx(mix._device_gains[1], frozen_gain * 0.5), "end fade midpoint is half gain")
 mix._process(0.41)
 check(mix._device_gains[1] == 0.0 and not mix.devices[1].playing, "end finishes device tail")
 check(not reply.stream_paused, "end does not pause final one-shots")

 mix.configure(sound_map)
 for i in range(16): mix.play("knock_reply_01", Vector3(0, 1, 7.8))
 mix.play("step_hard_01", listener)
 check(mix.dropped_voices == 1 and mix._voice_ids.all(func(id): return id == "knock_reply_01"), "overflow drops a new step rather than stealing an answer")
 check(mix.get_child_count() == 18, "reconfigure replaces rather than duplicates players")
 for player in mix.voices + mix.devices: player.stop()
 await create_timer(0.15, true, false, true).timeout
 mix.queue_free()
 await process_frame
 print("AUDIO CONFIG/MATH ", checks, " checks, failures ", failures, "; no listening or browser-output claim")
 quit(1 if failures else 0)
