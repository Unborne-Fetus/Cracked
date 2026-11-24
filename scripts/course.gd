extends Node3D
## Wide, continuous heightfield. Rendering and movement share the same function.
const CHUNK := 160.0
const HALF_WIDTH := 110.0
const CELL := 4.0
var phase := 0.0
var stage := 1
var length := 2400.0
var chunks: Dictionary = {}
var ground_material: StandardMaterial3D
var rock_material: StandardMaterial3D
var rock_mesh: SphereMesh

func _ready() -> void:
	ground_material = StandardMaterial3D.new()
	ground_material.vertex_color_use_as_albedo = true
	ground_material.roughness = 1.0
	ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rock_material = StandardMaterial3D.new()
	rock_material.albedo_color = Color(0.30, 0.23, 0.33)
	rock_material.roughness = 1.0
	rock_mesh = SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 4

func reset(seed_value: int, stage_value: int) -> void:
	for data in chunks.values():
		var node: Node3D = data["node"]
		remove_child(node)
		node.queue_free()
	chunks.clear()
	stage = stage_value
	length = 2400.0 + float(mini(stage - 1, 6)) * 300.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	phase = rng.randf_range(0.0, TAU)
	stream(0.0)

func elevation(x: float, s: float) -> float:
	# First hill is consistent: accelerating approach, valley, then crest.
	# Seeded variation blends in smoothly beyond the opening.
	var blend := smoothstep(80.0, 240.0, s)
	var local_phase := phase * blend
	var a := 15.0 * cos(s * 0.038 + local_phase)
	var b := 5.0 * sin(s * 0.069 + local_phase * 0.61)
	var c := 8.5 * sin(s * 0.018 + x * 0.042 + local_phase)
	var d := 4.0 * cos(x * 0.072 - s * 0.012)
	var hill_scale := 1.0 + minf(float(stage - 1) * 0.045, 0.30)
	return -s * 0.09 + (a + b + c + d) * hill_scale

func grade(x: float, s: float) -> Vector2:
	var e := 0.25
	return Vector2((elevation(x + e, s) - elevation(x - e, s)) / (2.0 * e), (elevation(x, s + e) - elevation(x, s - e)) / (2.0 * e))

func normal_at(x: float, s: float) -> Vector3:
	var g := grade(x, s)
	return Vector3(-g.x, 1.0, g.y).normalized()

func curvature(x: float, s: float) -> float:
	var e := 1.0
	return (elevation(x, s + e) - 2.0 * elevation(x, s) + elevation(x, s - e)) / (e * e)

func _color(x: float, s: float) -> Color:
	var palettes: Array[Color] = [Color(0.20, 0.56, 0.50), Color(0.68, 0.36, 0.35), Color(0.30, 0.44, 0.72)]
	var base := palettes[(stage - 1) % palettes.size()]
	var light := 0.88 + 0.12 * sin(s * 0.045 + x * 0.043)
	var stripes := 0.04 * sin(s * 0.22)
	light += stripes
	var path := 1.0 - smoothstep(48.0, HALF_WIDTH, absf(x))
	return base.lerp(Color(0.72, 0.74, 0.56), path * 0.21) * Color(light, light, light, 1.0)

func _vertex(tool: SurfaceTool, x: float, s: float, start: float) -> void:
	tool.set_color(_color(x, s))
	tool.set_normal(normal_at(x, s))
	tool.add_vertex(Vector3(x, elevation(x, s), -(s - start)))

func _build(index: int) -> void:
	var start := float(index) * CHUNK
	var node := Node3D.new()
	node.position.z = -start
	add_child(node)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(int(CHUNK / CELL)):
		var s := start + float(row) * CELL
		for col in range(int(HALF_WIDTH * 2.0 / CELL)):
			var x := -HALF_WIDTH + float(col) * CELL
			_vertex(st, x, s, start)
			_vertex(st, x, s + CELL, start)
			_vertex(st, x + CELL, s, start)
			_vertex(st, x + CELL, s, start)
			_vertex(st, x, s + CELL, start)
			_vertex(st, x + CELL, s + CELL, start)
	# Deep exposed sides make the terrain look like floating land, not a road.
	for row in range(int(CHUNK / CELL)):
		var s := start + float(row) * CELL
		for side in [-1.0, 1.0]:
			var x: float = side * HALF_WIDTH
			var a := Vector3(x, elevation(x, s), -(s - start))
			var b := Vector3(x, elevation(x, s + CELL), -(s + CELL - start))
			var lower_a := a - Vector3.UP * 30.0 - Vector3.RIGHT * side * 8.0
			var lower_b := b - Vector3.UP * 30.0 - Vector3.RIGHT * side * 8.0
			for point in [a, b, lower_a, lower_a, b, lower_b]:
				st.set_color(Color(0.28, 0.22, 0.32))
				st.set_normal(Vector3(side, 0.0, 0.0))
				st.add_vertex(point)
	st.index()
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = ground_material
	node.add_child(ground)
	var rocks: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(phase * 100000.0) + index * 9137
	if index >= 1 and start < length - 100.0:
		for i in range(3 + mini(stage - 1, 2)):
			var at := start + 24.0 + float(i) * 27.0 + rng.randf_range(-5.0, 5.0)
			var across := rng.randf_range(-65.0, 65.0)
			var radius := rng.randf_range(2.0, 4.8)
			var rock := MeshInstance3D.new()
			rock.mesh = rock_mesh
			rock.material_override = rock_material
			rock.scale = Vector3(radius, radius * 1.05, radius)
			rock.position = Vector3(across, elevation(across, at) + radius * 0.45, -(at - start))
			rock.rotation.y = rng.randf_range(0.0, TAU)
			node.add_child(rock)
			rocks.append({"x": across, "s": at, "r": radius, "used": false})
	chunks[index] = {"node": node, "rocks": rocks}

func stream(s: float) -> void:
	var current := int(floor(s / CHUNK))
	for index in range(maxi(-1, current - 2), current + 7):
		if not chunks.has(index):
			_build(index)
	for key in chunks.keys():
		if int(key) < current - 2 or int(key) >= current + 7:
			var node: Node3D = chunks[key]["node"]
			remove_child(node)
			node.queue_free()
			chunks.erase(key)

func obstacle_hit(a: Vector3, b: Vector3) -> bool:
	var start := int(floor(minf(-a.z, -b.z) / CHUNK))
	var finish := int(floor(maxf(-a.z, -b.z) / CHUNK))
	var line := Vector2(b.x - a.x, -b.z + a.z)
	for index in range(start - 1, finish + 2):
		if not chunks.has(index):
			continue
		for rock in chunks[index]["rocks"]:
			if bool(rock["used"]):
				continue
			var center := Vector2(float(rock["x"]), float(rock["s"]))
			var origin := Vector2(a.x, -a.z)
			var t := clampf((center - origin).dot(line) / maxf(0.001, line.length_squared()), 0.0, 1.0)
			var radius: float = rock["r"]
			if (origin + line * t).distance_to(center) < radius + 0.45 and lerpf(a.y, b.y, t) < elevation(center.x, center.y) + radius * 1.5:
				rock["used"] = true
				return true
	return false

func collapse_behind(s: float) -> void:
	for key in chunks.keys():
		if (float(key) + 1.0) * CHUNK < s - 20.0:
			var node: Node3D = chunks[key]["node"]
			node.hide()
