shader_type sky;
uniform float intensity : hint_range(0.0,1.0) = 0.0;
float hash31(vec3 p) {
	p=fract(p*0.1031);
	p+=dot(p,p.yzx+33.33);
	return fract((p.x+p.y)*p.z);
}
void sky(){
	vec3 d=normalize(EYEDIR);
	float y=d.y;
	float a=atan(d.z,d.x);
	float power= intensity;
	vec3 horizon=mix(vec3(0.14,0.025,0.20),vec3(0.42,0.025,0.32),power);
	vec3 color=mix(horizon,vec3(0.005,0.008,0.045),smoothstep(0.0,0.65,y));
	if(y<0.0){
		color=mix(horizon*0.45,vec3(0.003,0.004,0.021),smoothstep(0.0,0.65,-y));
	}
	// Large striped synthwave sunset, yellow at its crown, magenta at base.
	vec3 sun_dir=normalize(vec3(1.0,0.19,0.0));
	float radius=0.15+power*0.075;
	float cosdist=dot(d,sun_dir);
	float disc= smoothstep(cos(radius+0.002),cos(radius-0.002),cosdist);
	float h=clamp((y-sun_dir.y+radius)/(2.0*radius),0.0,1.0);
	float stripe=mix(smoothstep(0.30,0.46,fract(h*10.0)),1.0,smoothstep(0.55,0.80,h));
	vec3 sun=mix(vec3(0.98,0.055,0.40),vec3(1.0,0.86,0.14),h);
	color+=vec3(0.25,0.045,0.14)*pow(max(0.0,cosdist),25.0)*(0.4+power);
	color=mix(color,sun,disc*stripe);
	// Layered jagged purple mountain ranges, with neon crest.
	float ridge=-0.015+0.035*sin(a*9.0)+0.017*sin(a*23.0+0.8)+0.009*sin(a*41.0);
	float far_ridge=0.025+0.029*sin(a*6.0+0.8)+0.015*sin(a*15.0);
	color=mix(color,vec3(0.16,0.025,0.21)*(0.8+power*0.5),1.0-smoothstep(far_ridge-0.002,far_ridge+0.002,y));
	color=mix(color,vec3(0.052,0.012,0.085),1.0-smoothstep(ridge-0.002,ridge+0.002,y));
	color+=vec3(0.4,0.025,0.38)*exp(-abs(y-ridge)*220.0)*(0.35+power*0.8);
	// Infinite retro perspective grid below the horizon, no geometry cost.
	if(y< -0.026){
		vec2 p=d.xz/max(0.028,-y)*2.2;
		vec2 q=abs(fract(p)-0.5);
		float line=1.0-smoothstep(0.018,0.048,min(q.x,q.y));
		float fade=smoothstep(0.028,0.17,-y)*(1.0-smoothstep(0.80,1.0,-y));
		color+=vec3(0.22,0.035,0.47)*line*fade*(0.45+power*0.95);
	}
	vec3 grid=d*190.0;
	vec3 cell=floor(grid);
	float star=(1.0-smoothstep(0.06,0.24,length(fract(grid)-0.5)))*step(0.983,hash31(cell))*smoothstep(0.05,0.22,y);
	color+=star*vec3(0.7,0.80,1.0)*(0.45+power*0.7)*(1.0-disc);
	COLOR=color;
}
