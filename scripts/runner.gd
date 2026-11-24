extends Node3D
## Horizontal momentum, terrain tangency, natural takeoff and swept landing.
const GRAVITY := 32.0
const START_SPEED := 36.0
const MAX_SPEED := 250.0
const BOOST_COST := 28.0
const FOOT := 0.08
var speed := START_SPEED
var lateral := 0.0
var vy := 0.0
var grounded := true
var diving := false
var fallen := false
var boost_queued := false
var energy := 35.0
var boost_time := 0.0
var air_time := 0.0
var perfect_landings := 0
var good_landings := 0
var bad_landings := 0
var aim_steer := 0.0
var landing_compression := 0.0
var trail: MeshInstance3D
var trail_mesh := ImmediateMesh.new()
var trail_material := StandardMaterial3D.new()
var trail_samples: Array[Dictionary] = []
var trail_clock := 0.0
var scarf: Node3D
var touch_steer := 0.0
var touch_dive := false
var land_lock := 0.0
var cue := ""
var cue_time := 0.0
var gait := 0.0
var model: Node3D
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []

func _ready() -> void:
	model = Node3D.new()
	add_child(model)
	var suit := _material(Color(0.94, 0.79, 0.40))
	var dark := _material(Color(0.15, 0.17, 0.29))
	var accent := _material(Color(0.88, 0.28, 0.31))
	_part(model, Vector3(0.0, 1.06, 0.0), Vector3(0.55, 0.63, 0.32), suit)
	_part(model, Vector3(0.0, 0.74, 0.0), Vector3(0.46, 0.25, 0.28), dark)
	var head := MeshInstance3D.new()
	var helmet := SphereMesh.new()
	helmet.radius = 0.22
	helmet.height = 0.44
	head.mesh = helmet
	head.material_override = accent
	head.position = Vector3(0.0, 1.57, 0.0)
	model.add_child(head)
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.33, 1.29, 0.0)
		model.add_child(arm)
		_part(arm, Vector3(0.0, -0.22, 0.0), Vector3(0.16, 0.48, 0.17), suit)
		arms.append(arm)
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.14, 0.75, 0.0)
		model.add_child(leg)
		_part(leg, Vector3(0.0, -0.30, 0.0), Vector3(0.20, 0.64, 0.20), dark)
		_part(leg, Vector3(0.0, -0.65, -0.065), Vector3(0.22, 0.14, 0.35), accent)
		legs.append(leg)
	# Original scarf silhouette, with a world-space speed ribbon.
	scarf = Node3D.new()
	scarf.position = Vector3(0.0, 1.36, 0.17)
	model.add_child(scarf)
	_part(scarf, Vector3(0.0, 0.0, 0.38), Vector3(0.23, 0.08, 0.84), accent)
	trail = MeshInstance3D.new()
	trail.mesh = trail_mesh
	trail.top_level = true
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_material.vertex_color_use_as_albedo = true
	add_child(trail)

func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m

func _part(parent: Node3D, at: Vector3, dimensions: Vector3, mat: Material) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	instance.mesh = box
	instance.material_override = mat
	instance.position = at
	parent.add_child(instance)

func reset(course: Node3D) -> void:
	speed = START_SPEED
	lateral = 0.0
	vy = 0.0
	grounded = true
	diving = false
	fallen = false
	boost_queued = false
	energy = 35.0
	boost_time = 0.0
	air_time = 0.0
	perfect_landings = 0
	good_landings = 0
	bad_landings = 0
	aim_steer = 0.0
	landing_compression = 0.0
	trail_samples.clear()
	trail_mesh.clear_surfaces()
	trail_clock = 0.0
	touch_steer = 0.0
	touch_dive = false
	land_lock = 0.0
	cue = ""
	cue_time = 0.0
	gait = 0.0
	position = Vector3(0.0, float(course.call("elevation", 0.0, 0.0)) + FOOT, 0.0)
	model.rotation = Vector3.ZERO

func progress() -> float:
	return -position.z

static func ground_speed(v: float, slope: float, dt: float) -> float:
	# Maintain a strong running pace; downhill tangent gravity builds speed.
	var slope_force := -slope * (65.0 if slope < 0.0 else 22.0)
	var drive := 9.0 * (1.0 - v / 65.0)
	var drag := 0.00010 * v * v
	return clampf(v + (slope_force + drive - drag) * dt, 22.0, MAX_SPEED)

static func should_launch(v: float, curve: float, slope: float) -> bool:
	return v * v * curve < -GRAVITY * pow(1.0 + slope * slope, 1.5) * 0.82

static func landing_quality(v: Vector3, n: Vector3, slope: float) -> String:
	var impact := maxf(0.0, -v.dot(n))
	var ratio := impact / maxf(25.0, v.length())
	if slope < -0.10 and ratio < 0.22:
		return "PERFECT"
	if ratio < 0.38:
		return "GOOD"
	if ratio < 0.62:
		return "OK"
	return "BAD"

static func landing_speed(v: Vector3, n: Vector3, slope: float, dive: bool) -> float:
	var quality := landing_quality(v, n, slope)
	var tangent := v - n * v.dot(n)
	var forward := maxf(0.0, -tangent.z)
	var horizontal := maxf(0.0, -v.z)
	match quality:
		"PERFECT":
			return clampf(maxf(horizontal, forward) * 1.12 + (8.0 if dive else 4.0), 22.0, MAX_SPEED)
		"GOOD":
			return clampf(maxf(horizontal * 0.98, forward) + 2.5, 22.0, MAX_SPEED)
		"OK":
			return clampf(horizontal * 0.82, 22.0, MAX_SPEED)
		_:
			return clampf(horizontal * 0.52, 22.0, MAX_SPEED)

func request_boost() -> void:
	boost_queued = true

func _activate_boost() -> bool:
	if energy < BOOST_COST or boost_time > 0.0:
		return false
	energy -= BOOST_COST
	boost_time = 0.65
	speed = minf(MAX_SPEED, speed + 18.0)
	if not grounded:
		vy = maxf(vy, 8.0)
	cue = "BOOST"
	cue_time = 0.55
	return true

func _steer() -> float:
	var result := touch_steer + aim_steer + float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	for id in Input.get_connected_joypads():
		var axis := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
		if absf(axis) > 0.15:
			result += axis
	return clampf(result, -1.0, 1.0)

func _dive() -> bool:
	if touch_dive or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SHIFT):
		return true
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_A) or Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT) > 0.4:
			return true
	return false

func tick(dt: float, course: Node3D) -> void:
	if fallen:
		return
	cue_time = maxf(0.0, cue_time - dt)
	var steer := _steer()
	var dive := _dive()
	var count := maxi(1, int(ceil(dt / (1.0 / 120.0))))
	var step := dt / float(count)
	for i in range(count):
		_step(step, course, steer, dive)
		if fallen:
			break
	_pose(dt, course)
	_update_trail(dt)

func _step(dt: float, course: Node3D, steer: float, dive: bool) -> void:
	land_lock = maxf(0.0, land_lock - dt)
	var old := position
	var s := -position.z
	var g: Vector2 = course.call("grade", position.x, s)
	var target_lateral := steer * minf(72.0, speed * 0.74)
	lateral = lerpf(lateral, target_lateral, 1.0 - exp(-dt * (8.0 if grounded else 4.0)))
	if boost_queued:
		_activate_boost()
		boost_queued = false
	if boost_time > 0.0:
		speed = minf(MAX_SPEED, speed + 31.0 * dt)
		boost_time = maxf(0.0, boost_time - dt)
	if grounded:
		speed = ground_speed(speed, g.y, dt)
		var curve: float = course.call("curvature", position.x, s)
		if land_lock <= 0.0 and should_launch(speed, curve, g.y):
			grounded = false
			vy = g.y * speed + g.x * lateral + 1.0
			air_time = 0.0
			land_lock = 0.075
	if grounded:
		position.x += lateral * dt
		position.z -= speed * dt
		position.y = float(course.call("elevation", position.x, -position.z)) + FOOT
		diving = false
	else:
		air_time += dt
		diving = dive
		# Hold to descend, release to preserve airtime. Boost briefly floats.
		vy -= GRAVITY * (2.5 if diving else (0.45 if boost_time > 0.0 else 1.0)) * dt
		speed = maxf(22.0, speed - 0.14 * dt)
		var next := position + Vector3(lateral, vy, -speed) * dt
		var next_floor := float(course.call("elevation", next.x, -next.z)) + FOOT
		# Substeps and a bracketed crossing prevent tunneling at high speed.
		if next.y <= next_floor and (land_lock <= 0.0 or vy < 0.0):
			var low := 0.0
			var high := 1.0
			for i in range(9):
				var mid := (low + high) * 0.5
				var p := old.lerp(next, mid)
				if p.y > float(course.call("elevation", p.x, -p.z)) + FOOT:
					low = mid
				else:
					high = mid
			position = old.lerp(next, high)
			var normal: Vector3 = course.call("normal_at", position.x, -position.z)
			var slope: Vector2 = course.call("grade", position.x, -position.z)
			var velocity := Vector3(lateral, vy, -speed)
			var quality := landing_quality(velocity, normal, slope.y)
			if air_time >= 0.10:
				speed = landing_speed(velocity, normal, slope.y, diving)
				match quality:
					"PERFECT":
						perfect_landings += 1
						energy = minf(100.0, energy + 22.0 + minf(10.0, air_time * 4.0))
					"GOOD":
						good_landings += 1
						energy = minf(100.0, energy + 12.0)
					"BAD":
						bad_landings += 1
					_:
						energy = minf(100.0, energy + 3.0)
				cue = quality + " LANDING"
				cue_time = 0.7
				landing_compression = 1.0
			position.y = float(course.call("elevation", position.x, -position.z)) + FOOT
			vy = 0.0
			grounded = true
			land_lock = 0.14
			air_time = 0.0
		else:
			position = next
	if absf(position.x) > 110.0:
		fallen = true
		return
	if bool(course.call("obstacle_hit", old, position)):
		speed = maxf(14.0, speed * 0.60)
		cue = "MOMENTUM LOST"
		cue_time = 0.65

func _pose(dt: float, course: Node3D) -> void:
	gait += dt * clampf(speed * 0.24, 5.0, 24.0)
	var slope: Vector2 = course.call("grade", position.x, -position.z)
	landing_compression = move_toward(landing_compression, 0.0, dt * 4.8)
	model.scale.y = 1.0 - landing_compression * 0.16
	var pitch := atan(slope.y) if grounded else clampf(atan2(vy, speed), -0.8, 0.65)
	model.rotation.x = lerpf(model.rotation.x, pitch - (0.27 if grounded else (0.52 if diving else 0.02)), 1.0 - exp(-dt * 10.0))
	model.rotation.z = lerpf(model.rotation.z, -lateral / maxf(speed, 25.0) * 0.30, 1.0 - exp(-dt * 8.0))
	scarf.rotation.x = -0.12 + sin(gait * 0.55) * 0.12 - smoothstep(35.0, 130.0, speed) * 0.30
	model.rotation.y = lerpf(model.rotation.y, -atan2(lateral, speed), 1.0 - exp(-dt * 9.0))
	for i in range(2):
		var sign_value := 1.0 if i == 0 else -1.0
		var stride := sin(gait) * sign_value * 0.85 if grounded else (-0.45 if diving else sign_value * 0.25)
		legs[i].rotation.x = lerpf(legs[i].rotation.x, stride, 1.0 - exp(-dt * 18.0))
		arms[i].rotation.x = lerpf(arms[i].rotation.x, -stride if grounded else (1.0 if diving else -0.7), 1.0 - exp(-dt * 18.0))

func _update_trail(dt: float) -> void:
	trail_clock += dt
	var strength := smoothstep(32.0, 115.0, speed)
	var point := global_position + Vector3(0.0, 1.1, 0.35)
	while not trail_samples.is_empty() and (trail_clock - float(trail_samples[0]["t"]) > 0.48 or trail_samples.size() >= 48):
		trail_samples.pop_front()
	if strength > 0.01:
		trail_samples.append({"p": point, "t": trail_clock})
	trail_mesh.clear_surfaces()
	if trail_samples.size() < 2:
		return
	trail.global_position = point
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, trail_material)
	for item in trail_samples:
		var fade := clampf(1.0 - (trail_clock - float(item["t"])) / 0.48, 0.0, 1.0)
		var local: Vector3 = item["p"] - point
		var width := (0.10 + 0.35 * strength) * fade
		var tint := Color(1.0, 0.76, 0.40, strength * fade * fade * 0.85)
		trail_mesh.surface_set_color(tint)
		trail_mesh.surface_add_vertex(local - Vector3.RIGHT * width)
		trail_mesh.surface_set_color(tint)
		trail_mesh.surface_add_vertex(local + Vector3.RIGHT * width)
	trail_mesh.surface_end()
