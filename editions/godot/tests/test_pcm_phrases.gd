extends SceneTree
const Audio = preload("res://scripts/caretaker_audio.gd")
const Shift = preload("res://scripts/shift.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(label)
 else: print("PASS: ", label)
func _initialize() -> void: call_deferred("run")
func impulse(variant: int) -> AudioStreamWAV:
 var stream := AudioStreamWAV.new()
 stream.format = AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate = 48000
 var bytes := PackedByteArray(); bytes.resize(64)
 bytes.encode_s16((8 + variant * 4) * 2, 12000)
 stream.data = bytes
 return stream
func peak(bytes: PackedByteArray) -> int:
 var value := 0
 for offset in range(0, bytes.size(), 2): value = maxi(value, absi(bytes.decode_s16(offset)))
 return value
func advance(s: CaretakerShift, seconds: float) -> void:
 for i in range(int(round(seconds / .01))): s.step(.01, Vector3(0,0,-4.5))
func run() -> void:
 var mix := Audio.new(); root.add_child(mix)
 var fixtures := {}
 for i in range(3): fixtures["knock_reply_%02d" % (i + 1)] = impulse(i)
 fixtures["step_hard_01"] = fixtures["knock_reply_01"]
 mix.configure(fixtures)
 var rhythm: Array[float] = [0.0, .38, .86]
 var compiled: Dictionary = mix.compile_phrase(rhythm, .4)
 check(not compiled.is_empty(), "phrase compiles from PCM16 sources")
 check(compiled.onset_frames == PackedInt32Array([19200,37440,60480]), "0.4-second delay and internal intervals are exact 48k PCM frame offsets")
 var expected := PackedInt32Array([19208,37452,60496])
 var detected := PackedInt32Array()
 var bytes: PackedByteArray = compiled.stream.data
 for frame in range(bytes.size() / 2):
  if bytes.decode_s16(frame * 2) != 0: detected.append(frame)
 check(detected == expected, "only the three exact expected impulse onset samples exist")
 check(compiled.prefixes.size() == 4, "cancel alternatives include zero through all taps")
 for count in range(4):
  var prefix_bytes: PackedByteArray = compiled.prefixes[count]
  check(prefix_bytes.size() == bytes.size(), "cancel prefix %d preserves stream length" % count)
  for i in range(3): check(prefix_bytes.decode_s16(expected[i] * 2) == (12000 if i < count else 0), "prefix %d retains exactly started tap %d" % [count,i])
 check(fixtures.knock_reply_01.data.size() == 64, "compilation never overwrites the original sample")
 check(mix.compile_phrase([0.0,NAN]).is_empty() and mix.compile_phrase([.2,.1]).is_empty(), "nonfinite and reversed rhythms are rejected")
 check(mix.compile_phrase([0.,.1,.2,.3,.4,.5,.6]).is_empty() and mix.compile_phrase([0.0],9).is_empty(), "tap count and allocation duration are bounded")

 check(mix.play_phrase(rhythm,Vector3(0,1,13),10.4,10.0,1), "phrase claims one positional voice immediately at schedule time")
 check(mix._busy.count(true) == 1 and mix.voices[0].playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "all phrase taps use exactly one Stream player")
 var original_stream: AudioStream = mix.voices[0].stream
 mix.handle_event({"name":"knock_reply_01","position":Vector3.ZERO,"phrase_token":1},10.4)
 check(mix._busy.count(true) == 1, "logical per-hit observability cannot duplicate audio")
 check(not mix.play_phrase(rhythm,Vector3.ZERO,10,10,1) and mix.voices[0].stream == original_stream, "duplicate token does not restart or overwrite an active phrase")
 mix.pause(true)
 check(mix._deferred_starts.has(0) and not mix.voices[0].playing, "immediate pause cancels the queued start but retains its exact offset")
 await physics_frame; await physics_frame
 check(not mix.voices[0].playing, "queued phrase cannot leak through the next physics tick while paused")
 mix.pause(false)
 check(mix.voices[0].stream == original_stream and mix.voices[0].playing, "resume requeues the same complete phrase")
 mix.cancel_phrase(1)
 check(not mix._busy[0] and not mix._phrases.has(1), "cancel before actual playback does not invent a partial tail")
 check(mix.play_phrase(rhythm,Vector3.ZERO,10,10.5,2), "partially late phrase remains playable")
 check(is_equal_approx(mix._phrases[2].seek,.5) and is_equal_approx(mix.voices[mix._phrases[2].slot].get_playback_position(),.5), "late command seeks to its real elapsed offset instead of replaying missed time")
 check(not mix.play_phrase(rhythm,Vector3.ZERO,10,15,3) and mix.late_phrases_skipped == 1, "fully expired phrase is skipped, not spread into the future")
 mix.cancel_phrase(2)

 var sounds := {}
 for i in range(1,4): sounds["knock_reply_%02d" % i] = load("res://data/audio/knock_reply_%02d.wav" % i)
 sounds["door_close"] = AudioStreamWAV.load_from_file("res://data/audio/door_close.wav", {"compress/mode":0})
 sounds["step_hard_01"] = load("res://data/audio/step_hard_01.wav")
 mix.configure(sounds)
 var dense: Array[float] = [0.0,.08,.16,.24,.32,.40]
 var overlap := mix.compile_phrase(dense)
 check(not overlap.is_empty() and peak(overlap.stream.data) < 31128, "six authentic overlapping taps remain below the PCM ceiling")
 if overlap.is_empty(): quit(1); return
 check(is_equal_approx(overlap.normalization,1), "authentic six-tap phrase does not need attack-altering normalization")
 var phrase_data: PackedByteArray = overlap.stream.data
 var door_data: PackedByteArray = sounds.door_close.data
 var stress_peak := 0.0
 for frame in range(maxi(phrase_data.size(),door_data.size()) / 2):
  var value := 0.0
  if frame*2 < phrase_data.size(): value += float(phrase_data.decode_s16(frame*2)) / 32768 * .90
  if frame*2 < door_data.size(): value += float(door_data.decode_s16(frame*2)) / 32768 * .40
  stress_peak = maxf(stress_peak,absf(value))
 check(stress_peak < .9, "near-field six-tap phrase plus final door has unclipped scalar headroom before Master")
 print("PCM OVERLAP peak before Master/pan ",linear_to_db(stress_peak)," dBFS; source arithmetic, not listening")
 for offsets in [[0.0,.38,.86],[0.0,.271,.743],[0.0,.08,.16,.24,.32,.40],[0.0,.99,1.98,2.97,3.96,4.95]]:
  var pattern: Array[float] = []
  for value in offsets: pattern.append(value)
  var timed := mix.compile_phrase(pattern,.4)
  var cold_usec: int = mix.last_compile_usec
  var second := mix.compile_phrase(pattern,.4)
  print("PCM COMPILE offsets=",pattern," first_usec=",cold_usec," cached_usec=",mix.last_compile_usec," cache_bytes=",mix._phrase_cache_bytes)
  check(not timed.is_empty() and second.stream != timed.stream and second.stream.data == timed.stream.data, "cache shares immutable PCM but not mutable active WAV resources")
 check(mix._phrase_cache_bytes <= Audio.MAX_PHRASE_CACHE_BYTES, "phrase cache has an explicit 4 MiB bound")
 check(mix.play_phrase(rhythm,Vector3.ZERO,0,0,1), "authentic phrase starts")
 var held: AudioStream = mix.voices[0].stream
 for i in range(15): mix.play("step_hard_01",Vector3.ZERO)
 mix.play("step_hard_01",Vector3.ZERO)
 check(mix._busy.count(true) == 16 and mix.dropped_voices == 1 and mix.voices[0].stream == held, "full pool drops extra step without evicting or overwriting phrase")
 check(mix.play_phrase(rhythm,Vector3.ZERO,0,0,2) and mix.voices[0].stream == held and mix._phrases.has(1), "a second phrase reclaims only a lower-priority contact, preserving the first answer")

 var s := Shift.new(); s.keys=true; s.phase=Shift.Phase.INVESTIGATE; s.door_open=false
 s.taps=[0.0,.38,.86]; s.time=.86; s.last_tap=.86
 advance(s,1.01)
 var commands: Array = s.events.filter(func(e):return e.get("audio_action","")=="phrase")
 check(commands.size()==1 and commands[0].start_time>s.time, "state emits the PCM command before the delayed first hit")
 var token: int = commands[0].token
 advance(s,1.4)
 var hits: Array = s.events.filter(func(e):return e.has("phrase_token"))
 check(hits.size()==3 and hits.all(func(e):return e.phrase_token==token), "state retains every logical per-hit event with its shared token")
 check(not s.reply_active and s.events.filter(func(e):return e.get("audio_action","")=="cancel_phrase").is_empty(), "natural logical completion never cancels the last PCM tail")
 var manual := Shift.new(); manual.keys=true; manual.phase=Shift.Phase.INVESTIGATE; manual.door_open=false
 manual.knock(Vector3(0,0,-4.5),true); advance(manual,1.05); manual.events.clear()
 manual.interact("hall_door",Vector3(0,0,-4.5))
 check(manual.events.filter(func(e):return e.get("audio_action","")=="cancel_phrase").size()==1, "manual opening emits exactly one cancellation command")
 check(manual.last_phrase==[0.0,.38,.86], "cancel before first reply preserves the original remembered phrase")

 var opening := Shift.new(); opening.keys=true; opening.phase=Shift.Phase.INVESTIGATE; opening.door_open=false
 opening.schedule_phrase(rhythm,Vector3(0,1,-8),0,"initial")
 var initial_token: int = opening.phrase_serial
 opening.events.clear(); opening.interact("hall_door",Vector3(0,0,-4.5))
 check(opening.scheduled.size()==3 and opening.scheduled.all(func(e):return e.token==initial_token), "ordinary hall opening preserves the original initial phrase")
 check(opening.events.filter(func(e):return e.get("audio_action","")=="cancel_phrase").is_empty(), "hall opening does not invent an initial-phrase cancellation")
 var fast_exit := Shift.new(); fast_exit.keys=true; fast_exit.phase=Shift.Phase.JOURNAL
 fast_exit.schedule_phrase(rhythm,Vector3(0,1,-8),.1,"initial")
 fast_exit.schedule_phrase(rhythm,Vector3(-2,1,7.8),.4,"post")
 fast_exit.events.clear(); fast_exit.interact("journal",Vector3.ZERO); fast_exit.interact("exit",Vector3.ZERO)
 var exit_cancels: Array = fast_exit.events.filter(func(e):return e.get("audio_action","")=="cancel_phrase")
 check(fast_exit.phase==Shift.Phase.END and fast_exit.scheduled.is_empty(), "fast journal and exit clear future logical hits")
 check(exit_cancels.size()==2 and exit_cancels[0].token!=exit_cancels[1].token, "fast exit cancels every distinct pending initial/post PCM token exactly once")
 check(fast_exit.events[-1].get("name","")=="door_close", "exit cancellations are dispatched before the final door, never after")
 var partial_exit := Shift.new(); partial_exit.keys=true; partial_exit.phase=Shift.Phase.JOURNAL
 partial_exit.schedule_phrase(rhythm,Vector3(-2,1,7.8),.4,"post")
 advance(partial_exit,.41); partial_exit.events.clear()
 partial_exit.interact("journal",Vector3.ZERO); partial_exit.interact("exit",Vector3.ZERO)
 check(partial_exit.events.filter(func(e):return e.get("audio_action","")=="cancel_phrase").size()==1, "exit after the first post hit removes only future attacks through one tail-preserving command")
 var natural_exit := Shift.new(); natural_exit.keys=true; natural_exit.phase=Shift.Phase.JOURNAL
 natural_exit.schedule_phrase(rhythm,Vector3(-2,1,7.8),.4,"post")
 advance(natural_exit,1.27)
 check(natural_exit.events.filter(func(e):return e.has("phrase_token")).size()==3 and natural_exit.scheduled.is_empty(), "the natural final post hit leaves no scheduled attacks")
 natural_exit.events.clear(); natural_exit.interact("journal",Vector3.ZERO); natural_exit.interact("exit",Vector3.ZERO)
 check(natural_exit.events.filter(func(e):return e.get("audio_action","")=="cancel_phrase").is_empty(), "exit after the natural last post hit never cuts its still-playing tail")

 await physics_frame; await physics_frame
 mix.set_process(false)
 for player in mix.voices+mix.devices: player.stop()
 await create_timer(.15,true,false,true).timeout
 mix.queue_free(); await process_frame; await process_frame
 print("PCM PHRASES ",checks," checks, failures ",failures,"; no listening/WEB claim")
 quit(1 if failures else 0)
