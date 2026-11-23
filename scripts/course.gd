extends Node3D
## Endless ribbon generator. Progress is arc length, not world X.
## Each chunk owns its mesh, collision surface and obstacles.

const CHUNK_LENGTH := 192.0
const STEP := 2.0
const STEPS := 96
const HALF_WIDTH := 9.0
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
var hazard_mat: StandardMaterial3D
var stripe_mat: StandardMaterial3D
var origin_shift := Vector3.ZERO

func _ready() -> void:
	surface_mat = _material(Color(0.012, 0.018, 0.062))
	line_mat = _material(Color.WHITE)
	line_mat.vertex_color_use_as_albedo = true
	hazard_mat = _material(Color(1.0, 0.12, 0.36))
	stripe_mat = _material(Color(1.0, 0.77, 0.22))
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
		return "INVERSION"
	if index == 3:
		return "TURN"
	var choice: int = rng.randi_range(0, 4)
	var kinds: Array[String] = ["HILLS", "TURN", "BANKED TURN", "INVERSION", "HILLS"]
	return kinds[choice]

func _orientation(kind: String, u: float, start_yaw: float, target_yaw: float) -> Basis:
	var angle := lerpf(start_yaw, target_yaw, smoothstep(0.0, 1.0, u))
	var pitch := 0.0
	var roll := 0.0
	if kind == "HILLS":
		pitch = -0.32 * sin(TAU * u) - 0.15 * sin(PI * u)
	elif kind == "BANKED TURN":
		roll = signf(target_yaw - start_yaw) * 0.78 * sin(PI * u)
	elif kind == "TURN":
		roll = signf(target_yaw - start_yaw) * 0.22 * sin(PI * u)
	elif kind == "INVERSION":
		pitch = TAU * u
	var heading := Vector3(cos(angle), 0, sin(angle))
	var side := Vector3(-sin(angle), 0, cos(angle))
	var forward := heading * cos(pitch) + Vector3.UP * sin(pitch)
	if kind == "INVERSION":
		# Offset the loop sideways so its exit does not overlap the entrance.
		forward += side * (0.34 * sin(PI * u) * sin(PI * u))
	forward = forward.normalized()
	var right := (side - forward * side.dot(forward)).normalized().rotated(forward, roll)
	var up := right.cross(forward).normalized()
	return Basis(right, up, -forward).orthonormalized()

func _build_chunk(index: int) -> void:
	var kind := _kind(index)
	var start_yaw := yaw
	var target_yaw := yaw
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
		var basis := _orientation(kind, u, start_yaw, target_yaw)
		points.append(Transform3D(basis, p))
		if i < STEPS:
			var mid := _orientation(kind, (float(i) + 0.5) / float(STEPS), start_yaw, target_yaw)
			p += -mid.z * STEP
	tail += p
	yaw = target_yaw
	var hazards: Array[Dictionary] = []
	_build_mesh(node, points)
	# Leave space before the first obstacle and between hazards.
	var positions: Array[float] = [60.0, 115.0, 157.0]
	if index == 0:
		positions = [82.0, 137.0]
	for i in range(positions.size()):
		var at := positions[i]
		var lane := float(rng.randi_range(-2, 2)) * 3.0
		var width := 2.7 if i % 2 == 0 else 4.2
		var height := 3.0 if i % 2 == 0 else 1.1
		var hazard := {"s": float(index) * CHUNK_LENGTH + at, "lane": lane, "width": width, "height": height, "used": false}
		hazards.append(hazard)
		var frame: Transform3D = points[int(at / STEP)]
		# Use the exact interpolated frame for the rendered obstacle.
		frame = frame.interpolate_with(points[int(at / STEP) + 1], fmod(at, STEP) / STEP)
		var center := frame.origin + frame.basis.x * lane + frame.basis.y * (height * 0.5)
		_add_box(node, Transform3D(frame.basis, center), Vector3(width, height, 2.4), hazard_mat)
		_add_box(node, Transform3D(frame.basis, center + frame.basis.y * (height * 0.5)), Vector3(width + 0.12, 0.13, 2.5), stripe_mat)
	chunks[index] = {"node": node, "points": points, "kind": kind, "hazards": hazards}

func _add_box(parent: Node3D, frame: Transform3D, size: Vector3, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = mat
	mesh.transform = frame
	parent.add_child(mesh)

func _vertex(frame: Transform3D, lateral: float, lift: float = 0.0) -> Vector3:
	return frame.origin + frame.basis.x * lateral + frame.basis.y * lift

func _line(tool: SurfaceTool, a: Vector3, b: Vector3, color: Color) -> void:
	tool.set_color(color)
	tool.add_vertex(a)
	tool.set_color(color)
	tool.add_vertex(b)

func _build_mesh(node: Node3D, points: Array[Transform3D]) -> void:
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var grid := SurfaceTool.new()
	grid.begin(Mesh.PRIMITIVE_LINES)
	var blue := Color(0.08, 0.65, 0.94)
	var pink := Color(0.99, 0.12, 0.59)
	for i in range(STEPS):
		var a := _vertex(points[i], -HALF_WIDTH)
		var b := _vertex(points[i], HALF_WIDTH)
		var c := _vertex(points[i+1], -HALF_WIDTH)
		var d := _vertex(points[i+1], HALF_WIDTH)
		for v: Vector3 in [a, c, b, b, c, d]:
			fill.add_vertex(v)
			faces.append(v)
		for lane in range(7):
			var z := -HALF_WIDTH + float(lane) * HALF_WIDTH / 3.0
			_line(grid, _vertex(points[i], z, 0.035), _vertex(points[i+1], z, 0.035), pink if lane == 0 or lane == 6 else blue)
		if i % 2 == 0:
			_line(grid, _vertex(points[i], -HALF_WIDTH, 0.04), _vertex(points[i], HALF_WIDTH, 0.04), pink if i % 12 == 0 else blue)
	var solid := MeshInstance3D.new()
	solid.mesh = fill.commit()
	solid.material_override = surface_mat
	node.add_child(solid)
	var wire := MeshInstance3D.new()
	wire.mesh = grid.commit()
	wire.material_override = line_mat
	node.add_child(wire)
	# Collider exists for world queries and tools. The arcade runner follows
	# the same ribbon parametrically, so inversion contact is deterministic.
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

func swept_obstacles(from_s: float, to_s: float, from_lane: float, to_lane: float, from_height: float, to_height: float) -> int:
	var count := 0
	if to_s <= from_s:
		return count
	for index in range(maxi(0, int(floor((from_s - 2.0) / CHUNK_LENGTH))), int(floor((to_s + 2.0) / CHUNK_LENGTH)) + 1):
		if not chunks.has(index):
			continue
		var hazards: Array[Dictionary] = chunks[index]["hazards"]
		for hazard in hazards:
			if bool(hazard["used"]):
				continue
			var hs: float = hazard["s"]
			if to_s < hs - 1.7 or from_s > hs + 1.7:
				continue
			var t := clampf((hs - from_s) / (to_s - from_s), 0.0, 1.0)
			var lane := lerpf(from_lane, to_lane, t)
			var height := lerpf(from_height, to_height, t)
			if absf(lane - float(hazard["lane"])) <= float(hazard["width"]) * 0.5 + 0.55 and height < float(hazard["height"]):
				hazard["used"] = true
				count += 1
	return count
