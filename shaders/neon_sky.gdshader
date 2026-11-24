shader_type sky;
float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
void sky() {
	vec3 d = normalize(EYEDIR);
	float elevation = d.y;
	float azimuth = atan(d.z, d.x);
	vec3 horizon = vec3(0.105,0.065,0.21);
	vec3 color = mix(horizon,vec3(0.014,0.020,0.075),smoothstep(0.0,0.85,elevation));
	if (elevation < 0.0) {
		color = mix(horizon,vec3(0.003,0.007,0.027),smoothstep(0.0,0.65,-elevation));
	}
	float band = exp(-pow((elevation-0.23-0.055*sin(azimuth*3.0)-0.035*sin(azimuth*7.0))/0.075,2.0));
	color += band * vec3(0.016,0.085,0.105);
	vec3 sun_dir = normalize(vec3(-0.76,0.105,0.61));
	float distance_sun = acos(clamp(dot(d,sun_dir),-1.0,1.0));
	color += vec3(0.16,0.035,0.12)*exp(-distance_sun*7.0);
	float disc = 1.0-smoothstep(0.078,0.081,distance_sun);
	float stripe = smoothstep(0.20,0.40,fract(elevation*83.0));
	color = mix(color,vec3(0.92,0.24,0.45),disc*mix(stripe,1.0,smoothstep(0.08,0.16,elevation)));
	vec3 grid = d*190.0;
	vec3 cell = floor(grid);
	float star = (1.0-smoothstep(0.06,0.23,length(fract(grid)-0.5)))*step(0.985,hash31(cell))*smoothstep(0.035,0.25,elevation);
	color += star*mix(vec3(0.35,0.68,0.95),vec3(0.96,0.88,0.78),hash31(cell+vec3(7.0)));
	float ridge = -0.018+0.028*sin(azimuth*9.0)+0.018*sin(azimuth*17.0+0.6)+0.009*sin(azimuth*31.0);
	color = mix(color,vec3(0.012,0.014,0.043),(1.0-smoothstep(ridge-0.004,ridge+0.002,elevation))*0.82);
	COLOR = color;
}
