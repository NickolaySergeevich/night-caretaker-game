class_name CaretakerShift
extends RefCounted
# State transitions ported from caretaker_game.h and caretaker_shift.h.
enum Phase {TAKE, INSPECT, DARKEN, LOCK, RETURN, INVESTIGATE, JOURNAL, EXIT, END, CLASS_RECHECK, LIBRARY_RECHECK, FUSE}
var phase := Phase.TAKE
var keys := false
var torch := false
var torch_on := false
var hall_on := true
var door_open := true
var door_locked := false
var hall_checked := false
var hall_secured := false
var printer_on := true
var projector_on := true
var projector_cut := false
var corridor_power := true
var fuse_repaired := false
var library_rechecked := false
var paper_near_heard := false
var choice := false
var note := false
var note_time := 0.0
var room_open := [true,true,true,true]
var room_locked := [false,false,false,false]
var room_light := [true,true,true,true]
var room_visited := [false,false,false,false]
var time := 0.0
var events: Array[Dictionary] = []
var scheduled: Array[Dictionary] = []
var taps: Array[float] = []
var last_phrase: Array[float] = [0.0,.38,.86]
var last_tap := -10.0
var reply_active := false
var reply_heard := false
var phrase_serial := 0
var active_reply_token := 0
const CENTERS := [Vector2(-4.2,3.3),Vector2(-4.2,-1),Vector2(4.2,3.3),Vector2(4.2,-1)]
func emit_sound(name:String,position:Vector3) -> void:
 events.append({"name":name,"position":position})
func ready_room(i:int) -> bool:
 return room_visited[i] and not room_light[i] and (i!=0 or not printer_on) and (i!=2 or not projector_on)
func ordinary_complete() -> bool:
 if printer_on or projector_on or not hall_secured or door_open or not door_locked:return false
 for i in range(4):
  if not room_visited[i] or room_light[i] or not room_locked[i]:return false
 return true
func interact(id:String,position:Vector3) -> void:
 if phase==Phase.END:return
 var sound_position:=position
 match id:
  "keys", "journal":sound_position=Vector3(-2,1.1,7.8)
  "printer":sound_position=Vector3(-4,1.08,3.9)
  "projector":sound_position=Vector3(4.45,1.18,3.95)
  "fuse":sound_position=Vector3(6.9,1.4,-1)
  "hall_switch":sound_position=Vector3(1.5,1.3,-6.24)
  "exit":sound_position=Vector3(0,1.3,9.9)
 if id.begins_with("switch_") or id.begins_with("door_"):
  var room_id:=id.get_slice("_",1).to_int()
  if room_id<0 or room_id>=4:return
  sound_position=Vector3(-1.6 if room_id<2 else 1.6,1.3,3.0 if room_id%2==0 else -1.0)
 if id=="keys" and not keys:
  keys=true;torch=true;torch_on=true;phase=Phase.INSPECT;emit_sound("keys",sound_position)
 elif not keys:return
 elif id=="printer" and printer_on:
  printer_on=false;emit_sound("switch",sound_position)
 elif id=="projector" and projector_on:
  projector_on=false;emit_sound("switch",sound_position)
  if phase==Phase.CLASS_RECHECK:
   projector_cut=true;phase=Phase.LIBRARY_RECHECK
   emit_sound("chair",Vector3(-2.95,1,-2.2));emit_sound("paper",Vector3(-3.55,1,.93))
 elif id=="fuse" and phase==Phase.FUSE and not fuse_repaired:
  corridor_power=true;fuse_repaired=true;emit_sound("breaker",sound_position)
 elif id.begins_with("switch_"):
  var i:=id.trim_prefix("switch_").to_int()
  room_light[i]=not room_light[i];emit_sound("switch",sound_position)
 elif id.begins_with("door_"):
  var i:=id.trim_prefix("door_").to_int()
  if room_open[i]:
   room_open[i]=false;room_locked[i]=ready_room(i) and phase<=Phase.RETURN
   emit_sound("door_close",sound_position)
   if room_locked[i]:emit_sound("lock",sound_position)
  else:
   if room_locked[i]:emit_sound("unlock",sound_position)
   room_locked[i]=false;room_open[i]=true;emit_sound("door_open",sound_position)
 elif id=="hall_switch" and phase==Phase.DARKEN:
  hall_on=false;phase=Phase.LOCK;emit_sound("switch",sound_position)
 elif id=="hall_door":
  if door_open:
   # The player must lock from outside the hall.
   if phase<=Phase.RETURN and hall_checked and not hall_on and position.z < -6:return
   door_open=false;emit_sound("door_close",Vector3(0,1,-6))
   if phase<=Phase.RETURN and hall_checked and not hall_on:
    door_locked=true;hall_secured=true;emit_sound("lock",Vector3(0,1,-6))
    phase=Phase.RETURN if ordinary_complete() else Phase.INSPECT
  else:
   if door_locked:emit_sound("unlock",Vector3(0,1,-6))
   door_locked=false;door_open=true;emit_sound("door_open",Vector3(0,1,-6));cancel_reply()
 elif id=="journal" and phase==Phase.JOURNAL:
  note=true;note_time=time;phase=Phase.EXIT
 elif id=="exit" and phase==Phase.EXIT:
  # Discard only future attacks; the audio command retains already mixed tails.
  var pending_tokens:Dictionary={}
  for event in scheduled:pending_tokens[event.token]=true
  for token in pending_tokens:events.append({"audio_action":"cancel_phrase","token":token})
  phase=Phase.END;scheduled.clear();emit_sound("door_close",sound_position)
 if phase==Phase.INSPECT and ordinary_complete():phase=Phase.RETURN
func cancel_reply() -> void:
 if active_reply_token>0:events.append({"audio_action":"cancel_phrase","token":active_reply_token})
 _complete_reply()
 scheduled=scheduled.filter(func(e):return e.get("kind","")!="reply")
func _complete_reply() -> void:
 # Natural logical completion must NOT cancel the last PCM tap's tail.
 taps.clear();reply_active=false;active_reply_token=0
func knock(position:Vector3,looking_at_door:bool) -> void:
 if phase!=Phase.INVESTIGATE or door_open or position.z<=-6 or not looking_at_door or reply_active:return
 if position.distance_to(Vector3(0,position.y,-6))>2.1 or time-last_tap<.08:return
 if taps.size()<6:taps.append(time)
 last_tap=time
 emit_sound("knock_player_%02d" % (taps.size()%3+1),position)
func schedule_phrase(phrase:Array[float],position:Vector3,delay:float,kind:String) -> void:
 if phrase.is_empty():return
 phrase_serial+=1
 var token:=phrase_serial
 events.append({"audio_action":"phrase","token":token,"kind":kind,"phrase":phrase.duplicate(),"position":position,"start_time":time+delay})
 if kind=="reply":active_reply_token=token
 for i in range(phrase.size()):scheduled.append({"at":time+delay+phrase[i],"name":"knock_reply_%02d"%(i%3+1),"position":position,"kind":kind,"first":i==0,"token":token})
func step(dt:float,position:Vector3,looking_hall:bool=false) -> void:
 if not is_finite(dt) or dt<=0 or dt>.1 or phase==Phase.END:return
 time+=dt
 for i in range(4):
  if keys and room_open[i] and Vector2(position.x,position.z).distance_to(CENTERS[i])<1.6:room_visited[i]=true
 if phase==Phase.INSPECT and keys and not hall_checked and position.z < -12.1:
  hall_checked=true;phase=Phase.DARKEN;emit_sound("pipe_tick",Vector3(3,1,-12.5))
 if phase==Phase.RETURN and not ordinary_complete():phase=Phase.INSPECT
 if phase==Phase.INSPECT and ordinary_complete():phase=Phase.RETURN
 if phase==Phase.RETURN and Vector2(position.x,position.z).distance_to(Vector2(0,7.2))<1.3:
  phase=Phase.CLASS_RECHECK;projector_on=true
  emit_sound("switch",Vector3(4.45,1.18,3.95))
 if phase==Phase.LIBRARY_RECHECK and room_open[1] and not paper_near_heard and Vector2(position.x,position.z).distance_to(Vector2(-3.55,.93))<1.8:
  paper_near_heard=true;emit_sound("paper",Vector3(-3.55,1.55,.93))
 if phase==Phase.LIBRARY_RECHECK and room_open[1] and Vector2(position.x,position.z).distance_to(Vector2(-3.4,.35))<.9:library_rechecked=true
 if phase==Phase.LIBRARY_RECHECK and library_rechecked and position.x>-.95:
  phase=Phase.FUSE;corridor_power=false;emit_sound("breaker",Vector3(6.9,1,-1))
 if phase==Phase.FUSE and fuse_repaired and position.x<.95:
  phase=Phase.INVESTIGATE;schedule_phrase([0.0,.38,.86],Vector3(0,1,-8),0,"initial")
 if not taps.is_empty() and not reply_active and (time-last_tap>=1 or taps.size()==6):
  var phrase:Array[float]=[]
  for tap in taps:phrase.append(tap-taps[0])
  schedule_phrase(phrase,Vector3(0,1,-8),.4,"reply");reply_active=true;reply_heard=false
 if phase==Phase.INVESTIGATE and door_open and Vector2(position.x,position.z).distance_to(Vector2(0,-6))<1.35 and looking_hall:
  cancel_reply();phase=Phase.JOURNAL;schedule_phrase(last_phrase,Vector3(-2,1,7.8),.4,"post")
 scheduled.sort_custom(func(a,b):return a.at<b.at)
 while not scheduled.is_empty() and scheduled[0].at<=time:
  var event:Dictionary=scheduled.pop_front()
  events.append({"name":event.name,"position":event.position,"phrase_token":event.token})
  if event.kind=="reply" and event.first:
   last_phrase.clear()
   for tap in taps:last_phrase.append(tap-taps[0])
   reply_heard=true
 if reply_active and not scheduled.any(func(e):return e.kind=="reply"):_complete_reply()
func short_goal() -> String:
 match phase:
  Phase.TAKE:return "На столе оставили ключи и фонарь."
  Phase.INSPECT:
   var remaining:Array[String]=[]
   var names:=["Офис","Библиотека","Класс","Подсобка"]
   for i in range(4):
    if not room_locked[i]:remaining.append(names[i])
   if not hall_secured:remaining.append("Актовый зал и сцена")
   return "Вечерний обход\n"+"\n".join(remaining)
  Phase.DARKEN:return "В зале ещё горит свет."
  Phase.LOCK:return "Закрыть зал снаружи."
  Phase.RETURN:return "Вернуться на пост."
  Phase.CLASS_RECHECK:return "Перед уходом проверить, что всё выключено."
  Phase.LIBRARY_RECHECK:return "Перед записью ещё раз осмотреть помещения."
  Phase.FUSE:return "Проверить электрический щиток."
  Phase.INVESTIGATE:return "Проверить закрытые помещения перед уходом."
  Phase.JOURNAL:return "Сделать запись в журнале."
  Phase.EXIT:return "Смена закончилась."
 return ""
