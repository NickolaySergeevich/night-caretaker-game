class_name CaretakerAudio
extends Node3D
## Local, positional sound. No global ambience, bus creation, or jump-scare layer.
## Add to the tree, configure once, then update_devices on each active physics tick.

const VOICE_COUNT := 16
const SILENT_DB := -80.0
const OCCLUSION_SECONDS := 0.18
const DEVICE_SECONDS := 0.60
const DOOR_CROSSFADE_SECONDS := 0.12
const END_FADE_SECONDS := 0.80
const MAX_PHRASE_TAPS := 6
const MAX_PHRASE_SECONDS := 8.0
const PHRASE_PCM_CEILING := 31128 # 0.95 full scale; only attenuate overlaps.
const MAX_PHRASE_CACHE_BYTES := 4 * 1024 * 1024
const WEB_ADAPTER_PATH := "res://scripts/caretaker_web_audio.js"
const WEB_ADAPTER_VERSION := "caretaker-sample-4.6.3-v1"
const DEVICE_IDS := ["dev_printer", "dev_projector"]
const DEVICE_POSITIONS := [Vector3(-4, 1.08, 3.9), Vector3(4.45, 1.18, 3.95)]

var voices: Array[AudioStreamPlayer3D] = []
var devices: Array[AudioStreamPlayer3D] = []
var voice_cursor := 0
var dropped_voices := 0
var reclaimed_voices := 0
var _sounds: Dictionary = {}
var _voice_ids: Array[String] = []
var _busy: Array[bool] = []
var _voice_gains: Array[float] = []
var _voice_fades: Array[float] = []
var _device_gains: Array[float] = [0.0, 0.0]
var _device_targets: Array[float] = [0.0, 0.0]
var _end_start_gains: Array[float] = [0.0, 0.0]
var _listener := Vector3.ZERO
var _room_open := [true, true, true, true]
var _hall_open := true
var _paused := false
var _ending := false
var _end_elapsed := 0.0
var _reply_pcm: Array[PackedInt32Array] = []
var _reply_bytes: Array[PackedByteArray] = []
var _reply_peaks: Array[int] = []
var _reply_rate := 48000
var _phrases: Dictionary = {}
var _slot_tokens: Dictionary = {}
var _last_phrase_token := 0
var phrase_starts := 0
var phrase_cancels := 0
var late_phrases_skipped := 0
var _deferred_starts: Dictionary = {}
var _phrase_cache: Dictionary = {}
var _phrase_cache_bytes := 0
var phrase_cache_hits := 0
var last_compile_usec := 0
var web_sample_active := false
var web_audio_status := "native Stream"
var web_audio_failures := 0

func configure(sound_map: Dictionary) -> void:
 if web_sample_active: _web_call("reset")
 web_sample_active = false
 web_audio_failures = 0
 web_audio_status = "native Stream"
 for player in voices + devices:
  player.stop()
  remove_child(player)
  player.queue_free()
 voices.clear(); devices.clear(); _voice_ids.clear(); _busy.clear()
 _voice_gains.clear(); _voice_fades.clear()
 _sounds = sound_map.duplicate()
 _phrases.clear(); _slot_tokens.clear(); _reply_pcm.clear(); _reply_bytes.clear(); _reply_peaks.clear(); _deferred_starts.clear()
 _phrase_cache.clear(); _phrase_cache_bytes = 0; phrase_cache_hits = 0
 _last_phrase_token = 0; phrase_starts = 0; phrase_cancels = 0; late_phrases_skipped = 0
 _prepare_reply_pcm()
 _prepare_web_samples()
 if _reply_pcm.size() == 3:
  compile_phrase([0.0,.38,.86])
  compile_phrase([0.0,.38,.86],.4)
 voice_cursor = 0; dropped_voices = 0; reclaimed_voices = 0; _ending = false; _end_elapsed = 0.0
 _device_gains = [0.0, 0.0]; _device_targets = [0.0, 0.0]
 set_process(false)
 for i in range(VOICE_COUNT):
  var voice := _new_player()
  voice.finished.connect(_voice_finished.bind(i))
  voices.append(voice); _voice_ids.append(""); _busy.append(false)
  _voice_gains.append(0.0); _voice_fades.append(-1.0)
 for i in range(2):
  var device := _new_player()
  device.position = DEVICE_POSITIONS[i]
  if _sounds.get(DEVICE_IDS[i]) is AudioStreamWAV:
   var stream: AudioStreamWAV = _sounds[DEVICE_IDS[i]].duplicate()
   stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
   stream.loop_begin = 0
   stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
   device.stream = stream
   if web_sample_active: _register_web_stream(device, {})
   device.play(0.000001 if web_sample_active else 0.0)
   _flush_web_start(device)
   device.stream_paused = _paused
  devices.append(device)

func _new_player() -> AudioStreamPlayer3D:
 var player := AudioStreamPlayer3D.new()
 # Native/fallback retain the proven mixer. Exact WEB 4.6.3 opts into Sample
 # only after the separately tested adapter passes its runtime capability gate.
 player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if web_sample_active else AudioServer.PLAYBACK_TYPE_STREAM
 # We apply ONE explicit curve. max_distance > 0 would add a second linear fade.
 player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
 player.max_distance = 0.0
 player.unit_size = 1.0
 player.max_db = 0.0
 player.attenuation_filter_cutoff_hz = 20500.0
 player.panning_strength = 1.0
 player.volume_db = SILENT_DB
 add_child(player)
 return player

static func gain_for(id: String, distance: float, closed_doors: int = 0) -> float:
 if not is_finite(distance): return 0.0
 var base := 0.45
 var falloff := 0.14
 var door_gain := 0.70
 if id.begins_with("knock_reply_"):
  # Restore distant readability, but cap the near field rather than adding
  # a transient/sting. Existing source attacks and the slow falloff remain.
  return minf(0.90, 1.20 / (1.0 + 0.08 * maxf(distance, 0.0))) * pow(0.88, clampi(closed_doors, 0, 2))
 elif id == "chair" or id == "paper":
  base = 0.60; falloff = 0.08; door_gain = 0.82
 elif id.begins_with("step_"): base = 0.22
 elif id == "switch": base = 0.32
 elif id == "breaker" or id == "lock" or id == "unlock": base = 0.38
 elif id.begins_with("door_"): base = 0.40
 elif id.begins_with("dev_"): base = 0.30; door_gain = 0.60
 return base / (1.0 + falloff * maxf(distance, 0.0)) * pow(door_gain, clampi(closed_doors, 0, 2))

func play(id: String, position: Vector3) -> void:
 if _paused or _ending or not position.is_finite() or not (_sounds.get(id) is AudioStream): return
 var slot := _claim_slot(_priority(id))
 # Never steal an in-progress answer to make room for a footstep.
 if slot < 0: return
 if id == "door_open" or id == "door_close":
  for i in range(voices.size()):
   if _busy[i] and (_voice_ids[i] == "door_open" or _voice_ids[i] == "door_close") and voices[i].global_position.distance_to(position) < 0.25:
    _voice_fades[i] = DOOR_CROSSFADE_SECONDS
 _start_voice(slot, id, _sounds[id], position)

static func _priority(id: String) -> int:
 if id.begins_with("knock_reply_"): return 3
 if id == "chair" or id == "paper" or id == "pipe_tick": return 2
 if id.begins_with("step_"): return 0
 return 1

func _claim_slot(priority: int = 0) -> int:
 for offset in range(voices.size()):
  var candidate := (voice_cursor + offset) % voices.size()
  if not _busy[candidate]:
   return candidate
 # A full pool must not silently lose a story cue behind routine contacts.
 # Reclaim the lowest lower-priority class, oldest first; never steal an
 # equal/higher priority cue, and never let footsteps interrupt a reply.
 for lower in range(priority):
  for offset in range(voices.size()):
   var candidate := (voice_cursor + offset) % voices.size()
   if _priority(_voice_ids[candidate]) == lower:
    voices[candidate].stop()
    _voice_finished(candidate)
    reclaimed_voices += 1
    return candidate
 dropped_voices += 1
 return -1

func _start_voice(slot: int, id: String, stream: AudioStream, position: Vector3, seek: float = 0.0) -> void:
 var voice := voices[slot]
 # Web nodes need distinct resource IDs for lifecycle-scoped adapter metadata.
 voice.stream = stream.duplicate() if web_sample_active and not id.begins_with("knock_reply_phrase") else stream
 voice.global_position = position
 _voice_ids[slot] = id; _busy[slot] = true; _voice_fades[slot] = -1.0
 _voice_gains[slot] = _target_gain(id, position)
 _set_gain(voice, _voice_gains[slot])
 if web_sample_active:
  var info := _web_spatial_info(id, position)
  if _slot_tokens.has(slot):
   var phrase: Dictionary = _phrases[_slot_tokens[slot]]
   info.merge({"onsets":Array(phrase.onset_frames),"frames":phrase.duration_frames,"normalization":phrase.normalization})
  var registered := _register_web_stream(voice, info)
  if _slot_tokens.has(slot): _phrases[_slot_tokens[slot]]["web_sample"] = registered
 voice.play(maxf(seek, 0.000001) if web_sample_active else seek)
 _flush_web_start(voice)
 voice_cursor = (slot + 1) % voices.size()

func handle_event(event: Dictionary, simulation_time: float) -> void:
 # State keeps per-hit events for progression/tests. Only the immediately
 # scheduled PCM command owns audible reply playback; never replay late hits.
 var action: String = event.get("audio_action", "")
 if action == "phrase":
  var offsets: Array[float] = []
  for value in event.get("phrase", []): offsets.append(float(value))
  play_phrase(offsets, event.position, float(event.start_time), simulation_time, int(event.token), str(event.get("kind", "reply")))
 elif action == "cancel_phrase":
  cancel_phrase(int(event.token))
 elif not event.has("phrase_token"):
  play(str(event.get("name", "")), event.get("position", Vector3.ZERO))

func _prepare_reply_pcm() -> void:
 for variant in range(1, 4):
  var stream = _sounds.get("knock_reply_%02d" % variant)
  if not stream is AudioStreamWAV or stream.stereo or stream.format != AudioStreamWAV.FORMAT_16_BITS:
   _reply_pcm.clear(); return
  if variant == 1: _reply_rate = stream.mix_rate
  if stream.mix_rate != _reply_rate or stream.data.is_empty() or stream.data.size() % 2 != 0:
   _reply_pcm.clear(); return
  var bytes: PackedByteArray = stream.data
  var samples := PackedInt32Array()
  samples.resize(bytes.size() / 2)
  var peak := 0
  for frame in range(samples.size()):
   samples[frame] = bytes.decode_s16(frame * 2)
   peak = maxi(peak, absi(samples[frame]))
  _reply_pcm.append(samples)
  _reply_bytes.append(bytes)
  _reply_peaks.append(peak)

func compile_phrase(offsets: Array[float], leading_silence: float = 0.0) -> Dictionary:
 # Main-thread preparation only. The audio mixer later consumes one immutable
 # sample timeline, independently of rendering/physics callback frequency.
 var started := Time.get_ticks_usec()
 if _reply_pcm.size() != 3 or offsets.is_empty() or offsets.size() > MAX_PHRASE_TAPS or not is_finite(leading_silence) or leading_silence < 0.0: return {}
 var onsets := PackedInt32Array()
 var last := -1.0
 var total := 0
 for i in range(offsets.size()):
  var offset := offsets[i]
  if not is_finite(offset) or offset < 0.0 or offset < last or offset + leading_silence > MAX_PHRASE_SECONDS: return {}
  last = offset
  var frame := int(round((leading_silence + offset) * _reply_rate))
  onsets.append(frame)
  total = maxi(total, frame + _reply_pcm[i % 3].size())
 if total > int(MAX_PHRASE_SECONDS * _reply_rate): return {}
 var key := str(onsets)
 if _phrase_cache.has(key):
  phrase_cache_hits += 1
  var cached := _instantiate_phrase(_phrase_cache[key])
  last_compile_usec = Time.get_ticks_usec() - started
  return cached
 # Copy intact sample spans with native PackedByteArray operations. Only
 # genuinely overlapping frames need scalar mixing. This avoids walking
 # seconds of silence or re-encoding every non-overlapping source sample.
 var bound := 0
 for i in range(onsets.size()):
  var at_onset := 0
  for j in range(i + 1):
   if onsets[j] + _reply_pcm[j % 3].size() > onsets[i]: at_onset += _reply_peaks[j % 3]
  bound = maxi(bound, at_onset)
 if bound <= PHRASE_PCM_CEILING:
  var fast := _copy_phrase_spans(onsets, total, bound)
  _cache_phrase(key, fast)
  var compiled_fast := _instantiate_phrase(fast)
  last_compile_usec = Time.get_ticks_usec() - started
  return compiled_fast
 var accumulator := PackedInt32Array()
 accumulator.resize(total)
 var peak := 0
 for i in range(onsets.size()):
  var samples: PackedInt32Array = _reply_pcm[i % 3]
  for frame in range(samples.size()):
   accumulator[onsets[i] + frame] += samples[frame]
   peak = maxi(peak, absi(accumulator[onsets[i] + frame]))
 var normalization := minf(1.0, float(PHRASE_PCM_CEILING) / maxf(1.0, peak))
 var prefixes: Array[PackedByteArray] = []
 # Prepare all alternatives before starting playback. Cancellation never does
 # expensive PCM summing while holding the audio-thread lock.
 accumulator.fill(0)
 var bytes := PackedByteArray()
 bytes.resize(total * 2)
 prefixes.append(bytes)
 for i in range(onsets.size()):
  bytes = bytes.duplicate()
  var samples: PackedInt32Array = _reply_pcm[i % 3]
  for frame in range(samples.size()):
   var destination := onsets[i] + frame
   accumulator[destination] += samples[frame]
   bytes.encode_s16(destination * 2, int(round(accumulator[destination] * normalization)))
  prefixes.append(bytes)
 var template := {"onset_frames": onsets, "duration_frames": total, "normalization": normalization, "source_peak_pcm16": peak, "prefixes": prefixes}
 _cache_phrase(key, template)
 var compiled := _instantiate_phrase(template)
 last_compile_usec = Time.get_ticks_usec() - started
 return compiled

func _copy_phrase_spans(onsets: PackedInt32Array, total: int, bound: int) -> Dictionary:
 var bytes := PackedByteArray()
 bytes.resize(total * 2)
 var prefixes: Array[PackedByteArray] = [bytes]
 var previous_end := 0
 for i in range(onsets.size()):
  var source: PackedByteArray = _reply_bytes[i % 3].duplicate()
  var start := onsets[i]
  var end := start + source.size() / 2
  for frame in range(maxi(0, mini(previous_end, end) - start)):
   source.encode_s16(frame * 2, source.decode_s16(frame * 2) + bytes.decode_s16((start + frame) * 2))
  var combined := bytes.slice(0, start * 2)
  combined.append_array(source)
  combined.append_array(bytes.slice(end * 2))
  bytes = combined
  prefixes.append(bytes)
  previous_end = maxi(previous_end, end)
 return {"onset_frames":onsets,"duration_frames":total,"normalization":1.0,"source_peak_pcm16":bound,"source_peak_is_bound":true,"prefixes":prefixes}

func _cache_phrase(key: String, template: Dictionary) -> void:
 var byte_cost: int = template.duration_frames * 2 * template.prefixes.size()
 if byte_cost <= MAX_PHRASE_CACHE_BYTES:
  while not _phrase_cache.is_empty() and (_phrase_cache.size() >= 8 or _phrase_cache_bytes + byte_cost > MAX_PHRASE_CACHE_BYTES):
   var oldest = _phrase_cache.keys()[0]
   _phrase_cache_bytes -= int(_phrase_cache[oldest].duration_frames) * 2 * _phrase_cache[oldest].prefixes.size()
   _phrase_cache.erase(oldest)
  _phrase_cache[key] = template
  _phrase_cache_bytes += byte_cost

func _instantiate_phrase(template: Dictionary) -> Dictionary:
 var compiled := template.duplicate()
 var stream := AudioStreamWAV.new()
 stream.format = AudioStreamWAV.FORMAT_16_BITS
 stream.mix_rate = _reply_rate
 stream.stereo = false
 stream.data = template.prefixes[-1]
 compiled["stream"] = stream
 return compiled

func _accumulate_phrase(onsets: PackedInt32Array, total: int, keep_count: int) -> PackedInt32Array:
 var accumulator := PackedInt32Array()
 accumulator.resize(total)
 for i in range(mini(keep_count, onsets.size())):
  var samples: PackedInt32Array = _reply_pcm[i % 3]
  for frame in range(samples.size()): accumulator[onsets[i] + frame] += samples[frame]
 return accumulator

func _encode_phrase(accumulator: PackedInt32Array, normalization: float) -> PackedByteArray:
 var bytes := PackedByteArray()
 bytes.resize(accumulator.size() * 2)
 for frame in range(accumulator.size()): bytes.encode_s16(frame * 2, int(round(accumulator[frame] * normalization)))
 return bytes

func play_phrase(offsets: Array[float], position: Vector3, start_time: float, simulation_time: float, token: int, kind: String = "reply") -> bool:
 if _paused or _ending or token <= _last_phrase_token or not position.is_finite() or not is_finite(start_time) or not is_finite(simulation_time): return false
 var leading := maxf(0.0, start_time - simulation_time)
 var seek := maxf(0.0, simulation_time - start_time)
 var compiled := compile_phrase(offsets, leading)
 if compiled.is_empty(): return false
 _last_phrase_token = token
 if seek >= compiled.stream.get_length():
  late_phrases_skipped += 1
  return false
 var slot := _claim_slot(3)
 if slot < 0: return false
 compiled["slot"] = slot; compiled["kind"] = kind; compiled["cancelled"] = false
 compiled["seek"] = seek
 _phrases[token] = compiled
 _slot_tokens[slot] = token
 _start_voice(slot, "knock_reply_phrase", compiled.stream, position, seek)
 phrase_starts += 1
 return true

func cancel_phrase(token: int) -> void:
 if not _phrases.has(token) or _phrases[token].cancelled: return
 var record: Dictionary = _phrases[token]
 var slot: int = record.slot
 var voice := voices[slot]
 if web_sample_active and bool(record.get("web_sample", false)):
  var result = _web_call("cancel", [str(record.stream.get_instance_id())])
  if not _valid_web_cancel(result, record):
   web_audio_failures += 1
   web_audio_status = "Sample cancellation failed: voice stopped"
   push_warning("WEB phrase cancellation unavailable; stopping rather than replaying future hits")
   voice.stop(); _voice_finished(slot)
   return
  record.cancelled = true
  record["cancel_frontier_frames"] = int(result.frontier)
  record["kept_taps"] = int(result.keep)
  phrase_cancels += 1
  if int(result.keep) == 0:
   voice.stop(); _voice_finished(slot)
  return
 # WAV playback reports its mixer read frontier, not the speaker position.
 # Keep any tap whose attack may already be mixed; queued output cannot be
 # taken back. Replacing unique PCM preserves this playback's cursor and
 # current complete tap tails. No stop/seek/restart gap, no frame-based fade.
 AudioServer.lock()
 var playback := voice.get_stream_playback() if voice.has_stream_playback() else null
 var cursor: float = playback.get_playback_position() if playback != null and playback.is_playing() else 0.0
 var frontier := maxi(0, int(round(cursor * _reply_rate)))
 var keep := 0
 for onset in record.onset_frames:
  if onset < frontier: keep += 1
 record.stream.data = record.prefixes[keep]
 AudioServer.unlock()
 record.cancelled = true
 record["cancel_frontier_frames"] = frontier
 record["kept_taps"] = keep
 phrase_cancels += 1
 if keep == 0:
  voice.stop()
  _voice_finished(slot)
  return

func update_devices(state, listener_position: Vector3, dt: float) -> void:
 if _paused or not listener_position.is_finite() or not is_finite(dt) or dt <= 0.0: return
 _listener = listener_position
 _room_open = state.room_open.duplicate()
 _hall_open = state.door_open
 for i in range(devices.size()):
  var enabled: bool = state.printer_on if i == 0 else state.projector_on
  _device_targets[i] = _target_gain(DEVICE_IDS[i], devices[i].global_position) if enabled and not _ending else 0.0
  if not _ending:
   _device_gains[i] = lerpf(_device_gains[i], _device_targets[i], 1.0 - exp(-dt / DEVICE_SECONDS))
   _set_gain(devices[i], _device_gains[i])
 _advance_voices(dt)

func _target_gain(id: String, position: Vector3) -> float:
 # Original mix used horizontal distance; eye height must not mute nearby steps.
 var distance := Vector2(position.x - _listener.x, position.z - _listener.z).length()
 return gain_for(id, distance, _closed_doors(position, _listener))

static func _room_at(position: Vector3) -> int:
 if position.z < -3.5 or position.z > 5.5: return -1
 if position.x < -1.7: return 0 if position.z > 1.0 else 1
 if position.x > 1.7: return 2 if position.z > 1.0 else 3
 return -1

func _closed_doors(source: Vector3, listener: Vector3) -> int:
 var count := 0
 if not _hall_open and (source.z < -6.0) != (listener.z < -6.0): count += 1
 var source_room := _room_at(source)
 var listener_room := _room_at(listener)
 if source_room != listener_room:
  if source_room >= 0 and not _room_open[source_room]: count += 1
  if listener_room >= 0 and not _room_open[listener_room]: count += 1
 return mini(count, 2)

func _advance_voices(dt: float) -> void:
 for i in range(voices.size()):
  if not _busy[i]: continue
  if _voice_fades[i] >= 0.0:
   var previous := _voice_fades[i]
   _voice_fades[i] = maxf(0.0, previous - dt)
   _voice_gains[i] *= _voice_fades[i] / maxf(previous, 0.00001)
   if _voice_fades[i] <= 0.0:
    voices[i].stop(); _voice_finished(i)
  else:
   var target := _target_gain(_voice_ids[i], voices[i].global_position)
   _voice_gains[i] = lerpf(_voice_gains[i], target, 1.0 - exp(-dt / OCCLUSION_SECONDS))
  _set_gain(voices[i], _voice_gains[i])
  if web_sample_active and _voice_ids[i].begins_with("knock_reply_") and voices[i].stream != null:
   var info := _web_spatial_info(_voice_ids[i], voices[i].global_position)
   _web_call("update", [str(voices[i].stream.get_instance_id()), info.position, info.closed])

func _voice_finished(index: int) -> void:
 if web_sample_active and voices[index].stream != null:
  _web_call("release", [str(voices[index].stream.get_instance_id())])
 _deferred_starts.erase(index)
 if _slot_tokens.has(index):
  _phrases.erase(_slot_tokens[index])
  _slot_tokens.erase(index)
 _busy[index] = false; _voice_gains[index] = 0.0; _voice_fades[index] = -1.0

func pause(paused: bool) -> void:
 _paused = paused
 if web_sample_active:
  for player in voices + devices: player.stream_paused = paused
  return
 # AudioStreamPlayer3D.play is queued until a physics tick. Its pause setter
 # cannot reliably pause a playback which AudioServer has not registered yet.
 # Preserve those queued starts explicitly, instead of leaking sound in pause.
 for i in range(voices.size() + devices.size()):
  var key := i if i < voices.size() else -(i - voices.size()) - 1
  var player: AudioStreamPlayer3D = voices[i] if i < voices.size() else devices[i - voices.size()]
  if paused:
   var playback := player.get_stream_playback() if player.has_stream_playback() else null
   if player.playing and (playback == null or not playback.is_playing()):
    _deferred_starts[key] = player.get_playback_position()
    player.stop()
   else: player.stream_paused = true
  else:
   if _deferred_starts.has(key):
    player.play(float(_deferred_starts[key]))
    _deferred_starts.erase(key)
   else: player.stream_paused = false

func stop_devices() -> void:
 if _ending: return
 _ending = true; _end_elapsed = 0.0
 _end_start_gains = _device_gains.duplicate()
 _device_targets = [0.0, 0.0]
 # Finish the quiet fan tail even when the main game has opened its end panel.
 set_process(true)

func _process(dt: float) -> void:
 if not _ending or _paused or not is_finite(dt) or dt <= 0.0: return
 _end_elapsed += dt
 var remaining := clampf(1.0 - _end_elapsed / END_FADE_SECONDS, 0.0, 1.0)
 var envelope := remaining * remaining * (3.0 - 2.0 * remaining)
 for i in range(devices.size()):
  _device_gains[i] = _end_start_gains[i] * envelope
  _set_gain(devices[i], _device_gains[i])
  if remaining == 0.0: devices[i].stop()
 _advance_voices(dt)
 if remaining == 0.0: set_process(false)

func _set_gain(player: AudioStreamPlayer3D, gain: float) -> void:
 player.volume_db = maxf(SILENT_DB, linear_to_db(maxf(gain, 0.0001)))

func _prepare_web_samples() -> void:
 if not OS.has_feature("web"): return
 web_audio_status = "Stream fallback: Sample adapter unavailable"
 var version := Engine.get_version_info()
 if int(version.major) != 4 or int(version.minor) != 6 or int(version.patch) != 3: return
 if _reply_pcm.size() != 3 or not FileAccess.file_exists(WEB_ADAPTER_PATH): return
 var source := FileAccess.get_file_as_string(WEB_ADAPTER_PATH)
 var installed = JavaScriptBridge.eval(source, false)
 if not installed is bool or not installed: return
 var encoded: Array[String] = []
 for bytes in _reply_bytes: encoded.append(Marshalls.raw_to_base64(bytes))
 var prepared = _web_call("setup", [_reply_rate, encoded, true])
 if not prepared is bool or not prepared: return
 web_sample_active = true
 web_audio_status = WEB_ADAPTER_VERSION

func _web_call(method: String, arguments: Array = []):
 # JSON is the sole data boundary. No interpolated caller text is executable.
 var params: Array[String] = []
 for value in arguments: params.append(JSON.stringify(value))
 var code := "JSON.stringify(GodotAudio.caretaker.%s(%s))" % [method, ",".join(params)]
 var result = JavaScriptBridge.eval(code, false)
 return JSON.parse_string(result) if result is String else null

func _valid_web_cancel(result, record: Dictionary) -> bool:
 if not result is Dictionary: return false
 var ok = result.get("ok")
 var keep = result.get("keep")
 var frontier = result.get("frontier")
 if not ok is bool or not ok: return false
 if not (keep is int or keep is float) or not (frontier is int or frontier is float): return false
 return is_finite(float(keep)) and is_finite(float(frontier)) and float(keep) == floorf(float(keep)) and float(frontier) == floorf(float(frontier)) and keep >= 0 and keep <= record.onset_frames.size() and frontier >= 0 and frontier <= record.duration_frames

func _register_web_stream(player: AudioStreamPlayer3D, info: Dictionary) -> bool:
 var response = _web_call("register", [str(player.stream.get_instance_id()), info])
 var registered: bool = response is bool and response
 player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if registered else AudioServer.PLAYBACK_TYPE_STREAM
 if not registered:
  web_audio_failures += 1
  web_audio_status = "Stream fallback: Sample registration failed"
  push_warning(web_audio_status)
 return registered

func _flush_web_start(player: AudioStreamPlayer3D) -> void:
 if web_sample_active:
  # Stock Sample begins asynchronously, but initial 3D gains wait for physics.
  # Flush that standard notification now, before a long render can mute attack 1.
  player.notification(NOTIFICATION_INTERNAL_PHYSICS_PROCESS)

func _web_spatial_info(id: String, position: Vector3) -> Dictionary:
 # The owner's liked door timbre and device loops are deliberately untouched.
 # Steps use the shared softened source WAVs, without a second browser filter.
 # Other existing softening remains reproducible browser-buffer processing.
 if not id.begins_with("knock_reply_"):
  if id.begins_with("door_") or id.begins_with("dev_") or id.begins_with("step_"): return {}
  var cutoff := 4700.0
  var attack := 0.010
  if id == "switch" or id == "breaker" or id == "lock" or id == "unlock":
   cutoff = 3400.0; attack = 0.006
  return {"softKey":id,"cutoff":cutoff,"attack":attack}
 var relative := position - _listener
 var camera := get_viewport().get_camera_3d()
 if camera != null: relative = camera.global_transform.affine_inverse() * position
 return {"spatial":AudioServer.get_speaker_mode() == AudioServer.SPEAKER_MODE_STEREO,"position":[relative.x,relative.y,relative.z],"closed":_closed_doors(position,_listener)>0,"softKey":id,"cutoff":5200.0,"attack":0.008}

func _exit_tree() -> void:
 for player in voices + devices: player.stop()
 if web_sample_active: _web_call("reset")
