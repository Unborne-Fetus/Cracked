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
const RESERVE_MAX := 30.0
const RESERVE_EARN_FRACTION := 0.20
const GATE_REWARD := 4.0
const DIVE_ACCEL := 36.0
const DIVE_MAX_DOWN := 38.0
const PERFECT_IMPACT := 9.0
const DIVE_REWARD_MAX := 8.0
const TRANSFER_MAX := 24.0

var speed := START_SPEED
var distance := 8.0
var lane := 0.0
var lateral_speed := 0.0
var height := 0.0
var vertical_speed := 0.0
var grounded := true
var surface_side := 1
var screen_steer_sign := 1.0
var fallen := false
var fall_grace := 0.0
var rider_course: Node3D
var rider_clearance := 0.0
var rider_dive := 0.0
var rider_flourish := 0.0
var rider_bank := 0.0
var rider_brace := 0.0
var rider_trick_mix := 0.0
var rider_trick_clock := 0.0
var air_velocity := Vector3.ZERO
var air_basis := Basis.IDENTITY
var recover_air_roll := false
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
var jumps_disabled := false
var clean_gates := 0
var perfect_landings := 0
var dive_landings := 0
var double_jumps := 0
const RiderModel = preload("res://scripts/rider_model.gd")
var rider_model: Node3D
var board_pivot: Node3D
var kickflip_progress := 1.0
const KICKFLIP_TIME := 0.42
var rider_crouch := 0.0
var rider_phase := 0.0
var rider_steer := 0.0
var rider_landing := 0.0
var rider_impact := 0.0
var key_bindings: Dictionary = {}
var pad_bindings: Dictionary = {}
var momentum_reserve := 0.0
var double_jump_available := true
var diving := false
var touch_dive := false
var gate_timer := 0.0
var landing_reward_timer := 0.0
var landing_reward_text := ""
var dive_seconds := 0.0
var avatar: Node3D

func _ready() -> void:
	avatar = Node3D.new()
	add_child(avatar)
	rider_model = RiderModel.new()
	rider_model.name = "BlockRider"
	avatar.add_child(rider_model)
	board_pivot = rider_model.get("board")

func update_rider_sprite(_camera: Camera3D) -> void:
	if not is_instance_valid(rider_model):
		return
	# Legacy collision scale stays independent of the articulated model.
	rider_model.scale.y = 1.0 / maxf(0.05, avatar.scale.y)
	rider_model.position.y = rider_clearance / maxf(0.05, avatar.scale.y)
	rider_model.call("pose", rider_crouch, rider_steer, not grounded, kickflip_progress, rider_phase, rider_landing, rider_impact, rider_dive > 0.5, rider_dive, rider_trick_clock, rider_trick_mix, rider_flourish, rider_bank, rider_brace)

func _update_rider_animation(delta: float) -> void:
	rider_phase = fposmod(rider_phase + delta * (0.75 + clampf(speed / 100.0, 0.0, 1.5)), TAU * 50.0)
	var target := 0.88 if is_sliding else (0.60 if not grounded else 0.12 * smoothstep(30.0, 120.0, speed))
	if diving:
		target = 1.0
	rider_crouch = lerpf(rider_crouch, target, 1.0 - exp(-delta * 13.0))
	rider_steer = lerpf(rider_steer, clampf(lateral_speed / 25.0, -1.0, 1.0), 1.0 - exp(-delta * 10.0))
	rider_landing = move_toward(rider_landing, 0.0, delta * 3.4)
	rider_impact = move_toward(rider_impact, 0.0, delta * 3.8)
	rider_dive = move_toward(rider_dive, 1.0 if diving and not grounded else 0.0, delta * 7.0)
	rider_flourish = move_toward(rider_flourish, maxf(gate_timer, landing_reward_timer * 0.5), delta * 5.0)
	var bank_target := clampf(transform.basis.x.y, -1.0, 1.0) if grounded else 0.0
	rider_bank = lerpf(rider_bank, bank_target, 1.0-exp(-delta*7.0))
	var brace_target := 1.0 if not grounded and air_time > 0.25 and air_velocity.y < -10.0 else 0.0
	rider_brace = move_toward(rider_brace, brace_target, delta*4.0)
	var idle_trick := not grounded and not diving and air_time > 0.55 and kickflip_progress >= 1.0 and rider_impact < 0.2 and rider_brace < 0.35
	rider_trick_mix = move_toward(rider_trick_mix, 1.0 if idle_trick else 0.0, delta*5.0)
	if idle_trick:
		rider_trick_clock += delta
	elif grounded or rider_trick_mix <= 0.0:
		rider_trick_clock = 0.0
	# Sample the actual deck footprint, not only the rider's contact
	# point. Lift the complete visual rig enough to clear crests/banks.
	rider_clearance = 0.0
	if grounded and is_instance_valid(rider_course):
		for corner: Vector3 in [Vector3(-0.48,0.04,0.95), Vector3(0.48,0.04,0.95), Vector3(-0.64,0.02,0.3), Vector3(0.64,0.02,0.3), Vector3(-0.58,0.03,-0.68), Vector3(0.58,0.03,-0.68)]:
			var world_point := transform * corner
			var p: Vector3 = rider_course.call("project_position", world_point, distance)
			if bool(rider_course.call("support_at",p.x,p.y)):
				var clearance: float = rider_course.call("surface_clearance",p.x,p.y,p.z,surface_side)
				rider_clearance = maxf(rider_clearance,0.08-clearance)
		rider_clearance = clampf(rider_clearance,0.0,1.0)

func reset_run(course: Node3D) -> void:
	rider_course = course
	fall_grace = 0.0
	rider_clearance = 0.0
	rider_dive = 0.0
	rider_flourish = 0.0
	rider_bank = 0.0
	rider_brace = 0.0
	rider_trick_mix = 0.0
	rider_trick_clock = 0.0
	rider_model.position = Vector3.ZERO
	distance = 8.0
	speed = START_SPEED
	lane = 0.0
	lateral_speed = 0.0
	height = 0.0
	vertical_speed = 0.0
	grounded = true
	surface_side = 1
	screen_steer_sign = 1.0
	fallen = false
	air_velocity = Vector3.ZERO
	air_basis = Basis.IDENTITY
	recover_air_roll = false
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
	clean_gates = 0
	perfect_landings = 0
	dive_landings = 0
	double_jumps = 0
	momentum_reserve = 0.0
	double_jump_available = true
	diving = false
	touch_dive = false
	gate_timer = 0.0
	landing_reward_timer = 0.0
	landing_reward_text = ""
	dive_seconds = 0.0
	avatar.scale = Vector3.ONE
	avatar.position = Vector3.ZERO
	kickflip_progress = 1.0
	rider_crouch = 0.0
	rider_phase = 0.0
	rider_steer = 0.0
	rider_landing = 0.0
	rider_impact = 0.0
	rider_model.scale = Vector3.ONE
	rider_model.call("pose", 0.0, 0.0, false, 1.0)
	sync_pose(course)

func request_jump() -> void:
	if not jumps_disabled:
		queued_jump = true

func apply_cosmetic(_index: int) -> void:
	# Preserve saved unlocks, but the approved first set is monochrome.
	pass

func key_down(action: String, defaults: Array) -> bool:
	for code in key_bindings.get(action, defaults):
		if Input.is_key_pressed(int(code)):
			return true
	return false

func pad_down(device: int, action: String, defaults: Array) -> bool:
	for code in pad_bindings.get(action, defaults):
		if Input.is_joy_button_pressed(device, int(code)):
			return true
	return false

func _dive_input() -> bool:
	if touch_dive or key_down("dive", [KEY_F]):
		return true
	for device in Input.get_connected_joypads():
		if pad_down(device, "dive", [JOY_BUTTON_RIGHT_STICK]):
			return true
	return false

func _double_jump() -> bool:
	if grounded or not double_jump_available or jumps_disabled:
		return false
	double_jump_available = false
	double_jumps += 1
	kickflip_progress = 0.0
	var up := air_basis.y
	var impulse := jump_impulse_for_speed(speed) * 0.75
	air_velocity += up * maxf(0.0, impulse - air_velocity.dot(up))
	return true

func _banked_slide(grade: float, delta: float) -> void:
	var next_speed := slide_speed_step(speed, grade, delta)
	if next_speed > speed:
		momentum_reserve = minf(RESERVE_MAX, momentum_reserve + (next_speed - speed) * RESERVE_EARN_FRACTION)
	elif grade > 0.025:
		var spend := minf(momentum_reserve, speed - next_speed)
		momentum_reserve -= spend
		next_speed += spend
	speed = next_speed

func _reward_gates(course: Node3D, old_s: float, old_lane: float, old_height: float, new_height: float) -> void:
	var count: int = course.call("collect_clean_gates", old_s, distance, old_lane, lane, old_height, new_height)
	if count > 0:
		clean_gates += count
		gate_timer = 1.0
		if grounded and is_sliding:
			speed += GATE_REWARD * float(count)
		else:
			momentum_reserve = minf(RESERVE_MAX, momentum_reserve + GATE_REWARD * float(count))

func set_first_person(enabled: bool) -> void:
	avatar.visible = not enabled

func can_slide_on_grade(_grade: float) -> bool:
	return true

static func slide_speed_step(current: float, grade: float, delta: float) -> float:
	var change := SLIDE_BASE_ACCEL + maxf(-grade, 0.0) * SLIDE_DOWNHILL_ACCEL
	if grade > 0.025:
		change = -SLIDE_UPHILL_DRAG - grade * UPHILL_GRADE_DRAG
	var floor_speed := CLIMB_SPEED_FLOOR if grade > 0.025 else MIN_SPEED
	return maxf(minf(current, floor_speed), current + change * delta)

func step_speed(current: float, grade: float, grounded: bool, slide: bool, delta: float) -> float:
	var change := 0.0
	if grounded and slide:
		return slide_speed_step(current, grade, delta)
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
	if bool(course.call("is_extreme_bank", kind)) or kind in ["STACKED ROUTES", "SPLIT ROUTE", "HALFPIPE"]:
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

static func pad_axis(raw: float) -> float:
	return signf(raw) * clampf((absf(raw) - 0.18) / 0.82, 0.0, 1.0)

func _pad_steer() -> float:
	var result := 0.0
	for device in Input.get_connected_joypads():
		var axis := pad_axis(Input.get_joy_axis(device, JOY_AXIS_LEFT_X))
		if pad_down(device, "left", [JOY_BUTTON_DPAD_LEFT]):
			axis = -1.0
		if pad_down(device, "right", [JOY_BUTTON_DPAD_RIGHT]):
			axis = 1.0
		if absf(axis) > absf(result):
			result = axis
	return result

func _pad_jump() -> bool:
	for device in Input.get_connected_joypads():
		if pad_down(device, "jump", [JOY_BUTTON_A]):
			return true
	return false

func _slide_input() -> bool:
	if touch_slide:
		return true
	for device in Input.get_connected_joypads():
		if pad_down(device, "slide", [JOY_BUTTON_B, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]):
			return true
		if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > 0.3 or Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.3:
			return true
	return key_down("slide", SLIDE_KEYS)

func landing_speed(current: float, impact_speed: float) -> float:
	# Gentle contact with a downhill slope preserves speed; hitting the
	# surface hard costs momentum. No landing grants forward acceleration.
	var loss := clampf((impact_speed - SOFT_LANDING_SPEED) * HARD_LANDING_SCALE, 0.0, 0.52)
	return current * (1.0 - loss)

func landing_result(frame: Transform3D, velocity: Vector3, was_diving: bool, duration: float) -> Dictionary:
	var forward := -frame.basis.z
	var projected := maxf(0.0, velocity.dot(forward))
	var impact := maxf(0.0, -velocity.dot(frame.basis.y))
	var perfect := impact <= PERFECT_IMPACT and projected > 7.0 and velocity.normalized().dot(forward) >= 0.94
	# A downhill tangent already converts falling velocity into along-road
	# speed. Reward only real downward momentum and a reasonably aligned hit.
	var transfer := 0.0
	if forward.y < -0.06 and velocity.y < 0.0 and impact <= 24.0:
		transfer = minf(TRANSFER_MAX, maxf(0.0, projected - speed))
	var result := landing_speed(minf(speed, projected), impact) + transfer
	var dive_bonus := 0.0
	if was_diving and duration >= 0.10 and forward.y < -0.06 and impact <= 18.0 and projected > 7.0:
		dive_bonus = minf(DIVE_REWARD_MAX, -forward.y * 20.0)
	return {"speed": result + dive_bonus, "perfect": perfect, "transfer": transfer, "dive_bonus": dive_bonus}

func _apply_landing_result(frame: Transform3D) -> void:
	var result := landing_result(frame, air_velocity, diving, dive_seconds)
	speed = float(result["speed"])
	if bool(result["perfect"]):
		perfect_landings += 1
		landing_reward_text = "PERFECT LANDING"
		landing_reward_timer = 1.2
		momentum_reserve = minf(RESERVE_MAX, momentum_reserve + 2.0)
	if float(result["transfer"]) > 0.1:
		landing_reward_text = "MOMENTUM TRANSFER"
		landing_reward_timer = 1.2
	if float(result["dive_bonus"]) > 0.1:
		dive_landings += 1
		landing_reward_text = "DIVE LANDING  //  SPEED BONUS"
		landing_reward_timer = 1.2

func jump_impulse_for_speed(current: float) -> float:
	# Square-root scaling rewards speed without making jumps unboundedly tall.
	# The vertical impulse limit does NOT cap forward velocity.
	return minf(MAX_JUMP_IMPULSE, JUMP_IMPULSE + JUMP_SPEED_GAIN * sqrt(maxf(0.0, current - START_SPEED)))

func apply_obstacle_hit() -> void:
	rider_impact = 1.0
	speed *= OBSTACLE_RETAIN
	if not grounded:
		air_velocity *= OBSTACLE_RETAIN
	hits += 1
	hit_timer = 0.85

func landing_fraction() -> float:
	return smoothstep(0.0, 1.0, 1.0 - landing_blend / LANDING_BLEND_TIME)

func _body_support(normal: Vector3, body_basis: Basis, probe: int) -> float:
	# Exact normal support of the torso box and scaled visor ellipsoid.
	var y_scale := avatar.scale.y
	var nx := normal.dot(body_basis.x)
	var ny := normal.dot(body_basis.y)
	var nz := normal.dot(body_basis.z)
	if probe == 0:
		return 0.4 * absf(nx) + 0.625 * y_scale * absf(ny) + 0.4 * absf(nz)
	return 0.37 * sqrt(nx * nx + ny * ny * y_scale * y_scale + nz * nz)

func _body_offset(body_basis: Basis, probe: int) -> Vector3:
	if probe == 0:
		return body_basis.y * (0.64 * avatar.scale.y)
	return body_basis.y * (1.5 * avatar.scale.y) - body_basis.z * 0.15

func sync_pose(course: Node3D) -> void:
	if not grounded:
		return
	# The physical rider and board are attached to the contact frame on
	# the very first grounded tick. Never retain airborne roll on ground.
	var frame: Transform3D = course.call("surface_frame", distance, lane, surface_side)
	transform = frame
	avatar.position = Vector3.ZERO

func _finish_landing(course: Node3D) -> void:
	rider_landing = 1.0
	kickflip_progress = 1.0
	fall_grace = 0.0
	var frame: Transform3D = course.call("surface_frame", distance, lane, surface_side)
	landing_from_basis = air_basis
	# Small differences can still ease the camera, but a sideways or
	# inverted flight must not leave it pointed along the old wall.
	landing_blend = LANDING_BLEND_TIME if air_basis.y.dot(frame.basis.y) > 0.85 else 0.0
	air_basis = frame.basis
	recover_air_roll = false
	lateral_speed = clampf(lateral_speed, -35.0, 35.0)
	air_velocity = Vector3.ZERO
	height = 0.0
	vertical_speed = 0.0
	air_time = 0.0
	grounded = true
	double_jump_available = true
	diving = false
	landing_timer = LANDING_RECOVERY
	queued_jump = false
	sync_pose(course)

func is_grounded() -> bool:
	return grounded

func _begin_flight(frame: Transform3D, impulse: float, curved_launch: bool = false, trick: bool = false) -> void:
	kickflip_progress = 0.0 if trick else 1.0
	recover_air_roll = curved_launch
	grounded = false
	double_jump_available = true
	diving = false
	dive_seconds = 0.0
	air_time = 0.0
	landing_blend = 0.0
	air_basis = frame.basis
	avatar.position = Vector3.ZERO
	if impulse > 0.0:
		# Start just outside the actual riding face, not inside its slab.
		position += frame.basis.y * 0.04
	air_velocity = -frame.basis.z * speed + frame.basis.x * lateral_speed * float(surface_side) + frame.basis.y * impulse
	vertical_speed = impulse
	queued_jump = false
	is_sliding = false

func _body_sweep(course: Node3D, from_pos: Vector3, to_pos: Vector3, from_s: float, to_s: float) -> Dictionary:
	# Sweep the actual torso and head volumes against both faces. We only
	# intercept contacts where the body leads the feet; ordinary feet-first
	# landings continue to use the existing precise attachment logic.
	var best: Dictionary = {}
	var best_fraction := 2.0
	for probe in range(2):
		var offset := _body_offset(air_basis, probe)
		var old_p: Vector3 = course.call("project_position", from_pos + offset, from_s)
		var new_p: Vector3 = course.call("project_position", to_pos + offset, to_s)
		for side: int in [1, -1]:
			var old_face: Transform3D = course.call("surface_frame", old_p.x, old_p.y, side)
			var new_face: Transform3D = course.call("surface_frame", new_p.x, new_p.y, side)
			var support := _body_support(new_face.basis.y, air_basis, probe)
			if offset.dot(new_face.basis.y) - support > -0.06:
				continue
			var old_gap: float = course.call("surface_clearance", old_p.x, old_p.y, old_p.z, side)
			old_gap -= _body_support(old_face.basis.y, air_basis, probe)
			var new_gap: float = course.call("surface_clearance", new_p.x, new_p.y, new_p.z, side)
			new_gap -= support
			if old_gap < -0.06 or new_gap > 0.0 or new_gap >= old_gap:
				continue
			var fraction := clampf(old_gap / maxf(old_gap - new_gap, 0.0001), 0.0, 1.0)
			if fraction >= best_fraction:
				continue
			var hit: Vector3 = course.call("project_position", from_pos.lerp(to_pos, fraction) + offset, lerpf(from_s, to_s, fraction))
			if not bool(course.call("support_at", hit.x, hit.y)):
				continue
			# Do not reattach at the edge; head/torso contacts only deflect.
			var face: Transform3D = course.call("surface_frame", hit.x, hit.y, side)
			best_fraction = fraction
			best = {"fraction": fraction, "normal": face.basis.y, "side": side}
	return best

func _advance_flight(delta: float, course: Node3D, steer: float) -> void:
	# A twisting ribbon may move across a straight flight trajectory
	# even when both endpoint normals suggest outward velocity.
	# Limit each collision sweep to short spatial and temporal intervals.
	var steps := clampi(ceili(maxf(delta * 60.0, (air_velocity.length() + GRAVITY * delta) * delta / 1.25)), 1, 96)
	var step := delta / float(steps)
	for i in range(steps):
		if grounded or fallen:
			break
		_flight_step(step, course, steer)

func _recover_floor_contact(course: Node3D, old_pos: Vector3, next_pos: Vector3, old_s: float, predicted_s: float) -> bool:
	if air_time < 0.12:
		return false
	var contact: Vector3 = course.call("project_position", next_pos, predicted_s)
	if not bool(course.call("support_at", contact.x, contact.y)):
		return false
	var frame: Transform3D = course.call("surface_frame", contact.x, contact.y, 1)
	# Only upward-facing riding surfaces; retain true wall/ceiling
	# sweeps and head-first protection on inverted sections.
	if frame.basis.y.y < 0.60 or air_velocity.dot(frame.basis.y) > 0.15:
		return false
	var alignment := air_basis.y.dot(frame.basis.y)
	if alignment < -0.55:
		return false
	var gap: float = course.call("surface_clearance", contact.x, contact.y, contact.z, 1)
	var previous: Vector3 = course.call("project_position", old_pos, old_s)
	var previous_gap: float = course.call("surface_clearance", previous.x, previous.y, previous.z, 1)
	# A sideways torso can be the first thing touching the floor. A
	# small persistent overlap or descending crossing must settle rather
	# than requiring an exact new zero crossing on every physics step.
	var reach := 0.18 if alignment > 0.55 else 0.85
	if gap > reach or gap < -0.28 or previous_gap < -0.28 or gap > previous_gap + 0.035:
		return false
	if alignment > 0.55 and previous_gap > 0.0 and gap > 0.0:
		return false
	distance = contact.x
	lane = contact.y
	surface_side = 1
	_apply_landing_result(frame)
	lateral_speed = air_velocity.dot(frame.basis.x)
	_finish_landing(course)
	return true

func _check_fall(course: Node3D, point: Vector3, projected: Vector3, delta: float) -> void:
	# Airtime is never grounds for defeat. A high jump over a road,
	# or a rider on a bank below its spine, is still a valid run.
	var near: float = course.call("distance_to_rideable_surface",point,projected)
	if near <= FALL_DEPTH:
		fall_grace = 0.0
		return
	var info: Dictionary = course.call("nearest_road_point",point,projected)
	if float(info["distance"]) <= FALL_DEPTH:
		fall_grace = 0.0
		return
	var offset: Vector3 = point - Vector3(info["point"])
	var horizontal := Vector3(offset.x,0.0,offset.z)
	var escaping := offset.y < -FALL_DEPTH or (horizontal.length() > FALL_SIDE_DISTANCE and air_velocity.dot(horizontal) > 0.0)
	fall_grace = fall_grace + delta if escaping else 0.0
	if fall_grace > 0.22:
		fallen = true

func _obstacle_rebound(course: Node3D, collision: Dictionary, from_s: float, to_s: float, from_lane: float, to_lane: float, from_height: float, to_height: float) -> void:
	var fraction := maxf(0.0,float(collision["fraction"])-0.001)
	var hazard: Dictionary = collision["hazard"]
	var group: Dictionary = hazard["group"]
	var was_grounded := grounded
	distance = lerpf(from_s,to_s,fraction)
	lane = lerpf(from_lane,to_lane,fraction)
	var frame: Transform3D = course.call("surface_frame",distance,lane,1)
	var incoming := -frame.basis.z * speed + frame.basis.x * lateral_speed if grounded else air_velocity
	var axis := int(collision["axis"])
	var normal := (-frame.basis.z if axis == 0 else frame.basis.x if axis == 1 else frame.basis.y) * float(collision["sign"])
	var contact_height := maxf(0.0,lerpf(from_height,to_height,fraction))
	var contact_position := frame.origin + frame.basis.y * contact_height + normal * 0.12
	# Reflect the inward velocity, cap the reverse rebound, and steer
	# away from the struck object rather than teleporting through it.
	var incoming_normal := incoming.dot(normal)
	var outgoing := incoming - normal * minf(0.0,incoming_normal) * 1.25
	if axis == 0:
		var escape_sign := -1.0 if lane < float(hazard["lane"]) else 1.0
		outgoing = normal * clampf(absf(incoming_normal)*0.20,3.0,12.0) + frame.basis.x * escape_sign * 14.0 + frame.basis.y * 6.0
	elif axis == 1:
		outgoing = outgoing * 0.30 + normal * 8.0 + frame.basis.y * 3.0
	else:
		outgoing = outgoing * 0.30 + normal * 5.0
	grounded = false
	surface_side = 1
	air_basis = frame.basis
	recover_air_roll = true
	air_time = 0.0 if was_grounded else air_time
	air_velocity = outgoing
	speed = maxf(MIN_SPEED,speed * OBSTACLE_RETAIN)
	height = contact_height
	vertical_speed = outgoing.dot(frame.basis.y)
	is_sliding = false
	diving = false
	kickflip_progress = 1.0
	landing_blend = 0.0
	rider_impact = 1.0
	hit_timer = 0.85
	if not bool(group["used"]):
		group["used"] = true
		hits += 1
	transform = Transform3D(air_basis,contact_position)

func _flight_step(delta: float, course: Node3D, steer: float) -> void:
	air_time += delta
	# Launching off a curved wall can leave the rider ninety degrees
	# sideways. Recover roll in free space, not by rotating with the road.
	if (recover_air_roll and air_time > 0.12) or (air_time > 0.40 and air_basis.y.y < 0.45 and air_velocity.y < 0.0):
		var forward := -air_basis.z
		if absf(forward.dot(Vector3.UP)) < 0.95:
			var upright := Basis.looking_at(forward, Vector3.UP)
			air_basis = air_basis.slerp(upright, 1.0 - exp(-delta * 5.0)).orthonormalized()
	var previous_pos := position
	var old_s := distance
	var old_lane := lane
	var old_projection: Vector3 = course.call("project_position", previous_pos, distance)
	var old_height := old_projection.z
	var old_frame: Transform3D = course.call("sample", distance)
	# Flight follows the actual momentum vector and fixed takeoff basis.
	# The road can turn or rotate underneath without carrying the player.
	var flat_forward := -air_basis.z
	flat_forward.y = 0.0
	var steering_axis := flat_forward.cross(Vector3.UP)
	if steering_axis.length_squared() > 0.001:
		air_velocity += steering_axis.normalized() * steer * AIR_STEER_ACCEL * delta
	var horizontal := Vector3(air_velocity.x, 0.0, air_velocity.z)
	var drag := minf(AIR_DRAG * delta, horizontal.length())
	if horizontal.length_squared() > 0.0001:
		air_velocity -= horizontal.normalized() * drag
	var stream_accel: float = course.call("slipstream_accel", distance, lane, height, surface_side)
	if stream_accel > 0.0:
		air_velocity += -old_frame.basis.z * stream_accel * delta
		speed += stream_accel * delta
	var prev_velocity := air_velocity
	air_velocity.y -= GRAVITY * delta
	if diving:
		dive_seconds += delta
		# A controlled downward plunge, with no forward speed injection.
		air_velocity.y -= minf(DIVE_ACCEL * delta, maxf(0.0, air_velocity.y + DIVE_MAX_DOWN))
	var next_pos := previous_pos + (prev_velocity + air_velocity) * (0.5 * delta)
	# Stream ahead before projecting onto the route. A rebase must shift
	# free-flight positions too, otherwise they would jump by kilometres.
	var old_origin: Vector3 = course.get("origin_shift")
	var predicted_s := maxf(0.0, distance + air_velocity.dot(-old_frame.basis.z) * delta)
	course.call("stream", maxf(distance, predicted_s), speed)
	var new_origin: Vector3 = course.get("origin_shift")
	var shift := new_origin - old_origin
	previous_pos -= shift
	next_pos -= shift
	# Obstacles stop the motion before surface landing can skip past them.
	var obstacle_projection: Vector3 = course.call("project_position",next_pos,predicted_s)
	var obstacle_clear0: float = course.call("surface_clearance",old_projection.x,old_projection.y,old_projection.z,1)
	var obstacle_clear1: float = course.call("surface_clearance",obstacle_projection.x,obstacle_projection.y,obstacle_projection.z,1)
	if obstacle_clear0 >= -0.15 or obstacle_clear1 >= -0.15:
		var obstacle: Dictionary = course.call("first_obstacle_contact",old_projection.x,obstacle_projection.x,old_projection.y,obstacle_projection.y,obstacle_clear0,obstacle_clear1,1.7)
		if not obstacle.is_empty():
			_obstacle_rebound(course,obstacle,old_projection.x,obstacle_projection.x,old_projection.y,obstacle_projection.y,obstacle_clear0,obstacle_clear1)
			return
	if _recover_floor_contact(course, previous_pos, next_pos, old_s, predicted_s):
		return
	var body_contact := _body_sweep(course, previous_pos, next_pos, old_s, predicted_s)
	if not body_contact.is_empty():
		var normal: Vector3 = body_contact["normal"]
		# Stop at first impact and gently deflect away from the surface,
		# rather than allowing the feet to tunnel across the slab later.
		next_pos = previous_pos.lerp(next_pos, float(body_contact["fraction"])) + normal * 0.08
		var incoming := air_velocity.dot(normal)
		# A torso corner can touch first during a normal landing on a
		# slope. In that case settle the feet onto the same face instead
		# of repeatedly bouncing. Head-first impacts still deflect.
		var contact: Vector3 = course.call("project_position", next_pos, predicted_s)
		var recovery_contact := recover_air_roll and normal.y > 0.55 and air_basis.y.dot(normal) > -0.15
		if (air_basis.y.dot(normal) > 0.55 or recovery_contact) and bool(course.call("support_at", contact.x, contact.y)) and incoming < 0.0:
			distance = contact.x
			lane = contact.y
			surface_side = int(body_contact["side"])
			var landing_frame: Transform3D = course.call("surface_frame", distance, lane, surface_side)
			_apply_landing_result(landing_frame)
			lateral_speed = air_velocity.dot(landing_frame.basis.x) * float(surface_side)
			_finish_landing(course)
			return
		if incoming < 0.0:
			air_velocity -= normal * incoming * 1.2
			speed = landing_speed(speed, -incoming)
		else:
			air_velocity += normal * 0.5
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
		# A crossing at the beginning of the step is not a landing if the
		# player has already moved past the edge by the end of that step.
		# Keep both face checks, but require support under the new position.
		if not body_contact.is_empty() or not bool(course.call("support_at", distance, lane)) or old_gap < -0.025 or new_gap > 0.0 or new_gap >= old_gap:
			continue
		# The signed gap is relative to the rotating surface; a positive
		# world-space normal velocity does not rule out a collision.
		var fraction := clampf(old_gap / maxf(old_gap - new_gap, 0.0001), 0.0, 1.0)
		var hit_pos := previous_pos.lerp(next_pos, fraction)
		var hit: Vector3 = course.call("project_position", hit_pos, lerpf(old_s, distance, fraction))
		if not bool(course.call("support_at", hit.x, hit.y)):
			continue
		var landing_frame: Transform3D = course.call("surface_frame", hit.x, hit.y, side)
		var recovery_landing := recover_air_roll and landing_frame.basis.y.y > 0.55 and air_basis.y.dot(landing_frame.basis.y) > -0.15 and air_velocity.dot(landing_frame.basis.y) < 0.0
		if air_basis.y.dot(landing_frame.basis.y) < 0.25 and not recovery_landing:
			# The bank swept into the runner sideways or head-first. Keep
			# the whole body outside the contacted face rather than snapping
			# to the other side of the road.
			var normal := landing_frame.basis.y
			var push := 0.08
			for probe in range(2):
				push = maxf(push, _body_support(normal, air_basis, probe) - _body_offset(air_basis, probe).dot(normal) + 0.08)
			next_pos = landing_frame.origin + normal * push
			var incoming := air_velocity.dot(normal)
			air_velocity += normal * maxf(0.5, -incoming * 1.2)
			projected = course.call("project_position", next_pos, hit.x)
			distance = projected.x
			lane = projected.y
			height = projected.z
			break
		distance = hit.x
		lane = hit.y
		surface_side = side
		_apply_landing_result(landing_frame)
		lateral_speed = air_velocity.dot(landing_frame.basis.x) * float(surface_side)
		_finish_landing(course)
		break
	# If a projected crossing misses the actual edge, keep moving freely.
	if not grounded:
		transform = Transform3D(air_basis, next_pos)
		speed = maxf(0.0, speed - AIR_DRAG * delta)
		_check_fall(course,next_pos,Vector3(distance,lane,height),delta)
	if (grounded and surface_side > 0) or (not grounded and (old_height >= 0.0 or height >= 0.0)):
		var old_clear: float = course.call("surface_clearance", old_s, old_lane, old_height, 1)
		var new_clear: float = course.call("surface_clearance", distance, lane, height, 1) if not grounded else 0.0
		_reward_gates(course, old_s, old_lane, old_clear, new_clear)

func tick(delta: float, course: Node3D) -> void:
	if fallen:
		return
	var steer := touch_axis
	if key_down("left", [KEY_A, KEY_LEFT]):
		steer -= 1.0
	if key_down("right", [KEY_D, KEY_RIGHT]):
		steer += 1.0
	steer = clampf(steer + _pad_steer(), -1.0, 1.0)
	var slide := _slide_input()
	var jump := not jumps_disabled and (key_down("jump", [KEY_SPACE]) or _pad_jump())
	if jumps_disabled:
		queued_jump = false
	if jump and not jump_held:
		queued_jump = true
	jump_held = jump
	landing_timer = maxf(0.0, landing_timer - delta)
	if grounded:
		landing_blend = maxf(0.0, landing_blend - delta)
	hit_timer = maxf(0.0, hit_timer - delta)
	gate_timer = maxf(0.0, gate_timer - delta)
	landing_reward_timer = maxf(0.0, landing_reward_timer - delta)
	if grounded:
		var frame: Transform3D = course.call("surface_frame", distance, lane, surface_side)
		var grade := -frame.basis.z.y
		var section: String = course.call("section_name", distance)
		var curved_launch := section in ["HALFPIPE", "CORKSCREW TUNNEL", "STACKED ROUTES", "SPLIT ROUTE"]
		uphill = grade > 0.025
		var normal_accel := relative_normal_acceleration(course, distance, lane, speed, lateral_speed)
		var natural_lift := natural_lift_impulse(normal_accel, speed)
		if landing_timer <= 0.0 and (queued_jump or natural_lift > 0.0):
			var impulse := jump_impulse_for_speed(speed) if queued_jump else natural_lift
			_begin_flight(frame, impulse, curved_launch, queued_jump)
		else:
			is_sliding = slide
			if slide:
				_banked_slide(grade, delta)
				speed += float(course.call("recovery_accel", distance, lane, surface_side)) * delta
			else:
				speed = step_speed(speed, grade, true, false, delta)
			speed += float(course.call("slipstream_accel", distance, lane, 0.0, surface_side)) * delta
			var old_s := distance
			var old_lane := lane
			var steer_speed := 23.0 + minf(speed * 0.10, 12.0)
			var steering_factor := 0.62 if slide else 1.0
			var base_frame: Transform3D = course.call("sample", distance)
			var screen_right := (-base_frame.basis.z).cross(Vector3.UP).normalized()
			var screen_alignment := (frame.basis.x * float(surface_side)).dot(screen_right)
			# A/D moves in the visible horizontal direction where possible.
			# On a vertical wall retain the last mapping to avoid jitter.
			if absf(screen_alignment) > 0.18:
				screen_steer_sign = signf(screen_alignment)
			# A small gravity-driven drift makes vertical walls meaningfully
			# different from flat ground, while steering can counter it.
			var wall_drift := -frame.basis.x.y * float(surface_side) * 5.0
			lateral_speed = move_toward(lateral_speed, steer * screen_steer_sign * steer_speed * steering_factor + wall_drift, 82.0 * delta * steering_factor)
			var next_s := distance + speed * delta
			var next_lane := lane + lateral_speed * delta
			course.call("stream", next_s, speed)
			var edge: float = course.call("half_width_at", next_s)
			var obstacle: Dictionary = course.call("first_obstacle_contact",old_s,next_s,old_lane,next_lane,0.0,0.0,0.95 if slide else 1.7) if surface_side > 0 else {}
			if not obstacle.is_empty():
				_obstacle_rebound(course,obstacle,old_s,next_s,old_lane,next_lane,0.0,0.0)
				_update_rider_animation(delta)
				return
			if absf(next_lane) > edge or not bool(course.call("support_at", next_s, next_lane)):
				# No invisible walls. Start flight from the last supported
				# point, then allow the player to steer back if possible.
				sync_pose(course)
				_begin_flight(frame, 0.0, curved_launch)
			else:
				distance = next_s
				lane = next_lane
				height = 0.0
				vertical_speed = 0.0
				if surface_side > 0:
					_reward_gates(course, old_s, old_lane, 0.0, 0.0)
				sync_pose(course)
	if not grounded:
		is_sliding = false
		diving = _dive_input()
		if queued_jump:
			_double_jump()
			queued_jump = false
		_advance_flight(delta, course, steer)
		kickflip_progress = minf(1.0, kickflip_progress + delta / KICKFLIP_TIME)
	else:
		diving = false
	avatar.scale.y = lerpf(avatar.scale.y, 0.55 if is_sliding else 1.0, minf(delta * 12.0, 1.0))
	_update_rider_animation(delta)
