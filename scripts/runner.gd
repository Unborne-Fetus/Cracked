extends Node3D
## Horizontal momentum, terrain tangency, natural takeoff and swept landing.
const GRAVITY := 32.0
const START_SPEED := 28.0
const FOOT := 0.08
var speed := START_SPEED
var lateral := 0.0
var vy := 0.0
var grounded := true
var diving := false
var fallen := false
var jump_queued := false
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
	jump_queued = false
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
	var gravity_gain := -slope * (48.0 if slope < 0.0 else 30.0)
	var drive := 7.0 * (1.0 - v / 38.0)
	var drag := 0.00020 * v * v
	return clampf(v + (gravity_gain + drive - drag) * dt, 14.0, 220.0)

static func landing_speed(v: Vector3, n: Vector3, slope: float, dive: bool) -> float:
	var impact := maxf(0.0, -v.dot(n))
	var tangent := v - n * v.dot(n)
	var forward := maxf(0.0, -tangent.z)
	var good := slope < -0.12 and impact < 20.0
	var boost := (minf(15.0, maxf(0.0, -v.y) * 0.24 + 4.0) if dive else 4.0) if good else 0.0
	var retain := 1.0 if impact < 12.0 else clampf(1.0 - (impact - 12.0) * 0.011, 0.48, 1.0)
	return clampf(forward * retain + boost, 14.0, 220.0)

func request_jump() -> void:
	jump_queued = true

func _steer() -> float:
	var result := touch_steer + float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	for id in Input.get_connected_joypads():
		var axis := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
		if absf(axis) > 0.15:
			result += axis
	return clampf(result, -1.0, 1.0)

func _dive() -> bool:
	if touch_dive or Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_F):
		return true
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER) or Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT) > 0.4:
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

func _step(dt: float, course: Node3D, steer: float, dive: bool) -> void:
	land_lock = maxf(0.0, land_lock - dt)
	var old := position
	var s := -position.z
	var g: Vector2 = course.call("grade", position.x, s)
	var target_lateral := steer * minf(38.0, speed * 0.60)
	lateral = lerpf(lateral, target_lateral, 1.0 - exp(-dt * (7.0 if grounded else 2.5)))
	if grounded:
		speed = ground_speed(speed, g.y, dt)
		var curve: float = course.call("curvature", position.x, s)
		var lift := speed * speed * curve < -GRAVITY * 0.94
		if land_lock <= 0.0 and (jump_queued or lift):
			grounded = false
			vy = g.y * speed + g.x * lateral + (11.5 if jump_queued else 1.2)
			land_lock = 0.16
		jump_queued = false
	if grounded:
		position.x += lateral * dt
		position.z -= speed * dt
		position.y = float(course.call("elevation", position.x, -position.z)) + FOOT
		diving = false
	else:
		jump_queued = false
		diving = dive
		vy -= GRAVITY * (2.7 if diving else 1.0) * dt
		speed = maxf(12.0, speed - 0.32 * dt)
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
			var impact := maxf(0.0, -velocity.dot(normal))
			speed = landing_speed(velocity, normal, slope.y, diving)
			position.y = float(course.call("elevation", position.x, -position.z)) + FOOT
			vy = 0.0
			grounded = true
			land_lock = 0.28
			cue = "PERFECT LANDING" if slope.y < -0.12 and impact < 20.0 else ("HARD LANDING" if impact > 25.0 else "")
			cue_time = 0.8 if not cue.is_empty() else 0.0
		else:
			position = next
	if absf(position.x) > 96.0:
		fallen = true
		return
	if bool(course.call("obstacle_hit", old, position)):
		speed = maxf(14.0, speed * 0.60)
		cue = "MOMENTUM LOST"
		cue_time = 0.65

func _pose(dt: float, course: Node3D) -> void:
	gait += dt * clampf(speed * 0.24, 5.0, 24.0)
	var slope: Vector2 = course.call("grade", position.x, -position.z)
	var pitch := -atan(slope.y) if grounded else clampf(atan2(vy, speed), -0.8, 0.65)
	model.rotation.x = lerpf(model.rotation.x, pitch + (0.22 if grounded else (0.55 if diving else -0.05)), 1.0 - exp(-dt * 10.0))
	model.rotation.y = lerpf(model.rotation.y, -atan2(lateral, speed), 1.0 - exp(-dt * 9.0))
	for i in range(2):
		var sign_value := 1.0 if i == 0 else -1.0
		var stride := sin(gait) * sign_value * 0.85 if grounded else (-0.45 if diving else sign_value * 0.25)
		legs[i].rotation.x = lerpf(legs[i].rotation.x, stride, 1.0 - exp(-dt * 18.0))
		arms[i].rotation.x = lerpf(arms[i].rotation.x, -stride if grounded else (1.0 if diving else -0.7), 1.0 - exp(-dt * 18.0))
