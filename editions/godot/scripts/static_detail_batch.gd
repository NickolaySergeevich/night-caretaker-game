extends RefCounted
# Spatially bounded static batching: identical materials and shadow flags,
# spatially bounded; all moving/toggled nodes, labels and glass remain separate.
static func apply(building:Node3D)->Dictionary:
 if building.has_meta("static_detail_batch_stats"):
  return building.get_meta("static_detail_batch_stats")
 var protected:Array=[]
 protected.append_array(building.room_panels);protected.append_array(building.lit_surfaces);protected.append(building.hall_panel)
 var groups:Dictionary={}
 var eligible:=0
 for node in building.get_children():
  if not node is MeshInstance3D or protected.has(node) or not node.visible:continue
  if node.has_meta("preserve_detail_transform"):continue # Keep thin window occluders at their original transform precision.
  if not node.mesh is BoxMesh or not node.material_override is StandardMaterial3D:continue
  if not node.basis.is_equal_approx(Basis.IDENTITY):continue # Avoid re-encoding transformed normals.
  var mat:StandardMaterial3D=node.material_override
  if mat.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue
  var size_:Vector3=node.mesh.size
  if maxf(size_.x,maxf(size_.y,size_.z))>4.5:continue
  var properties:Dictionary={}
  for prop in mat.get_property_list():
   var key:String=prop.name
   if int(prop.usage)&PROPERTY_USAGE_STORAGE and not key.begins_with("resource_"):
    properties[key]=mat.get(key)
  var cell:=Vector3i(floori(node.position.x/4.5),0,floori(node.position.z/4.5))
  var key:=str(cell)+"|"+var_to_str(properties)+"|"+str(node.layers)+"|"+str(node.cast_shadow)
  if not groups.has(key):groups[key]=[]
  groups[key].append(node);eligible+=1
 var removed:=0;var batches:=0;var source_triangles:=0;var destination_triangles:=0
 for key in groups:
  var nodes:Array=groups[key]
  if nodes.size()<2:continue
  var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
  for node in nodes:
   st.append_from(node.mesh,0,node.transform)
   var source:Array=node.mesh.surface_get_arrays(0)
   source_triangles+=source[Mesh.ARRAY_INDEX].size()/3
  var batch:=MeshInstance3D.new();batch.name="BatchedStaticDetail%d"%batches;batch.mesh=st.commit()
  batch.material_override=nodes[0].material_override;batch.layers=nodes[0].layers;batch.cast_shadow=nodes[0].cast_shadow
  building.add_child(batch)
  var arrays:Array=batch.mesh.surface_get_arrays(0)
  destination_triangles+=arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size()/3
  batch.set_meta("static_detail_batch_output",true)
  for node in nodes:
   node.set_meta("static_detail_batch_source",true);node.hide()
  removed+=nodes.size();batches+=1
 assert(source_triangles==destination_triangles,"Batching must not drop geometry")
 var stats:Dictionary={"eligible_nodes":eligible,"source_nodes":removed,"batch_nodes":batches,"source_triangles":source_triangles,"destination_triangles":destination_triangles}
 building.set_meta("static_detail_batch_stats",stats)
 return stats

static func restore(building:Node3D)->void:
 # Reversible comparison route. No lights or collisions are ever modified.
 for node in building.get_children():
  if node.has_meta("static_detail_batch_source"):
   node.show();node.remove_meta("static_detail_batch_source")
  elif node.has_meta("static_detail_batch_output"):
   building.remove_child(node);node.queue_free()
 building.remove_meta("static_detail_batch_stats")
