extends Node3D
## Optional circuit combat. Abstract pulse tags, robotic drones, shields.
var enabled := false
var shield := 100.0
var score := 0
var cooldown := 0.0
var spawn_clock := 0.0
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
	shield=100.0
	score=0
	cooldown=0.0
	spawn_clock=0.7
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
	drones.append({"node":node,"body":body,"ring":ring,"s":at,"lane":lane,"health":2,"charge":rng.randf_range(1.0,2.0),"phase":rng.randf()*TAU})

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

func tick(delta: float,course: Node3D,runner: Node3D) -> void:
	if not enabled:
		return
	cooldown=maxf(0.0,cooldown-delta)
	spawn_clock-=delta
	if spawn_clock<=0.0 and drones.size()<8:
		_spawn(course,runner)
		spawn_clock=1.1
	for i in range(pulses.size()-1,-1,-1):
		pulses[i]["time"]=float(pulses[i]["time"])-delta
		if float(pulses[i]["time"])<=0.0:
			pulses[i]["node"].queue_free()
			pulses.remove_at(i)
	for i in range(drones.size()-1,-1,-1):
		var data:=drones[i]
		var at:=float(data["s"])
		if at<float(runner.get("distance"))-40.0 or not bool(course.call("has_distance",at)):
			data["node"].queue_free()
			drones.remove_at(i)
			continue
		data["phase"]=float(data["phase"])+delta*2.0
		var frame: Transform3D=course.call("surface_frame",at,float(data["lane"]),1)
		var node: Node3D=data["node"]
		node.transform=Transform3D(frame.basis,frame.origin+frame.basis.y*(5.5+sin(float(data["phase"]))*1.4))
		var range_to_player:=node.position.distance_to(runner.position)
		if range_to_player<100.0:
			data["charge"]=float(data["charge"])-delta
			var alert:=float(data["charge"])<0.55
			(data["ring"] as MeshInstance3D).material_override=alert_mat if alert else drone_mat
			if float(data["charge"])<=0.0:
				# A visible charged pulse is avoidable by changing lane or
				# jumping out of the target corridor during the warning.
				var close_lane:=absf(float(runner.get("lane"))-float(data["lane"]))<9.0
				_pulse(node.position,runner.position+Vector3.UP*0.8,enemy_mat,0.12)
				if close_lane and bool(runner.get("grounded")):
					shield=maxf(0.0,shield-12.0)
					runner.set("speed",maxf(7.0,float(runner.get("speed"))*0.94))
				data["charge"]=2.2
		else:
			(data["ring"] as MeshInstance3D).material_override=drone_mat
