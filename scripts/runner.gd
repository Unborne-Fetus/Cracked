extends Node3D
## Horizontal momentum, terrain tangency, natural takeoff and swept landing.
const GRAVITY := 32.0
const START_SPEED := 36.0
const MAX_SPEED := 250.0
const BOOST_COST := 28.0
const FOOT := 0.08
const RiderModel = preload("res://scripts/rider_model.gd")
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
var touch_steer := 0.0
var touch_dive := false
var land_lock := 0.0
var cue := ""
var cue_time := 0.0
var gait := 0.0
var model: Node3D
var landing_marker: MeshInstance3D
var landing_mat: StandardMaterial3D
var marker_clock := 0.0
var last_landing := ""
var landing_serial := 0
var flow_chain := 0
var upgrades: Dictionary = {}
var collected := 0
var last_motion := Vector3.ZERO
var ability := 0
var protected_time := 0.0
var air_charge := 0.0
var peak_speed := 0.0
var peak_chain := 0
var impacts := 0
var void_rescues := 0
var safe_position := Vector3.ZERO
var cooldown := 0.0
var course_route := 0
var gust_time := 0.0
var gust_direction := 0.0
var energy_lock := 0.0

func _ready() -> void:
	model = RiderModel.new()
	model.name = "OriginalRider"
	add_child(model)
	trail = MeshInstance3D.new()
	trail.mesh = trail_mesh
	trail.top_level = true
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_material.vertex_color_use_as_albedo = true
	add_child(trail)
	landing_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 1.3
	ring.outer_radius = 1.58
	ring.rings = 24
	ring.ring_segments = 8
	landing_marker.mesh = ring
	landing_marker.top_level = true
	landing_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	landing_mat = StandardMaterial3D.new()
	landing_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	landing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	landing_marker.material_override = landing_mat
	add_child(landing_marker)
	landing_marker.hide()

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
	last_landing = ""
	landing_serial = 0
	flow_chain = 0
	collected = 0
	last_motion = Vector3.ZERO
	protected_time = 0.0
	air_charge = 0.0
	gust_time = 0.0
	gust_direction = 0.0
	energy_lock = 0.0
	peak_speed = START_SPEED
	peak_chain = 0
	impacts = 0
	void_rescues = 0
	cooldown = 0.0
	course_route = int(course.get("route_style"))
	marker_clock = 0.0
	landing_marker.hide()
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
	safe_position = position
	model.rotation = Vector3.ZERO
	model.scale = Vector3.ONE
	model.call("pose_run", 0.0, speed, 0.0, true, false, 0.0, 0.0, 1.0)

func progress() -> float:
	return -position.z

static func ground_speed(v: float, slope: float, dt: float, cap: float = MAX_SPEED) -> float:
	# Maintain a strong running pace; downhill tangent gravity builds speed.
	var slope_force := -slope * (65.0 if slope < 0.0 else 22.0)
	var drive := 9.0 * (1.0 - v / 65.0)
	var drag := 0.00010 * v * v
	return clampf(v + (slope_force + drive - drag) * dt, 22.0, cap)

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

static func landing_speed(v: Vector3, n: Vector3, slope: float, dive: bool, cap: float = MAX_SPEED) -> float:
	var quality := landing_quality(v, n, slope)
	var tangent := v - n * v.dot(n)
	var forward := maxf(0.0, -tangent.z)
	var horizontal := maxf(0.0, -v.z)
	match quality:
		"PERFECT":
			return clampf(maxf(horizontal, forward) * 1.12 + (8.0 if dive else 4.0), 22.0, cap)
		"GOOD":
			return clampf(maxf(horizontal * 0.98, forward) + 2.5, 22.0, cap)
		"OK":
			return clampf(horizontal * 0.82, 22.0, cap)
		_:
			return clampf(horizontal * 0.52, 22.0, cap)

func apply_upgrades(values: Dictionary, ability_value: int = 0) -> void:
	upgrades = values.duplicate()
	ability = clampi(ability_value, 0, 3)

func apply_start_bonuses() -> void:
	speed = minf(speed_limit(), speed + float(rank_of("start")) * 8.0 + (float(rank_of("restspeed")) * 7.0 if course_route == 3 else 0.0))
	energy = minf(100.0, energy + float(rank_of("battery")) * 15.0 + (float(rank_of("trialboost")) * 12.0 if course_route == 4 else 0.0))

func speed_limit() -> float:
	return MAX_SPEED + float(rank_of("cap")) * 15.0

func air_drag() -> float:
	return 0.14 * (1.0 - float(rank_of("drag")) * 0.22)

func boost_accel() -> float:
	return (31.0 if ability == 0 else (9.0 if ability == 1 else (22.0 if ability == 2 else 18.0))) + float(rank_of("synergy")) * minf(12.0, float(upgrades.size()) * 1.5)

func rank_of(id: String) -> int:
	return clampi(int(upgrades.get(id, 0)), 0, 3)

func boost_cost() -> float:
	return maxf(10.0, [28.0, 32.0, 26.0, 35.0][ability] - float(rank_of("boost")) * 4.0 - float(rank_of("saver")) * 3.0 - (4.0 if has_set(["charge", "boost", "saver"]) else 0.0))

func flight_gravity(dive: bool, boost: float) -> float:
	if dive:
		return GRAVITY * (2.5 + float(rank_of("dive")) * 0.20 + (1.4 if boost > 0.0 and ability == 2 else 0.0))
	if boost > 0.0 and ability == 1:
		return GRAVITY * maxf(0.10, 0.22 - float(rank_of("float")) * 0.035)
	return GRAVITY * (maxf(0.15, 0.45 - float(rank_of("float")) * 0.07) if boost > 0.0 else (1.0 - float(rank_of("glide")) * 0.10))

func request_boost() -> void:
	boost_queued = true

func _activate_boost() -> bool:
	if energy < boost_cost() or boost_time > 0.0 or cooldown > 0.0 or energy_lock > 0.0:
		return false
	energy -= boost_cost()
	boost_time = float([0.65, 1.35, 0.65, 0.85][ability]) + float(rank_of("boosttime")) * 0.18
	cooldown = boost_time + maxf(0.10, 0.5 - float(rank_of("heat")) * 0.12)
	var initial := float([18.0, 6.0, 9.0, 14.0][ability]) + float(rank_of("boost")) * 5.0
	if not grounded:
		initial += float(rank_of("apex")) * 6.0
		if ability == 2:
			vy = minf(vy, -22.0)
		else:
			vy = maxf(vy, 12.0 if ability == 1 else 8.0)
	speed = minf(speed_limit(), speed + initial)
	if ability == 3 or rank_of("guard") > 0:
		protected_time = boost_time if ability == 3 else float(rank_of("guard")) * 0.18
	cue = str(["BURST", "GLIDE", "SURGE", "PHASE"][ability])
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
	marker_clock -= dt
	if marker_clock <= 0.0:
		marker_clock = 0.075
		_update_landing_marker(course, dive)

func _step(dt: float, course: Node3D, steer: float, dive: bool) -> void:
	land_lock = maxf(0.0, land_lock - dt)
	protected_time = maxf(0.0, protected_time - dt)
	cooldown = maxf(0.0, cooldown - dt)
	gust_time = maxf(0.0, gust_time - dt)
	energy_lock = maxf(0.0, energy_lock - dt)
	var old := position
	var s := -position.z
	var g: Vector2 = course.call("grade", position.x, s)
	var target_lateral := steer * minf(76.0, speed * 0.66) * (1.0 + float(rank_of("steer")) * 0.08) + (gust_direction * 12.0 if gust_time > 0.0 else 0.0)
	lateral = lerpf(lateral, target_lateral, 1.0 - exp(-dt * (8.0 if grounded else 4.0) * (1.0 + float(rank_of("steer")) * 0.15 + (float(rank_of("wind")) * 0.17 if not grounded else 0.0))))
	if boost_queued:
		_activate_boost()
		boost_queued = false
	if boost_time > 0.0:
		speed = minf(speed_limit(), speed + boost_accel() * dt)
		boost_time = maxf(0.0, boost_time - dt)
	if grounded:
		var next_speed := ground_speed(speed, g.y, dt, speed_limit())
		var change := next_speed - speed
		if change < 0.0 and g.y > 0.0:
			change *= 1.0 - float(rank_of("coast")) * 0.13
		var extra := float(rank_of("sprint")) * 1.5 * dt * (1.0 - smoothstep(50.0, 120.0, speed)) + float(rank_of("threshold")) * 2.0 * dt * smoothstep(80.0, 150.0, speed)
		if has_set(["stride", "sprint", "coast"]): extra += 2.0 * dt
		if speed < 40.0:
			extra += float(rank_of("recoveryrun")) * 3.0 * dt
		speed = clampf(speed + change * (1.0 + float(rank_of("stride")) * 0.08 if change > 0.0 else 1.0) + extra, 22.0, speed_limit())
		var curve: float = course.call("curvature", position.x, s)
		if land_lock <= 0.0 and should_launch(speed, curve, g.y):
			grounded = false
			vy = g.y * speed + g.x * lateral + 1.0 + float(rank_of("launch")) * 2.0 + (3.0 if has_set(["glide", "launch", "wind"]) else 0.0)
			speed = minf(speed_limit(), speed + float(rank_of("launchspeed")) * 3.0)
			energy = minf(100.0, energy + float(rank_of("launchcharge")) * 4.0)
			air_time = 0.0
			land_lock = 0.075
	if grounded:
		var next_ground := position + Vector3(lateral, 0.0, -speed) * dt
		if not bool(course.call("has_ground", next_ground.x, -next_ground.z)):
			grounded = false
			vy = g.y * speed + g.x * lateral
			air_time = 0.0
			land_lock = 0.0
		else:
			position = next_ground
			position.y = float(course.call("elevation", position.x, -position.z)) + FOOT
			safe_position = position
			diving = false
	if not grounded:
		air_time += dt
		diving = dive or (ability == 2 and boost_time > 0.0)
		energy = minf(100.0, energy + float(rank_of("aircharge")) * 3.0 * dt)
		# Hold to descend, release to preserve airtime. Boost briefly floats.
		vy -= flight_gravity(diving, boost_time) * dt
		speed = maxf(22.0, speed - air_drag() * dt)
		var next := position + Vector3(lateral, vy, -speed) * dt
		var next_floor := float(course.call("elevation", next.x, -next.z)) + FOOT
		var support: bool = course.call("has_ground", next.x, -next.z)
		if support and not bool(course.call("has_ground", old.x, -old.z)) and next.y < next_floor - 0.5:
			_fail_or_rescue(course)
			return
		if next.y < next_floor - 32.0:
			_fail_or_rescue(course)
			return
		# Substeps and a bracketed crossing prevent tunneling at high speed.
		if support and next.y <= next_floor and (land_lock <= 0.0 or vy < 0.0):
			position = contact_point(course, old, next)
			var normal: Vector3 = course.call("normal_at", position.x, -position.z)
			var slope: Vector2 = course.call("grade", position.x, -position.z)
			var velocity := Vector3(lateral, vy, -speed)
			var quality := landing_quality(velocity, normal, slope.y)
			if air_time >= 0.10:
				var landing_result := landing_speed(velocity, normal, slope.y, diving, speed_limit())
				if landing_result < speed:
					landing_result = lerpf(landing_result, speed, float(rank_of("landing")) * 0.13 + (0.12 if has_set(["landing", "impact", "guardian"]) else 0.0))
				speed = landing_result
				if quality == "PERFECT":
					speed = minf(speed_limit(), speed + float(rank_of("perfect")) * 5.0)
				elif quality == "GOOD":
					speed = minf(speed_limit(), speed + float(rank_of("good")) * 4.0)
				last_landing = quality
				landing_serial += 1
				flow_chain = flow_chain + 1 if quality == "PERFECT" or quality == "GOOD" else 0
				peak_chain = maxi(peak_chain, flow_chain)
				if flow_chain == 1 and perfect_landings + good_landings == 0:
					energy = minf(100.0, energy + float(rank_of("first")) * 10.0)
				match quality:
					"PERFECT":
						perfect_landings += 1
						energy = minf(100.0, energy + 22.0 + minf(10.0, air_time * 4.0) + minf(8.0, float(flow_chain) * 2.0))
					"GOOD":
						good_landings += 1
						energy = minf(100.0, energy + 12.0)
					"BAD":
						bad_landings += 1
					_:
						energy = minf(100.0, energy + 3.0)
				if quality == "PERFECT" or quality == "GOOD":
					energy = minf(100.0, energy + float(rank_of("charge")) * 6.0 + minf(5.0, float(flow_chain)) * float(rank_of("chain")) + (float(rank_of("divecharge")) * 5.0 if diving else 0.0))
					speed = minf(speed_limit(), speed + minf(5.0, float(flow_chain)) * float(rank_of("momentum")) * 1.5)
				else:
					energy = minf(100.0, energy + float(rank_of("composure")) * 5.0)
				cue = quality + " LANDING"
				cue_time = 0.7
				landing_compression = 1.0
			position.y = float(course.call("elevation", position.x, -position.z)) + FOOT
			safe_position = position
			vy = 0.0
			landing_marker.hide()
			grounded = true
			land_lock = 0.14
			air_time = 0.0
		else:
			position = next
	if absf(position.x) > 125.0:
		_fail_or_rescue(course)
		return
	peak_speed = maxf(peak_speed, speed)
	last_motion = position - old
	var gained: int = course.call("collect_sparks", old, position, 3.6 + float(rank_of("magnet")) * 2.0)
	if gained > 0:
		collected += gained + (gained / 2) * rank_of("fortune")
		energy = minf(100.0, energy + float(gained) * 1.5)
	if bool(course.call("obstacle_hit", old, position)):
		if protected_time > 0.0:
			return
		impacts += 1
		speed = maxf(22.0, speed * (0.60 + float(rank_of("impact")) * 0.10))
		flow_chain = 0
		cue = "MOMENTUM LOST"
		cue_time = 0.65

func apply_guardian_hit(effect: int = 0, direction: float = 1.0) -> void:
	if protected_time > 0.0:
		return
	impacts += 1
	speed = maxf(22.0, speed * (0.68 + float(rank_of("guardian")) * 0.08))
	flow_chain = 0
	match effect:
		1:
			energy = maxf(0.0, energy - 20.0)
			cue = "ENERGY DRAIN"
		2:
			gust_time = 0.8
			gust_direction = signf(direction)
			cue = "CROSSWIND"
		3:
			energy_lock = 1.4
			cue = "ABILITY JAMMED"
		4:
			if not grounded: vy = minf(vy, -14.0)
			cue = "DOWNDRAFT"
		_:
			cue = "GUARDIAN WAVE"
	cue_time = 0.7

func _pose(dt: float, course: Node3D) -> void:
	gait += dt * clampf(speed * 0.24, 5.0, 24.0)
	var slope: Vector2 = course.call("grade", position.x, -position.z)
	landing_compression = move_toward(landing_compression, 0.0, dt * 4.8)
	var pitch := atan(slope.y) if grounded else clampf(atan2(vy, speed), -0.8, 0.65)
	var steer := clampf(lateral / maxf(speed, 25.0), -1.0, 1.0)
	model.rotation.y = lerpf(model.rotation.y, -atan2(lateral, speed), 1.0 - exp(-dt * 9.0))
	model.rotation.x = lerpf(model.rotation.x, pitch * (0.65 if grounded else 0.30), 1.0 - exp(-dt * 10.0))
	model.call("pose_run", gait, speed, steer, grounded, diving, landing_compression, pitch, 1.0 - exp(-dt * 20.0))

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
		var tint := Color(0.35, 0.92, 1.0, strength * fade * fade * 0.85)
		trail_mesh.surface_set_color(tint)
		trail_mesh.surface_add_vertex(local - Vector3.RIGHT * width)
		trail_mesh.surface_set_color(tint)
		trail_mesh.surface_add_vertex(local + Vector3.RIGHT * width)
	trail_mesh.surface_end()

# Predict the landing using the same acceleration, horizontal drag and support
# test as flight. The marker is deliberately absent on ground and over void.
func predict_landing(course: Node3D, dive: bool) -> Dictionary:
	if grounded or fallen:
		return {}
	var p := position
	var vertical := vy
	var forward := speed
	var predicted_lateral := lateral
	var steer := _steer()
	var remaining_boost := boost_time
	var lock := land_lock
	var step := 1.0 / 120.0
	for i in range(360):
		lock = maxf(0.0, lock - step)
		var was_boosting := remaining_boost > 0.0
		if was_boosting:
			forward = minf(speed_limit(), forward + boost_accel() * step)
			remaining_boost = maxf(0.0, remaining_boost - step)
		vertical -= flight_gravity(dive or (ability == 2 and remaining_boost > 0.0), remaining_boost) * step
		forward = maxf(22.0, forward - air_drag() * step)
		var target_lateral := steer * minf(76.0, forward * 0.66) * (1.0 + float(rank_of("steer")) * 0.08) + (gust_direction * 12.0 if gust_time > float(i + 1) * step else 0.0)
		predicted_lateral = lerpf(predicted_lateral, target_lateral, 1.0 - exp(-step * 4.0 * (1.0 + float(rank_of("steer")) * 0.15 + float(rank_of("wind")) * 0.17)))
		var next := p + Vector3(predicted_lateral, vertical, -forward) * step
		var floor_y: float = course.call("elevation", next.x, -next.z)
		var supported: bool = course.call("has_ground", next.x, -next.z)
		if supported and next.y <= floor_y + FOOT and (lock <= 0.0 or vertical < 0.0):
			if not bool(course.call("has_ground", p.x, -p.z)) and next.y < floor_y - 0.5:
				return {}
			var contact := contact_point(course, p, next)
			var n: Vector3 = course.call("normal_at", contact.x, -contact.z)
			var slope: Vector2 = course.call("grade", contact.x, -contact.z)
			contact.y = float(course.call("elevation", contact.x, -contact.z))
			return {"point": contact, "normal": n, "quality": landing_quality(Vector3(predicted_lateral, vertical, -forward), n, slope.y), "seconds": float(i + 1) * step}
		if next.y < floor_y - 32.0 or absf(next.x) > 125.0:
			return {}
		p = next
	return {}

func _update_landing_marker(course: Node3D, dive: bool) -> void:
	var prediction := predict_landing(course, dive)
	if prediction.is_empty():
		landing_marker.hide()
		return
	var normal: Vector3 = prediction["normal"]
	var right := Vector3.RIGHT.slide(normal).normalized()
	landing_marker.global_transform = Transform3D(Basis(right, normal, right.cross(normal).normalized()), (prediction["point"] as Vector3) + normal * 0.22)
	var quality: String = prediction["quality"]
	landing_mat.albedo_color = Color(0.45, 1.0, 0.70, 0.88) if quality == "PERFECT" else (Color(0.98, 0.83, 0.32, 0.85) if quality == "GOOD" or quality == "OK" else Color(1.0, 0.34, 0.34, 0.85))
	landing_marker.show()

func has_set(ids: Array) -> bool:
	for id in ids:
		if rank_of(str(id)) == 0:
			return false
	return true

func _fail_or_rescue(course: Node3D) -> void:
	if rank_of("lastchance") > 0 and void_rescues == 0:
		# Recover on the supported side of the current gap, never rewind progress.
		var s := -position.z
		for x in [80.0, -80.0, 0.0]:
			if bool(course.call("has_ground", float(x), s)):
				position = Vector3(float(x), float(course.call("elevation", float(x), s)) + FOOT, -s)
				speed = maxf(30.0, speed * 0.55)
				lateral = 0.0
				vy = 0.0
				grounded = true
				air_time = 0.0
				land_lock = 0.4
				void_rescues += 1
				impacts += 1
				trail_samples.clear()
				landing_marker.hide()
				cue = "LAST LIGHT"
				cue_time = 0.8
				return
	fallen = true
	landing_marker.hide()

static func contact_point(course: Node3D, a: Vector3, b: Vector3) -> Vector3:
	var low := 0.0
	var high := 1.0
	for i in range(10):
		var mid := (low + high) * 0.5
		var p := a.lerp(b, mid)
		if not bool(course.call("has_ground", p.x, -p.z)) or p.y > float(course.call("elevation", p.x, -p.z)) + FOOT:
			low = mid
		else:
			high = mid
	return a.lerp(b, high)
