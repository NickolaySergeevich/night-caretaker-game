extends SceneTree
const Shift=preload("res://scripts/shift.gd")
var failed:=false
var checks:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failed=true;push_error(label)
 else:print("PASS: ",label)
func _initialize()->void:
 var s:=Shift.new();var p:=Vector3(0,0,8.8)
 s.interact("printer",p);check(s.printer_on,"no tasks before keys")
 s.interact("keys",p);check(s.keys and s.torch_on and s.phase==Shift.Phase.INSPECT,"keys begin shift")
 for i in range(4):
  s.step(.016,Vector3(Shift.CENTERS[i].x,0,Shift.CENTERS[i].y))
  s.interact("switch_%d"%i,p)
 s.interact("printer",p);s.interact("projector",p)
 for i in range(4):s.interact("door_%d"%i,p)
 check(s.room_locked.all(func(x):return x),"all visited dark rooms locked")
 s.step(.016,Vector3(0,0,-12.5));check(s.phase==Shift.Phase.DARKEN,"hall inspection advances")
 s.interact("hall_switch",p);check(not s.hall_on,"hall light switches off")
 s.interact("hall_door",Vector3(0,0,-7));check(s.door_open,"cannot lock yourself inside hall")
 s.interact("hall_door",Vector3(0,0,-5));check(s.ordinary_complete(),"ordinary shift complete")
 s.step(.016,Vector3(0,0,7.2));check(s.phase==Shift.Phase.CLASS_RECHECK and s.projector_on,"return triggers projector")
 s.interact("door_2",p);s.interact("projector",p);check(s.phase==Shift.Phase.LIBRARY_RECHECK,"unplug projector")
 s.interact("door_1",p);s.step(.016,Vector3(-3.4,0,.35));s.step(.016,Vector3(0,0,.35))
 check(s.phase==Shift.Phase.FUSE and not s.corridor_power,"library visit triggers fuse")
 s.interact("fuse",Vector3(6.9,0,-1));s.step(.016,Vector3(0,0,-1))
 check(s.phase==Shift.Phase.INVESTIGATE,"restored fuse triggers knocks")
 var door_position:=Vector3(0,0,-4.5)
 s.knock(door_position,true);s.step(.1,door_position);s.knock(door_position,true)
 for i in range(20):s.step(.1,door_position)
 check(s.last_phrase.size()==2,"heard reply remembers player rhythm")
 s.interact("hall_door",door_position);s.step(.016,Vector3(0,0,-5.5),true)
 check(s.phase==Shift.Phase.JOURNAL,"open hall leads to journal")
 s.interact("journal",p);check(s.note and s.phase==Shift.Phase.EXIT,"journal unlocks exit")
 s.interact("exit",p);check(s.phase==Shift.Phase.END,"shift can finish")
 print("Checks: ",checks);quit(1 if failed else 0)
