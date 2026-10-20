shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_disabled;
uniform float closure=0.0;
void fragment(){
 float across=smoothstep(0.,.15,UV.y)*smoothstep(0.,.15,1.-UV.y);
 float toward_door=smoothstep(0.,1.,UV.x);
 ALBEDO=vec3(.40,.48,.52)*across*toward_door*closure;
 ALPHA=across*toward_door*.80*closure;
}
