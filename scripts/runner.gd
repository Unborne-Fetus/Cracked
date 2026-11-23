extends Node3D
## Arcade track-relative runner: the local up vector turns with the ribbon.

const START_SPEED := 22.0
const MIN_SPEED := 7.0
const SLIDE_BASE_ACCEL := 8.0
const SLIDE_DOWNHILL_ACCEL := 100.0
const SLIDE_UPHILL_DRAG := 25.0
const UPHILL_GRADE_DRAG := 52.0
const RUN_DRAG := 1.2
const AIR_DRAG := 0.8
const LANDING_RECOVERY := 0.18
const JUMP_IMPULSE := 12.5
const JUMP_SPEED_GAIN := 1.55
const MAX_JUMP_IMPULSE := 45.0
const GRAVITY := 24.0
const CONTACT_PROBE := 3.0
const CURVATURE_GAIN := 1.05
const TAKEOFF_THRESHOLD := 1.5
const MIN_TAKEOFF_SPEED := 38.0
const NORMAL_ACCEL_LIMIT := 32.0
const NATURAL_LIFT_MIN := 0.6
const NATURAL_LIFT_MAX := 2.6
const SLIDE_KEYS: Array[int] = [KEY_SHIFT, KEY_CTRL, KEY_C, KEY_S, KEY_DOWN]
const SOFT_LANDING_SPEED := 9.0
const HARD_LANDING_SCALE := 0.014
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

func step_speed(current: float, grade: float, grounded: bool, slide: bool, delta: float) -> float:
	var change := 0.0
	if grounded and slide:
		if grade > 0.025:
			change = -SLIDE_UPHILL_DRAG - grade * UPHILL_GRADE_DRAG
		else:
			change = SLIDE_BASE_ACCEL + maxf(-grade, 0.0) * SLIDE_DOWNHILL_ACCEL
	elif grounded:
		change = -RUN_DRAG - maxf(grade, 0.0) * 14.0
	else:
		change = -AIR_DRAG
	# No cap; the low-speed walking floor cannot increase a slower value.
	return maxf(minf(current, MIN_SPEED), current + change * delta)

func relative_normal_acceleration(course: Node3D, at: float, _across: float, forward_speed: float, _side_speed: float = 0.0) -> float:
	# Only the change in longitudinal pitch can launch the runner.
	# Roll and lateral steering must not create artificial vertical force.
	var frame: Transform3D = course.call("sample", at)
	var before: Transform3D = course.call("sample", at - CONTACT_PROBE)
	var after: Transform3D = course.call("sample", at + CONTACT_PROBE)
	var curvature := (-after.basis.z.y + before.basis.z.y) / (2.0 * CONTACT_PROBE)
	var upright := smoothstep(0.25, 0.90, frame.basis.y.y)
	var kind: String = course.call("section_name", at)
	if kind == "180 BANK" or kind == "360 BANK":
		upright = 0.0
	# A gentle, bounded relative acceleration prevents violent launches at
	# uncapped speeds. Manual jumping still works through the banks.
	return clampf(-GRAVITY - curvature * forward_speed * forward_speed * CURVATURE_GAIN * upright, -NORMAL_ACCEL_LIMIT, NORMAL_ACCEL_LIMIT)

func natural_lift_impulse(normal_accel: float, forward_speed: float) -> float:
	if forward_speed < MIN_TAKEOFF_SPEED or normal_accel <= TAKEOFF_THRESHOLD:
		return 0.0
	return clampf(NATURAL_LIFT_MIN + (normal_accel - TAKEOFF_THRESHOLD) * 0.075, NATURAL_LIFT_MIN, NATURAL_LIFT_MAX)

func is_slide_key(code: int) -> bool:
	return SLIDE_KEYS.has(code)

func _slide_input() -> bool:
	if touch_slide or Input.is_joy_button_pressed(0, JOY_BUTTON_B):
		return true
	for code in SLIDE_KEYS:
		if Input.is_key_pressed(code):
			return true
	return false

func landing_speed(current: float, impact_speed: float) -> float:
	# Gentle contact with a downhill slope preserves speed; hitting the
	# surface hard costs momentum. No landing grants forward acceleration.
	var loss := clampf((impact_speed - SOFT_LANDING_SPEED) * HARD_LANDING_SCALE, 0.0, 0.52)
	return current * (1.0 - loss)

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
	var slide := _slide_input()
	var jump := Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if jump and not jump_held:
		queued_jump = true
	jump_held = jump
	var ground := is_grounded()
	landing_timer = maxf(0.0, landing_timer - delta)
	var normal_accel := relative_normal_acceleration(course, distance, lane, speed, lateral_speed)
	var natural_lift := natural_lift_impulse(normal_accel, speed)
	if ground and queued_jump and landing_timer <= 0.0:
		vertical_speed = jump_impulse_for_speed(speed)
		height = 0.01
		ground = false
		queued_jump = false
	elif ground and natural_lift > 0.0 and landing_timer <= 0.0:
		# A falling-away surface releases the runner automatically.
		# Separation is vertical only; it never awards forward momentum.
		vertical_speed = natural_lift
		height = 0.015
		ground = false
		queued_jump = false
	var frame: Transform3D = course.call("sample", distance)
	var grade := -frame.basis.z.y
	is_sliding = ground and slide
	uphill = grade > 0.025
	speed = step_speed(speed, grade, ground, slide, delta)
	var old_s := distance
	var old_lane := lane
	var old_height := height
	# Wider track needs stronger steering, especially at high forward speeds.
	var steer_speed := 23.0 + minf(speed * 0.10, 12.0)
	# Standing gives precise lane changes; sliding trades control for speed.
	var steering_factor := 0.62 if is_sliding else (0.72 if not ground else 1.0)
	lateral_speed = move_toward(lateral_speed, steer * steer_speed * steering_factor, 82.0 * delta * steering_factor)
	var next_s := distance + speed * delta
	var limit: float = course.call("lane_limit", next_s)
	lane = clampf(lane + lateral_speed * delta, -limit, limit)
	if not ground:
		# Integrate the gap from the moving surface, including curvature.
		# Unlike the old tether, the road falling away creates actual airtime.
		var previous_normal_speed := vertical_speed
		vertical_speed += normal_accel * delta
		var next_height := height + (previous_normal_speed + vertical_speed) * 0.5 * delta
		if next_height <= 0.0 and vertical_speed <= 0.0:
			speed = landing_speed(speed, -vertical_speed)
			height = 0.0
			vertical_speed = 0.0
			landing_timer = LANDING_RECOVERY
			queued_jump = false
		else:
			height = maxf(0.0, next_height)
	else:
		height = 0.0
		vertical_speed = 0.0
	hit_timer = maxf(0.0, hit_timer - delta)
	distance += speed * delta
	course.call("stream", distance)
	var count: int = course.call("swept_obstacles", old_s, distance, old_lane, lane, old_height, height, 0.95 if is_sliding else 1.7)
	for _i in range(count):
		apply_obstacle_hit()
	sync_pose(course)
	avatar.scale.y = lerpf(avatar.scale.y, 0.55 if is_sliding else 1.0, minf(delta * 12.0, 1.0))
