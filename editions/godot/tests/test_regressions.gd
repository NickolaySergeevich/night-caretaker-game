extends SceneTree
const Shift=preload("res://scripts/shift.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func advance(s:CaretakerShift,seconds:float)->void:
 var count:=int(ceil(seconds/.02))
 for i in range(count):s.step(seconds/count,Vector3(0,0,-4.5))
func investigated()->CaretakerShift:
 var s:=Shift.new();s.keys=true;s.phase=Shift.Phase.INVESTIGATE;s.door_open=false
 return s
func _initialize()->void:
 var permutations:=0
 for a in range(4):
  for b in range(4):
   for c in range(4):
    for d in range(4):
     var order:=[a,b,c,d]
     if a==b or a==c or a==d or b==c or b==d or c==d:continue
     var s:=Shift.new();s.interact("keys",Vector3.ZERO)
     for i in order:
      s.step(.02,Vector3(Shift.CENTERS[i].x,0,Shift.CENTERS[i].y))
      if i==0:s.interact("printer",Vector3.ZERO)
      if i==2:s.interact("projector",Vector3.ZERO)
      s.interact("switch_%d"%i,Vector3.ZERO);s.interact("door_%d"%i,Vector3.ZERO)
     check(s.room_locked.all(func(v):return v),"room order "+str(order))
     check(not s.ordinary_complete(),"hall still required "+str(order))
     s.hall_secured=true;s.hall_checked=true;s.hall_on=false;s.door_open=false;s.door_locked=true
     s.step(.02,Vector3.ZERO)
     check(s.phase==Shift.Phase.RETURN,"completion "+str(order))
     s.interact("door_%d"%d,Vector3.ZERO);s.step(.02,Vector3.ZERO)
     check(s.phase==Shift.Phase.INSPECT,"reopen invalidates completion")
     permutations+=1
 check(permutations==24,"24 room orders")
 var p:=Vector3(0,0,-4.5)
 var early:=investigated()
 early.knock(p,true);advance(early,1.1);early.interact("hall_door",p);advance(early,.8)
 check(early.last_phrase==[0.0,.38,.86],"cancel before hearing keeps original phrase")
 check(not early.reply_active and early.scheduled.is_empty(),"opening cancels pending reply")
 var heard:=investigated()
 heard.knock(p,true);advance(heard,.24);heard.knock(p,true);advance(heard,1.42)
 check(heard.last_phrase.size()==2,"first heard reply remembers phrase")
 heard.interact("hall_door",p)
 check(not heard.reply_active and heard.scheduled.is_empty(),"opening cancels rest after first reply")
 var limit:=investigated()
 for i in range(9):limit.knock(p,true);advance(limit,.10)
 check(limit.taps.size()<=6,"six-tap limit")
 var order:=Shift.new()
 order.schedule_phrase([0.0,.08],Vector3.ZERO,.4,"initial")
 advance(order,.39);order.events.clear();order.step(.1,p)
 check(order.events.size()==2 and order.events[0].name=="knock_reply_01" and order.events[1].name=="knock_reply_02","due events keep chronological order")
 var invalid:=Shift.new()
 invalid.step(NAN,p);invalid.step(-1,p);invalid.step(.2,p)
 check(invalid.time==0,"invalid delta rejected")
 var location:=Shift.new();location.interact("keys",Vector3(100,0,100))
 check(location.events[0].position==Vector3(-2,1.1,7.8),"key sound comes from desk")
 var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/manifest.json"))
 var ids:Array=[]
 for asset in manifest.assets:ids.append(asset.id)
 check(ids.size()==26,"26 runtime sounds")
 for id in ["chair","paper","breaker","dev_printer","dev_projector"]:check(ids.has(id),"restored "+id)
 for choice in [false,true]:
  var s:=Shift.new();s.keys=true;s.choice=choice;s.phase=Shift.Phase.JOURNAL;s.interact("journal",p);s.interact("exit",p)
  check(s.phase==Shift.Phase.END and s.choice==choice,"journal choice preserved to end")
 print("REGRESSIONS ",checks," checks, failures ",failures)
 quit(1 if failures else 0)
