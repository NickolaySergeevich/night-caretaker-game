shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(1.0);
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
 world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 world_normal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
}
void fragment() {
 vec3 base = COLOR.rgb*tint.rgb;
 // Low-contrast continuous plaster variation, not an unfiltered 125-cell/m
 // hash which became sparkling blocks on moving/distant surfaces.
 float mottling = 1.0 + .012 * sin(world_pos.x * 2.9 + world_pos.z * 3.7)
                         * sin(world_pos.y * 4.1 + world_pos.z * .8);
 vec2 wall_uv = abs(world_normal.x)>.7 ? world_pos.zy : world_pos.xy;
 float broad=sin(wall_uv.x*8.1+sin(wall_uv.y*6.3))*sin(wall_uv.y*11.7+wall_uv.x*1.3);
 float fine_phase=wall_uv.x*71.0+sin(wall_uv.y*43.0)*2.0;
 float fine=sin(fine_phase)*sin(wall_uv.y*67.0)*(1.0-smoothstep(.5,1.8,fwidth(fine_phase)));
 ALBEDO = base * (mottling+.022*broad+.007*fine);
 ROUGHNESS = .94;
 SPECULAR = .08;
 // The inherited corridor already has physical linoleum seams. A second
 // grid caused crossing lines; do not draw another one over it.
 if (world_normal.y > .9 && world_pos.y < .015) { ROUGHNESS=.86; }
 // Brown joinery receives restrained grain; painted walls remain matte.
 if (base.r > base.g * 1.18 && base.g > base.b * 1.12) {
  float phase = (world_pos.x+world_pos.z) * 48.0 + sin(world_pos.y * 3.0) * 1.5;
  float wood = sin(phase) * (1.0-smoothstep(.5,2.0,fwidth(phase)));
  ALBEDO *= .98 + .02 * wood;
  ROUGHNESS = .90;
 }
}
