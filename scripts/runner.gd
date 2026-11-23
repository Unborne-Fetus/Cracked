extends CharacterBody3D
## Momentum-driven capsule. Forward is +X, steering is lateral (+/-Z).
## Speed increases only while sliding on level/downhill ground; no speed cap.

const START_SPEED := 22.0
const MIN_SPEED := 7.0
const GRAVITY := 27.0
const JUMP_IMPULSE := 12.0
const SLIDE_BASE_ACCEL := 3.0
const SLIDE_DOWNHILL_ACCEL := 64.0
const UPHILL_DRAG := 35.0
const GROUND_FRICTION := 1.2
const AIR_FRICTION := 0.45
const UPHILL_SLIDE_LIMIT := 0.025

var speed := START_SPEED
var touch_axis := 0.0
var queued_jump := false
var jump_held := false
var grounded_last_frame := false
var is_sliding := false
var touch_slide := false
var gameplay_seconds := 0.0
var avatar: Node3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 1.5
	floor_max_angle = deg_to_rad(65.0)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.55
	shape.height = 2.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	_create_avatar()

func _create_avatar() -> void:
	avatar = Node3D.new()
	add_child(avatar)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.04, 0.77, 0.97)
	suit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	suit.emission_enabled = true
	suit.emission = Color(0.03, 0.42, 0.92)
	suit.emission_energy_multiplier = 1.5
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(1.0, 0.18, 0.62)
	trim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.9, 1.3, 0.72)
	body.mesh = body_mesh
	body.position.y = -0.02
	body.material_override = suit
	avatar.add_child(body)
	var visor := MeshInstance3D.new()
	var visor_mesh := SphereMesh.new()
	visor_mesh.radius = 0.39
	visor_mesh.height = 0.78
	visor.mesh = visor_mesh
	visor.position = Vector3(0.20, 0.78, 0.0)
	visor.material_override = trim
	avatar.add_child(visor)
	var trail := MeshInstance3D.new()
	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(1.0, 0.09, 0.14)
	trail.mesh = trail_mesh
	trail.position = Vector3(-0.60, -0.6, 0)
	trail.material_override = trim
	avatar.add_child(trail)

func reset_run(spawn_position: Vector3) -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	speed = START_SPEED
	touch_axis = 0.0
	queued_jump = false
	jump_held = false
	grounded_last_frame = false
	is_sliding = false
	touch_slide = false
	gameplay_seconds = 0.0
	set_physics_process(true)

func request_jump() -> void:
	queued_jump = true

func set_first_person(enabled: bool) -> void:
	if avatar != null:
		avatar.visible = not enabled

func can_slide_on_grade(grade: float) -> bool:
	# Grade > 0 means uphill in the forward direction. Uphill cancels a slide.
	return grade <= UPHILL_SLIDE_LIMIT

func step_speed(current: float, grade: float, grounded: bool, sliding_requested: bool, delta: float) -> float:
	# Pure speed model (also exercised by a headless regression test).
	# Only a grounded slide on non-uphill terrain adds horizontal speed.
	var next_speed := current
	if grounded and sliding_requested and can_slide_on_grade(grade):
		next_speed += (SLIDE_BASE_ACCEL + maxf(-grade, 0.0) * SLIDE_DOWNHILL_ACCEL) * delta
	elif grounded:
		next_speed -= (GROUND_FRICTION + maxf(grade, 0.0) * UPHILL_DRAG) * delta
	else:
		next_speed -= AIR_FRICTION * delta
	# Minimum movement prevents deadlocking at the start; no upper speed limit.
	return maxf(MIN_SPEED, next_speed)

func _physics_process(delta: float) -> void:
	gameplay_seconds += delta
	var grounded := is_on_floor()
	var steer := touch_axis
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steer -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steer += 1.0
	steer += Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	steer = clampf(steer, -1.0, 1.0)
	
	var slide_requested := touch_slide or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	var key_jump := Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if key_jump and not jump_held:
		queued_jump = true
	jump_held = key_jump
	
	var grade := 0.0
	if grounded:
		var normal := get_floor_normal()
		# On this track, -normal.x / normal.y is forward d(height)/dx.
		grade = -normal.x / maxf(normal.y, 0.2)
		velocity.y = -1.2
		if queued_jump:
			velocity.y = JUMP_IMPULSE
			grounded = false
			queued_jump = false
	else:
		velocity.y -= GRAVITY * delta
	is_sliding = grounded and slide_requested and can_slide_on_grade(grade)
	speed = step_speed(speed, grade, grounded, slide_requested, delta)
	# No propulsion, boost pads, collision bonuses, or upper velocity clamp.
	velocity.x = speed
	var lateral_target := steer * minf(speed * 0.48, 19.0)
	velocity.z = move_toward(velocity.z, lateral_target, 28.0 * delta)
	move_and_slide()
	grounded_last_frame = is_on_floor()
	if avatar != null:
		avatar.rotation.x = lerpf(avatar.rotation.x, -steer * 0.18, minf(delta * 8.0, 1.0))
		avatar.scale.y = lerpf(avatar.scale.y, 0.68 if is_sliding else 1.0, minf(delta * 12.0, 1.0))
		avatar.position.y = lerpf(avatar.position.y, -0.27 if is_sliding else 0.0, minf(delta * 12.0, 1.0))
