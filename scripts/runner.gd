extends CharacterBody3D
## Momentum-driven capsule. Forward is +X, steering is lateral (+/-Z).
## Ground gradient modifies speed instead of hard-capping it.

const START_SPEED := 22.0
const MIN_SPEED := 5.0
const GRAVITY := 27.0
const JUMP_IMPULSE := 12.0
const DOWNHILL_FORCE := 55.0
const UPHILL_FORCE := 41.0
const PROPULSION := 4.7
const DRAG := 0.0032

var speed := START_SPEED
var touch_axis := 0.0
var queued_jump := false
var jump_held := false
var grounded_last_frame := false
var last_boost_time := -10.0
var gameplay_seconds := 0.0
var avatar: Node3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.9
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
	last_boost_time = -10.0
	gameplay_seconds = 0.0
	set_physics_process(true)

func request_jump() -> void:
	queued_jump = true

func set_first_person(enabled: bool) -> void:
	if avatar != null:
		avatar.visible = not enabled

func add_boost(amount: float) -> void:
	speed += amount
	last_boost_time = gameplay_seconds

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
	
	var key_jump := Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if key_jump and not jump_held:
		queued_jump = true
	jump_held = key_jump
	
	if grounded:
		var normal := get_floor_normal()
		# Surface gradient: normal.x = -d(height)/dx for forward-facing ground.
		var grade := -normal.x / maxf(normal.y, 0.2)
		speed += (PROPULSION + maxf(-grade, 0.0) * DOWNHILL_FORCE - maxf(grade, 0.0) * UPHILL_FORCE) * delta
		velocity.y = -1.2
		if queued_jump:
			velocity.y = JUMP_IMPULSE + minf(speed * 0.075, 7.0)
			grounded = false
			queued_jump = false
	else:
		velocity.y -= GRAVITY * delta
		# Allow air steering without turning airborne speed into a second boost.
	
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_joy_button_pressed(0, JOY_BUTTON_B):
		speed -= 24.0 * delta
	speed -= DRAG * speed * speed * delta
	speed = maxf(MIN_SPEED, speed)
	velocity.x = speed
	var lateral_target := steer * minf(speed * 0.48, 19.0)
	velocity.z = move_toward(velocity.z, lateral_target, 28.0 * delta)
	var falling_speed := velocity.y
	move_and_slide()
	if not grounded_last_frame and is_on_floor() and falling_speed < -3.0:
		var landing_grade := -get_floor_normal().x / maxf(get_floor_normal().y, 0.2)
		# Landing into a downhill face carries speed; steep uphill landings cost speed.
		if landing_grade < -0.12:
			speed *= 1.065
		elif landing_grade > 0.16:
			speed *= 0.91
	grounded_last_frame = is_on_floor()
	if avatar != null:
		avatar.rotation.x = lerpf(avatar.rotation.x, -steer * 0.18, minf(delta * 8.0, 1.0))
