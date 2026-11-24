shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 grid_color : source_color = vec4(1.0,0.12,0.3,1.0);
varying vec3 local_position;
varying vec3 local_normal;
void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}
float grid_line(vec2 p) {
	vec2 v = abs(fract(p + 0.5) - 0.5);
	vec2 aa = max(fwidth(p), vec2(0.001));
	vec2 line = 1.0 - smoothstep(vec2(0.025), vec2(0.025) + aa, v);
	return max(line.x, line.y);
}
void fragment() {
	vec3 weight = abs(normalize(local_normal));
	weight = pow(weight, vec3(5.0));
	weight /= max(weight.x+weight.y+weight.z, 0.001);
	vec3 p = local_position * 0.75;
	float line = grid_line(p.yz)*weight.x + grid_line(p.xz)*weight.y + grid_line(p.xy)*weight.z;
	ALBEDO = mix(grid_color.rgb * 0.13, grid_color.rgb, clamp(line,0.0,1.0));
}
