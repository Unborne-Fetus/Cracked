shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform float velocity=0.0;
uniform float progress=0.0;

// Piecewise-linear ridges preserve sharp peaks rather than rounded sine hills.
float ridge(float x){
	return 1.0-abs(fract(x)*2.0-1.0);
}
void vertex(){
	float u=UV.x;
	float r=UV.y;
	// Fixed angular phases keep peaks in place even at maximum speed.
	float primary=ridge(u*9.0+0.11);
	float secondary=ridge(u*17.0+r*0.72+0.37);
	float detail=ridge(u*29.0-r*0.53+0.09);
	float crest=0.08+0.68*primary+0.18*secondary+0.14*detail;
	float center=0.40+0.12*ridge(u*7.0+0.31);
	float profile=max(0.0,min(r/center,(1.0-r)/(1.0-center)));
	float speed_power=pow(clamp(velocity*0.5,0.0,1.0),1.65);
	float height=135.0+100.0*progress+85.0*speed_power;
	// Slow, small vertical breathing only: no migrating ridges or large waves.
	float breathing=1.0+(0.018+0.022*speed_power)*sin(TIME*0.14+u*6.2831853*3.0);
	VERTEX.y=profile*(12.0+height*crest)*breathing;
}
void fragment(){
	vec2 grid=UV*vec2(128.0,18.0);
	vec2 line=abs(fract(grid+0.5)-0.5);
	float edge=1.0-smoothstep(0.025,0.075,min(line.x,line.y));
	float diagonal=1.0-smoothstep(0.018,0.065,abs(fract(grid.x+grid.y+0.5)-0.5));
	vec3 fill=vec3(0.026,0.006,0.054);
	vec3 neon=mix(vec3(0.55,0.035,0.83),vec3(0.98,0.06,0.70),clamp(velocity*0.65,0.0,1.0));
	ALBEDO=mix(fill,neon,max(edge,diagonal*0.52)*(0.65+0.25*clamp(velocity,0.0,1.0)));
}
