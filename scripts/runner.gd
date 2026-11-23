extends Node3D
## Grounded runner follows the ribbon; airborne runner uses world-space flight.

const START_SPEED := 22.0
const MIN_SPEED := 7.0
const SLIDE_BASE_ACCEL := 8.0
const SLIDE_DOWNHILL_ACCEL := 100.0
const SLIDE_UPHILL_DRAG := 5.0
const UPHILL_GRADE_DRAG := 32.0
const CLIMB_SPEED_FLOOR := 18.0
const FALL_DEPTH := 30.0
const FALL_SIDE_DISTANCE := 48.0
const AIR_STEER_ACCEL := 13.0
const RUN_DRAG := 1.2
const AIR_DRAG := 0.8
const LANDING_RECOVERY := 0.18
const LANDING_BLEND_TIME := 0.50
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
var grounded := true
var surface_side := 1
var fallen := false
var air_velocity := Vector3.ZERO
var air_basis := Basis.IDENTITY
var air_time := 0.0
var touch_axis := 0.0
var touch_slide := false
var queued_jump := false
var jump_held := false
var is_sliding := false
var uphill := false
var landing_timer := 0.0
var landing_blend := 0.0
var landing_from_basis := Basis.IDENTITY
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
	grounded = true
	surface_side = 1
	fallen = false
	air_velocity = Vector3.ZERO
	air_basis = Basis.IDENTITY
	air_time = 0.0
	touch_axis = 0.0
	touch_slide = false
	queued_jump = false
	jump_held = false
	is_sliding = false
	uphill = false
	landing_timer = 0.0
	landing_blend = 0.0
	landing_from_basis = Basis.IDENTITY
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
		change = -RUN_DRAG - maxf(grade, 0.0) * 5.0
	else:
		change = -AIR_DRAG
	# No cap; the low-speed walking floor cannot increase a slower value.
	var floor_speed := CLIMB_SPEED_FLOOR if grounded and grade > 0.025 else MIN_SPEED
	return maxf(minf(current, floor_speed), current + change * delta)

func relative_normal_acceleration(course: Node3D, at: float, _across: float, forward_speed: float, _side_speed: float = 0.0) -> float:
	# Only the change in longitudinal pitch can launch the runner.
	# Roll and lateral steering must not create artificial vertical force.
	var frame: Transform3D = course.call("surface_frame", at, _across, surface_side)
	var before: Transform3D = course.call("surface_frame", at - CONTACT_PROBE, _across, surface_side)
	var after: Transform3D = course.call("surface_frame", at + CONTACT_PROBE, _across, surface_side)
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
	if not grounded:
		air_velocity *= OBSTACLE_RETAIN
	hits += 1
	hit_timer = 0.85

func landing_fraction() -> float:
	return smoothstep(0.0, 1.0, 1.0 - landing_blend / LANDING_BLEND_TIME)

func sync_pose(course: Node3D) -> void:
	# Contact position is exact, but the displayed orientation eases in
	# from the actual flight basis. No change to the collision point.
	if not grounded:
		return
	var frame: Transform3D = course.call("surface_frame", distance, lane, surface_side)
	var body_basis := frame.basis
	if landing_blend > 0.0:
		body_basis = landing_from_basis.slerp(frame.basis, landing_fraction()).orthonormalized()
	transform = Transform3D(body_basis, frame.origin)

func _finish_landing(course: Node3D) -> void:
	landing_from_basis = air_basis
	landing_blend = LANDING_BLEND_TIME
	height = 0.0
	vertical_speed = 0.0
	air_time = 0.0
	grounded = true
	landing_timer = LANDING_RECOVERY
	queued_jump = false
	sync_pose(course)

func is_grounded() -> bool:
	return grounded

func _begin_flight(frame: Transform3D, impulse: float) -> void:
	grounded = false
	air_time = 0.0
	landing_blend = 0.0
	air_basis = transform.basis
	air_velocity = -frame.basis.z * speed + frame.basis.x * lateral_speed * float(surface_side) + frame.basis.y * impulse
	vertical_speed = impulse
	queued_jump = false
	is_sliding = false

func _advance_flight(delta: float, course: Node3D, steer: float) -> void:
	air_time += delta
	var previous_pos := position
	var old_s := distance
	var old_lane := lane
	var old_projection: Vector3 = course.call("project_position", previous_pos, distance)
	var old_height := old_projection.z
	var old_frame: Transform3D = course.call("sample", distance)
	# Flight follows the actual momentum vector and fixed takeoff basis.
	# The road can turn or rotate underneath without carrying the player.
	var steering_axis := air_basis.x
	steering_axis.y = 0.0
	if steering_axis.length_squared() > 0.001:
		air_velocity += steering_axis.normalized() * steer * AIR_STEER_ACCEL * delta
	var horizontal := Vector3(air_velocity.x, 0.0, air_velocity.z)
	var drag := minf(AIR_DRAG * delta, horizontal.length())
	if horizontal.length_squared() > 0.0001:
		air_velocity -= horizontal.normalized() * drag
	var prev_velocity := air_velocity
	air_velocity.y -= GRAVITY * delta
	var next_pos := previous_pos + (prev_velocity + air_velocity) * (0.5 * delta)
	# Stream ahead before projecting onto the route. A rebase must shift
	# free-flight positions too, otherwise they would jump by kilometres.
	var old_origin: Vector3 = course.get("origin_shift")
	var predicted_s := maxf(0.0, distance + air_velocity.dot(-old_frame.basis.z) * delta)
	course.call("stream", maxf(distance, predicted_s))
	var new_origin: Vector3 = course.get("origin_shift")
	var shift := new_origin - old_origin
	previous_pos -= shift
	next_pos -= shift
	var projected: Vector3 = course.call("project_position", next_pos, predicted_s)
	distance = projected.x
	lane = projected.y
	height = projected.z
	var new_frame: Transform3D = course.call("sample", distance)
	var limit: float = course.call("half_width_at", distance)
	vertical_speed = air_velocity.dot(new_frame.basis.y)
	# Both faces are rideable. Check for entry from the outside of either
	# face, never teleport across the slab or attach to its interior.
	for side: int in [1, -1]:
		var old_gap: float = course.call("surface_clearance", old_projection.x, old_projection.y, old_height, side)
		var new_gap: float = course.call("surface_clearance", distance, lane, height, side)
		var face: Transform3D = course.call("surface_frame", distance, lane, side)
		var toward := air_velocity.dot(face.basis.y)
		# A crossing at the beginning of the step is not a landing if the
		# player has already moved past the edge by the end of that step.
		# Keep both face checks, but require support under the new position.
		if absf(lane) > limit or old_gap < -0.025 or new_gap > 0.0 or toward >= 0.0:
			continue
		var fraction := clampf(old_gap / maxf(old_gap - new_gap, 0.0001), 0.0, 1.0)
		var hit_pos := previous_pos.lerp(next_pos, fraction)
		var hit: Vector3 = course.call("project_position", hit_pos, lerpf(old_s, distance, fraction))
		if absf(hit.y) > float(course.call("half_width_at", hit.x)):
			continue
		distance = hit.x
		lane = hit.y
		surface_side = side
		var landing_frame: Transform3D = course.call("surface_frame", distance, lane, surface_side)
		var forward_velocity := maxf(0.0, air_velocity.dot(-landing_frame.basis.z))
		speed = landing_speed(minf(speed, forward_velocity), maxf(0.0, -air_velocity.dot(landing_frame.basis.y)))
		lateral_speed = air_velocity.dot(landing_frame.basis.x) * float(surface_side)
		_finish_landing(course)
		break
	# If a projected crossing misses the actual edge, keep moving freely.
	if not grounded:
		transform = Transform3D(air_basis, next_pos)
		speed = maxf(0.0, speed - AIR_DRAG * delta)
		var world_drop := new_frame.origin.y - next_pos.y
		if world_drop > FALL_DEPTH or absf(lane) > limit + FALL_SIDE_DISTANCE or air_time > 8.0:
			fallen = true
	if (grounded and surface_side > 0) or (not grounded and (old_height >= 0.0 or height >= 0.0)):
		var old_clear: float = course.call("surface_clearance", old_s, old_lane, old_height, 1)
		var new_clear: float = course.call("surface_clearance", distance, lane, height, 1) if not grounded else 0.0
		var count: int = course.call("swept_obstacles", old_s, distance, old_lane, lane, old_clear, new_clear, 1.7)
		for _i in range(count):
			apply_obstacle_hit()

func tick(delta: float, course: Node3D) -> void:
	if fallen:
		return
	var steer := touch_axis
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steer -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steer += 1.0
	steer = clampf(steer + Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -1.0, 1.0)
	var slide := _slide_input()
	var jump := Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if jump and not jump_held and grounded:
		queued_jump = true
	jump_held = jump
	landing_timer = maxf(0.0, landing_timer - delta)
	if grounded:
		landing_blend = maxf(0.0, landing_blend - delta)
	hit_timer = maxf(0.0, hit_timer - delta)
	if grounded:
		var frame: Transform3D = course.call("surface_frame", distance, lane, surface_side)
		var grade := -frame.basis.z.y
		uphill = grade > 0.025
		var normal_accel := relative_normal_acceleration(course, distance, lane, speed, lateral_speed)
		var natural_lift := natural_lift_impulse(normal_accel, speed)
		if landing_timer <= 0.0 and (queued_jump or natural_lift > 0.0):
			var impulse := jump_impulse_for_speed(speed) if queued_jump else natural_lift
			_begin_flight(frame, impulse)
		else:
			is_sliding = slide
			speed = step_speed(speed, grade, true, slide, delta)
			var old_s := distance
			var old_lane := lane
			var steer_speed := 23.0 + minf(speed * 0.10, 12.0)
			var steering_factor := 0.62 if slide else 1.0
			lateral_speed = move_toward(lateral_speed, steer * float(surface_side) * steer_speed * steering_factor, 82.0 * delta * steering_factor)
			var next_s := distance + speed * delta
			var next_lane := lane + lateral_speed * delta
			course.call("stream", next_s)
			var edge: float = course.call("half_width_at", next_s)
			if absf(next_lane) > edge:
				# No invisible walls. Start flight from the last supported
				# point, then allow the player to steer back if possible.
				sync_pose(course)
				_begin_flight(frame, 0.0)
			else:
				distance = next_s
				lane = next_lane
				height = 0.0
				vertical_speed = 0.0
				if surface_side > 0:
					var count: int = course.call("swept_obstacles", old_s, distance, old_lane, lane, 0.0, 0.0, 0.95 if slide else 1.7)
					for _i in range(count):
						apply_obstacle_hit()
				sync_pose(course)
	if not grounded:
		is_sliding = false
		_advance_flight(delta, course, steer)
	avatar.scale.y = lerpf(avatar.scale.y, 0.55 if is_sliding else 1.0, minf(delta * 12.0, 1.0))
