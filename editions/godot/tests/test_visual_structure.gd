extends SceneTree
const Main=preload("res://scripts/main.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var game:=Main.new();root.add_child(game);await process_frame
 var b:Node3D=game.building
 check(b.static_chunks.size()>10,"world split into spatial chunks")
 var peak:=0;var worst:=AABB()
 for mesh in b.static_chunks:
  var box:AABB=mesh.get_aabb();var overlaps:=0
  for light in b.get_children():
   if not light is OmniLight3D:continue
   var p:Vector3=light.position
   var near_point:=Vector3(clampf(p.x,box.position.x,box.end.x),clampf(p.y,box.position.y,box.end.y),clampf(p.z,box.position.z,box.end.z))
   if near_point.distance_to(p)<light.omni_range:overlaps+=1
  if overlaps>peak:peak=overlaps;worst=box
 check(peak<=8,"Compatibility omni budget on all chunks: %d"%peak)
 print("SPATIAL chunks ",b.static_chunks.size()," peak omni ",peak," worst ",worst)
 check(b.room_lamps.all(func(l):return l is SpotLight3D and l.shadow_enabled),"ceiling fixtures have bounded downward shadowed cones")
 var spot_count:=2 # player's beam and broad spill, irrespective of enabled state
 for node in b.get_children():
  if node is SpotLight3D:spot_count+=1
 check(spot_count<=8,"global SpotLight budget conservatively <=8")
 check(b.printed_surfaces.size()==11,"all static printed signs replaced, none silently lost")
 check(b.printed_surfaces.all(func(l):return l is Label3D),"surface typography is real glyph rendering, not geometry pixels")
 await physics_frame
 for label in b.printed_surfaces:
  var normal:Vector3=label.global_basis.z
  var ray:=PhysicsRayQueryParameters3D.create(label.global_position+normal*.02,label.global_position-normal*.2,2)
  var hit:Dictionary=b.get_world_3d().direct_space_state.intersect_ray(ray)
  check(not hit.is_empty() and hit.position.distance_to(label.global_position)<.012 and (label.global_position-hit.position).dot(normal)>=-.0001,"printed sign is in front of and touches its support: "+label.text)
 for mesh in b.printed_surfaces:check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"printed text casts no shadow")
 check(b.get_node("YardLight").position.x<9.3-.055/2-.1,"yard light is outside opaque pole geometry")
 for j in range(3):
  var sill=b.get_node("WindowSill%d"%j)
  check(sill.position.y+sill.mesh.size.y/2>1.185,"window reveal does not coincide with wall top")
 var angle:float=b.clock_hands[2].rotation.z
 game.shift.time+=5;b.sync(game.shift,0)
 check(not is_equal_approx(angle,b.clock_hands[2].rotation.z),"seconds hand follows simulation")
 check(b.clock_hands[2].rotation.z>0,"clockwise hand viewed from the room side")
 var frozen:float=b.clock_hands[2].rotation.z;b.sync(game.shift,1)
 check(is_equal_approx(frozen,b.clock_hands[2].rotation.z),"clock does not invent time during pause")
 check(b.projector_lamp.position.x>4.82,"projector beam starts beyond lens")
 check((-b.projector_lamp.basis.z).dot((Vector3(6.88,1.68,3.29)-b.projector_lamp.position).normalized())>.999,"projector aims at screen")
 check(b.projected_slide.material_override.albedo_texture!=null,"projector has real slide surface")
 check(not b.projected_slide.material_override.emission_enabled,"projected image is not emissive and can receive real shadows")
 check(b.projector_spill is OmniLight3D and b.projector_spill.shadow_enabled,"screen bounce is an actual shadowed room light, never a floor quad")
 check(b.projector_spill.position.x>1.7 and b.projector_spill.position.y>1.0,"reflected source remains inside the room near the screen")
 game.shift.room_open[2]=true;game.shift.projector_on=true;b.sync(game.shift,10)
 check(b.projector_spill.visible,"opening the door does not delete the room light")
 game.shift.room_open[2]=false;b.sync(game.shift,0)
 check(b.projector_spill.visible,"door command does not alter source energy or visibility")
 b.sync(game.shift,10)
 check(b.projector_spill.visible,"closed leaf is responsible for occlusion, not a visibility trick")
 game.shift.projector_on=false;b.sync(game.shift,0)
 check(not b.projector_spill.visible,"power removal switches off reflected source")
 var body=game.player.get_node("PlayerShadow")
 check(body.layers==2 and body.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,"player has a moving shadow caster")
 check((game.lamp.shadow_caster_mask&body.layers)==0 and (b.projector_lamp.shadow_caster_mask&body.layers)!=0,"torch excludes own body, projector includes it")
 check(is_equal_approx(game.camera.near,.10) and game.camera.far==60.0,"depth range bounded to building scale")
 check(b.paper_material.shader!=null and is_equal_approx(b.paper.position.y,1.74),"paper fixed at upper vent edge")
 check(b.hall_door.get_child(0).mesh.size.x<1.2 and b.hall_right!=null,"hall has normal-width double leaves")
 game.shift.door_open=true;b.sync(game.shift,10)
 var clear_wall:=true
 for leaf_hinge in [b.hall_door,b.hall_right]:
  var leaf:MeshInstance3D=leaf_hinge.get_child(0)
  for corner in range(8):
   if (leaf.global_transform*leaf.get_aabb().get_endpoint(corner)).z>=-6.2:clear_wall=false
 check(clear_wall,"fully open hall leaves do not clip the front wall")
 game.shift.choice=true;game.shift.note=true;b.sync(game.shift,0)
 check(b.journal_ink.font.resource_path.ends_with("Caveat.ttf") and b.journal_ink.font.has_char(0x416),"journal uses a licensed Cyrillic handwriting font")
 check(b.journal_ink.text.ends_with("Источник\nне установлен."),"journal ink reflects chosen entry")
 game._resume();game.capture_pending=false
 var motion:=InputEventMouseMotion.new();motion.relative=Vector2(200,0);motion.screen_relative=Vector2(10,0)
 var yaw:float=game.player.rotation.y;game._apply_mouse_motion(motion)
 check(is_equal_approx(game.player.rotation.y-yaw,-10*game.sensitivity),"mouse uses physical screen delta not content-scaled delta")
 game._release_pointer();game._physics_process(.016)
 check(not game.hint.text.is_empty(),"pointer release instruction remains visible")
 game._resume();game.shift.phase=CaretakerShift.Phase.END;game._physics_process(.016)
 check(game.end_elapsed==0 and game.menu_kind!="end","ending starts fade before panel")
 game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
 check(not game.paused,"focus loss cannot replace ending fade with pause panel")
 game._process(.8);check(game.end_fade.color.a>.4 and game.end_fade.color.a<.6,"ending fades gradually")
 game._process(1.1);check(game.menu_kind=="end" and game.end_fade.color.a==1,"ending panel follows full fade")
 for voice in game.voices+game.devices:voice.stop()
 game.queue_free();await process_frame;await process_frame
 print("VISUAL STRUCTURE ",checks," checks, failures ",failures);quit(1 if failures else 0)
