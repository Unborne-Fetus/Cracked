extends Node3D
## A chaser that advances in world-space; it never modifies player momentum.
## Speed keeps rising with time, so hesitation steadily becomes more dangerous.

const INITIAL_GAP := 92.0
const INITIAL_SPEED := 11.0
const ACCELERATION := 0.44

var front_x := -INITIAL_GAP
var speed := INITIAL_SPEED
var elapsed := 0.0

func _ready() -> void:
	_make_storm_wall()

func reset(start_x: float) -> void:
	front_x = start_x - INITIAL_GAP
	speed = INITIAL_SPEED
	elapsed = 0.0
	position.x = front_x

func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	front_x += speed * delta + 0.5 * ACCELERATION * delta * delta
	speed += ACCELERATION * delta
	elapsed += delta
	position.x = front_x

func gap_to(player_x: float) -> float:
	return player_x - front_x

func _make_storm_wall() -> void:
	# Low-cost, transparent magenta fog pane backed by a jagged neon lattice.
	var fog := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(82.0, 48.0)
	fog.mesh = quad
	fog.rotation.y = PI * 0.5
	fog.position.y = 13.0
	var fog_material := StandardMaterial3D.new()
	fog_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fog_material.albedo_color = Color(0.84, 0.04, 0.31, 0.38)
	fog_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	fog.material_override = fog_material
	add_child(fog)
	
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_LINES)
	var hot := Color(1.0, 0.11, 0.44)
	var cold := Color(0.56, 0.06, 0.94)
	for i in range(20):
		var z := -39.0 + float(i) * 4.0
		_add_line(lines, Vector3(0, -11, z), Vector3(0, 38, z + 2.0), hot if i % 2 == 0 else cold)
	for i in range(15):
		var y := -11.0 + float(i) * 3.5
		_add_line(lines, Vector3(0, y, -40), Vector3(0, y + 2, 40), cold if i % 2 == 0 else hot)
	var lattice := MeshInstance3D.new()
	lattice.mesh = lines.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	lattice.material_override = material
	add_child(lattice)

func _add_line(tool: SurfaceTool, a: Vector3, b: Vector3, color: Color) -> void:
	tool.set_color(color)
	tool.add_vertex(a)
	tool.set_color(color)
	tool.add_vertex(b)
