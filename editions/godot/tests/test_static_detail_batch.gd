extends SceneTree
func _initialize()->void:call_deferred("run")
func material_signature(mat:StandardMaterial3D)->String:
 var properties:Dictionary={}
 for prop in mat.get_property_list():
  var key:String=prop.name
  if int(prop.usage)&PROPERTY_USAGE_STORAGE and not key.begins_with("resource_"):properties[key]=mat.get(key)
 return var_to_str(properties)
func triangle_signatures(nodes:Array)->Array[String]:
 var result:Array[String]=[]
 for node in nodes:
  var arrays:Array=node.mesh.surface_get_arrays(0)
  var v:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var n:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
  var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
  if indices.is_empty():
   for i in range(v.size()):indices.append(i)
  var key:=material_signature(node.material_override)+"|"+str(node.layers)+"|"+str(node.cast_shadow)
  for first in range(0,indices.size(),3):
   var entries:Array[String]=[]
   for offset in range(3):
    var i:int=indices[first+offset]
    var point:Vector3=node.transform*v[i]
    var normal:Vector3=(node.transform.basis*n[i]).normalized()
    entries.append("%.5f,%.5f,%.5f;%.5f,%.5f,%.5f;%.5f,%.5f"%[point.x,point.y,point.z,normal.x,normal.y,normal.z,uv[i].x,uv[i].y])
   result.append((key+"|"+"|".join(entries)).replace("-0.00000","0.00000"))
 result.sort();return result
func run()->void:
 var b=load("res://scripts/building.gd").new();b.static_detail_batching_enabled=false;root.add_child(b)
 var children:Array=b.get_children();var lights_before:Array=[];var collision_before:Array=[]
 for n in b.find_children("*","CollisionObject3D",true,false):collision_before.append(n.get_instance_id())
 for n in b.get_children():
  if n is Light3D:lights_before.append({"id":n.get_instance_id(),"shadow":n.shadow_enabled,"mask":n.light_cull_mask,"caster_mask":n.shadow_caster_mask,"energy":n.light_energy})
 var result=load("res://scripts/static_detail_batch.gd").apply(b)
 assert(result.source_nodes>result.batch_nodes)
 assert(result.source_triangles==result.destination_triangles)
 for state in lights_before:
  var n=instance_from_id(state.id)
  assert(n.shadow_enabled==state.shadow and n.light_cull_mask==state.mask and n.shadow_caster_mask==state.caster_mask and n.light_energy==state.energy)
 var before:Array=[];var after:Array=[]
 for n in children:
  if n is MeshInstance3D and not n.visible:before.append(n)
 for n in b.get_children():
  if n is MeshInstance3D and str(n.name).begins_with("BatchedStaticDetail"):after.append(n)
 var sig_before:=triangle_signatures(before);var sig_after:=triangle_signatures(after)
 if sig_before!=sig_after:
  var out:=FileAccess.open("user://batch-difference.txt",FileAccess.WRITE)
  out.store_line("before=%d after=%d"%[sig_before.size(),sig_after.size()])
  for item in sig_before:
   if not sig_after.has(item):out.store_line("MISSING "+item)
  for item in sig_after:
   if not sig_before.has(item):out.store_line("NEW "+item)
  out.close();print("BATCH_GEOMETRY_MISMATCH");quit(1);return
 var collision_after:Array=[]
 for n in b.find_children("*","CollisionObject3D",true,false):collision_after.append(n.get_instance_id())
 assert(collision_before==collision_after,"Batching must not touch collision nodes")
 for n in b.room_panels+b.lit_surfaces:assert(n.visible)
 assert(b.hall_panel.visible)
 result["world_triangle_signature_sha256"]="\n".join(sig_before).sha256_text()
 result["precision"]="World vertices/normals/UV at1e-5, exact material properties, winding/layers/shadow mode"
 result["lights_unchanged"]=lights_before.size();result["collision_nodes_unchanged"]=collision_before.size()
 var f:=FileAccess.open("user://batch-headless-report.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
 var original_count:int=b.get_child_count()
 load("res://scripts/static_detail_batch.gd").apply(b)
 assert(b.get_child_count()==original_count,"Applying twice does not add duplicate batches")
 load("res://scripts/static_detail_batch.gd").restore(b)
 for node in before:assert(node.visible,"Restore must recover original static details")
 assert(triangle_signatures(before)==sig_before)
 assert(not b.has_meta("static_detail_batch_stats"))
 var defaults=load("res://scripts/building.gd").new();root.add_child(defaults)
 assert(defaults.static_detail_batch_stats.source_nodes==result.source_nodes and defaults.static_detail_batch_stats.batch_nodes==result.batch_nodes,"Production default uses the verified bounded groups")
 defaults.queue_free()
 print("BATCH_STATIC_DETAILS_HEADLESS_PASS ",result)
 b.queue_free();await process_frame;quit()
