extends SceneTree
# Regression contracts for quiet event timing and truthful optional objectives.
# This checks state, queued source positions and callbacks, not perception or listening.
# Run: godot --headless --audio-driver Dummy --path godot --script res://tests/test_event_readability.gd
const Shift = preload("res://scripts/shift.gd")
const Main = preload("res://scripts/main.gd")
const POST := Vector3(-2, 1, 7.8)
const HALL_SOURCE := Vector3(0, 1, -8)
const HALL_LISTENER := Vector3(0, 0, -4.5)
const SHEET := Vector3(-3.55, 0, .93)
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error("EVENT READABILITY: " + label)
 else:
  print("PASS: ", label)

func collect(s: CaretakerShift, trace: Array[Dictionary]) -> void:
 for event in s.events:
  if event.has("audio_action"): continue
  var entry: Dictionary = event.duplicate(true)
  entry["at"] = s.time
  trace.append(entry)
 s.events.clear()

func advance(s: CaretakerShift, seconds: float, position: Vector3, trace: Array[Dictionary], looking_hall: bool = false) -> void:
 var steps := maxi(1, int(ceil(seconds / .01)))
 for i in range(steps):
  s.step(seconds / steps, position, looking_hall)
  collect(s, trace)

func named(trace: Array[Dictionary], id: String) -> Array[Dictionary]:
 return trace.filter(func(event: Dictionary) -> bool: return event.name == id)

func prefix(trace: Array[Dictionary], id: String) -> Array[Dictionary]:
 return trace.filter(func(event: Dictionary) -> bool: return str(event.name).begins_with(id))

func return_ready() -> CaretakerShift:
 var s := Shift.new()
 s.keys = true
 s.phase = Shift.Phase.RETURN
 s.room_visited.fill(true)
 s.room_light.fill(false)
 s.room_open.fill(false)
 s.room_locked.fill(true)
 s.printer_on = false
 s.projector_on = false
 s.hall_checked = true
 s.hall_secured = true
 s.hall_on = false
 s.door_open = false
 s.door_locked = true
 return s

func investigated() -> CaretakerShift:
 var s := Shift.new()
 s.keys = true
 s.phase = Shift.Phase.INVESTIGATE
 s.door_open = false
 s.door_locked = true
 return s

func test_relay_and_library() -> void:
 var s := return_ready()
 var trace: Array[Dictionary] = []
 check(s.ordinary_complete(), "relay fixture has a genuinely completed ordinary shift")
 advance(s, .2, Vector3(0, 0, 5), trace)
 check(s.phase == Shift.Phase.RETURN and trace.is_empty(), "no automatic relay before returning to the post")
 advance(s, .02, Vector3(0, 0, 7.2), trace)
 check(s.phase == Shift.Phase.CLASS_RECHECK and s.projector_on, "RETURN becomes CLASS_RECHECK and restores the projector")
 check(trace.size() == 1 and trace[0].name == "switch", "restart queues exactly one existing household switch sound")
 check(trace.size() == 1 and trace[0].position == Vector3(4.45, 1.18, 3.95), "restart sound belongs to the projector, not the listener")
 advance(s, .5, Vector3(0, 0, 7.2), trace)
 advance(s, .1, Vector3(0, 0, 5), trace)
 advance(s, .1, Vector3(0, 0, 7.2), trace)
 check(named(trace, "switch").size() == 1, "waiting and revisiting the post do not repeat the relay")

 trace.clear()
 s.interact("projector", Vector3(3.3, 0, 3.1))
 collect(s, trace)
 check(s.projector_cut and not s.projector_on and s.phase == Shift.Phase.LIBRARY_RECHECK, "cutting the restarted projector advances the preserved library event")
 check(trace.size() == 3 and trace[0].name == "switch" and trace[1].name == "chair" and trace[2].name == "paper", "projector cutoff preserves switch, chair and paper in original order")
 check(named(trace, "chair").size() == 1 and named(trace, "chair")[0].position == Vector3(-2.95, 1, -2.2), "original chair event retains its library source")
 check(named(trace, "paper").size() == 1 and named(trace, "paper")[0].position == Vector3(-3.55, 1, .93), "original paper event retains its library source")
 check(not s.paper_near_heard, "remote paper event does not consume the separate proximity rustle")
 s.interact("projector", Vector3(3.3, 0, 3.1))
 collect(s, trace)
 check(trace.size() == 3, "repeated interaction with the unplugged projector does not replay the library event")

 trace.clear()
 advance(s, .2, SHEET, trace)
 check(trace.is_empty() and not s.paper_near_heard, "proximity does not rustle through the closed library door")
 s.interact("door_1", Vector3(-1.4, 0, -1))
 s.events.clear()
 advance(s, .2, Vector3(-4.2, 0, -2.5), trace)
 check(trace.is_empty() and not s.paper_near_heard, "an open library alone is insufficient when the sheet is distant")
 advance(s, .02, SHEET, trace)
 check(s.paper_near_heard and named(trace, "paper").size() == 1, "approaching the sheet through the open library queues one local rustle")
 check(trace.size() == 1 and trace[0].position == Vector3(-3.55, 1.55, .93), "local rustle comes from the attached sheet and adds no other cue")
 advance(s, .5, SHEET, trace)
 advance(s, .1, Vector3(-4.2, 0, -2.5), trace)
 advance(s, .1, SHEET, trace)
 s.interact("door_1", SHEET)
 s.interact("door_1", SHEET)
 s.events.clear()
 advance(s, .2, SHEET, trace)
 check(named(trace, "paper").size() == 1, "waiting, leaving, returning and reopening cannot repeat the local rustle")
 check(named(trace, "chair").is_empty(), "the local rustle does not repeat the original chair movement")
 advance(s, .02, Vector3(0, 0, .35), trace)
 check(s.phase == Shift.Phase.FUSE and not s.corridor_power, "the existing library exit still advances to the fuse task")

 var ordinary := Shift.new()
 ordinary.keys = true
 ordinary.phase = Shift.Phase.INSPECT
 ordinary.interact("projector", Vector3.ZERO)
 check(ordinary.events.size() == 1 and ordinary.events[0].name == "switch", "ordinary projector shutdown does not prematurely emit chair or paper")
 var early := Shift.new()
 early.keys = true
 early.phase = Shift.Phase.CLASS_RECHECK
 early.step(.02, SHEET)
 check(not early.paper_near_heard and early.events.is_empty(), "the nearby sheet is silent before its library phase")

func test_full_post_reply() -> void:
 var s := investigated()
 var trace: Array[Dictionary] = []
 var rhythm: Array[float] = [0.0, .23, .77]
 s.knock(HALL_LISTENER, true)
 collect(s, trace)
 for i in range(1, rhythm.size()):
  advance(s, rhythm[i] - rhythm[i - 1], HALL_LISTENER, trace)
  s.knock(HALL_LISTENER, true)
  collect(s, trace)
 check(prefix(trace, "knock_player_").size() == 3, "three deliberate player taps are accepted")
 advance(s, 2.3, HALL_LISTENER, trace)
 check(s.last_phrase.size() == rhythm.size(), "a completed hall answer remembers every tap")
 for i in range(mini(s.last_phrase.size(), rhythm.size())):
  check(absf(s.last_phrase[i] - rhythm[i]) < .00001, "heard answer retains player rhythm offset %d" % i)
 var hall_reply := prefix(trace, "knock_reply_")
 check(hall_reply.size() == 3 and hall_reply.all(func(e: Dictionary) -> bool: return e.position == HALL_SOURCE), "the first full answer is emitted from inside the hall")
 check(not s.reply_active and s.scheduled.is_empty(), "completed hall answer leaves no pending duplicate")

 s.interact("hall_door", HALL_LISTENER)
 s.events.clear()
 trace.clear()
 var door_view := Vector3(0, 0, -5.2)
 s.step(.01, door_view, false)
 check(s.phase == Shift.Phase.INVESTIGATE and s.scheduled.is_empty(), "opening without looking into the hall does not trigger the post reply")
 s.step(.01, door_view, true)
 collect(s, trace)
 var scheduled_at := s.time
 check(s.phase == Shift.Phase.JOURNAL and s.scheduled.size() == rhythm.size(), "looking into the open hall schedules the complete remembered rhythm at the post")
 check(s.scheduled.all(func(e: Dictionary) -> bool: return e.kind == "post" and e.position == POST), "post answer keeps its mundane distant desk source")
 check(trace.is_empty(), "post answer is delayed rather than an immediate sting")
 advance(s, .39, door_view, trace, true)
 check(trace.is_empty(), "the original 0.4-second post delay is preserved")
 advance(s, 1.0, door_view, trace, true)
 var post_reply := prefix(trace, "knock_reply_")
 check(post_reply.size() == rhythm.size() and trace.size() == rhythm.size(), "all post taps complete with no added sound or scare event")
 for i in range(mini(post_reply.size(), rhythm.size())):
  check(post_reply[i].name == "knock_reply_%02d" % (i + 1), "post reply uses the existing tap asset %d" % i)
  check(post_reply[i].position == POST, "post tap %d retains the distant position" % i)
  check(absf(post_reply[i].at - (scheduled_at + .4 + rhythm[i])) <= .011, "post tap %d retains its scheduled rhythm within one simulation step" % i)
 check(Vector2(POST.x - door_view.x, POST.z - door_view.z).length() > 13.0, "the post reply is tested from the actual distant hall doorway")
 advance(s, 2, door_view, trace, true)
 check(trace.size() == rhythm.size() and s.scheduled.is_empty() and s.phase == Shift.Phase.JOURNAL, "staying at the hall does not loop the reply or invent a new finale phase")

 var no_taps := investigated()
 no_taps.interact("hall_door", HALL_LISTENER)
 no_taps.events.clear()
 var original: Array[Dictionary] = []
 advance(no_taps, 1.4, door_view, original, true)
 check(original.size() == 3 and original.all(func(e: Dictionary) -> bool: return e.position == POST and str(e.name).begins_with("knock_reply_")), "without player taps the original three-tap post phrase is retained")

func test_journal_state() -> void:
 for selected in [false, true]:
  var s := Shift.new()
  s.keys = true
  s.phase = Shift.Phase.JOURNAL
  s.time = 3661.25
  s.choice = selected
  s.interact("journal", POST)
  var written_at := s.note_time
  check(s.note and s.phase == Shift.Phase.EXIT and is_equal_approx(written_at, 3661.25), "journal choice %s captures simulation time once" % selected)
  var trace: Array[Dictionary] = []
  advance(s, 2.5, Vector3(0, 0, 8), trace)
  s.interact("journal", POST)
  check(is_equal_approx(s.note_time, written_at) and s.choice == selected, "later state time and repeated journal interaction cannot rewrite choice %s" % selected)
  s.interact("exit", Vector3(0, 0, 9))
  check(s.phase == Shift.Phase.END and s.events.size() == 1 and s.events[0].name == "door_close", "choice %s ends with the existing final door only" % selected)
  var ended_at := s.time
  s.step(.1, Vector3.ZERO)
  s.interact("journal", POST)
  check(s.time == ended_at and s.note_time == written_at and s.choice == selected, "END freezes the recorded time and choice %s" % selected)

func test_optional_goals() -> void:
 var s := Shift.new()
 var forbidden: Array[String] = ["проектор", "включил", "включён", "включен", "сам собой", "снова", "стул", "лист", "шорох", "скрип", "стук", "стуч", "слыш", "ответ", "кто-то", "пуг"]
 for phase in [Shift.Phase.CLASS_RECHECK, Shift.Phase.LIBRARY_RECHECK, Shift.Phase.INVESTIGATE]:
  s.phase = phase
  var goal := s.short_goal().to_lower()
  check(not goal.is_empty() and (goal.contains("провер") or goal.contains("осмотр")), "optional goal %d gives an actionable duty" % phase)
  var claims: Array[String] = []
  for word in forbidden:
   if goal.contains(word): claims.append(word)
  check(claims.is_empty(), "optional goal %d does not name or assert an unseen event: %s" % [phase, str(claims)])
  var event_count := s.events.size()
  var pending_count := s.scheduled.size()
  s.short_goal()
  check(s.events.size() == event_count and s.scheduled.size() == pending_count, "reading goal %d does not cause a cue" % phase)

func test_pause_and_journal_callbacks() -> void:
 var game := Main.new()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 game.set_process_unhandled_input(false)
 await process_frame
 game.shift.time = 12.5
 game.building.sync(game.shift, 0)
 var clock_before: float = game.building.clock_hands[2].rotation.z
 var paper_before: float = game.building.paper_material.get_shader_parameter("paper_time")
 var phrase: Array[float] = [0.0, .2]
 game.shift.schedule_phrase(phrase, HALL_SOURCE, .05, "initial")
 game.shift.events.clear() # The immediate audio command is tested separately.
 var scheduled_before: Array = game.shift.scheduled.duplicate(true)
 game._show("Пауза", "pause")
 for i in range(30): game._physics_process(.02)
 await create_timer(.06, true, false, true).timeout
 check(is_equal_approx(game.shift.time, 12.5), "real Main pause does not advance state.time")
 check(game.shift.scheduled == scheduled_before and game.shift.events.is_empty(), "paused Main preserves pending cue deadlines without emitting them")
 check(is_equal_approx(game.building.clock_hands[2].rotation.z, clock_before), "paused Main freezes the seconds hand")
 check(is_equal_approx(game.building.paper_material.get_shader_parameter("paper_time"), paper_before), "paused Main freezes the paper shader phase")
 game.building.sync(game.shift, .5)
 check(is_equal_approx(game.building.clock_hands[2].rotation.z, clock_before), "render sync alone cannot invent clock time")
 check(is_equal_approx(game.building.paper_material.get_shader_parameter("paper_time"), paper_before), "render sync alone cannot invent paper time")
 game.shift.time += 1
 game.building.sync(game.shift, 0)
 check(not is_equal_approx(game.building.clock_hands[2].rotation.z, clock_before), "the seconds hand follows changed simulation time, not render delta")
 check(not is_equal_approx(game.building.paper_material.get_shader_parameter("paper_time"), paper_before), "paper motion follows changed simulation time, not render delta")

 for selected in [false, true]:
  game.shift = Shift.new()
  game.shift.keys = true
  game.shift.phase = Shift.Phase.JOURNAL
  game.shift.time = 3661.25
  game._show("Журнал", "journal")
  game._resume()
  check(not game.shift.note and game.shift.note_time == 0 and game.shift.phase == Shift.Phase.JOURNAL, "closing journal before choice %s does not commit an entry" % selected)
  game._show("Журнал", "journal")
  game._write_journal(selected)
  game.building.sync(game.shift, 0)
  var ink: String = game.building.journal_ink.text
  var written_at: float = game.shift.note_time
  check(game.shift.note and game.shift.choice == selected and game.shift.phase == Shift.Phase.EXIT, "real journal callback commits choice %s" % selected)
  check(ink.begins_with("23:01\n") and ink.ends_with("Источник\nне установлен." if selected else "Посторонних\nне обнаружено."), "visible ink uses the selected entry and time of writing for choice %s" % selected)
  game.shift.time += 125
  game.building.sync(game.shift, 0)
  check(game.building.journal_ink.text == ink and game.shift.note_time == written_at, "later simulation time leaves the written ink unchanged for choice %s" % selected)
  game._write_journal(not selected)
  game.building.sync(game.shift, 0)
  check(game.shift.choice == selected and game.shift.note_time == written_at and game.building.journal_ink.text == ink, "a stale opposite-choice callback cannot rewrite committed entry %s" % selected)

 game.audio_scene.set_process(false)
 for voice in game.voices + game.devices: voice.stop()
 await create_timer(.15, true, false, true).timeout
 game.queue_free()
 await process_frame
 await process_frame

func test_web_fade_branch_contract() -> void:
 # Native headless cannot prove browser pointer lock. Execute the production
 # method body with only its feature predicate forced true, entirely in memory.
 var source := FileAccess.get_file_as_string("res://scripts/main.gd")
 var predicate := "OS.has_feature(\"web\")"
 check(source.count(predicate) == 1, "WEB branch probe identifies exactly one platform predicate")
 var pointer_condition := ""
 for line in source.split("\n"):
  if line.contains(predicate): pointer_condition = line
 check(pointer_condition.contains("end_elapsed<0"), "WEB pointer-loss condition explicitly excludes the final fade")
 if source.count(predicate) != 1: return
 var forced_web := GDScript.new()
 forced_web.source_code = source.replace(predicate, "true")
 var compile_error := forced_web.reload()
 check(compile_error == OK, "unchanged Main body compiles with the single in-memory WEB predicate override")
 if compile_error != OK: return
 var game: Node3D = forced_web.new()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 game.set_process_unhandled_input(false)
 await process_frame
 await physics_frame
 await physics_frame
 game._resume()
 game.grace = -1
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 game._process(.01)
 check(game.paused and game.menu_kind == "pointer" and game.audio_scene._paused, "forced WEB branch still pauses normal gameplay after pointer loss")
 game._resume("gamepad")
 game.grace = -1
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 game._process(.01)
 check(not game.paused and game.menu_kind=="gameplay" and not game.audio_scene._paused,"forced WEB branch permits pad play without pointer capture")

 game.paused = false
 game.menu_kind = ""
 game.panel.hide()
 game.audio_scene.pause(false)
 game.shift.keys = true
 game.shift.phase = Shift.Phase.EXIT
 game.shift.interact("exit", game.player.position)
 game._physics_process(.016)
 check(game.end_elapsed == 0 and not game.paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "final door deliberately releases the pointer while starting the fade")
 check(game.audio_scene._voice_ids.has("door_close") and not game.audio_scene._paused, "the final door is queued without pausing the audio scene")
 game._process(.8)
 check(not game.paused and game.menu_kind != "pointer" and not game.audio_scene._paused, "forced WEB pointer-loss branch cannot interrupt the active fade or pause its audio")
 check(game.end_fade.color.a > .4 and game.end_fade.color.a < .6, "final fade remains gradual after pointer release")
 game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
 check(not game.paused and not game.audio_scene._paused, "focus loss during final fade cannot replace it with an audio-pausing menu")
 var escape := InputEventKey.new()
 escape.physical_keycode = KEY_ESCAPE
 escape.pressed = true
 game._unhandled_input(escape)
 check(not game.paused and game.menu_kind != "pointer", "Escape during the finishing fade cannot trigger pointer pause")
 game._process(1.1)
 check(game.menu_kind == "end" and game.end_fade.color.a == 1, "the existing end panel follows the completed fade")
 check(not game.audio_scene._paused, "end panel leaves the final one-shot audio tail unpaused")
 game.audio_scene.set_process(false)
 for voice in game.voices + game.devices: voice.stop()
 await create_timer(.15, true, false, true).timeout
 game.queue_free()
 await process_frame
 await process_frame

func run() -> void:
 test_relay_and_library()
 test_full_post_reply()
 test_journal_state()
 test_optional_goals()
 await test_pause_and_journal_callbacks()
 await test_web_fade_branch_contract()
 print("EVENT READABILITY ", checks, " checks, failures ", failures)
 print("Scope: state/source/timing/text contracts only; no listening, visual perception or WEB acceptance claim.")
 quit(1 if failures else 0)
