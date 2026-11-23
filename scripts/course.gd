extends Node3D
## Endless ribbon generator. Progress is arc length, not world X.
## Each chunk owns its mesh, collision surface and obstacles.

const CHUNK_LENGTH := 192.0
const STEP := 1.0
const STEPS := 192
const HALF_WIDTH := 22.0
const CROSS_STEPS := 12
const THICKNESS := 0.45
const COLOR_CYCLE := 12000.0
const AHEAD := 5
const BEHIND := 2
const REBASE_DISTANCE := 2048.0

var chunks: Dictionary = {}
var next_index := 0
var tail := Vector3.ZERO
var yaw := 0.0
var rng := RandomNumberGenerator.new()
var surface_mat: StandardMaterial3D
var line_mat: StandardMaterial3D
var origin_shift := Vector3.ZERO

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
	tail = Vector3.ZERO
	yaw = 0.0
	origin_shift = Vector3.ZERO
	rng.seed = seed_value
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
	var kinds: Array[String] = ["HILLS", "TURN", "BANKED TURN", "HILLS", "180 BANK", "360 BANK", "BANKED TURN"]
	return kinds[rng.randi_range(0, kinds.size() - 1)]

func _orientation(kind: String, u: float, start_yaw: float, target_yaw: float, bank_sign: float = 1.0) -> Basis:
	var angle := lerpf(start_yaw, target_yaw, smoothstep(0.0, 1.0, u))
	var pitch := 0.0
	var roll := 0.0
	if kind == "HILLS":
		pitch = -0.32 * sin(TAU * u) - 0.15 * sin(PI * u)
	elif kind == "BANKED TURN":
		roll = signf(target_yaw - start_yaw) * 0.78 * sin(PI * u)
	elif kind == "TURN":
		roll = signf(target_yaw - start_yaw) * 0.22 * sin(PI * u)
	elif kind == "180 BANK":
		# A smooth half-roll to an inverted stretch, then unwind.
		# Entry and exit are both upright so neighboring chunks join cleanly.
		roll = bank_sign * PI * smoothstep(0.0, 0.36, u) * (1.0 - smoothstep(0.64, 1.0, u))
	elif kind == "360 BANK":
		# Continuous barrel roll with zero roll rate at both seams.
		roll = bank_sign * TAU * smoothstep(0.0, 1.0, u)
	var heading := Vector3(cos(angle), 0, sin(angle))
	var side := Vector3(-sin(angle), 0, cos(angle))
	var forward := heading * cos(pitch) + Vector3.UP * sin(pitch)
	forward = forward.normalized()
	var right := (side - forward * side.dot(forward)).normalized().rotated(forward, roll)
	var up := right.cross(forward).normalized()
	return Basis(right, up, -forward).orthonormalized()

func _build_chunk(index: int) -> void:
	var kind := _kind(index)
	var start_yaw := yaw
	var target_yaw := yaw
	var bank_sign := -1.0 if rng.randf() < 0.5 else 1.0
	if kind == "TURN" or kind == "BANKED TURN":
		var direction := -1.0 if yaw > 0.35 else (1.0 if yaw < -0.35 else (-1.0 if rng.randf() < 0.5 else 1.0))
		target_yaw = clampf(yaw + direction * rng.randf_range(0.75, 1.35), -1.25, 1.25)
	var node := Node3D.new()
	node.name = "Track_%d" % index
	node.position = tail
	add_child(node)
	var points: Array[Transform3D] = []
	var p := Vector3.ZERO
	for i in range(STEPS + 1):
		var u := float(i) / float(STEPS)
		var basis := _orientation(kind, u, start_yaw, target_yaw, bank_sign)
		points.append(Transform3D(basis, p))
		if i < STEPS:
			var mid := _orientation(kind, (float(i) + 0.5) / float(STEPS), start_yaw, target_yaw, bank_sign)
			p += -mid.z * STEP
	tail += p
	yaw = target_yaw
	var hazards: Array[Dictionary] = []
	_build_mesh(node, points, float(index) * CHUNK_LENGTH)
	# Leave space before the first obstacle and between hazards.
	var positions: Array[float] = [35.0, 72.0, 108.0, 144.0, 174.0]
	if index == 0:
		positions = [82.0, 137.0]
	elif index >= 2 and kind != "180 BANK" and kind != "360 BANK":
		positions = [18.0, 40.0, 140.0, 161.0, 180.0]
	elif kind == "180 BANK" or kind == "360 BANK":
		positions = [30.0, 160.0]
	for i in range(positions.size()):
		var at: float = positions[i]
		var lane := float(rng.randi_range(-5, 5)) * 3.2
		# Keep the approach and immediate exit from route gates navigable.
		if index >= 2 and kind != "180 BANK" and kind != "360 BANK" and at >= 130.0 and at <= 150.0:
			lane = 10.0 if index % 2 == 0 else -10.0
		var shape_id := (index * 5 + i) % 10
		if index > 5:
			shape_id = rng.randi_range(0, 9)
		if index == 0 and i == 0:
			shape_id = 0
		var frame := points[int(at / STEP)].interpolate_with(points[int(at / STEP) + 1], fmod(at, STEP) / STEP)
		_spawn_obstacle(node, hazards, frame, float(index) * CHUNK_LENGTH + at, lane, shape_id)
	# Route gates have a guaranteed opening, but it moves across the track.
	# Wide tall walls discourage jumping over every obstacle instead of steering.
	if index >= 2 and kind != "180 BANK" and kind != "360 BANK":
		var gate_at := 94.0
		var gate_frame := points[int(gate_at / STEP)]
		var opening := -10.0 if index % 2 == 0 else 10.0
		var gap_width := maxf(9.0, 13.0 - float(index) * 0.12)
		_spawn_route_gate(node, hazards, gate_frame, float(index) * CHUNK_LENGTH + gate_at, opening, gap_width)
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

func lane_limit() -> float:
	return HALF_WIDTH - 0.75

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

func _build_mesh(node: Node3D, points: Array[Transform3D], start_s: float) -> void:
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var grid := SurfaceTool.new()
	grid.begin(Mesh.PRIMITIVE_LINES)
	for i in range(STEPS):
		var s0 := start_s + float(i) * STEP
		var s1 := s0 + STEP
		var dark0 := track_color(s0, 0.0, 0.72, 0.105)
		var dark1 := track_color(s1, 0.0, 0.72, 0.105)
		var underside0 := track_color(s0, 0.02, 0.65, 0.065)
		var underside1 := track_color(s1, 0.02, 0.65, 0.065)
		for j in range(CROSS_STEPS):
			var z0 := lerpf(-HALF_WIDTH, HALF_WIDTH, float(j) / float(CROSS_STEPS))
			var z1 := lerpf(-HALF_WIDTH, HALF_WIDTH, float(j + 1) / float(CROSS_STEPS))
			var a := _vertex(points[i], z0)
			var b := _vertex(points[i], z1)
			var c := _vertex(points[i+1], z0)
			var d := _vertex(points[i+1], z1)
			_quad(fill, a, b, c, d, dark0, dark1)
			for v: Vector3 in [a, c, b, b, c, d]:
				faces.append(v)
			var ba := _vertex(points[i], z0, -THICKNESS)
			var bb := _vertex(points[i], z1, -THICKNESS)
			var bc := _vertex(points[i+1], z0, -THICKNESS)
			var bd := _vertex(points[i+1], z1, -THICKNESS)
			_quad(fill, bb, ba, bd, bc, underside0, underside1)
			# Both running-surface grid and collider use the same tessellation.
			if i % 4 == 0:
				_line(grid, _vertex(points[i], z0, 0.075), _vertex(points[i], z1, 0.075), track_color(s0, 0.0, 0.8, 0.7), track_color(s0, 0.0, 0.8, 0.7))
		for j in range(CROSS_STEPS + 1):
			var z := lerpf(-HALF_WIDTH, HALF_WIDTH, float(j) / float(CROSS_STEPS))
			var edge := j == 0 or j == CROSS_STEPS
			var ca := track_color(s0, 0.19 if edge else 0.0)
			var cb := track_color(s1, 0.19 if edge else 0.0)
			_line(grid, _vertex(points[i], z, 0.075), _vertex(points[i+1], z, 0.075), ca, cb)
		for side: float in [-HALF_WIDTH, HALF_WIDTH]:
			_quad(fill, _vertex(points[i], side), _vertex(points[i], side, -THICKNESS), _vertex(points[i+1], side), _vertex(points[i+1], side, -THICKNESS), track_color(s0, 0.19, 0.8, 0.55), track_color(s1, 0.19, 0.8, 0.55))
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

func stream(distance: float) -> void:
	var current := maxi(0, int(floor(distance / CHUNK_LENGTH)))
	while next_index <= current + AHEAD:
		_build_chunk(next_index)
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
	return chunks.has(maxi(0, int(floor(distance / CHUNK_LENGTH))))

func sample(distance: float) -> Transform3D:
	var index := maxi(0, int(floor(distance / CHUNK_LENGTH)))
	if not chunks.has(index):
		return Transform3D.IDENTITY
	var data: Dictionary = chunks[index]
	var points: Array[Transform3D] = data["points"]
	var node: Node3D = data["node"]
	var local_distance := distance - float(index) * CHUNK_LENGTH
	if local_distance < 0.0:
		var first := points[0]
		first.origin += node.position - first.basis.z * local_distance
		return first
	var unit := clampf(local_distance / STEP, 0.0, float(STEPS))
	var i := mini(int(floor(unit)), STEPS - 1)
	var frame := points[i].interpolate_with(points[i+1], unit - float(i))
	frame.origin += node.position
	return frame

func section_name(distance: float) -> String:
	var index := maxi(0, int(floor(distance / CHUNK_LENGTH)))
	if not chunks.has(index):
		return "TRACK"
	return str(chunks[index]["kind"])

func swept_obstacles(from_s: float, to_s: float, from_lane: float, to_lane: float, from_height: float, to_height: float, player_height: float = 1.7) -> int:
	var count := 0
	if to_s <= from_s:
		return count
	for index in range(maxi(0, int(floor((from_s - 4.0) / CHUNK_LENGTH))), int(floor((to_s + 4.0) / CHUNK_LENGTH)) + 1):
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
