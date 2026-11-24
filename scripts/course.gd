extends Node3D
## Wide, continuous heightfield. Rendering and movement share the same function.
const CHUNK := 160.0
const HALF_WIDTH := 110.0
const CELL := 4.0
var phase := 0.0
var seed_value_saved := 0
var ridge_material: StandardMaterial3D
var ridge_mesh: CylinderMesh
var stage := 1
var route_style := 0
var guardian_world := false
var spark_mesh: SphereMesh
var spark_material: StandardMaterial3D
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
	ridge_material = StandardMaterial3D.new()
	ridge_material.albedo_color = Color(0.39, 0.39, 0.54)
	ridge_material.roughness = 1.0
	ridge_mesh = CylinderMesh.new()
	ridge_mesh.top_radius = 0.18
	ridge_mesh.bottom_radius = 1.0
	ridge_mesh.height = 2.0
	ridge_mesh.radial_segments = 5
	spark_mesh = SphereMesh.new()
	spark_mesh.radius = 0.65
	spark_mesh.height = 1.3
	spark_mesh.radial_segments = 8
	spark_mesh.rings = 4
	spark_material = StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = Color(1.0, 0.82, 0.25)

func reset(seed_value: int, stage_value: int, route_value: int = 0, guardian_value: bool = false) -> void:
	for data in chunks.values():
		var node: Node3D = data["node"]
		remove_child(node)
		node.queue_free()
	chunks.clear()
	stage = stage_value
	route_style = clampi(route_value, 0, 4)
	guardian_world = guardian_value
	seed_value_saved = seed_value
	length = 2240.0 + float(mini(stage - 1, 6)) * 160.0 + (320.0 if guardian_world else 0.0)
	if route_style == 3 and not guardian_world:
		length = 1760.0
	elif route_style == 4:
		length += 320.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	phase = rng.randf_range(0.0, TAU)
	stream(0.0)

func elevation(x: float, s: float) -> float:
	# Smoothly vary wavelength and phase so there is no repeating single sine hill.
	var blend := smoothstep(75.0, 250.0, s)
	var phase_offset := phase * blend
	var wavelength := 0.034 + 0.004 * sin(s * 0.0019 + phase)
	var a := 17.0 * cos(s * 0.036 + phase_offset + 0.40 * sin(s * 0.009))
	var b := 4.5 * sin(s * 0.067 + phase_offset * 0.61)
	var c := 10.0 * sin(s * 0.019 + x * 0.037 + phase_offset)
	var d := 4.5 * cos(x * 0.065 - s * 0.011)
	var rolling := 3.2 * sin(s * wavelength + x * 0.012)
	var hill_scale := 1.0 + minf(float(stage - 1) * 0.042, 0.28)
	var route_scale := float([0.92, 1.0, 1.18, 0.78, 1.24][route_style])
	return -s * 0.115 + (a + b + c + d + rolling) * hill_scale * lerpf(1.0, route_scale, blend)

# Each ravine is a real rectangular hole. An alternate corridor always exists.
func gap_rect(index: int) -> Rect2:
	if route_style == 3 or index < 3 or posmod(index - 3, 3 if route_style in [1, 4] else 4) != 0 or float(index) * CHUNK > length - 250.0:
		return Rect2()
	var direction := posmod(seed_value_saved + index, 2)
	var width := 152.0 if route_style in [1, 4] else 128.0
	var start_x := -HALF_WIDTH if direction == 0 else HALF_WIDTH - width
	var start_s := float(index) * CHUNK + 64.0
	return Rect2(start_x, start_s, width, 28.0 + 4.0 * float(mini(stage - 1, 3)) + (8.0 if route_style == 4 else 0.0))

func has_ground(x: float, s: float) -> bool:
	if absf(x) > HALF_WIDTH:
		return false
	var rect := gap_rect(int(floor(s / CHUNK)))
	return not rect.has_area() or not rect.has_point(Vector2(x, s))

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
			if not has_ground(x + CELL * 0.5, s + CELL * 0.5):
				continue
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
			if not has_ground(x - float(side) * 0.1, s + CELL * 0.5):
				continue
			var a := Vector3(x, elevation(x, s), -(s - start))
			var b := Vector3(x, elevation(x, s + CELL), -(s + CELL - start))
			var lower_a: Vector3 = a - Vector3.UP * 30.0 - Vector3.RIGHT * float(side) * 8.0
			var lower_b: Vector3 = b - Vector3.UP * 30.0 - Vector3.RIGHT * float(side) * 8.0
			for point in [a, b, lower_a, lower_a, b, lower_b]:
				st.set_color(Color(0.28, 0.22, 0.32))
				st.set_normal(Vector3(side, 0.0, 0.0))
				st.add_vertex(point)
	var gap := gap_rect(index)
	if gap.has_area():
		# Cliff faces are generated from the same bounds as collision.
		for border_s in [gap.position.y, gap.end.y]:
			for col in range(int(gap.size.x / CELL)):
				var x := gap.position.x + float(col) * CELL
				_cliff(st, Vector2(x, float(border_s)), Vector2(x + CELL, float(border_s)), start)
		var border_x := gap.end.x if gap.position.x < -100.0 else gap.position.x
		for row in range(int(gap.size.y / CELL)):
			var s := gap.position.y + float(row) * CELL
			_cliff(st, Vector2(border_x, s), Vector2(border_x, s + CELL), start)
	st.index()
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = ground_material
	node.add_child(ground)
	var rocks: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(phase * 100000.0) + index * 9137
	if index >= 1 and start < length - 100.0:
		for i in range(1 if route_style == 3 else (6 if route_style == 4 else 3 + mini(stage - 1, 2))):
			var at := start + 20.0 + float(i) * 23.0 + rng.randf_range(-4.0, 4.0)
			var across := rng.randf_range(-65.0, 65.0)
			if not has_ground(across, at) or absf(across) < 9.0:
				continue
			var radius := rng.randf_range(2.0, 4.8)
			var rock := MeshInstance3D.new()
			rock.mesh = rock_mesh
			rock.material_override = rock_material
			rock.scale = Vector3(radius, radius * 1.05, radius)
			rock.position = Vector3(across, elevation(across, at) + radius * 0.45, -(at - start))
			rock.rotation.y = rng.randf_range(0.0, TAU)
			node.add_child(rock)
			rocks.append({"x": across, "s": at, "r": radius, "used": false})
	# Side silhouettes and contrasting landmarks provide genuine speed reference.
	for i in range(6):
		var across := (-1.0 if i % 2 == 0 else 1.0) * rng.randf_range(72.0, 99.0)
		var at := start + 12.0 + float(i) * 23.0
		if not has_ground(across, at):
			continue
		var spire := MeshInstance3D.new()
		spire.mesh = ridge_mesh
		spire.material_override = ridge_material
		var tall := rng.randf_range(5.0, 14.0)
		spire.scale = Vector3(rng.randf_range(1.4, 3.6), tall, rng.randf_range(1.4, 3.6))
		spire.position = Vector3(across, elevation(across, at) + tall * 0.72, -(at - start))
		spire.rotation.y = rng.randf_range(0.0, TAU)
		node.add_child(spire)
		rocks.append({"x": across, "s": at, "r": maxf(spire.scale.x, spire.scale.z), "used": false, "height": tall * 1.72})
	var sparks: Array[Dictionary] = []
	if index >= 0 and start < length - 80.0:
		for i in range(3):
			var at := start + 24.0 + float(i) * 48.0
			var across := sin(float(index * 3 + i) * 0.62 + phase) * 24.0
			if not has_ground(across, at):
				var hole := gap_rect(index)
				across = 80.0 if hole.position.x < -100.0 else -80.0
			if not has_ground(across, at):
				continue
			var spark := MeshInstance3D.new()
			spark.mesh = spark_mesh
			spark.material_override = spark_material
			var height := elevation(across, at) + 1.6
			spark.position = Vector3(across, height, -(at - start))
			spark.scale = Vector3(1.0, 1.55, 1.0)
			node.add_child(spark)
			sparks.append({"point": Vector3(across, height, -at), "node": spark, "used": false})
	chunks[index] = {"node": node, "rocks": rocks, "sparks": sparks}

func _cliff(st: SurfaceTool, a: Vector2, b: Vector2, start: float) -> void:
	var va := Vector3(a.x, elevation(a.x, a.y), -(a.y - start))
	var vb := Vector3(b.x, elevation(b.x, b.y), -(b.y - start))
	var normal := (vb - va).cross(Vector3.DOWN).normalized()
	for point in [va, vb, va - Vector3.UP * 34.0, va - Vector3.UP * 34.0, vb, vb - Vector3.UP * 34.0]:
		st.set_normal(normal)
		st.set_color(Color(0.29, 0.23, 0.36))
		st.add_vertex(point)


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
			if (origin + line * t).distance_to(center) < radius + 0.45 and lerpf(a.y, b.y, t) < elevation(center.x, center.y) + float(rock.get("height", radius * 1.5)):
				rock["used"] = true
				return true
	return false

func collapse_behind(s: float) -> void:
	for key in chunks.keys():
		if (float(key) + 1.0) * CHUNK < s - 20.0:
			var node: Node3D = chunks[key]["node"]
			node.hide()

func collect_sparks(a: Vector3, b: Vector3, reach: float = 3.6) -> int:
	var gained := 0
	var first := int(floor(minf(-a.z, -b.z) / CHUNK))
	var last := int(floor(maxf(-a.z, -b.z) / CHUNK))
	var segment := b - a
	for index in range(first - 1, last + 2):
		if not chunks.has(index):
			continue
		for spark in chunks[index]["sparks"]:
			if bool(spark["used"]):
				continue
			var point: Vector3 = spark["point"]
			var t := clampf((point - a).dot(segment) / maxf(0.001, segment.length_squared()), 0.0, 1.0)
			if (a + segment * t).distance_to(point) <= reach:
				spark["used"] = true
				var instance: Node3D = spark["node"]
				instance.hide()
				gained += 2
	return gained
