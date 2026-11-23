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
	next_index = 0
	chunk_starts.assign([0.0])
	tail = Vector3.ZERO
	yaw = 0.0
	origin_shift = Vector3.ZERO
	rng.seed = seed_value
	terrain_bag.clear()
	last_kind = ""
	sustained_roll_queue.clear()
	sustained_roll_sign = 1.0
	stream(0.0)

func _kind(index: int) -> String:
	# Opening sequence introduces each mechanic; thereafter seeded variety.
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
	if terrain_bag.is_empty():
		terrain_bag.assign(["HILLS", "TURN", "BANKED TURN", "LONG DESCENT", "S CURVE", "NARROW BRIDGE", "ROLLING RIDGES", "CAMBER WAVE", "STEEP CLIMB", "DROP AND RECOVERY", "BANKED DESCENT", "WIDE BASIN", "CHICANE", "180 BANK", "360 BANK", "WALL ENTRY", "CEILING ENTRY"])
	var choice := rng.randi_range(0, terrain_bag.size() - 1)
	if terrain_bag.size() > 1 and terrain_bag[choice] == last_kind:
		choice = (choice + 1) % terrain_bag.size()
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
	return kind == "180 BANK" or kind == "360 BANK" or is_sustained_roll(kind)

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
	if is_extreme_bank(kind) or kind in ["BANKED TURN", "TURN", "BANKED DESCENT", "S CURVE", "CHICANE", "CAMBER WAVE"]:
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
	var kind := _kind(index)
	last_kind = kind
	var start_s := chunk_starts[index]
	var length := bank_length(kind, planned_speed)
	# Keep a constant number of cross-sections; long banks have lower
	# curvature so this retains the same angular tessellation resolution.
	var step_length := length / float(STEPS)
	chunk_starts.append(start_s + length)
	var strength := 1.0 if index < 6 else rng.randf_range(0.78, 1.16)
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
	var node := Node3D.new()
	node.name = "Track_%d" % index
	node.position = tail
	add_child(node)
	var points: Array[Transform3D] = []
	var p := Vector3.ZERO
	for i in range(STEPS + 1):
		var u := float(i) / float(STEPS)
		var basis := _orientation(kind, u, start_yaw, target_yaw, bank_sign, strength)
		points.append(Transform3D(basis, p))
		if i < STEPS:
			var mid := _orientation(kind, (float(i) + 0.5) / float(STEPS), start_yaw, target_yaw, bank_sign, strength)
			p += -mid.z * step_length
	tail += p
	yaw = target_yaw
	var hazards: Array[Dictionary] = []
	_build_mesh(node, points, start_s, kind, index, step_length)
	# Leave room to experience the geometry itself, without filling every
	# new terrain feature with barriers.
	var positions: Array[float] = [35.0, 72.0, 108.0, 144.0, 174.0]
	if index == 0:
		positions = [82.0, 137.0]
	elif is_sustained_roll(kind) or kind == "NARROW BRIDGE" or kind == "ROLLING RIDGES" or kind == "DROP AND RECOVERY" or kind == "CHICANE":
		positions.clear()
	elif index >= 2 and kind != "180 BANK" and kind != "360 BANK":
		# Conditional array literals are untyped Variants in GDScript.
		# Explicit assignment converts the contents to Array[float].
		if index < 6:
			positions.assign([18.0, 40.0, 140.0, 161.0, 180.0])
		else:
			positions.assign([32.0, 156.0])
	elif kind == "180 BANK" or kind == "360 BANK":
		positions = [30.0, 160.0]
	for i in range(positions.size()):
		var at: float = positions[i]
		var lane := float(rng.randi_range(-8, 8)) * 4.8
		if _ramp_lift(index, kind, at, lane) > 0.02:
			lane = -ramp_center(index)
		# Keep the approach and immediate exit from route gates navigable.
		if index >= 2 and kind != "180 BANK" and kind != "360 BANK" and at >= 130.0 and at <= 150.0:
			lane = 14.0 if index % 2 == 0 else -14.0
		var lane_bound := width_for_kind(kind, at / CHUNK_LENGTH) - 6.0
		lane = clampf(lane, -lane_bound, lane_bound)
		var shape_id := (index * 5 + i) % 10
		if index > 5:
			shape_id = rng.randi_range(0, 9)
		if index == 0 and i == 0:
			shape_id = 0
		var frame := points[int(at / STEP)].interpolate_with(points[int(at / STEP) + 1], fmod(at, STEP) / STEP)
		frame.origin += frame.basis.y * _ramp_lift(index, kind, at, lane)
		_spawn_obstacle(node, hazards, frame, start_s + at * step_length, lane, shape_id)
	# Route gates have a guaranteed opening, but it moves across the track.
	# Wide tall walls discourage jumping over every obstacle instead of steering.
	if index >= 2 and not is_extreme_bank(kind) and (index < 6 or (kind == "HILLS" or kind == "TURN") and index % 3 == 0):
		var gate_at := 94.0
		var gate_frame := points[int(gate_at / STEP)]
		var opening := -14.0 if index % 2 == 0 else 14.0
		var gap_width := maxf(18.0, 24.0 - float(index) * 0.12)
		_spawn_route_gate(node, hazards, gate_frame, start_s + gate_at * step_length, opening, gap_width)
	chunks[index] = {"node": node, "points": points, "kind": kind, "hazards": hazards}

func track_color(distance: float, accent: float = 0.0, saturation: float = 0.84, value: float = 0.95) -> Color:
	# Absolute arc-length color: stable across chunk seams and origin rebases.
	return Color.from_hsv(fposmod(0.54 + distance / COLOR_CYCLE + accent, 1.0), saturation, value)

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
	var group := {"used": false, "shape": 10, "gate": true, "opening": opening, "gap_width": gap_width}
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

func _ramp_lift(index: int, kind: String, local_s: float, across: float) -> float:
	# A local rise, crest and runout occupying only a portion of the road.
	# The other lanes remain unchanged; no ramp on narrow or inverted banks.
	if index == 0 or (index != 1 and index % 3 != 0) or kind == "NARROW BRIDGE" or is_extreme_bank(kind):
		return 0.0
	var lateral := 1.0 - smoothstep(5.0, 12.0, absf(across - ramp_center(index)))
	var rise := smoothstep(58.0, 99.0, local_s)
	var runout := 1.0 - smoothstep(99.0, 132.0, local_s)
	return (5.0 + float(index % 3)) * lateral * rise * runout

func surface_lift(distance: float, across: float) -> float:
	var index := chunk_index_at(distance)
	if not chunks.has(index):
		return 0.0
	var local_s := (distance - chunk_starts[index]) * CHUNK_LENGTH / (chunk_starts[index + 1] - chunk_starts[index])
	return _ramp_lift(index, section_name(distance), local_s, across)

func surface_frame(distance: float, across: float, side: int = 1) -> Transform3D:
	var frame := sample(distance)
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
	var lift := surface_lift(distance, across)
	return raw_height - lift if side > 0 else lift - THICKNESS - raw_height

func lane_limit(distance: float = -1.0) -> float:
	return (HALF_WIDTH if distance < 0.0 else half_width_at(distance)) - 0.75

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
	for i in range(STEPS):
		var s0 := start_s + float(i) * step_length
		var s1 := s0 + step_length
		var width0 := width_for_kind(kind, float(i) / float(STEPS))
		var width1 := width_for_kind(kind, float(i + 1) / float(STEPS))
		var dark0 := track_color(s0, 0.0, 0.72, 0.105)
		var dark1 := track_color(s1, 0.0, 0.72, 0.105)
		var underside0 := track_color(s0, 0.02, 0.65, 0.065)
		var underside1 := track_color(s1, 0.02, 0.65, 0.065)
		for j in range(CROSS_STEPS):
			var z0 := lerpf(-width0, width0, float(j) / float(CROSS_STEPS))
			var z1 := lerpf(-width0, width0, float(j + 1) / float(CROSS_STEPS))
			var next_z0 := lerpf(-width1, width1, float(j) / float(CROSS_STEPS))
			var next_z1 := lerpf(-width1, width1, float(j + 1) / float(CROSS_STEPS))
			var h0 := _ramp_lift(index, kind, float(i) * STEP, z0)
			var h1 := _ramp_lift(index, kind, float(i) * STEP, z1)
			var h2 := _ramp_lift(index, kind, float(i + 1) * STEP, next_z0)
			var h3 := _ramp_lift(index, kind, float(i + 1) * STEP, next_z1)
			var a := _vertex(points[i], z0, h0)
			var b := _vertex(points[i], z1, h1)
			var c := _vertex(points[i+1], next_z0, h2)
			var d := _vertex(points[i+1], next_z1, h3)
			_quad(fill, a, b, c, d, dark0, dark1)
			for v: Vector3 in [a, c, b, b, c, d]:
				faces.append(v)
			var ba := _vertex(points[i], z0, h0 - THICKNESS)
			var bb := _vertex(points[i], z1, h1 - THICKNESS)
			var bc := _vertex(points[i+1], next_z0, h2 - THICKNESS)
			var bd := _vertex(points[i+1], next_z1, h3 - THICKNESS)
			_quad(fill, bb, ba, bd, bc, underside0, underside1)
			for v: Vector3 in [bb, bd, ba, ba, bd, bc]:
				faces.append(v)
			# Both running-surface grid and collider use the same tessellation.
			if i % 4 == 0:
				_line(grid, _vertex(points[i], z0, h0 + 0.075), _vertex(points[i], z1, h1 + 0.075), track_color(s0, 0.0, 0.8, 0.7), track_color(s0, 0.0, 0.8, 0.7))
				_line(grid, _vertex(points[i], z0, h0 - THICKNESS - 0.075), _vertex(points[i], z1, h1 - THICKNESS - 0.075), track_color(s0, 0.07, 0.8, 0.7), track_color(s0, 0.07, 0.8, 0.7))
		for j in range(CROSS_STEPS + 1):
			var z := lerpf(-width0, width0, float(j) / float(CROSS_STEPS))
			var next_z := lerpf(-width1, width1, float(j) / float(CROSS_STEPS))
			var edge := j == 0 or j == CROSS_STEPS
			var ca := track_color(s0, 0.19 if edge else 0.0)
			var cb := track_color(s1, 0.19 if edge else 0.0)
			var lift0 := _ramp_lift(index, kind, float(i) * STEP, z)
			var lift1 := _ramp_lift(index, kind, float(i + 1) * STEP, next_z)
			_line(grid, _vertex(points[i], z, lift0 + 0.075), _vertex(points[i+1], next_z, lift1 + 0.075), ca, cb)
			_line(grid, _vertex(points[i], z, lift0 - THICKNESS - 0.075), _vertex(points[i+1], next_z, lift1 - THICKNESS - 0.075), track_color(s0, 0.07), track_color(s1, 0.07))
		for side: float in [-1.0, 1.0]:
			_quad(fill, _vertex(points[i], side * width0), _vertex(points[i], side * width0, -THICKNESS), _vertex(points[i+1], side * width1), _vertex(points[i+1], side * width1, -THICKNESS), track_color(s0, 0.19, 0.8, 0.55), track_color(s1, 0.19, 0.8, 0.55))
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
	while next_index == 0 or distance >= chunk_starts[-1]:
		_build_chunk(next_index, planned_speed)
		next_index += 1
	var current := chunk_index_at(distance)
	while next_index <= current + AHEAD:
		_build_chunk(next_index, planned_speed)
		next_index += 1
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
	return Vector3(s, offset.dot(local_frame.basis.x), offset.dot(local_frame.basis.y))

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
