shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform float paper_time=0.0;
void vertex(){
 float free_edge=clamp(-VERTEX.y/.36,0.,1.);
 // Top edge is pinned to the vent. The free lower edge bends, never a rigid sign.
 VERTEX.z-=free_edge*free_edge*(.007+.004*sin(paper_time*1.35+free_edge*2.));
}
void fragment(){ALBEDO=COLOR.rgb;ROUGHNESS=1.;}
