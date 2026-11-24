extends Node3D
## Endless ribbon generator. Progress is arc length, not world X.
## Each chunk owns its mesh, collision surface and obstacles.

const CHUNK_LENGTH := 192.0
const STEP := 1.0
const STEPS := 192
const HALF_WIDTH := 60.0
const CROSS_STEPS := 30
const THICKNESS := 0.45
const COLOR_CYCLE := 12000.0
const AHEAD := 5
const BEHIND := 2
const REBASE_DISTANCE := 2048.0
const RECOVERY_ACCEL := 18.0
const RECOVERY_HALF_WIDTH := 6.0
const SPECIAL_TRACKS: Array[String] = ["SPLIT ROUTE", "GAP CROSSING", "CORKSCREW TUNNEL", "HALFPIPE", "STACKED ROUTES", "SLIPSTREAM"]
const RunnerRules = preload("res://scripts/runner.gd")
const StormRules = preload("res://scripts/storm.gd")

var chunks: Dictionary = {}
var next_index := 0
var chunk_starts: Array[float] = [0.0]
var tail := Vector3.ZERO
var yaw := 0.0
var rng := RandomNumberGenerator.new()
var surface_mat: StandardMaterial3D
var line_mat: StandardMaterial3D
var origin_shift := Vector3.ZERO
var terrain_bag: Array[String] = []
var last_kind := ""
var sustained_roll_queue: Array[String] = []
var sustained_roll_sign := 1.0
var route_forecast: Dictionary = {}
var pursuit_context: Dictionary = {}
var demanding_sections := 0
var recovery_sections := 0
var rejected_layouts := 0
var fixed_daily_layout := false
# Fixed sequence is a test fixture only, never the default live course.
var showcase_layout := false
var recent_kinds: Array[String] = []
var sections_since_split := 0
# Archive the exact generated geometry, not merely the seed: endless
# generation is adaptive to the player's speed and storm gap.
const REPLAY_CHUNK_LIMIT := 768
var replay_recipes: Array[Dictionary] = []
var replay_layout := false

func _ready() -> void:
	surface_mat = _material(Color.WHITE)
	surface_mat.vertex_color_use_as_albedo = true
	line_mat = _material(Color.WHITE)
	line_mat.vertex_color_use_as_albedo = true
	reset_course(4731)

func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func reset_course(seed_value: int) -> void:
	for data in chunks.values():
		var node: Node3D = data["node"]
		remove_child(node)
		node.queue_free()
	chunks.clear()
	replay_recipes.clear()
	replay_layout = false
	next_index = 0
	chunk_starts.assign([0.0])
	tail = Vector3.ZERO
	yaw = 0.0
	origin_shift = Vector3.ZERO
	rng.seed = seed_value
	terrain_bag.clear()
	recent_kinds.clear()
	sections_since_split = 0
	last_kind = ""
	sustained_roll_queue.clear()
	sustained_roll_sign = 1.0
	route_forecast = {"speed": 22.0, "lane": 0.0, "gap": 92.0, "storm_speed": StormRules.INITIAL_SPEED, "time": 0.0, "min_gap": 92.0, "valid": true}
	pursuit_context.clear()
	demanding_sections = 0
	recovery_sections = 0
	rejected_layouts = 0
	stream(0.0)

func _showcase_kind(index: int) -> String:
	# Deterministic geometry fixture for headless regression tests only.
	if index == 0:
		return "HILLS"
	if index == 1:
		return "BANKED TURN"
	if index == 2:
		return "HILLS"
	if index == 3:
		return "TURN"
	if index == 4:
		return "180 BANK"
	if index == 5:
		return "360 BANK"
	# Seeded shuffle bag avoids repeated runs of the same terrain. The
	# two extreme banks occur much less often than the everyday profiles.
	if index == 6:
		return "LONG DESCENT"
	if index == 7:
		return "S CURVE"
	if index == 8:
		return "NARROW BRIDGE"
	if index == 9:
		return "ROLLING RIDGES"
	if index == 10:
		return "CAMBER WAVE"
	if index == 11:
		return "STEEP CLIMB"
	if index == 12:
		return "DROP AND RECOVERY"
	if index == 13:
		return "BANKED DESCENT"
	if index == 14:
		return "WIDE BASIN"
	if index == 15:
		return "CHICANE"
	# Long wall/ceiling sections have their own connected entrance,
	# sustained straight, and exit. The orientation stays constant across
	# the middle chunk instead of constantly twisting.
	if not sustained_roll_queue.is_empty():
		return sustained_roll_queue.pop_front()
	if index == 16:
		sustained_roll_queue.assign(["WALL RUN", "WALL EXIT"])
		return "WALL ENTRY"
	if index == 19:
		sustained_roll_queue.assign(["CEILING RUN", "CEILING EXIT"])
		return "CEILING ENTRY"
	# Showcase new route mechanics after the original introductory sequence.
	if index >= 23 and index <= 28:
		return SPECIAL_TRACKS[index - 23]
	return ""

func _kind(index: int) -> String:
	if not sustained_roll_queue.is_empty():
		return sustained_roll_queue.pop_front()
	if showcase_layout:
		var fixture := _showcase_kind(index)
		if not fixture.is_empty():
			return fixture
	if index == 0:
		# Start with a forgiving accelerating section, but not the same
		# section or longitudinal profile every run.
		var opening: Array[String] = ["HILLS", "LONG DESCENT", "WIDE BASIN", "SLIPSTREAM", "BANKED DESCENT"]
		return opening[rng.randi_range(0, opening.size() - 1)]
	# Never interrupt a committed wall/ceiling sequence. Insert a full
	# recovery section after repeated demanding terrain or a poor forecast.
	if demanding_sections >= 2 or (last_kind != "RECOVERY RUN" and float(route_forecast.get("gap", 92.0)) < 38.0 and float(route_forecast.get("speed", 22.0)) < float(route_forecast.get("storm_speed", 14.0)) + 12.0):
		if showcase_layout:
			return "RECOVERY RUN"
		var recovery: Array[String] = ["RECOVERY RUN", "LONG DESCENT", "SLIPSTREAM", "BANKED DESCENT"]
		recovery.erase(last_kind)
		return recovery[rng.randi_range(0, recovery.size() - 1)]
	# A branching stretch roughly every 3–5 ordinary sections, rather
	# than one appearance per 23-profile bag. Stacked decks count too.
	if not showcase_layout and index >= 2 and (sections_since_split >= 4 or (sections_since_split >= 2 and rng.randf() < 0.40)):
		return "STACKED ROUTES" if rng.randf() < 0.18 else "SPLIT ROUTE"
	if terrain_bag.is_empty():
		terrain_bag.assign(["HILLS", "TURN", "BANKED TURN", "LONG DESCENT", "S CURVE", "NARROW BRIDGE", "ROLLING RIDGES", "CAMBER WAVE", "STEEP CLIMB", "DROP AND RECOVERY", "BANKED DESCENT", "WIDE BASIN", "CHICANE", "180 BANK", "360 BANK", "WALL ENTRY", "CEILING ENTRY", "SPLIT ROUTE", "GAP CROSSING", "CORKSCREW TUNNEL", "HALFPIPE", "STACKED ROUTES", "SLIPSTREAM"])
	var candidates: Array[int] = []
	for i in range(terrain_bag.size()):
		var candidate := terrain_bag[i]
		if candidate == last_kind or recent_kinds.has(candidate):
			continue
		# Give the player an acceleration runway before difficult geometry.
		if index < 2 and (is_extreme_bank(candidate) or candidate in ["SPLIT ROUTE", "GAP CROSSING", "STACKED ROUTES", "STEEP CLIMB", "NARROW BRIDGE"]):
			continue
		candidates.append(i)
	if candidates.is_empty():
		for i in range(terrain_bag.size()):
			if terrain_bag[i] != last_kind and (index >= 2 or not is_extreme_bank(terrain_bag[i])):
				candidates.append(i)
	var choice := rng.randi_range(0, terrain_bag.size() - 1) if candidates.is_empty() else candidates[rng.randi_range(0, candidates.size() - 1)]
	var result: String = terrain_bag[choice]
	terrain_bag.remove_at(choice)
	if result == "WALL ENTRY":
		sustained_roll_queue.assign(["WALL RUN", "WALL EXIT"])
	elif result == "CEILING ENTRY":
		sustained_roll_queue.assign(["CEILING RUN", "CEILING EXIT"])
	return result

func is_sustained_roll(kind: String) -> bool:
	return kind.begins_with("WALL ") or kind.begins_with("CEILING ")

func is_extreme_bank(kind: String) -> bool:
	return kind == "180 BANK" or kind == "360 BANK" or is_sustained_roll(kind) or kind in ["CORKSCREW TUNNEL", "HALFPIPE"]

func width_for_kind(kind: String, u: float) -> float:
	var envelope := smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.75, 1.0, u))
	if kind == "NARROW BRIDGE":
		return lerpf(HALF_WIDTH, 30.0, envelope)
	if kind == "WIDE BASIN":
		return lerpf(HALF_WIDTH, 78.0, envelope)
	return HALF_WIDTH

func chunk_index_at(distance: float) -> int:
	return clampi(chunk_starts.bsearch(maxf(0.0, distance), false) - 1, 0, maxi(0, next_index - 1))

func bank_length(kind: String, planned_speed: float) -> float:
	if is_extreme_bank(kind) or kind in ["BANKED TURN", "TURN", "BANKED DESCENT", "S CURVE", "CHICANE", "CAMBER WAVE", "STACKED ROUTES", "SPLIT ROUTE", "SLIPSTREAM"]:
		# Scale length, not roll angle; no change to already generated road.
		return CHUNK_LENGTH * clampf(planned_speed / 65.0, 1.0, 8.0)
	return CHUNK_LENGTH

func half_width_at(distance: float) -> float:
	var index := chunk_index_at(distance)
	var kind := section_name(distance)
	var length := chunk_starts[index + 1] - chunk_starts[index]
	var u := clampf((distance - chunk_starts[index]) / length, 0.0, 1.0)
	return width_for_kind(kind, u)

func _roll_ease(u: float) -> float:
	# Integrate a softly eased angular velocity with a long constant-rate
	# middle. Unlike cubic smoothstep, this avoids a sharp peak roll rate.
	var t := clampf(u, 0.0, 1.0)
	var ramp := 0.18
	var scale := 1.0 - ramp
	if t < ramp:
		var x := t / ramp
		return 0.5 * ramp * (x - sin(PI * x) / PI) / scale
	if t > 1.0 - ramp:
		var x := (1.0 - t) / ramp
		return 1.0 - 0.5 * ramp * (x - sin(PI * x) / PI) / scale
	return (t - ramp * 0.5) / scale

func _orientation(kind: String, u: float, start_yaw: float, target_yaw: float, bank_sign: float = 1.0, strength: float = 1.0) -> Basis:
	var angle := lerpf(start_yaw, target_yaw, smoothstep(0.0, 1.0, u))
	var pitch := 0.0
	var roll := 0.0
	if kind == "HILLS":
		pitch = -0.32 * sin(TAU * u) - 0.15 * sin(PI * u)
	elif kind == "BANKED TURN":
		roll = signf(target_yaw - start_yaw) * 0.64 * sin(PI * u) * sin(PI * u)
	elif kind == "TURN":
		roll = signf(target_yaw - start_yaw) * 0.18 * sin(PI * u) * sin(PI * u)
	elif kind == "LONG DESCENT":
		pitch = -0.44 * sin(PI * u) * strength
	elif kind == "RECOVERY RUN":
		pitch = -0.32 * sin(PI * u)
	elif kind == "SLIPSTREAM":
		pitch = -0.18 * sin(PI * u)
	elif kind == "CORKSCREW TUNNEL":
		roll = bank_sign * TAU * _roll_ease(u)
	elif kind == "STEEP CLIMB":
		# Shorter, gentler sustained climb with shallow downhill approaches.
		pitch = (0.28 * pow(sin(PI * u), 4.0) - 0.10 * pow(sin(TAU * u), 2.0)) * strength
	elif kind == "ROLLING RIDGES":
		pitch = 0.23 * sin(TAU * 2.0 * u) * strength
	elif kind == "DROP AND RECOVERY":
		pitch = (-0.62 * exp(-pow((u - 0.28) / 0.15, 2.0)) + 0.30 * exp(-pow((u - 0.68) / 0.17, 2.0))) * sin(PI * u) * strength
	elif kind == "S CURVE":
		angle = clampf(start_yaw + bank_sign * 0.33 * sin(TAU * u) * sin(PI * u) * strength, -1.25, 1.25)
		roll = bank_sign * 0.32 * sin(TAU * u) * sin(PI * u)
	elif kind == "CHICANE":
		angle = clampf(start_yaw + bank_sign * 0.18 * sin(TAU * 2.0 * u) * sin(PI * u) * strength, -1.25, 1.25)
		roll = bank_sign * 0.23 * sin(TAU * 2.0 * u) * sin(PI * u)
	elif kind == "CAMBER WAVE":
		roll = bank_sign * 0.46 * sin(TAU * u) * sin(PI * u) * strength
		pitch = -0.10 * sin(TAU * u)
	elif kind == "BANKED DESCENT":
		pitch = -0.34 * sin(PI * u) * strength
		roll = signf(target_yaw - start_yaw) * 0.52 * sin(PI * u) * sin(PI * u)
	elif kind == "WIDE BASIN":
		pitch = -0.20 * sin(TAU * u) * strength
	elif is_sustained_roll(kind):
		var target_roll := PI * 0.5 if kind.begins_with("WALL ") else PI
		var progress := 1.0
		if kind.ends_with("ENTRY"):
			progress = _roll_ease(u)
		elif kind.ends_with("EXIT"):
			progress = 1.0 - _roll_ease(u)
		roll = bank_sign * target_roll * progress
	elif kind == "180 BANK":
		# A smooth half-roll to an inverted stretch, then unwind.
		# Entry and exit are both upright so neighboring chunks join cleanly.
		roll = bank_sign * PI * _roll_ease(u / 0.44) * (1.0 - _roll_ease((u - 0.56) / 0.44))
	elif kind == "360 BANK":
		# Continuous barrel roll with zero roll rate at both seams.
		roll = bank_sign * TAU * _roll_ease(u)
	var heading := Vector3(cos(angle), 0, sin(angle))
	var side := Vector3(-sin(angle), 0, cos(angle))
	var forward := heading * cos(pitch) + Vector3.UP * sin(pitch)
	forward = forward.normalized()
	var right := (side - forward * side.dot(forward)).normalized().rotated(forward, roll)
	var up := right.cross(forward).normalized()
	return Basis(right, up, -forward).orthonormalized()

func _build_chunk(index: int, planned_speed: float = 22.0) -> void:
	if fixed_daily_layout:
		planned_speed = 65.0 + minf(float(index) * 2.0, 130.0)
	var kind := _kind(index)
	var start_s := chunk_starts[index]
	var length := bank_length(kind, planned_speed)
	if not showcase_layout:
		# Independent, seeded longitudinal variation. Stretch technical
		# sections, rather than squeezing banks below the safe base length.
		length *= rng.randf_range(1.0, 1.45)
		if kind in ["SPLIT ROUTE", "STACKED ROUTES"]:
			length = maxf(length, planned_speed * 3.4)
	var step_length := length / float(STEPS)
	var strength := 1.0 if showcase_layout and index < 6 else rng.randf_range(0.72, 1.22)
	var start_yaw := yaw
	var target_yaw := yaw
	var bank_sign := -1.0 if rng.randf() < 0.5 else 1.0
	if is_sustained_roll(kind):
		if kind.ends_with("ENTRY"):
			sustained_roll_sign = bank_sign
		bank_sign = sustained_roll_sign
	if kind == "TURN" or kind == "BANKED TURN" or kind == "BANKED DESCENT":
		var direction := -1.0 if yaw > 0.35 else (1.0 if yaw < -0.35 else (-1.0 if rng.randf() < 0.5 else 1.0))
		target_yaw = clampf(yaw + direction * rng.randf_range(0.75, 0.98), -1.25, 1.25)
	# Plan terrain and obstacle groups before instantiating the mesh. The
	# preview uses the same grades, slide acceleration and storm equations
	# as gameplay, with conservative lateral reach and obstacle bounds.
	var points := _make_points(kind, start_yaw, target_yaw, bank_sign, strength, step_length)
	var layout := _plan_obstacles(index, kind, points, step_length, planned_speed)
	var forecast := _validate_routes(index, kind, points, step_length, layout, route_forecast)
	if (not showcase_layout or index >= 29) and not is_extreme_bank(kind) and kind != "RECOVERY RUN" and (not bool(forecast["valid"]) or float(forecast["min_gap"]) < 14.0):
		rejected_layouts += 1
		# First remove optional obstacles; if terrain itself remains risky,
		# replace it with a clear downhill recovery stretch.
		layout.clear()
		forecast = _validate_routes(index, kind, points, step_length, layout, route_forecast)
		if not bool(forecast["valid"]) or float(forecast["min_gap"]) < 14.0:
			# Try different obstacle-free downhill profiles before falling
			# back to a recovery run; avoid making every rejected section identical.
			var alternatives: Array[String] = []
			if not showcase_layout:
				alternatives.assign(["LONG DESCENT", "SLIPSTREAM", "BANKED DESCENT"])
			while not alternatives.is_empty():
				var pick := rng.randi_range(0, alternatives.size() - 1)
				var alternate := alternatives[pick]
				alternatives.remove_at(pick)
				if alternate == last_kind:
					continue
				var alternative_length := maxf(length, bank_length(alternate, planned_speed))
				var alternative_step := alternative_length / float(STEPS)
				var alternative_points := _make_points(alternate, start_yaw, start_yaw, bank_sign, strength, alternative_step)
				var alternative_forecast := _validate_routes(index, alternate, alternative_points, alternative_step, layout, route_forecast)
				if bool(alternative_forecast["valid"]) and float(alternative_forecast["min_gap"]) >= 14.0:
					kind = alternate
					length = alternative_length
					step_length = alternative_step
					points = alternative_points
					forecast = alternative_forecast
					target_yaw = start_yaw
					break
			if not bool(forecast["valid"]) or float(forecast["min_gap"]) < 14.0:
				kind = "RECOVERY RUN"
				target_yaw = start_yaw
				length = bank_length(kind, planned_speed)
				step_length = length / float(STEPS)
				points = _make_points(kind, start_yaw, target_yaw, bank_sign, 1.0, step_length)
				forecast = _validate_routes(index, kind, points, step_length, layout, route_forecast)
	last_kind = kind
	if kind in ["SPLIT ROUTE", "STACKED ROUTES"]:
		sections_since_split = 0
	else:
		sections_since_split += 1
	recent_kinds.append(kind)
	if recent_kinds.size() > 4:
		recent_kinds.pop_front()
	route_forecast = forecast
	chunk_starts.append(start_s + length)
	if kind in ["RECOVERY RUN", "LONG DESCENT", "BANKED DESCENT", "SLIPSTREAM"]:
		demanding_sections = 0
		recovery_sections += 1
	elif kind in ["HILLS", "STEEP CLIMB", "ROLLING RIDGES", "DROP AND RECOVERY", "NARROW BRIDGE"] or is_extreme_bank(kind):
		demanding_sections += 1
	else:
		demanding_sections = maxi(0, demanding_sections - 1)
	var absolute_origin := tail + origin_shift
	if replay_recipes.size() < REPLAY_CHUNK_LIMIT:
		replay_recipes.append({"index": index, "start": start_s, "length": length, "kind": kind, "origin": absolute_origin, "points": points, "layout": layout.duplicate(true)})
	_instantiate_chunk(index, kind, points, start_s, step_length, tail, layout, forecast)
	tail += points[-1].origin
	yaw = target_yaw

func _instantiate_chunk(index: int, kind: String, points: Array[Transform3D], start_s: float, step_length: float, local_origin: Vector3, layout: Array[Dictionary], forecast: Dictionary = {}) -> void:
	var node := Node3D.new()
	node.name = "Track_%d" % index
	node.position = local_origin
	add_child(node)
	var hazards: Array[Dictionary] = []
	_build_mesh(node, points, start_s, kind, index, step_length)
	for item in layout:
		var at: float = item["at"]
		var i := mini(int(floor(at)), STEPS - 1)
		var frame := points[i].interpolate_with(points[i + 1], at - float(i))
		if bool(item.get("gate", false)):
			# Gate remains at the base road; the opening follows the marked shortcut.
			_spawn_route_gate(node, hazards, frame, start_s + at * step_length, float(item["lane"]), float(item["gap"]))
		else:
			var lane: float = item["lane"]
			frame.origin += frame.basis.y * _ramp_lift(index, kind, at, lane)
			_spawn_obstacle(node, hazards, frame, start_s + at * step_length, lane, int(item["shape"]))
	chunks[index] = {"node": node, "points": points, "kind": kind, "hazards": hazards, "layout": layout, "forecast": forecast}

func _make_points(kind: String, start_yaw: float, target_yaw: float, bank_sign: float, strength: float, step_length: float) -> Array[Transform3D]:
	var points: Array[Transform3D] = []
	var p := Vector3.ZERO
	for i in range(STEPS + 1):
		var u := float(i) / float(STEPS)
		var basis := _orientation(kind, u, start_yaw, target_yaw, bank_sign, strength)
		points.append(Transform3D(basis, p))
		if i < STEPS:
			var mid := _orientation(kind, (float(i) + 0.5) / float(STEPS), start_yaw, target_yaw, bank_sign, strength)
			p += -mid.z * step_length
	return points

func _plan_obstacles(index: int, kind: String, points: Array[Transform3D], step_length: float, planned_speed: float) -> Array[Dictionary]:
	var layout: Array[Dictionary] = []
	if kind in SPECIAL_TRACKS or kind in ["RECOVERY RUN", "STEEP CLIMB", "LONG DESCENT", "NARROW BRIDGE", "ROLLING RIDGES", "DROP AND RECOVERY", "CHICANE"] or is_sustained_roll(kind):
		return layout
	var positions: Array[float] = []
	if not showcase_layout:
		if index == 0:
			positions.assign([rng.randf_range(100.0, 150.0)])
		else:
			var at := rng.randf_range(24.0, 54.0)
			while at < 170.0:
				positions.append(at)
				at += rng.randf_range(38.0, 76.0)
	elif index == 0:
		positions.assign([82.0, 137.0])
	elif index == 1:
		positions.assign([35.0, 72.0, 108.0, 144.0, 174.0])
	elif kind == "180 BANK" or kind == "360 BANK":
		positions.assign([30.0, 160.0])
	elif index < 6:
		positions.assign([18.0, 40.0, 140.0, 161.0, 180.0])
	else:
		positions.assign([32.0, 100.0, 156.0])
	var previous := -100000.0
	var reaction_spacing := maxf(28.0, planned_speed * 1.15)
	var gate := (index >= 2 and index < 6 if showcase_layout else index >= 2 and rng.randf() < 0.17 and planned_speed < 100.0 and kind in ["TURN", "BANKED TURN", "WIDE BASIN"]) and not is_extreme_bank(kind)
	var gate_lane := shortcut_center(index) if has_shortcut(kind) else (-14.0 if index % 2 == 0 else 14.0)
	for i in range(positions.size()):
		var at: float = positions[i]
		var shape_id := (index * 5 + i) % 10 if showcase_layout and index < 6 else rng.randi_range(0, 9)
		# Intro retains its shape showcase. Later layouts enforce a full
		# reaction interval, and exclude blind crests, hard slopes and edges.
		if not showcase_layout or index >= 6:
			if gate and absf(at - 94.0) * step_length < reaction_spacing:
				continue
			if (at - previous) * step_length < reaction_spacing:
				continue
			var before_i := maxi(0, int(at) - 14)
			var after_i := mini(STEPS, int(at) + 12)
			var before_grade := -points[before_i].basis.z.y
			var after_grade := -points[after_i].basis.z.y
			if before_grade > 0.075 or before_grade - after_grade > 0.10:
				continue
		var safe_lane := recovery_center(index) if _has_recovery(kind) else 0.0
		# Keep the recovery/bypass and a broad centre corridor obstacle-free.
		# Gate approach and exit stay clear around the opening.
		var bound := width_for_kind(kind, at / CHUNK_LENGTH) - 7.0
		var lane := float(rng.randi_range(-8, 8)) * 4.8
		lane = clampf(lane, -bound, bound)
		if absf(lane) < 15.0 or absf(lane - safe_lane) < 14.0 or absf(_ramp_lift(index, kind, at, lane)) > 0.02 or (gate and absf(lane - gate_lane) < 16.0):
			lane = -42.0 if safe_lane >= 0.0 else 42.0
			if gate:
				lane = -42.0 if gate_lane >= 0.0 else 42.0
			lane = clampf(lane, -bound, bound)
		if (not showcase_layout or index >= 6) and (absf(lane - safe_lane) < 14.0 or absf(lane) < 15.0):
			continue
		if has_shortcut(kind) and absf(lane - shortcut_center(index)) < 15.0:
			lane = clampf(-shortcut_center(index), -bound, bound)
		layout.append({"at": at, "lane": lane, "shape": shape_id})
		previous = at
	if gate:
		layout.append({"at": 94.0, "lane": gate_lane, "gap": 24.0, "gate": true})
	return layout

func _forecast_grade(index: int, kind: String, points: Array[Transform3D], at: float, lane: float, step_length: float) -> float:
	var i := clampi(int(round(at)), 1, STEPS - 1)
	var frame := points[i]
	var slope := (_ramp_lift(index, kind, float(i + 1), lane) - _ramp_lift(index, kind, float(i - 1), lane)) / (2.0 * step_length)
	return (-frame.basis.z + frame.basis.y * slope).normalized().y

func _validate_routes(index: int, kind: String, points: Array[Transform3D], step_length: float, layout: Array[Dictionary], initial: Dictionary, begin_at: float = 0.0) -> Dictionary:
	# Evaluate distinct reachable lane choices, not merely a centreline.
	# A conservative steering rate and padded obstacle envelope account for
	# player reaction time. Predict pursuit without slowing the live storm.
	var best: Dictionary = {}
	var best_score := -INF
	for target: float in [-44.0, -28.0, -14.0, 0.0, 14.0, 28.0, 44.0]:
		var v := maxf(7.0, float(initial.get("speed", 22.0)))
		var lane := float(initial.get("lane", 0.0))
		var gap := float(initial.get("gap", 92.0))
		var storm_v := float(initial.get("storm_speed", StormRules.INITIAL_SPEED))
		var elapsed := float(initial.get("time", 0.0))
		var min_gap := gap
		var clear := true
		var at := clampf(begin_at, 0.0, float(STEPS))
		while at < float(STEPS):
			var next_at := minf(float(STEPS), at + 4.0)
			var ds := (next_at - at) * step_length
			var dt := ds / maxf(7.0, v)
			var old_lane := lane
			var bound := width_for_kind(kind, next_at / CHUNK_LENGTH) - 2.0
			var desired := clampf(target, -bound, bound)
			# Steer toward the known gate opening before entering its zone.
			for item in layout:
				if bool(item.get("gate", false)) and at < float(item["at"]) + 3.0:
					desired = float(item["lane"])
					break
			lane = move_toward(lane, desired, 12.0 * dt)
			if absf(lane) > bound or not _cell_supported(kind, next_at, lane):
				clear = false
			for item in layout:
				var obstacle_at: float = item["at"]
				if obstacle_at + 4.0 / step_length < at or obstacle_at - 4.0 / step_length > next_at:
					continue
				var cross_lane := lerpf(old_lane, lane, clampf((obstacle_at - at) / maxf(0.01, next_at - at), 0.0, 1.0))
				if bool(item.get("gate", false)):
					if absf(cross_lane - float(item["lane"])) > float(item["gap"]) * 0.5 - 1.5:
						clear = false
				elif absf(cross_lane - float(item["lane"])) < 6.0:
					clear = false
			var grade := _forecast_grade(index, kind, points, (at + next_at) * 0.5, lane, step_length)
			v = RunnerRules.slide_speed_step(v, grade, dt)
			v += _recovery_strength(index, kind, (at + next_at) * 0.5, lane) * RECOVERY_ACCEL * dt
			if kind == "SLIPSTREAM":
				v += 14.0 * _profile_envelope(next_at) * (1.0 - smoothstep(7.0, 12.0, absf(lane - slipstream_center(index, next_at)))) * dt
			var acceleration := StormRules.ACCELERATION + StormRules.ACCELERATION_GROWTH * elapsed
			gap += ds - storm_v * dt - 0.5 * acceleration * dt * dt - StormRules.ACCELERATION_GROWTH * dt * dt * dt / 6.0
			storm_v += acceleration * dt + 0.5 * StormRules.ACCELERATION_GROWTH * dt * dt
			elapsed += dt
			min_gap = minf(min_gap, gap)
			at = next_at
		var valid := clear and min_gap > 1.0
		var score := min_gap + gap * 0.15 + v * 0.6 + (100000.0 if valid else (10000.0 if clear else 0.0))
		if score > best_score:
			best_score = score
			best = {"speed": v, "lane": lane, "gap": gap, "storm_speed": storm_v, "time": elapsed, "min_gap": min_gap, "valid": valid, "clear": clear, "target_lane": target}
	return best

func set_pursuit_context(at: float, across: float, speed: float, gap: float, storm_speed: float, elapsed: float) -> void:
	pursuit_context = {"at": at, "lane": across, "speed": speed, "gap": gap, "storm_speed": storm_speed, "time": elapsed, "min_gap": gap, "valid": true}

func _refresh_forecast() -> void:
	if fixed_daily_layout or pursuit_context.is_empty() or next_index == 0:
		return
	var at: float = pursuit_context["at"]
	var index := chunk_index_at(at)
	if not chunks.has(index):
		return
	var prediction := pursuit_context.duplicate()
	# Reforecast the committed lookahead from the actual runner and storm.
	# Existing road stays fixed; only not-yet-generated chunks can change.
	for i in range(index, next_index):
		if not chunks.has(i):
			continue
		var data: Dictionary = chunks[i]
		var step_length := (chunk_starts[i + 1] - chunk_starts[i]) / float(STEPS)
		var begin_at := maxf(0.0, (at - chunk_starts[i]) / step_length)
		prediction = _validate_routes(i, str(data["kind"]), data["points"], step_length, data["layout"], prediction, begin_at)
	route_forecast = prediction



func biome_name(distance: float) -> String:
	var names: Array[String] = ["NEON LOWLANDS", "AMBER CANYONS", "GLACIAL RIBBONS", "VIOLET ABYSS", "EMERALD CURRENTS"]
	return names[posmod(int(floor(maxf(0.0, distance) / 2400.0)), names.size())]

func track_color(distance: float, accent: float = 0.0, saturation: float = 0.84, value: float = 0.95) -> Color:
	# Continuous transition between terrain palettes, with no seam flashes.
	var hues: Array[float] = [0.54, 0.09, 0.53, 0.78, 0.36]
	var zone := maxf(0.0, distance) / 2400.0
	var index := int(floor(zone))
	var blend := smoothstep(0.72, 1.0, zone - floor(zone))
	var hue := lerpf(hues[posmod(index, hues.size())], hues[posmod(index + 1, hues.size())], blend)
	return Color.from_hsv(fposmod(hue + distance / COLOR_CYCLE * 0.12 + accent, 1.0), saturation, value)

func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _round_mesh(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh

func _part(parent: Node3D, frame: Transform3D, lane: float, bottom: float, width: float, height: float, depth: float, mesh: Mesh, mat: Material, hazards: Array[Dictionary], at: float, group: Dictionary, profile: String = "BOX", tilt: float = 0.0) -> void:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = mat
	var basis := frame.basis.rotated(-frame.basis.z, tilt)
	visual.transform = Transform3D(basis, frame.origin + frame.basis.x * lane + frame.basis.y * (bottom + height * 0.5))
	parent.add_child(visual)
	hazards.append({"s": at, "lane": lane, "width": width, "height": height, "bottom": bottom, "depth": depth, "profile": profile, "group": group})

func _spawn_obstacle(node: Node3D, hazards: Array[Dictionary], frame: Transform3D, at: float, lane: float, shape_id: int) -> void:
	var mat := _material(track_color(at, 0.40, 0.88, 1.0))
	var accent := _material(track_color(at, 0.48, 0.42, 1.0))
	var group := {"used": false, "shape": shape_id}
	match shape_id:
		0: # Tall rectangular block
			_part(node, frame, lane, 0.0, 3.5, 5.0, 3.0, _box_mesh(Vector3(3.5, 5.0, 3.0)), mat, hazards, at, group)
		1: # Round column
			_part(node, frame, lane, 0.0, 4.0, 5.5, 4.0, _round_mesh(2.0, 2.0, 5.5, 12), mat, hazards, at, group, "ROUND")
		2: # Cone
			_part(node, frame, lane, 0.0, 5.0, 5.5, 5.0, _round_mesh(0.0, 2.5, 5.5, 12), mat, hazards, at, group, "CONE")
		3: # Octahedral-style crystal, two tapered halves
			_part(node, frame, lane, 0.0, 4.8, 2.4, 4.8, _round_mesh(2.4, 0.0, 2.4, 4), mat, hazards, at, group, "INVERSE_CONE")
			_part(node, frame, lane, 2.4, 4.8, 3.0, 4.8, _round_mesh(0.0, 2.4, 3.0, 4), accent, hazards, at, group, "CONE")
		4: # Sphere
			var sphere := SphereMesh.new()
			sphere.radius = 2.1
			sphere.height = 4.2
			sphere.radial_segments = 16
			sphere.rings = 8
			_part(node, frame, lane, 0.0, 4.2, 4.2, 4.2, sphere, mat, hazards, at, group, "SPHERE")
		5: # Jumpable low hurdle
			_part(node, frame, lane, 0.0, 9.0, 1.35, 2.0, _box_mesh(Vector3(9.0, 1.35, 2.0)), mat, hazards, at, group)
		6: # Arch with a real opening
			_part(node, frame, lane - 3.4, 0.0, 1.5, 5.0, 2.2, _box_mesh(Vector3(1.5, 5.0, 2.2)), mat, hazards, at, group)
			_part(node, frame, lane + 3.4, 0.0, 1.5, 5.0, 2.2, _box_mesh(Vector3(1.5, 5.0, 2.2)), mat, hazards, at, group)
			_part(node, frame, lane, 3.4, 8.3, 1.6, 2.2, _box_mesh(Vector3(8.3, 1.6, 2.2)), accent, hazards, at, group)
		7: # Stair-step barrier
			_part(node, frame, lane - 2.8, 0.0, 2.8, 1.1, 2.8, _box_mesh(Vector3(2.8, 1.1, 2.8)), mat, hazards, at, group)
			_part(node, frame, lane, 0.0, 2.8, 2.4, 2.8, _box_mesh(Vector3(2.8, 2.4, 2.8)), accent, hazards, at, group)
			_part(node, frame, lane + 2.8, 0.0, 2.8, 3.8, 2.8, _box_mesh(Vector3(2.8, 3.8, 2.8)), mat, hazards, at, group)
		8: # Hexagonal prism
			_part(node, frame, lane, 0.0, 5.0, 3.6, 5.0, _round_mesh(2.5, 2.5, 3.6, 6), mat, hazards, at, group, "ROUND")
		9: # Paired spires with a central path
			_part(node, frame, lane - 3.6, 0.0, 3.0, 6.0, 3.0, _round_mesh(0.0, 1.5, 6.0, 5), mat, hazards, at, group, "CONE")
			_part(node, frame, lane + 3.6, 0.0, 3.0, 6.0, 3.0, _round_mesh(0.0, 1.5, 6.0, 5), accent, hazards, at, group, "CONE")

func _spawn_route_gate(node: Node3D, hazards: Array[Dictionary], frame: Transform3D, at: float, opening: float, gap_width: float) -> void:
	var mat := _material(track_color(at, 0.40, 0.92, 0.85))
	var group := {"used": false, "rewarded": false, "shape": 10, "gate": true, "opening": opening, "gap_width": gap_width}
	var left_edge := opening - gap_width * 0.5
	var right_edge := opening + gap_width * 0.5
	var left_width := left_edge + HALF_WIDTH
	var right_width := HALF_WIDTH - right_edge
	var wall_height := 42.0
	_part(node, frame, (-HALF_WIDTH + left_edge) * 0.5, 0.0, left_width, wall_height, 2.0, _box_mesh(Vector3(left_width, wall_height, 2.0)), mat, hazards, at, group)
	_part(node, frame, (right_edge + HALF_WIDTH) * 0.5, 0.0, right_width, wall_height, 2.0, _box_mesh(Vector3(right_width, wall_height, 2.0)), mat, hazards, at, group)
	# Contrasting edges visually identify the opening before the player reaches it.
	var edge_mat := _material(track_color(at, 0.20, 0.52, 1.0))
	for edge: float in [left_edge, right_edge]:
		var edge_mesh := MeshInstance3D.new()
		edge_mesh.mesh = _box_mesh(Vector3(0.18, wall_height, 2.15))
		edge_mesh.material_override = edge_mat
		edge_mesh.transform = Transform3D(frame.basis, frame.origin + frame.basis.x * edge + frame.basis.y * wall_height * 0.5)
		node.add_child(edge_mesh)

func ramp_center(index: int) -> float:
	return 28.0 if index % 2 == 1 else -28.0

func recovery_center(index: int) -> float:
	return -28.0 if index % 2 == 0 else 28.0

func bypass_center(index: int) -> float:
	return recovery_center(index)

func _has_recovery(kind: String) -> bool:
	return kind in ["RECOVERY RUN", "LONG DESCENT", "STEEP CLIMB"]

func _recovery_strength(index: int, kind: String, local_s: float, across: float) -> float:
	if not _has_recovery(kind):
		return 0.0
	var envelope := smoothstep(12.0, 32.0, local_s) * (1.0 - smoothstep(160.0, 180.0, local_s))
	return envelope * (1.0 - smoothstep(RECOVERY_HALF_WIDTH - 2.0, RECOVERY_HALF_WIDTH, absf(across - recovery_center(index))))

func recovery_accel(distance: float, across: float, side: int = 1) -> float:
	if side < 0 or not has_distance(distance):
		return 0.0
	var index := chunk_index_at(distance)
	var local_s := (distance - chunk_starts[index]) * CHUNK_LENGTH / (chunk_starts[index + 1] - chunk_starts[index])
	return RECOVERY_ACCEL * _recovery_strength(index, section_name(distance), local_s, across)

func has_shortcut(kind: String) -> bool:
	return kind in ["HILLS", "STEEP CLIMB", "ROLLING RIDGES"]

func shortcut_center(index: int) -> float:
	return 44.0 if index % 2 == 0 else -44.0

func _shortcut_weight(index: int, kind: String, local_s: float, across: float) -> float:
	if not has_shortcut(kind):
		return 0.0
	var envelope := smoothstep(0.0, 18.0, local_s) * (1.0 - smoothstep(174.0, 192.0, local_s))
	return envelope * (1.0 - smoothstep(5.0, 13.0, absf(across - shortcut_center(index))))

func shortcut_at(distance: float, across: float) -> bool:
	if not has_distance(distance):
		return false
	var index := chunk_index_at(distance)
	var local_s := (distance - chunk_starts[index]) * CHUNK_LENGTH / (chunk_starts[index + 1] - chunk_starts[index])
	return _shortcut_weight(index, section_name(distance), local_s, across) > 0.5

func _shortcut_lift(index: int, kind: String, local_s: float, across: float) -> float:
	var u := clampf(local_s / CHUNK_LENGTH, 0.0, 1.0)
	var weight := _shortcut_weight(index, kind, local_s, across)
	if kind == "HILLS":
		# Smooth, lower-grade chord around the central valley and climb.
		var estimated_y := CHUNK_LENGTH * (0.32 / TAU * (cos(TAU * u) - 1.0) + 0.15 / PI * (cos(PI * u) - 1.0))
		var chord_y := -CHUNK_LENGTH * 0.30 / PI * smoothstep(0.0, 1.0, u)
		return (chord_y - estimated_y) * weight
	if kind == "STEEP CLIMB":
		return 10.0 * sin(TAU * u) * pow(sin(PI * u), 2.0) * weight
	if kind == "ROLLING RIDGES":
		return -3.5 * (1.0 - cos(TAU * 2.0 * u)) * weight
	return 0.0

func _ramp_lift(index: int, kind: String, local_s: float, across: float) -> float:
	if kind in SPECIAL_TRACKS:
		return 0.0
	var shortcut := _shortcut_lift(index, kind, local_s, across)
	# Alternate grade on major climbs: distribute the elevation change
	# over the approaches, while flattening the sharp central ascent.
	if kind == "STEEP CLIMB":
		var u := clampf(local_s / CHUNK_LENGTH, 0.0, 1.0)
		var weight := 1.0 - smoothstep(7.0, 19.0, absf(across - bypass_center(index)))
		return 10.0 * sin(TAU * u) * pow(sin(PI * u), 2.0) * weight + shortcut
	# A local rise, crest and runout occupying only a portion of the road.
	# The other lanes remain unchanged; no ramp on narrow or inverted banks.
	if index == 0 or (index != 1 and index % 3 != 0) or kind in ["NARROW BRIDGE", "RECOVERY RUN", "LONG DESCENT"] or is_extreme_bank(kind):
		return shortcut
	var lateral := 1.0 - smoothstep(5.0, 12.0, absf(across - ramp_center(index)))
	var rise := smoothstep(58.0, 99.0, local_s)
	var runout := 1.0 - smoothstep(99.0, 132.0, local_s)
	return (5.0 + float(index % 3)) * lateral * rise * runout + shortcut

func surface_lift(distance: float, across: float) -> float:
	var index := chunk_index_at(distance)
	if not chunks.has(index):
		return 0.0
	var local_s := (distance - chunk_starts[index]) * CHUNK_LENGTH / (chunk_starts[index + 1] - chunk_starts[index])
	return _ramp_lift(index, section_name(distance), local_s, across)

func surface_position(distance: float, across: float) -> Vector3:
	# Map only needs a point, not a full tangent/normal reconstruction.
	var index := chunk_index_at(distance)
	var kind := section_name(distance)
	var local_s := _local_s(distance)
	return _profile_vertex(sample(distance), kind, local_s, across, _ramp_lift(index, kind, local_s, across))

func surface_frame(distance: float, across: float, side: int = 1) -> Transform3D:
	var frame := sample(distance)
	var kind := section_name(distance)
	if _special_profile(kind):
		var local_s := _local_s(distance)
		var normal := _cross_normal(kind, local_s, across)
		var up := (frame.basis.x * normal.x + frame.basis.y * normal.y).normalized()
		var before := _profile_vertex(sample(distance - 0.25), section_name(distance - 0.25), _local_s(distance - 0.25), across)
		var after := _profile_vertex(sample(distance + 0.25), section_name(distance + 0.25), _local_s(distance + 0.25), across)
		var forward := (after - before).normalized()
		if forward.length_squared() < 0.5:
			forward = -frame.basis.z
		var right := forward.cross(up).normalized()
		up = right.cross(forward).normalized()
		var point := _profile_vertex(frame, kind, local_s, across, 0.0 if side > 0 else -THICKNESS)
		return Transform3D(Basis(right * float(side), up * float(side), -forward).orthonormalized(), point)
	var lift := surface_lift(distance, across)
	var slope := (surface_lift(distance + 0.5, across) - surface_lift(distance - 0.5, across))
	var cross_slope := surface_lift(distance, across + 0.5) - surface_lift(distance, across - 0.5)
	var forward := (-frame.basis.z + frame.basis.y * slope).normalized()
	var right := (frame.basis.x + frame.basis.y * cross_slope).normalized()
	var up := right.cross(forward).normalized()
	right = forward.cross(up).normalized()
	var point := frame.origin + frame.basis.x * across + frame.basis.y * (lift if side > 0 else lift - THICKNESS)
	return Transform3D(Basis(right * float(side), up * float(side), -forward).orthonormalized(), point)

func surface_clearance(distance: float, across: float, raw_height: float, side: int) -> float:
	var lift := 0.0 if _special_profile(section_name(distance)) else surface_lift(distance, across)
	return raw_height - lift if side > 0 else lift - THICKNESS - raw_height

func lane_limit(distance: float = -1.0) -> float:
	return (HALF_WIDTH if distance < 0.0 else half_width_at(distance)) - 0.75

func _special_profile(kind: String) -> bool:
	return kind in ["CORKSCREW TUNNEL", "HALFPIPE", "STACKED ROUTES"]

func _profile_envelope(local_s: float) -> float:
	return smoothstep(0.0, 45.0, local_s) * (1.0 - smoothstep(147.0, 192.0, local_s))

func _cross_xy(kind: String, local_s: float, across: float) -> Vector2:
	var envelope := _profile_envelope(local_s)
	if kind in ["CORKSCREW TUNNEL", "HALFPIPE"]:
		var angle := (PI * 0.975 if kind == "CORKSCREW TUNNEL" else PI * 0.48) * envelope
		if angle > 0.0001:
			var radius := HALF_WIDTH / angle
			var theta := across / radius
			return Vector2(radius * sin(theta), radius * (1.0 - cos(theta)))
	if kind == "STACKED ROUTES" and across < 0.0:
		# Upper left deck gradually crosses above the lower right deck.
		return Vector2(across + 60.0 * envelope, 22.0 * envelope)
	return Vector2(across, 0.0)

func _cross_normal(kind: String, local_s: float, across: float) -> Vector2:
	if kind in ["CORKSCREW TUNNEL", "HALFPIPE"]:
		var angle := (PI * 0.975 if kind == "CORKSCREW TUNNEL" else PI * 0.48) * _profile_envelope(local_s)
		var theta := across / HALF_WIDTH * angle
		return Vector2(-sin(theta), cos(theta))
	return Vector2.UP * -1.0

func _cell_supported(kind: String, local_s: float, across: float) -> bool:
	if kind == "SPLIT ROUTE":
		var opening := 12.0 * _profile_envelope(local_s)
		return absf(across) >= opening
	if kind == "GAP CROSSING":
		return not (local_s >= 76.0 and local_s < 96.0 and across > 12.0)
	if kind == "STACKED ROUTES":
		# A centre opening keeps the upper and lower deck physically separate.
		return absf(across) >= 4.0 * _profile_envelope(local_s)
	return true

func _local_s(distance: float) -> float:
	var index := chunk_index_at(distance)
	return (distance - chunk_starts[index]) * CHUNK_LENGTH / (chunk_starts[index + 1] - chunk_starts[index])

func support_at(distance: float, across: float) -> bool:
	if not has_distance(distance) or absf(across) > half_width_at(distance):
		return false
	var kind := section_name(distance)
	if kind not in ["SPLIT ROUTE", "GAP CROSSING", "STACKED ROUTES"]:
		return true
	var local_s := floorf(_local_s(distance)) + 0.5
	# Match the emitted mesh cells (4 m across, 1 normalized metre long).
	var cell := clampf(floorf((across + HALF_WIDTH) / 4.0), 0.0, 29.0) * 4.0 - HALF_WIDTH + 2.0
	return _cell_supported(kind, local_s, cell)

func _profile_vertex(frame: Transform3D, kind: String, local_s: float, lateral: float, lift: float = 0.0) -> Vector3:
	var xy := _cross_xy(kind, local_s, lateral)
	var normal := _cross_normal(kind, local_s, lateral)
	return frame.origin + frame.basis.x * (xy.x + normal.x * lift) + frame.basis.y * (xy.y + normal.y * lift)

func slipstream_center(index: int, local_s: float) -> float:
	return (1.0 if index % 2 == 0 else -1.0) * (24.0 + 12.0 * sin(TAU * local_s / CHUNK_LENGTH))

func slipstream_accel(distance: float, across: float, altitude: float = 0.0, side: int = 1) -> float:
	if side < 0 or section_name(distance) != "SLIPSTREAM" or absf(altitude) > 8.0:
		return 0.0
	var index := chunk_index_at(distance)
	var local_s := _local_s(distance)
	return 14.0 * _profile_envelope(local_s) * (1.0 - smoothstep(7.0, 12.0, absf(across - slipstream_center(index, local_s))))

func _vertex(frame: Transform3D, lateral: float, lift: float = 0.0) -> Vector3:
	return frame.origin + frame.basis.x * lateral + frame.basis.y * lift

func _line(tool: SurfaceTool, a: Vector3, b: Vector3, ca: Color, cb: Color) -> void:
	tool.set_color(ca)
	tool.add_vertex(a)
	tool.set_color(cb)
	tool.add_vertex(b)

func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	tool.set_color(ca)
	tool.add_vertex(a)
	tool.set_color(cb)
	tool.add_vertex(b)
	tool.set_color(cc)
	tool.add_vertex(c)

func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color) -> void:
	# a,b share the first cross-section; c,d share the next.
	_tri(tool, a, c, b, ca, cb, ca)
	_tri(tool, b, c, d, ca, cb, cb)

func _build_mesh(node: Node3D, points: Array[Transform3D], start_s: float, kind: String, index: int, step_length: float) -> void:
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var grid := SurfaceTool.new()
	grid.begin(Mesh.PRIMITIVE_LINES)
	# Shared corners appear in up to four cells and both grid axes.
	# Cache each row once, retaining the exact previous tessellation.
	var top := PackedVector3Array()
	var bottom := PackedVector3Array()
	var grid_top := PackedVector3Array()
	var grid_bottom := PackedVector3Array()
	var stride := CROSS_STEPS + 1
	var vertex_count := (STEPS + 1) * stride
	top.resize(vertex_count)
	bottom.resize(vertex_count)
	grid_top.resize(vertex_count)
	grid_bottom.resize(vertex_count)
	for row in range(STEPS + 1):
		var local_s := float(row)
		var width := width_for_kind(kind, local_s / float(STEPS))
		var frame := points[row]
		for column in range(stride):
			var across := lerpf(-width, width, float(column) / float(CROSS_STEPS))
			var lift := _ramp_lift(index, kind, local_s, across)
			var xy := _cross_xy(kind, local_s, across)
			var normal := _cross_normal(kind, local_s, across)
			var normal3 := frame.basis.x * normal.x + frame.basis.y * normal.y
			var point := frame.origin + frame.basis.x * xy.x + frame.basis.y * xy.y + normal3 * lift
			var vertex := row * stride + column
			top[vertex] = point
			bottom[vertex] = point - normal3 * THICKNESS
			grid_top[vertex] = point + normal3 * 0.075
			grid_bottom[vertex] = point - normal3 * (THICKNESS + 0.075)
	for i in range(STEPS):
		var s0 := start_s + float(i) * step_length
		var s1 := s0 + step_length
		var width0 := width_for_kind(kind, float(i) / float(STEPS))
		var width1 := width_for_kind(kind, float(i + 1) / float(STEPS))
		var dark0 := track_color(s0, 0.0, 0.72, 0.105)
		var dark1 := track_color(s1, 0.0, 0.72, 0.105)
		var underside0 := track_color(s0, 0.02, 0.65, 0.065)
		var underside1 := track_color(s1, 0.02, 0.65, 0.065)
		var line0 := track_color(s0)
		var line1 := track_color(s1)
		var under_line0 := track_color(s0, 0.07)
		var under_line1 := track_color(s1, 0.07)
		var edge_line0 := track_color(s0, 0.19)
		var edge_line1 := track_color(s1, 0.19)
		var cross_line := track_color(s0, 0.0, 0.8, 0.7)
		var under_cross_line := track_color(s0, 0.07, 0.8, 0.7)
		for j in range(CROSS_STEPS):
			var z0 := lerpf(-width0, width0, float(j) / float(CROSS_STEPS))
			var z1 := lerpf(-width0, width0, float(j + 1) / float(CROSS_STEPS))
			var next_z0 := lerpf(-width1, width1, float(j) / float(CROSS_STEPS))
			var next_z1 := lerpf(-width1, width1, float(j + 1) / float(CROSS_STEPS))
			if not _cell_supported(kind, float(i) + 0.5, (z0 + z1) * 0.5):
				continue
			var vertex := i * stride + j
			var next_vertex := vertex + stride
			var a := top[vertex]
			var b := top[vertex + 1]
			var c := top[next_vertex]
			var d := top[next_vertex + 1]
			var recovery0 := _recovery_strength(index, kind, float(i), (z0 + z1) * 0.5)
			var recovery1 := _recovery_strength(index, kind, float(i + 1), (next_z0 + next_z1) * 0.5)
			var shortcut0 := _shortcut_weight(index, kind, float(i), (z0 + z1) * 0.5)
			var shortcut1 := _shortcut_weight(index, kind, float(i + 1), (next_z0 + next_z1) * 0.5)
			var stream0 := 0.0
			var stream1 := 0.0
			if kind == "SLIPSTREAM":
				stream0 = _profile_envelope(float(i)) * (1.0 - smoothstep(7.0, 12.0, absf((z0 + z1) * 0.5 - slipstream_center(index, float(i)))))
				stream1 = _profile_envelope(float(i + 1)) * (1.0 - smoothstep(7.0, 12.0, absf((next_z0 + next_z1) * 0.5 - slipstream_center(index, float(i + 1)))))
			var color0 := dark0.lerp(Color(0.11, 0.36, 0.65), shortcut0 * 0.85).lerp(Color(0.03, 0.58, 0.26), recovery0)
			var color1 := dark1.lerp(Color(0.11, 0.36, 0.65), shortcut1 * 0.85).lerp(Color(0.03, 0.58, 0.26), recovery1)
			_quad(fill, a, b, c, d, color0.lerp(Color(0.65, 0.24, 1.0), stream0), color1.lerp(Color(0.65, 0.24, 1.0), stream1))
			for v: Vector3 in [a, c, b, b, c, d]:
				faces.append(v)
			var ba := bottom[vertex]
			var bb := bottom[vertex + 1]
			var bc := bottom[next_vertex]
			var bd := bottom[next_vertex + 1]
			_quad(fill, bb, ba, bd, bc, underside0, underside1)
			for v: Vector3 in [bb, bd, ba, ba, bd, bc]:
				faces.append(v)
			# Both running-surface grid and collider use the same tessellation.
			if i % 4 == 0:
				_line(grid, grid_top[vertex], grid_top[vertex + 1], cross_line, cross_line)
				_line(grid, grid_bottom[vertex], grid_bottom[vertex + 1], under_cross_line, under_cross_line)
		for j in range(CROSS_STEPS + 1):
			var z := lerpf(-width0, width0, float(j) / float(CROSS_STEPS))
			if not _cell_supported(kind, float(i) + 0.5, z - 2.0) and not _cell_supported(kind, float(i) + 0.5, z + 2.0):
				continue
			var edge := j == 0 or j == CROSS_STEPS
			var vertex := i * stride + j
			_line(grid, grid_top[vertex], grid_top[vertex + stride], edge_line0 if edge else line0, edge_line1 if edge else line1)
			_line(grid, grid_bottom[vertex], grid_bottom[vertex + stride], under_line0, under_line1)
		for side: float in [-1.0, 1.0]:
			_quad(fill, _profile_vertex(points[i], kind, float(i), side * width0), _profile_vertex(points[i], kind, float(i), side * width0, -THICKNESS), _profile_vertex(points[i+1], kind, float(i + 1), side * width1), _profile_vertex(points[i+1], kind, float(i + 1), side * width1, -THICKNESS), track_color(s0, 0.19, 0.8, 0.55), track_color(s1, 0.19, 0.8, 0.55))
	var solid := MeshInstance3D.new()
	solid.mesh = fill.commit()
	solid.material_override = surface_mat
	node.add_child(solid)
	var wire := MeshInstance3D.new()
	wire.mesh = grid.commit()
	wire.material_override = line_mat
	node.add_child(wire)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	collider.shape = shape
	body.add_child(collider)
	node.add_child(body)

func stream(distance: float, planned_speed: float = 22.0) -> void:
	if replay_layout:
		return
	if next_index > 0 and (distance >= chunk_starts[-1] or next_index <= chunk_index_at(distance) + AHEAD):
		_refresh_forecast()
	while next_index == 0 or distance >= chunk_starts[-1]:
		if not _append_stream_chunk(planned_speed):
			return
	var current := chunk_index_at(distance)
	while next_index <= current + AHEAD:
		if not _append_stream_chunk(planned_speed):
			return
	for key in chunks.keys():
		if int(key) < current - BEHIND:
			var node: Node3D = chunks[key]["node"]
			remove_child(node)
			node.queue_free()
			chunks.erase(key)
	# Keep floating-point coordinates small even during very long runs.
	var frame := sample(distance)
	if frame.origin.length() > REBASE_DISTANCE:
		var shift := frame.origin
		for data in chunks.values():
			var node: Node3D = data["node"]
			node.position -= shift
		tail -= shift
		origin_shift += shift

func _append_stream_chunk(planned_speed: float) -> bool:
	# If generation aborts on a runtime error, don't advance the index
	# or spin forever trying to stream a nonexistent section.
	var previous_end := chunk_starts[-1]
	_build_chunk(next_index, planned_speed)
	if chunk_starts.size() != next_index + 2 or chunk_starts[-1] <= previous_end or not chunks.has(next_index):
		push_error("Track generation failed at chunk %d" % next_index)
		return false
	next_index += 1
	return true

func has_distance(distance: float) -> bool:
	return distance < chunk_starts[-1] and chunks.has(chunk_index_at(distance))

func sample(distance: float) -> Transform3D:
	var index := chunk_index_at(distance)
	if not chunks.has(index):
		return Transform3D.IDENTITY
	var data: Dictionary = chunks[index]
	var points: Array[Transform3D] = data["points"]
	var node: Node3D = data["node"]
	var local_distance := distance - chunk_starts[index]
	if local_distance < 0.0:
		var first := points[0]
		first.origin += node.position - first.basis.z * local_distance
		return first
	var unit := clampf(local_distance * float(STEPS) / (chunk_starts[index + 1] - chunk_starts[index]), 0.0, float(STEPS))
	var i := mini(int(floor(unit)), STEPS - 1)
	var frame := points[i].interpolate_with(points[i+1], unit - float(i))
	frame.origin += node.position
	return frame

func project_position(world_pos: Vector3, guess_s: float) -> Vector3:
	# Project onto the nearest cross-section locally. Bounded Newton-like
	# steps avoid snapping to a different branch of a twisted track.
	var s := maxf(0.0, guess_s)
	var min_s := maxf(0.0, guess_s - 64.0)
	var max_s := guess_s + 64.0
	for i in range(6):
		if not has_distance(s):
			break
		var frame := sample(s)
		var along := (world_pos - frame.origin).dot(-frame.basis.z)
		if absf(along) < 0.005:
			break
		s = clampf(s + clampf(along, -18.0, 18.0), min_s, max_s)
	if not has_distance(s):
		s = guess_s
	var local_frame := sample(s)
	var offset := world_pos - local_frame.origin
	var across := offset.dot(local_frame.basis.x)
	var raw_y := offset.dot(local_frame.basis.y)
	var kind := section_name(s)
	if _special_profile(kind):
		var local_s := _local_s(s)
		if kind in ["CORKSCREW TUNNEL", "HALFPIPE"]:
			var angle := (PI * 0.975 if kind == "CORKSCREW TUNNEL" else PI * 0.48) * _profile_envelope(local_s)
			if angle > 0.0001:
				var radius := HALF_WIDTH / angle
				across = atan2(across, radius - raw_y) * radius
		elif kind == "STACKED ROUTES":
			var envelope := _profile_envelope(local_s)
			var lower := clampf(across, 0.001, HALF_WIDTH)
			var upper := clampf(across - 60.0 * envelope, -HALF_WIDTH, -0.001)
			var upper_xy := _cross_xy(kind, local_s, upper)
			var lower_xy := _cross_xy(kind, local_s, lower)
			var query := Vector2(across, raw_y)
			if query.distance_squared_to(upper_xy) < query.distance_squared_to(lower_xy):
				across -= 60.0 * envelope
			# Retain out-of-bounds lanes for edge detection.
		var xy := _cross_xy(kind, local_s, across)
		var n := _cross_normal(kind, local_s, across)
		raw_y = (Vector2(offset.dot(local_frame.basis.x), raw_y) - xy).dot(n)
	return Vector3(s, across, raw_y)

func section_name(distance: float) -> String:
	var index := chunk_index_at(distance)
	if not chunks.has(index):
		return "TRACK"
	return str(chunks[index]["kind"])

func swept_obstacles(from_s: float, to_s: float, from_lane: float, to_lane: float, from_height: float, to_height: float, player_height: float = 1.7) -> int:
	var count := 0
	if to_s <= from_s:
		return count
	for index in range(chunk_index_at(from_s - 4.0), chunk_index_at(to_s + 4.0) + 1):
		if not chunks.has(index):
			continue
		var hazards: Array[Dictionary] = chunks[index]["hazards"]
		for hazard in hazards:
			var group: Dictionary = hazard["group"]
			if bool(group["used"]):
				continue
			var hs: float = hazard["s"]
			var depth: float = hazard["depth"]
			if to_s < hs - depth * 0.5 - 0.5 or from_s > hs + depth * 0.5 + 0.5:
				continue
			var t := clampf((hs - from_s) / (to_s - from_s), 0.0, 1.0)
			var lane := lerpf(from_lane, to_lane, t)
			var feet := lerpf(from_height, to_height, t)
			var bottom: float = hazard["bottom"]
			var h: float = hazard["height"]
			if feet >= bottom + h or feet + player_height <= bottom:
				continue
			var radius: float = float(hazard["width"]) * 0.5
			var profile: String = hazard["profile"]
			if profile == "CONE":
				radius *= 1.0 - clampf((feet - bottom) / h, 0.0, 1.0)
			elif profile == "INVERSE_CONE":
				radius *= clampf((feet + player_height - bottom) / h, 0.0, 1.0)
			elif profile == "SPHERE":
				var center_y := bottom + h * 0.5
				var closest_y := clampf(center_y, feet, feet + player_height)
				radius *= sqrt(maxf(0.0, 1.0 - pow((closest_y - center_y) / (h * 0.5), 2.0)))
			if absf(lane - float(hazard["lane"])) <= radius + 0.55:
				group["used"] = true
				count += 1
	return count

func collect_clean_gates(from_s: float, to_s: float, from_lane: float, to_lane: float, from_height: float, to_height: float) -> int:
	var count := 0
	if to_s <= from_s:
		return 0
	for index in range(chunk_index_at(from_s), chunk_index_at(to_s) + 1):
		if not chunks.has(index):
			continue
		for hazard in chunks[index]["hazards"]:
			var group: Dictionary = hazard["group"]
			var at: float = hazard["s"]
			if not bool(group.get("gate", false)) or bool(group.get("rewarded", false)) or at <= from_s or at > to_s:
				continue
			group["rewarded"] = true
			var fraction := (at - from_s) / (to_s - from_s)
			var across := lerpf(from_lane, to_lane, fraction)
			var feet := lerpf(from_height, to_height, fraction)
			if not bool(group["used"]) and feet >= -0.1 and feet < 40.0 and absf(across - float(group["opening"])) < float(group["gap_width"]) * 0.5 - 0.8:
				count += 1
	return count

func begin_replay_layout(recipes: Array) -> void:
	for data in chunks.values():
		var node: Node3D = data["node"]
		remove_child(node)
		node.queue_free()
	chunks.clear()
	replay_layout = true
	replay_recipes.assign(recipes)
	chunk_starts.assign([0.0])
	for recipe in replay_recipes:
		chunk_starts.append(float(recipe["start"]) + float(recipe["length"]))
	next_index = replay_recipes.size()
	origin_shift = Vector3.ZERO

func replay_stream(distance: float, shift: Vector3) -> void:
	if not replay_layout or replay_recipes.is_empty():
		return
	var current := chunk_index_at(distance)
	var first := maxi(0, current - BEHIND)
	var last := mini(next_index - 1, current + AHEAD)
	var adjustment := shift - origin_shift
	for key in chunks.keys():
		var node: Node3D = chunks[key]["node"]
		if int(key) < first or int(key) > last:
			remove_child(node)
			node.queue_free()
			chunks.erase(key)
		else:
			node.position -= adjustment
	origin_shift = shift
	for index in range(first, last + 1):
		if chunks.has(index):
			continue
		var recipe: Dictionary = replay_recipes[index]
		var points: Array[Transform3D] = []
		points.assign(recipe["points"])
		var layout: Array[Dictionary] = []
		layout.assign(recipe["layout"])
		var absolute_origin: Vector3 = recipe["origin"]
		_instantiate_chunk(index, str(recipe["kind"]), points, float(recipe["start"]), float(recipe["length"]) / float(STEPS), absolute_origin - origin_shift, layout)

func distance_to_rideable_surface(world_pos: Vector3, projected: Vector3) -> float:
	# For curled cross-sections the centerline is not the road. Measure to
	# both actual faces, including the nearest edge at the tunnel's slit.
	var at := projected.x
	var edge := half_width_at(at)
	var across := clampf(projected.y, -edge, edge)
	var nearest := INF
	for test_lane: float in [across, -edge, edge]:
		if not support_at(at, test_lane):
			continue
		for side: int in [1, -1]:
			var face := surface_frame(at, test_lane, side)
			nearest = minf(nearest, world_pos.distance_to(face.origin))
	return nearest

func is_curved_enclosure(distance: float) -> bool:
	var kind := section_name(distance)
	return kind == "CORKSCREW TUNNEL" or kind == "HALFPIPE" or kind == "STACKED ROUTES"
