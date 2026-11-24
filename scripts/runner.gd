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
var jumps_disabled := false
var clean_gates := 0
var perfect_landings := 0
var dive_landings := 0
var double_jumps := 0
const RiderSprites = preload("res://scripts/rider_sprites.gd")
var rider_sprite: Sprite3D
var rider_textures: Array[Texture2D] = []
var rider_side_textures: Array[Texture2D] = []
var rider_is_side_view := false
var rider_pose := RiderSprites.CRUISE
var rider_facing_left := false
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
	rider_textures = RiderSprites.make_textures()
	rider_side_textures = RiderSprites.make_textures(true)
	rider_sprite = Sprite3D.new()
	rider_sprite.name = "PixelHoverboardRider"
	rider_sprite.texture = rider_textures[RiderSprites.CRUISE]
	rider_sprite.pixel_size = RiderSprites.PIXEL_SIZE
	rider_sprite.position.y = RiderSprites.HEIGHT * RiderSprites.PIXEL_SIZE * 0.5
	rider_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	rider_sprite.shaded = false
	rider_sprite.double_sided = true
	rider_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	avatar.add_child(rider_sprite)

func update_rider_sprite(camera: Camera3D) -> void:
	if not is_instance_valid(rider_sprite):
		return
	# Preserve the physical bank-relative up axis. Face the camera only
	# around that axis, so the sprite never disappears edge-on or turns
	# upright during a wall/ceiling ride.
	var relative := avatar.to_local(camera.global_position)
	if Vector2(relative.x, relative.z).length_squared() > 0.0001:
		rider_sprite.rotation.y = atan2(relative.x, relative.z)
	var next_pose := RiderSprites.CRUISE
	if not grounded:
		next_pose = RiderSprites.BOOST if diving else RiderSprites.CARVE
	elif is_sliding:
		next_pose = RiderSprites.BOOST if speed >= 90.0 and absf(lateral_speed) < 5.0 else RiderSprites.CARVE
	var side_view := absf(relative.x) > absf(relative.z) * (0.85 if rider_is_side_view else 1.20)
	if next_pose != rider_pose or side_view != rider_is_side_view:
		rider_pose = next_pose
		rider_is_side_view = side_view
		rider_sprite.texture = rider_side_textures[rider_pose] if side_view else rider_textures[rider_pose]
	# Hysteresis avoids rapid mirroring when the steering input is neutral.
	if grounded and absf(lateral_speed) > 2.5:
		rider_facing_left = lateral_speed * screen_steer_sign < 0.0
	rider_sprite.flip_h = relative.x < 0.0 if rider_is_side_view else rider_facing_left
	# The original collision envelope is unchanged; sprite-only pitch
	# expresses the jump/dive and never changes contact or momentum.
	var tilt := 0.0
	if not grounded:
		tilt = -0.18 if diving else 0.12
	rider_sprite.rotation.z = -tilt if rider_facing_left else tilt

func reset_run(course: Node3D) -> void:
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
	rider_pose = RiderSprites.CRUISE
	rider_is_side_view = false
	rider_facing_left = false
	rider_sprite.texture = rider_textures[rider_pose]
	rider_sprite.flip_h = false
	rider_sprite.rotation = Vector3.ZERO
	sync_pose(course)

func request_jump() -> void:
	if not jumps_disabled:
		queued_jump = true

func apply_cosmetic(_index: int) -> void:
	# Preserve saved unlocks, but the approved first set is monochrome.
	rider_sprite.modulate = Color.WHITE

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
	if bool(course.call("is_extreme_bank", kind)):
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
	# Contact position is exact, but the displayed orientation eases in
	# from the actual flight basis. No change to the collision point.
	if not grounded:
		return
	var frame: Transform3D = course.call("surface_frame", distance, lane, surface_side)
	var body_basis := frame.basis
	if landing_blend > 0.0:
		body_basis = landing_from_basis.slerp(frame.basis, landing_fraction()).orthonormalized()
	transform = Transform3D(body_basis, frame.origin)
	# A blended body may still point into the road on an inverted landing.
	# Lift only the visual avatar enough to keep head and torso above the
	# face, preserving exact physical foot contact and the eased rotation.
	var lift := 0.0
	if landing_blend > 0.0:
		for probe in range(2):
			var gap := _body_offset(body_basis, probe).dot(frame.basis.y) - _body_support(frame.basis.y, body_basis, probe)
			lift = maxf(lift, -gap)
	avatar.position = body_basis.inverse() * frame.basis.y * lift

func _finish_landing(course: Node3D) -> void:
	landing_from_basis = air_basis
	landing_blend = LANDING_BLEND_TIME
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

func _begin_flight(frame: Transform3D, impulse: float) -> void:
	grounded = false
	double_jump_available = true
	diving = false
	dive_seconds = 0.0
	air_time = 0.0
	landing_blend = 0.0
	air_basis = transform.basis
	# If a new takeoff interrupts a landing blend, carry its visual position
	# into flight rather than snapping the avatar through the road.
	position += air_basis * avatar.position
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

func _flight_step(delta: float, course: Node3D, steer: float) -> void:
	air_time += delta
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
		if air_basis.y.dot(normal) > 0.55 and bool(course.call("support_at", contact.x, contact.y)) and incoming < 0.0:
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
		if air_basis.y.dot(landing_frame.basis.y) < 0.25:
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
		var world_drop := new_frame.origin.y - next_pos.y
		if bool(course.call("is_curved_enclosure", distance)):
			# A corkscrew can extend over 38 m below its reference
			# spine. Being inside it, or close to either curved face,
			# is not falling out of the world.
			var separation: float = course.call("distance_to_rideable_surface", next_pos, Vector3(distance, lane, height))
			if separation > FALL_DEPTH and (world_drop > FALL_DEPTH or absf(lane) > limit + FALL_SIDE_DISTANCE or air_time > 8.0):
				fallen = true
		elif world_drop > FALL_DEPTH or absf(lane) > limit + FALL_SIDE_DISTANCE or air_time > 8.0:
			fallen = true
	if (grounded and surface_side > 0) or (not grounded and (old_height >= 0.0 or height >= 0.0)):
		var old_clear: float = course.call("surface_clearance", old_s, old_lane, old_height, 1)
		var new_clear: float = course.call("surface_clearance", distance, lane, height, 1) if not grounded else 0.0
		var count: int = course.call("swept_obstacles", old_s, distance, old_lane, lane, old_clear, new_clear, 1.7)
		for _i in range(count):
			apply_obstacle_hit()
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
		uphill = grade > 0.025
		var normal_accel := relative_normal_acceleration(course, distance, lane, speed, lateral_speed)
		var natural_lift := natural_lift_impulse(normal_accel, speed)
		if landing_timer <= 0.0 and (queued_jump or natural_lift > 0.0):
			var impulse := jump_impulse_for_speed(speed) if queued_jump else natural_lift
			_begin_flight(frame, impulse)
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
			if absf(next_lane) > edge or not bool(course.call("support_at", next_s, next_lane)):
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
					_reward_gates(course, old_s, old_lane, 0.0, 0.0)
				sync_pose(course)
	if not grounded:
		is_sliding = false
		diving = _dive_input()
		if queued_jump:
			_double_jump()
			queued_jump = false
		_advance_flight(delta, course, steer)
	else:
		diving = false
	avatar.scale.y = lerpf(avatar.scale.y, 0.55 if is_sliding else 1.0, minf(delta * 12.0, 1.0))
