extends Node3D

signal hazard_hit(body: Node3D)
## Procedural static test course. A visible grid and the physics collider are
## built from the same height function, so the wireframe matches every slope.

const LENGTH := 1050.0
const HALF_WIDTH := 24.0
const STEP_X := 4.0
const STEP_Z := 3.0

var surface_material: StandardMaterial3D
var line_material: StandardMaterial3D

func _ready() -> void:
	_make_materials()
	_build_ground()
	_build_decorations()

func surface_height(x: float, z: float) -> float:
	var bank: float = pow(absf(z) / HALF_WIDTH, 2.0) * 2.6
	return -0.065 * x + sin(x * 0.023) * 5.8 + sin(x * 0.064) * 1.65 + bank

func _make_materials() -> void:
	surface_material = StandardMaterial3D.new()
	surface_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface_material.albedo_color = Color(0.009, 0.015, 0.052)
	surface_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.cull_mode = BaseMaterial3D.CULL_DISABLED

func _point(x: float, z: float, offset: float = 0.0) -> Vector3:
	return Vector3(x, surface_height(x, z) + offset, z)

func _build_ground() -> void:
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	var collision_vertices := PackedVector3Array()
	var nx := int(LENGTH / STEP_X)
	var nz := int(HALF_WIDTH * 2.0 / STEP_Z)
	for ix in range(nx):
		var x := float(ix) * STEP_X
		for iz in range(nz):
			var z := -HALF_WIDTH + float(iz) * STEP_Z
			var a := _point(x, z)
			var b := _point(x + STEP_X, z)
			var c := _point(x, z + STEP_Z)
			var d := _point(x + STEP_X, z + STEP_Z)
			for v in [a, c, b, b, c, d]:
				fill.add_vertex(v)
				collision_vertices.append(v)
	fill.generate_normals()
	var ground := MeshInstance3D.new()
	ground.mesh = fill.commit()
	ground.material_override = surface_material
	add_child(ground)
	var physics_body := StaticBody3D.new()
	physics_body.collision_layer = 1
	physics_body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	# Terrain triangles may be approached from either side during high-speed landings.
	# Without backface collisions, the body can pass through one-sided faces.
	shape.backface_collision = true
	shape.set_faces(collision_vertices)
	collider.shape = shape
	physics_body.add_child(collider)
	add_child(physics_body)
	
	var grid := SurfaceTool.new()
	grid.begin(Mesh.PRIMITIVE_LINES)
	for ix in range(nx + 1):
		var x := float(ix) * STEP_X
		var tint := Color(0.96, 0.12, 0.62) if ix % 10 == 0 else Color(0.05, 0.66, 0.91)
		for iz in range(nz):
			var z := -HALF_WIDTH + float(iz) * STEP_Z
			_line(grid, _point(x, z, 0.10), _point(x, z + STEP_Z, 0.10), tint)
	for iz in range(nz + 1):
		var z := -HALF_WIDTH + float(iz) * STEP_Z
		var tint := Color(0.99, 0.20, 0.64) if iz == 0 or iz == nz else Color(0.05, 0.52, 0.82)
		for ix in range(nx):
			var x := float(ix) * STEP_X
			_line(grid, _point(x, z, 0.10), _point(x + STEP_X, z, 0.10), tint)
	var grid_visual := MeshInstance3D.new()
	grid_visual.mesh = grid.commit()
	grid_visual.material_override = line_material
	add_child(grid_visual)

func _line(tool: SurfaceTool, a: Vector3, b: Vector3, color: Color) -> void:
	tool.set_color(color)
	tool.add_vertex(a)
	tool.set_color(color)
	tool.add_vertex(b)

func _neon(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.5
	return m

func _box(size: Vector3, where: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = where
	visual.material_override = material
	add_child(visual)

func _gate(x: float, color: Color) -> void:
	var mat := _neon(color)
	var left_y := surface_height(x, -21.0)
	var right_y := surface_height(x, 21.0)
	_box(Vector3(0.55, 13.0, 0.55), Vector3(x, left_y + 6.5, -21), mat)
	_box(Vector3(0.55, 13.0, 0.55), Vector3(x, right_y + 6.5, 21), mat)
	_box(Vector3(0.7, 0.55, 42.5), Vector3(x, maxf(left_y, right_y) + 13.0, 0), mat)

func _hazard(x: float, z: float, size: Vector3, color: Color) -> void:
	# Obstacle visuals and trigger share exactly the same dimensions.
	# Area3D hazards are reliable even when the player is moving very fast.
	var center := Vector3(x, surface_height(x, z) + size.y * 0.5 + 0.05, z)
	_box(size, center, _neon(color))
	# Top stripe makes tall pillars and low jumpable hurdles easy to read.
	_box(Vector3(size.x + 0.2, 0.18, size.z + 0.2),
		center + Vector3(0, size.y * 0.5, 0), _neon(Color(1.0, 0.73, 0.23)))
	var area := Area3D.new()
	area.name = "Obstacle"
	area.add_to_group("obstacle_hazards")
	area.collision_layer = 4
	area.collision_mask = 2
	area.monitoring = true
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	area.add_child(collider)
	area.position = center
	add_child(area)
	area.body_entered.connect(_on_hazard_body_entered)

func _on_hazard_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		hazard_hit.emit(body)

func _build_decorations() -> void:
	# Wide luminous gates indicate progress; only the marked hazard blocks hurt.
	for x in [50.0, 180.0, 350.0, 540.0, 735.0, 950.0]:
		_gate(x, Color(0.94, 0.13, 0.64) if int(x) % 2 == 0 else Color(0.1, 0.96, 1.0))
	
	# Alternating single pillars force lane changes. Each leaves several exits.
	var pillars: Array[Vector2] = [
		Vector2(110.0, 0.0), Vector2(162.0, -11.0),
		Vector2(163.0, 11.0), Vector2(288.0, 8.0),
		Vector2(354.0, -4.0), Vector2(432.0, -13.0),
		Vector2(434.0, 10.0), Vector2(575.0, -7.0),
		Vector2(646.0, 9.0), Vector2(719.0, -13.0),
		Vector2(720.0, 13.0), Vector2(793.0, 0.0),
		Vector2(884.0, 12.0), Vector2(968.0, -7.0)
	]
	for p in pillars:
		_hazard(p.x, p.y, Vector3(3.4, 6.0, 4.2), Color(1.0, 0.19, 0.41))
	
	# Wide barriers are avoidable by steering, while short hurdles can be jumped.
	_hazard(228.0, -13.0, Vector3(3.2, 5.8, 15.0), Color(0.94, 0.11, 0.58))
	_hazard(503.0, 0.0, Vector3(3.0, 1.7, 12.0), Color(1.0, 0.44, 0.11))
	_hazard(685.0, 14.0, Vector3(3.0, 5.8, 14.0), Color(0.94, 0.11, 0.58))
	_hazard(925.0, 0.0, Vector3(3.0, 1.8, 15.0), Color(1.0, 0.44, 0.11))
	
	_gate(LENGTH - 15.0, Color(1.0, 0.83, 0.25))
	_box(Vector3(1.4, 0.12, 44.0), Vector3(LENGTH - 15.0,
		surface_height(LENGTH - 15.0, 0.0) + 0.14, 0.0), _neon(Color(1.0, 0.8, 0.25)))
	
	# Background vector pillars provide scale without texture dependencies.
	var cyan := _neon(Color(0.06, 0.53, 0.83))
	for i in range(16):
		var x := 60.0 + float(i) * 61.0
		for side in [-1.0, 1.0]:
			var z: float = side * 39.0
			_box(Vector3(0.35, 16.0 + float(i % 4) * 6.0, 0.35),
				Vector3(x, surface_height(x, z) + 8.0, z), cyan)
