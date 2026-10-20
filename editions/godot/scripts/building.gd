class_name CaretakerBuilding
extends Node3D
const StaticDetailBatch = preload("res://scripts/static_detail_batch.gd")
var static_detail_batching_enabled := true
var static_detail_batch_stats:Dictionary = {}
var ranges:Dictionary
var vertices:=PackedVector3Array()
var normals:=PackedVector3Array()
var colors:=PackedColorArray()
var indices:=PackedInt32Array()
var material:ShaderMaterial
var print_material:StandardMaterial3D
var static_chunks:Array[MeshInstance3D]=[]
var printed_surfaces:Array[GeometryInstance3D]=[]
var clock_hands:Array[Node3D]=[]
var projector_lamp:SpotLight3D
var projector_spill:OmniLight3D
var projected_slide:MeshInstance3D
var journal_ink:Label3D
var handwriting:Font = preload("res://assets/fonts/Caveat.ttf")
var paper_material:ShaderMaterial
var hall_right:Node3D
var paper:Node3D
var lit_surfaces:Array[MeshInstance3D]=[]
var room_panels:Array[MeshInstance3D]=[]
var hall_panel:MeshInstance3D
var paper_time:=0.0
var hall_door:Node3D
var doors:Array[Node3D]=[]
var room_lamps:Array[SpotLight3D]=[]
var hall_lamp:OmniLight3D
var corridor_lamps:Array[OmniLight3D]=[]
var items:Node3D
var note:Node3D
var projector:Node3D
func _ready()->void:
 ranges=JSON.parse_string(FileAccess.get_file_as_string("res://data/ranges.json"))
 var f:=FileAccess.open("res://data/scene.bin",FileAccess.READ)
 var n:=f.get_32();var m:=f.get_32()
 for i in range(n):
  vertices.append(Vector3(f.get_float(),f.get_float(),f.get_float()))
  normals.append(Vector3(f.get_float(),f.get_float(),f.get_float()))
  colors.append(Color(f.get_float(),f.get_float(),f.get_float()))
 for i in range(m):indices.append(f.get_16())
 material=ShaderMaterial.new();material.shader=load("res://shaders/surfaces.gdshader")
 print_material=StandardMaterial3D.new();print_material.vertex_color_use_as_albedo=true;print_material.roughness=1.0;print_material.metallic_specular=0.0
 _static_parts()
 _clock()
 _collision_boxes()
 _hall_doors()
 detail_box(Vector3(0,2.38,-6.06),Vector3(2.4,.51,.15),Color(.19,.15,.09))
 for i in range(4):doors.append(mesh_part(ranges.room_doors[i][0],ranges.room_doors[i][1],Vector3(-1.6 if i<2 else 1.6,0,(3.0 if i%2==0 else -1.0)-.65),true))
 items=mesh_part(ranges.items[0],ranges.items[1],Vector3.ZERO,false)
 note=Node3D.new();add_child(note);note.hide()
 _journal()
 paper=mesh_part(ranges.paper[0],36,Vector3(-3.57,1.74,.906),false)
 paper_material=ShaderMaterial.new();paper_material.shader=load("res://shaders/paper.gdshader")
 paper.get_child(0).material_override=paper_material;paper.get_child(0).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var paper_ink:=Label3D.new();paper_ink.text="Выключай\nсвет";paper_ink.font=handwriting;paper_ink.font_size=48;paper_ink.pixel_size=.0010;paper_ink.outline_size=0;paper_ink.shaded=true;paper_ink.modulate=Color(.24,.25,.21)
 paper_ink.position=Vector3(0,-.15,-.006);paper_ink.rotation.y=PI;paper_ink.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;paper.add_child(paper_ink)
 projector=mesh_part(ranges.projector[0],ranges.projector[1],Vector3.ZERO,false)
 var glow:=StandardMaterial3D.new();glow.vertex_color_use_as_albedo=true;glow.emission_enabled=true;glow.emission=Color(.25,.4,.75);glow.emission_energy_multiplier=.16
 projector.get_child(0).material_override=glow
 projector_lamp=SpotLight3D.new();projector_lamp.position=Vector3(4.86,1.0,3.95);projector_lamp.spot_angle=29;projector_lamp.spot_range=4;projector_lamp.light_color=Color(.65,.76,1);projector_lamp.light_energy=1.4;projector_lamp.shadow_enabled=true;add_child(projector_lamp)
 projector_lamp.look_at(Vector3(6.88,1.68,3.29),Vector3.UP)
 _projection()
 lamp(Vector3(-.6,2.5,7.6),Color(1,.76,.52),1.3,5)
 var desk_light:=SpotLight3D.new();desk_light.position=Vector3(-2.68,1.30,7.30);desk_light.spot_angle=48;desk_light.spot_range=1.7;desk_light.light_color=Color(1,.72,.39);desk_light.light_energy=.8;desk_light.shadow_enabled=true;add_child(desk_light);desk_light.look_at(Vector3(-2.3,1.0,7.75),Vector3.UP)
 hall_lamp=lamp(Vector3(0,2.5,-10),Color(1,.8,.55),2.0,6.8)
 for z in [-4.0,0.0,4.0]:corridor_lamps.append(lamp(Vector3(0,2.5,z),Color(.52,.72,.8),.85,3.6))
 for room_id in range(4):
  var center:Vector2=CaretakerShift.CENTERS[room_id]
  var tint:Color=[Color(.88,.92,.80),Color(1,.81,.59),Color(.84,.92,1),Color(.84,1,.87)][room_id]
  var energy:float=[1.3,1.45,1.5,1.25][room_id]
  var ceiling:=SpotLight3D.new();ceiling.position=Vector3(center.x,2.65,center.y);ceiling.rotation.x=-PI*.5;ceiling.spot_angle=78;ceiling.spot_range=5.0;ceiling.spot_attenuation=.7;ceiling.light_color=tint;ceiling.light_energy=energy*1.5;ceiling.shadow_enabled=true;ceiling.shadow_bias=.12;ceiling.shadow_normal_bias=2.0;ceiling.light_specular=.12;add_child(ceiling);room_lamps.append(ceiling)
  room_panels.append(detail_box(Vector3(center.x,2.705,center.y),Vector3(.42,.012,.28),Color(1,.87,.64),true))
 for z in [-4.0,0.0,4.0]:
  detail_box(Vector3(0,2.75,z),Vector3(.7,.08,.36),Color(.25,.31,.28))
  lit_surfaces.append(detail_box(Vector3(0,2.7,z),Vector3(.6,.012,.28),Color(.52,.75,.83),true))
 hall_panel=detail_box(Vector3(0,2.698,-10),Vector3(.72,.012,.32),Color(1,.8,.52),true)
 detail_box(Vector3(0,2.687,7.48),Vector3(.56,.012,.3),Color(1,.73,.4),true)
 _details()
 if static_detail_batching_enabled:static_detail_batch_stats=StaticDetailBatch.apply(self)
func lamp(position_:Vector3,tint:Color,energy:float,radius:float)->OmniLight3D:
 var l:=OmniLight3D.new();l.position=position_;l.light_color=tint;l.light_energy=energy;l.omni_range=radius;l.shadow_enabled=true;add_child(l);return l
func mesh_part(first:int,length:int,hinge:Vector3,collision:bool,layer:int=1)->Node3D:
 var triangles:Array=[]
 for i in range(first,first+length,3):
  if first==int(ranges.projector[0]) and (vertices[indices[i]].y<.02 or vertices[indices[i]].x>6.0):continue
  triangles.append(i)
 return _mesh_triangles(triangles,hinge,collision,layer,material)
func _mesh_triangles(triangles:Array,hinge:Vector3,collision:bool,layer:int,mat:Material)->Node3D:
 var holder:=Node3D.new();holder.position=hinge;add_child(holder)
 var v:=PackedVector3Array();var n:=PackedVector3Array();var c:=PackedColorArray()
 for i in triangles:
  for offset in [0,2,1]:
   var idx:int=indices[i+offset];v.append(vertices[idx]-hinge);n.append(normals[idx]);c.append(colors[idx])
 var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=v;arrays[Mesh.ARRAY_NORMAL]=n;arrays[Mesh.ARRAY_COLOR]=c
 var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.material_override=mat;holder.add_child(instance)
 if collision:
  var body:=StaticBody3D.new();body.collision_layer=layer;var shape:=CollisionShape3D.new();shape.shape=mesh.create_trimesh_shape();body.add_child(shape);holder.add_child(body)
 return holder
func _static_parts()->void:
 # Compatibility selects lights per mesh, not per room. Small spatial chunks
 # avoid a whole-building object competing for ten omni-light slots.
 var printed:Dictionary={}
 for span in ranges.lettering:
  for i in range(int(span[0]),int(span[0]+span[1]),3):printed[i]=true
 var groups:Dictionary={}
 var triangles:Array=[]
 for i in range(0,int(ranges.static_count),3):
  if printed.has(i):continue
  if i<int(ranges.clock[0]) or i>=int(ranges.clock[0]+ranges.clock[1]):
   _split_triangle(indices[i],indices[i+1],indices[i+2],triangles)
 for i in triangles:
  if i>=int(ranges.clock[0]) and i<int(ranges.clock[0]+ranges.clock[1]):continue
  var center:Vector3=(vertices[indices[i]]+vertices[indices[i+1]]+vertices[indices[i+2]])/3.0
  var key:=Vector3i(floori(center.x/4.5),0,floori(center.z/4.5))
  if not groups.has(key):groups[key]=[]
  groups[key].append(i)
 for key in groups:
  var holder:=_mesh_triangles(groups[key],Vector3.ZERO,true,2,material)
  var instance:MeshInstance3D=holder.get_child(0)
  static_chunks.append(instance)
 for sign in ranges.signs:
  if int(sign.first)>=int(ranges.static_count):continue
  var label:=Label3D.new();label.text=sign.text;label.font_size=48;label.pixel_size=float(sign.scale)*7.8/48.0;label.outline_size=0;label.shaded=true;label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT;label.vertical_alignment=VERTICAL_ALIGNMENT_TOP
  label.position=Vector3(sign.position[0],sign.position[1],sign.position[2]);label.rotation.y=float(sign.side)*PI*.5;label.modulate=Color(sign.color[0],sign.color[1],sign.color[2]);label.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  # Several source glyph planes sat 2–13 cm in front of their support. Keep
  # only a 2 mm anti-z-fighting separation from each actual board/wall face.
  match str(sign.text):
   "АКТОВЫЙ ЗАЛ":label.position.z=-5.953
   "ПОСТ ОХРАНЫ":label.position.z=9.948
   "ВЫХОД":label.position.z=9.923
   "ОФИС","БИБЛИОТЕКА":label.position.x=-1.463
   "КЛАСС","ПОДСОБКА":label.position.x=1.453
   "АДМИНИСТРАЦИЯ":label.position.x=-6.998
   "ПЯТНИЦА","НЕ ЗАБУДЬТЕ ВЫКЛЮЧИТЬ СВЕТ":label.position.z=5.438
   "СВЕТ":label.position.x=6.898
  add_child(label);printed_surfaces.append(label)
func _clock()->void:
 for i in range(3):
  var pivot:=Node3D.new();pivot.position=Vector3(-1.65,2.25,9.946-i*.002);add_child(pivot)
  var hand:=MeshInstance3D.new();var mesh:=BoxMesh.new()
  var length_:float=[.105,.15,.16][i]
  mesh.size=Vector3(.010 if i<2 else .004,length_,.002);hand.mesh=mesh;hand.position.y=length_*.42
  var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.08,.10,.09) if i<2 else Color(.32,.12,.09);mat.roughness=1;hand.material_override=mat
  hand.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;pivot.add_child(hand);clock_hands.append(pivot)
 for i in range(12):
  if i%3==0:continue
  var angle:=TAU*i/12.0
  var tick:=detail_box(Vector3(-1.65+sin(angle)*.163,2.25+cos(angle)*.163,9.949),Vector3(.006,.015,.002),Color(.18,.20,.16))
  tick.rotation.z=-angle;tick.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
func sync(state:CaretakerShift,dt:float)->void:
 var seconds:=state.time
 clock_hands[0].rotation.z=TAU*(22.0/12.0+seconds/43200.0)
 clock_hands[1].rotation.z=TAU*fmod(seconds/3600.0,1.0)
 clock_hands[2].rotation.z=TAU*fmod(seconds/60.0,1.0)
 hall_door.rotation.y=move_toward(hall_door.rotation.y,2.95 if state.door_open else 0.0,dt*1.8)
 hall_right.rotation.y=-hall_door.rotation.y
 for i in range(4):
  var angle:float=(-PI*.5 if i<2 else PI*.5) if state.room_open[i] else 0.0
  doors[i].rotation.y=move_toward(doors[i].rotation.y,angle,dt*2.5)
  room_lamps[i].visible=state.room_light[i]
 hall_lamp.visible=state.hall_on
 for light in corridor_lamps:light.visible=state.corridor_power
 items.visible=not state.keys;note.visible=state.note;projector.visible=state.projector_on
 projector_lamp.visible=state.projector_on
 projector_spill.visible=state.projector_on
 projected_slide.visible=state.projector_on
 journal_ink.text=("%02d:%02d\n"%[22+int(state.note_time/3600),int(state.note_time/60)%60])+("Источник\nне установлен." if state.choice else "Посторонних\nне обнаружено.")
 paper_time=state.time
 paper_material.set_shader_parameter("paper_time",paper_time)
 for i in range(room_panels.size()):room_panels[i].visible=state.room_light[i]
 for surface in lit_surfaces:surface.visible=state.corridor_power
 hall_panel.visible=state.hall_on

func detail_box(pos:Vector3,size_:Vector3,tint:Color,emissive:bool=false)->MeshInstance3D:
 var box:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size_;box.mesh=mesh;box.position=pos
 var mat:=StandardMaterial3D.new();mat.albedo_color=tint;mat.roughness=.92;mat.metallic_specular=.12
 if emissive:mat.emission_enabled=true;mat.emission=tint;mat.emission_energy_multiplier=1.3
 box.material_override=mat;add_child(box);return box
func _details()->void:
 # Thin green glass sits inside the existing window frames, catching the torch.
 for j in range(3):
  var glass:=detail_box(Vector3(3.925,1.72,-12.45+j*2.1),Vector3(.008,1.0,1.0),Color(.14,.23,.26,.23))
  var mat:StandardMaterial3D=glass.material_override
  mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.roughness=.12;mat.metallic=.25
 # Small lived-in objects on existing desks, outside the walking route.
 for i in range(5):
  detail_box(Vector3(-5.45+i*.005,.856+i*.012,5.05+i*.004),Vector3(.24,.012,.3),Color(.66,.62,.49))
 for i in range(3):
  detail_box(Vector3(3.35+i*.22,.862,1.72),Vector3(.18,.024,.26),Color(.26+i*.09,.31,.28))
 detail_box(Vector3(5.33,1.13,5.402),Vector3(.2,.04,.018),Color(.66,.65,.56))
 detail_box(Vector3(5.6,1.13,5.402),Vector3(.09,.06,.025),Color(.16,.18,.15))
 _human_details()
 _exterior()
 # Cable conduit and coloured labels clarify the utility-room equipment.
 for i in range(3):
  detail_box(Vector3(6.765,1.57,-1.27+i*.24),Vector3(.012,.055,.10),Color(.63,.54,.31))

func collision_box(pos:Vector3,size_:Vector3)->void:
 var body:=StaticBody3D.new();body.position=pos;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size_;shape.shape=box;body.add_child(shape);add_child(body)
func _collision_boxes()->void:
 collision_box(Vector3(0,-.12,-2),Vector3(14.5,.24,24.5))
 for i in range(ranges.walls.size()):
  var b:Array=ranges.walls[i]
  var height_:float=1.0 if i==13 else (.65 if i>=14 and i<=17 else 2.8)
  collision_box(Vector3(b[0]+b[2]/2,height_/2,b[1]+b[3]/2),Vector3(b[2],height_,b[3]))
 for b in ranges.room_furniture:
  collision_box(Vector3(b[0]+b[2]/2,.425,b[1]+b[3]/2),Vector3(b[2],.85,b[3]))

func _hall_doors()->void:
 # Two ordinary-width leaves fit the existing 2.4 m opening; the old 2.4 m
 # single leaf swung across the entire hall and looked out of scale.
 for side in [-1,1]:
  var hinge:=Node3D.new();hinge.position=Vector3(side*1.2,0,-6.26);add_child(hinge)
  var leaf:=detail_box(Vector3(side*-.599,1.06,.075),Vector3(1.198,2.12,.15),Color(.23,.19,.12))
  var wood:=material.duplicate();wood.set_shader_parameter("tint",Color(.23,.19,.12));leaf.material_override=wood
  remove_child(leaf);hinge.add_child(leaf)
  var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.198,2.12,.15)
  shape.shape=box;shape.position=leaf.position;body.add_child(shape);hinge.add_child(body)
  for y in [.53,1.55]:
   var inset:=detail_box(Vector3(side*-.59,y,.157),Vector3(.93,.75,.018),Color(.29,.24,.15));remove_child(inset);hinge.add_child(inset)
  var handle:=detail_box(Vector3(side*-1.03,1.08,.19),Vector3(.025,.18,.035),Color(.49,.43,.28));remove_child(handle);hinge.add_child(handle)
  if side==-1:hall_door=hinge
  else:hall_right=hinge
func _journal()->void:
 journal_ink=Label3D.new();journal_ink.font=handwriting;journal_ink.font_size=48;journal_ink.pixel_size=.0011
 journal_ink.modulate=Color(.16,.19,.22);journal_ink.outline_size=0;journal_ink.no_depth_test=false;journal_ink.shaded=true
 journal_ink.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 note.add_child(journal_ink)
 journal_ink.position=Vector3(-2.22,1.36,7.93)+Vector3(.57,.82,0)*.011
 journal_ink.basis=Basis(Vector3(0,0,-1),Vector3(-.82,.57,0).normalized(),Vector3(.57,.82,0).normalized())
func _projection()->void:
 projected_slide=MeshInstance3D.new();var screen:=QuadMesh.new();screen.size=Vector2(2.10,.90);projected_slide.mesh=screen;projected_slide.layers=4
 projected_slide.position=Vector3(6.884,1.68,3.29);projected_slide.rotation.y=-PI*.5
 var mat:=StandardMaterial3D.new();mat.albedo_texture=load("res://assets/projector-slide.svg");mat.albedo_color=Color(.55,.59,.53);mat.roughness=1;mat.metallic_specular=0
 mat.disable_ambient_light=true # Image receives the real projector light and its shadows, not self-illumination.
 projected_slide.material_override=mat;projected_slide.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(projected_slide)
 # A bounded proxy for light reflected from the projection screen. Unlike
 # the former emissive floor quad, this illuminates room surfaces and is
 # occluded by the actual leaf, walls and player. This is not real-time GI.
 projector_spill=lamp(Vector3(6.64,1.28,3.29),Color(.61,.72,.92),2.2,8.0)
 projector_spill.light_cull_mask=1;projector_spill.omni_attenuation=.8;projector_spill.light_specular=.04
 projector_spill.shadow_bias=.025;projector_spill.shadow_normal_bias=.25

func _split_triangle(a:int,b:int,c:int,out:Array)->void:
 # Some inherited walls are single long quads. Centroid bucketing alone still
 # leaves a room-spanning AABB and exceeds the per-mesh light limit.
 var ab:=vertices[a].distance_squared_to(vertices[b]);var bc:=vertices[b].distance_squared_to(vertices[c]);var ca:=vertices[c].distance_squared_to(vertices[a])
 if maxf(ab,maxf(bc,ca))<=2.25:
  out.append(indices.size());indices.append_array(PackedInt32Array([a,b,c]));return
 if bc>ab and bc>=ca:
  var old:=a;a=b;b=c;c=old
 elif ca>ab and ca>bc:
  var old:=a;a=c;c=b;b=old
 var mid:=vertices.size();vertices.append((vertices[a]+vertices[b])*.5);normals.append((normals[a]+normals[b]).normalized());colors.append(colors[a].lerp(colors[b],.5))
 _split_triangle(a,mid,c,out);_split_triangle(mid,b,c,out)

func surface_note(pos:Vector3,caption:String,size_:float=.0006)->Label3D:
 var label:=Label3D.new();label.text=caption;label.font=handwriting;label.font_size=40;label.pixel_size=size_;label.outline_size=0;label.shaded=true;label.modulate=Color(.18,.22,.21)
 label.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;label.position=pos;label.rotation.x=-PI*.5;add_child(label);return label
func _human_details()->void:
 # Things left by people doing ordinary work, with surfaces beneath them.
 surface_note(Vector3(-5.435,.911,5.065),"Картридж заказан.\nДо пятницы печатать\nтолько необходимое.",.00042)
 surface_note(Vector3(-3.13,.871,-2.9),"Книги на ремонт\n3 обложки, 1 корешок",.00052)
 # The chalk tray is attached to the existing board; no floating chalk blocks.
 detail_box(Vector3(4.35,1.087,5.39),Vector3(2.5,.025,.10),Color(.21,.25,.21))
 for i in range(3):detail_box(Vector3(4.1+i*.10,1.105,5.37),Vector3(.065,.012,.014),Color(.66,.68,.56))
 # Two spent bulbs in the utility box link its label to real objects.
 var tag:=surface_note(Vector3(3.9,.29,-2.643),"ЛАМПЫ\nПРОВЕРИТЬ",.0008);tag.rotation=Vector3.ZERO
 var model_tag:=surface_note(Vector3(4.43,1.005,3.718),"ЛП-12",.0007);model_tag.rotation=Vector3(0,PI,0)
 for i in range(2):
  var bulb:=MeshInstance3D.new();var mesh:=SphereMesh.new();mesh.radius=.035;mesh.height=.07;mesh.radial_segments=12;mesh.rings=6;bulb.mesh=mesh;bulb.position=Vector3(3.64+i*.25,.485,-2.94)
  var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.68,.70,.65);mat.roughness=.38;mat.metallic_specular=.22;bulb.material_override=mat;add_child(bulb)
  detail_box(bulb.position+Vector3(.039,-.007,0),Vector3(.03,.03,.03),Color(.30,.33,.31))

func _exterior()->void:
 # A modest ordinary yard beyond real openings, not an image pasted to glass.
 # No event, silhouette, or motion is attached to it. A single ordinary
 # yard lamp illuminates the fence and reveals depth through the glazing.
 detail_box(Vector3(10,-.13,-10),Vector3(11.6,.16,11),Color(.075,.10,.10))
 for z in [-14.0,-12.5,-11.0,-9.5,-8.0,-6.5]:
  detail_box(Vector3(7.8,.63,z),Vector3(.045,1.25,.045),Color(.13,.16,.16))
 for height in [.28,.96]:detail_box(Vector3(7.8,height,-10.25),Vector3(.035,.035,7.5),Color(.12,.16,.16))
 detail_box(Vector3(14.3,1.6,-11.2),Vector3(2.2,3.2,6.8),Color(.10,.13,.14))
 detail_box(Vector3(14.3,3.27,-11.2),Vector3(2.5,.14,7.1),Color(.055,.075,.085))
 for z in [-13.3,-11.4,-9.5]:
  var window:=detail_box(Vector3(13.19,1.92,z),Vector3(.01,.66,.56),Color(.18,.20,.17))
  var mat:StandardMaterial3D=window.material_override
  mat.emission_enabled=true;mat.emission=Color(.17,.18,.13);mat.emission_energy_multiplier=.18
 for j in range(3):
  var z:float=-12.45+j*2.1
  var sill:=detail_box(Vector3(4.08,1.19,z),Vector3(.34,.03,1.12),Color(.27,.30,.27));sill.name="WindowSill%d"%j;sill.set_meta("preserve_detail_transform",true)
  var upper_frame:=detail_box(Vector3(4.08,2.24,z),Vector3(.34,.03,1.12),Color(.27,.30,.27));upper_frame.set_meta("preserve_detail_transform",true)

 detail_box(Vector3(9.3,1.55,-11.8),Vector3(.055,3.1,.055),Color(.12,.14,.13))
 detail_box(Vector3(9.12,3.12,-11.8),Vector3(.48,.11,.24),Color(.21,.23,.20))
 var yard_lamp:=lamp(Vector3(8.96,3.01,-11.8),Color(.86,.72,.47),1.4,10.0)
 yard_lamp.name="YardLight";yard_lamp.light_specular=.06;yard_lamp.shadow_bias=.025;yard_lamp.shadow_normal_bias=.25
