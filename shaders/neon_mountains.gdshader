shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform float velocity=0.0;
uniform float progress=0.0;
void vertex(){
	float a=UV.x*6.2831853;
	float r=UV.y;
	float clock=TIME*(0.45+velocity*1.7);
	float profile=sin(3.14159265*r);
	float ridge=0.50+0.25*sin(a*9.0+clock+r*8.0)+0.16*sin(a*17.0-clock*0.73+r*13.0)+0.09*sin(a*29.0+clock*1.3);
	float extreme=90.0+140.0*progress+560.0*pow(velocity,1.4);
	VERTEX.y=profile*(20.0+extreme*pow(max(0.0,ridge),1.7))*(0.70+0.30*sin(clock+r*11.0));
}
void fragment(){
	vec2 grid=UV*vec2(128.0,18.0);
	vec2 line=abs(fract(grid+0.5)-0.5);
	float edge=1.0-smoothstep(0.025,0.075,min(line.x,line.y));
	vec3 fill=vec3(0.026,0.006,0.054);
	vec3 neon=mix(vec3(0.55,0.035,0.83),vec3(0.98,0.06,0.70),clamp(velocity*0.65,0.0,1.0));
	ALBEDO=mix(fill,neon,edge*(0.65+0.25*clamp(velocity,0.0,1.0)));
}
