extends Node3D
## Circuit combat: robotic drones and momentum-only penalties.
var enabled := false
var score := 0
var cooldown := 0.0
var spawn_clock := 0.0
var reward_pending := 0
var reward_timer := 0.0
var attack_timer := 0.0
var last_attack_loss := 0.0
const DRONE_CAP := 4
var drones: Array[Dictionary] = []
var pulses: Array[Dictionary] = []
var body_mesh: SphereMesh
var ring_mesh: TorusMesh
var drone_mat: StandardMaterial3D
var alert_mat: StandardMaterial3D
var player_mat: StandardMaterial3D
var enemy_mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=color
	return mat

func _ready() -> void:
	body_mesh=SphereMesh.new()
	body_mesh.radius=1.3
	body_mesh.height=2.6
	body_mesh.radial_segments=12
	body_mesh.rings=6
	ring_mesh=TorusMesh.new()
	ring_mesh.inner_radius=1.4
	ring_mesh.outer_radius=1.8
	ring_mesh.rings=12
	ring_mesh.ring_segments=8
	drone_mat=_material(Color(0.94,0.13,0.55))
	alert_mat=_material(Color(1.0,0.76,0.16))
	player_mat=_material(Color(0.15,1.0,0.95))
	enemy_mat=_material(Color(1.0,0.34,0.28))

func reset(active: bool, seed_value: int = 0) -> void:
	for child in get_children():
		child.queue_free()
	drones.clear()
	pulses.clear()
	enabled=active
	score=0
	cooldown=0.0
	spawn_clock=1.2
	reward_pending=0
	reward_timer=0.0
	attack_timer=0.0
	last_attack_loss=0.0
	rng.seed=seed_value

func _mesh(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=mat
	parent.add_child(node)
	return node

func _spawn(course: Node3D, runner: Node3D) -> void:
	var at: float=float(runner.get("distance"))+clampf(float(runner.get("speed"))*2.8,105.0,420.0)
	if not bool(course.call("has_distance",at)):
		return
	var lane_limit: float=float(course.call("half_width_at",at))-8.0
	var lane:=rng.randf_range(-lane_limit,lane_limit)
	if not bool(course.call("support_at",at,lane)):
		lane=float(course.call("guided_fork_lane",at,lane,lane,0.0))
	if not bool(course.call("support_at",at,lane)):
		return
	var node:=Node3D.new()
	add_child(node)
	var body:=_mesh(node,body_mesh,drone_mat)
	var ring:=_mesh(node,ring_mesh,drone_mat)
	ring.rotation.x=PI*0.5
	drones.append({"node":node,"body":body,"ring":ring,"s":at,"lane":lane,"health":2,"charge":rng.randf_range(1.8,3.0),"phase":rng.randf()*TAU,"lead":rng.randf_range(24.0,48.0),"offset":rng.randf_range(-8.0,8.0),"warning_lane":lane})

func _pulse(origin: Vector3, target: Vector3, mat: Material, lifetime: float) -> void:
	var node:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	var span:=origin.distance_to(target)
	mesh.size=Vector3(0.11,0.11,maxf(0.1,span))
	node.mesh=mesh
	node.material_override=mat
	add_child(node)
	node.position=(origin+target)*0.5
	if span>0.01:
		var dir:=(target-origin).normalized()
		node.basis=Basis.looking_at(dir,Vector3.RIGHT if absf(dir.y)>0.98 else Vector3.UP)
	pulses.append({"node":node,"time":lifetime})

func fire(camera: Camera3D, screen: Vector2) -> void:
	if not enabled or cooldown>0.0:
		return
	cooldown=0.20
	var origin:=camera.project_ray_origin(screen)
	var direction:=camera.project_ray_normal(screen).normalized()
	var nearest:=420.0
	var hit:=-1
	for i in range(drones.size()):
		var drone: Node3D=drones[i]["node"]
		var offset:=drone.global_position-origin
		var along:=offset.dot(direction)
		if along<=0.0 or along>=nearest:
			continue
		if (offset-direction*along).length()<=2.8:
			nearest=along
			hit=i
	_pulse(origin+direction*1.0,origin+direction*nearest,player_mat,0.075)
	if hit>=0:
		var target:=drones[hit]
		target["health"]=int(target["health"])-1
		if int(target["health"])<=0:
			target["node"].queue_free()
			drones.remove_at(hit)
			score+=1
			reward_pending+=1

func _apply_momentum_hit(runner: Node3D) -> void:
	last_attack_loss = float(runner.get("speed")) * 0.40
	runner.call("combat_momentum", 0.0, 0.60)
	runner.set("momentum_reserve", maxf(0.0, float(runner.get("momentum_reserve")) - 10.0))
	attack_timer = 0.85

func tick(delta: float,course: Node3D,runner: Node3D) -> void:
	if not enabled:
		return
	cooldown=maxf(0.0,cooldown-delta)
	reward_timer=maxf(0.0,reward_timer-delta)
	attack_timer=maxf(0.0,attack_timer-delta)
	if reward_pending>0:
		var speed_value: float=runner.get("speed")
		var bonus:=float(reward_pending)*clampf(speed_value*0.16,12.0,45.0)
		runner.call("combat_momentum",bonus,1.0)
		runner.set("momentum_reserve",minf(30.0,float(runner.get("momentum_reserve"))+8.0*float(reward_pending)))
		reward_pending=0
		reward_timer=1.5
	spawn_clock-=delta
	if spawn_clock<=0.0 and drones.size()<DRONE_CAP:
		_spawn(course,runner)
		spawn_clock=3.4
	for i in range(pulses.size()-1,-1,-1):
		pulses[i]["time"]=float(pulses[i]["time"])-delta
		if float(pulses[i]["time"])<=0.0:
			pulses[i]["node"].queue_free()
			pulses.remove_at(i)
	for i in range(drones.size()-1,-1,-1):
		var data:=drones[i]
		var player_s: float=runner.get("distance")
		var player_speed: float=runner.get("speed")
		var player_lane: float=runner.get("lane")
		var lead:=float(data["lead"])+float(i)*6.0
		var goal_s:=player_s+lead+minf(player_speed*0.10,24.0)
		var at:=maxf(player_s+14.0,lerpf(float(data["s"]),goal_s,1.0-exp(-delta*3.8)))
		if not bool(course.call("has_distance",at)):
			at=player_s+14.0
		if not bool(course.call("has_distance",at)):
			continue
		data["s"]=at
		data["phase"]=float(data["phase"])+delta*2.0
		# Track the same branch and screen area instead of being passed.
		var lane_goal:=player_lane+float(data["offset"])+sin(float(data["phase"]))*3.0
		var lane_limit: float=course.call("half_width_at",at)
		lane_goal=clampf(lane_goal,-lane_limit+4.0,lane_limit-4.0)
		var guided: float=course.call("guided_fork_lane",at,lane_goal,lane_goal,0.0)
		data["lane"]=clampf(lerpf(float(data["lane"]),guided,1.0-exp(-delta*4.0)),-lane_limit+4.0,lane_limit-4.0)
		data["lane"]=float(course.call("guided_fork_lane",at,guided,float(data["lane"]),0.0))
		var frame: Transform3D=course.call("surface_frame",at,float(data["lane"]),1)
		var node: Node3D=data["node"]
		# Follow the rider's altitude too, within reasonable visibility.
		var lift:=clampf(float(runner.get("height")),0.0,120.0)
		node.transform=Transform3D(frame.basis,frame.origin+frame.basis.y*5.5+Vector3.UP*lift)
		var range_to_player:=node.position.distance_to(runner.position)
		if range_to_player<maxf(130.0,player_speed*1.4):
			var old_charge:=float(data["charge"])
			data["charge"]=old_charge-delta
			if old_charge>=0.65 and float(data["charge"])<0.65:
				data["warning_lane"]=player_lane
			var alert:=float(data["charge"])<0.65
			(data["ring"] as MeshInstance3D).material_override=alert_mat if alert else drone_mat
			if float(data["charge"])<=0.0:
				var close_lane:=absf(player_lane-float(data["warning_lane"]))<10.0
				_pulse(node.position,runner.position+Vector3.UP*0.8,enemy_mat,0.12)
				if close_lane and attack_timer<=0.0:
					_apply_momentum_hit(runner)
				data["charge"]=rng.randf_range(2.2,3.0)
		else:
			(data["ring"] as MeshInstance3D).material_override=drone_mat
