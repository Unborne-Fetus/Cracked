extends Node3D
## Arcade track-relative runner: the local up vector turns with the ribbon.

const START_SPEED := 22.0
const MIN_SPEED := 7.0
const SLIDE_BASE_ACCEL := 3.0
const SLIDE_DOWNHILL_ACCEL := 55.0
const SLIDE_UPHILL_DRAG := 25.0
const UPHILL_GRADE_DRAG := 52.0
const RUN_DRAG := 1.2
const AIR_DRAG := 2.2
const SLIDE_DRAIN := 0.42
const SLIDE_RECOVERY := 0.65
const EXHAUSTED_SLIDE_DRAG := 9.0
const LANDING_RECOVERY := 0.18
const JUMP_IMPULSE := 12.5
const JUMP_SPEED_GAIN := 1.55
const MAX_JUMP_IMPULSE := 45.0
const GRAVITY := 27.0
const OBSTACLE_RETAIN := 0.30

var speed := START_SPEED
var distance := 8.0
var lane := 0.0
var lateral_speed := 0.0
var height := 0.0
var vertical_speed := 0.0
var touch_axis := 0.0
var touch_slide := false
var queued_jump := false
var jump_held := false
var is_sliding := false
var uphill := false
var slide_grip := 1.0
var landing_timer := 0.0
var hit_timer := 0.0
var hits := 0
var avatar: Node3D

func _ready() -> void:
	avatar = Node3D.new()
	add_child(avatar)
	var cyan := StandardMaterial3D.new()
	cyan.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyan.albedo_color = Color(0.04, 0.85, 1.0)
	var pink := StandardMaterial3D.new()
	pink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pink.albedo_color = Color(1.0, 0.14, 0.56)
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 1.25, 0.8)
	body.mesh = mesh
	body.position.y = 0.64
	body.material_override = cyan
	avatar.add_child(body)
	var visor := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.37
	sphere.height = 0.74
	visor.mesh = sphere
	visor.position = Vector3(0, 1.5, -0.15)
	visor.material_override = pink
	avatar.add_child(visor)

func reset_run(course: Node3D) -> void:
	distance = 8.0
	speed = START_SPEED
	lane = 0.0
	lateral_speed = 0.0
	height = 0.0
	vertical_speed = 0.0
	touch_axis = 0.0
	touch_slide = false
	queued_jump = false
	jump_held = false
	is_sliding = false
	uphill = false
	slide_grip = 1.0
	landing_timer = 0.0
	hit_timer = 0.0
	hits = 0
	sync_pose(course)

func request_jump() -> void:
	queued_jump = true

func set_first_person(enabled: bool) -> void:
	avatar.visible = not enabled

func can_slide_on_grade(_grade: float) -> bool:
	return true

func step_speed(current: float, grade: float, grounded: bool, slide: bool, delta: float, grip: float = 1.0) -> float:
	var change := 0.0
	if grounded and slide:
		if grade > 0.025:
			change = -SLIDE_UPHILL_DRAG - grade * UPHILL_GRADE_DRAG
		else:
			var traction := smoothstep(0.0, 0.30, grip)
			var gain := SLIDE_BASE_ACCEL + maxf(-grade, 0.0) * SLIDE_DOWNHILL_ACCEL
			change = lerpf(-EXHAUSTED_SLIDE_DRAG, gain, traction)
	elif grounded:
		change = -RUN_DRAG - maxf(grade, 0.0) * 14.0
	else:
		change = -AIR_DRAG
	# No cap; the low-speed walking floor cannot increase a slower value.
	return maxf(minf(current, MIN_SPEED), current + change * delta)

func update_slide_grip(delta: float, grounded: bool, slide: bool) -> void:
	# Releasing slide on the ground restores traction. Holding it in the
	# air does not reset the meter, so repeated jumps cannot bypass fatigue.
	if grounded and slide:
		slide_grip = maxf(0.0, slide_grip - SLIDE_DRAIN * delta)
	elif grounded and not slide:
		slide_grip = minf(1.0, slide_grip + SLIDE_RECOVERY * delta)

func jump_impulse_for_speed(current: float) -> float:
	# Square-root scaling rewards speed without making jumps unboundedly tall.
	# The vertical impulse limit does NOT cap forward velocity.
	return minf(MAX_JUMP_IMPULSE, JUMP_IMPULSE + JUMP_SPEED_GAIN * sqrt(maxf(0.0, current - START_SPEED)))

func apply_obstacle_hit() -> void:
	speed *= OBSTACLE_RETAIN
	speed = maxf(minf(speed, MIN_SPEED), speed)
	hits += 1
	hit_timer = 0.85

func sync_pose(course: Node3D) -> void:
	var frame: Transform3D = course.call("sample", distance)
	transform = Transform3D(frame.basis, frame.origin + frame.basis.x * lane + frame.basis.y * height)

func is_grounded() -> bool:
	return height <= 0.0001

func tick(delta: float, course: Node3D) -> void:
	var steer := touch_axis
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steer -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steer += 1.0
	steer = clampf(steer + Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -1.0, 1.0)
	var slide := touch_slide or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	var jump := Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if jump and not jump_held:
		queued_jump = true
	jump_held = jump
	var ground := is_grounded()
	landing_timer = maxf(0.0, landing_timer - delta)
	if ground and queued_jump and landing_timer <= 0.0:
		vertical_speed = jump_impulse_for_speed(speed)
		height = 0.01
		ground = false
		queued_jump = false
	var frame: Transform3D = course.call("sample", distance)
	var grade := -frame.basis.z.y
	is_sliding = ground and slide
	uphill = grade > 0.025
	update_slide_grip(delta, ground, slide)
	speed = step_speed(speed, grade, ground, slide, delta, slide_grip)
	var old_s := distance
	var old_lane := lane
	var old_height := height
	# Wider track needs stronger steering, especially at high forward speeds.
	var steer_speed := 23.0 + minf(speed * 0.10, 12.0)
	# Standing gives precise lane changes; sliding trades control for speed.
	var steering_factor := 0.62 if is_sliding else (0.72 if not ground else 1.0)
	lateral_speed = move_toward(lateral_speed, steer * steer_speed * steering_factor, 82.0 * delta * steering_factor)
	var limit: float = course.call("lane_limit")
	lane = clampf(lane + lateral_speed * delta, -limit, limit)
	if not ground:
		vertical_speed -= GRAVITY * delta
		height = maxf(0.0, height + vertical_speed * delta)
		if height <= 0.0:
			vertical_speed = 0.0
			landing_timer = LANDING_RECOVERY
			queued_jump = false
	hit_timer = maxf(0.0, hit_timer - delta)
	distance += speed * delta
	course.call("stream", distance)
	var count: int = course.call("swept_obstacles", old_s, distance, old_lane, lane, old_height, height, 0.95 if is_sliding else 1.7)
	for _i in range(count):
		apply_obstacle_hit()
	sync_pose(course)
	avatar.scale.y = lerpf(avatar.scale.y, 0.55 if is_sliding else 1.0, minf(delta * 12.0, 1.0))
