extends Node3D
## Pursuit is measured along the same endless track as the player.

const INITIAL_GAP := 92.0
const INITIAL_SPEED := 14.0
const ACCELERATION := 1.05
const ACCELERATION_GROWTH := 0.012

var front_s := -INITIAL_GAP
var speed := INITIAL_SPEED
var elapsed := 0.0
var catch_time := 0.0
var confirmed_gap := INF

func _ready() -> void:
	var fog := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(170.0, 94.0)
	fog.mesh = quad
	fog.position.y = 7.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.83, 0.05, 0.33, 0.45)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fog.material_override = mat
	add_child(fog)
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_LINES)
	for i in range(57):
		var x := -84.0 + float(i) * 3.0
		lines.add_vertex(Vector3(x, -13, 0))
		lines.add_vertex(Vector3(x + 1.0, 27, 0))
	for i in range(10):
		var y := -8.0 + float(i) * 3.3
		lines.add_vertex(Vector3(-84, y, 0))
		lines.add_vertex(Vector3(84, y + 1, 0))
	var lattice := MeshInstance3D.new()
	lattice.mesh = lines.commit()
	var grid := StandardMaterial3D.new()
	grid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid.albedo_color = Color(1.0, 0.12, 0.56)
	grid.cull_mode = BaseMaterial3D.CULL_DISABLED
	lattice.material_override = grid
	add_child(lattice)

func reset(start_s: float) -> void:
	front_s = start_s - INITIAL_GAP
	speed = INITIAL_SPEED
	elapsed = 0.0
	catch_time=0.0
	confirmed_gap=INF

func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var acceleration := ACCELERATION + ACCELERATION_GROWTH * elapsed
	front_s += speed * delta + 0.5 * acceleration * delta * delta + ACCELERATION_GROWTH * delta * delta * delta / 6.0
	speed += acceleration * delta + 0.5 * ACCELERATION_GROWTH * delta * delta
	elapsed += delta

func gap_to(player_s: float) -> float:
	return player_s - front_s

func confirms_catch(delta: float, runner: Node3D, course: Node3D) -> bool:
	var at:float=runner.get("distance")
	var gap:=gap_to(at)
	confirmed_gap=gap
	if not is_finite(gap) or gap>1.0:
		catch_time=0.0
		return false
	# High-altitude projection is only an estimate. Never use it alone
	# to kill a rider who is visibly far from the track/storm.
	if not bool(runner.get("grounded")):
		var p:=Vector3(at,float(runner.get("lane")),float(runner.get("height")))
		var nearby:float=course.call("distance_to_rideable_surface",runner.position,p)
		if nearby>16.0 or not bool(course.call("has_distance",at)):
			catch_time=0.0
			return false
	catch_time+=maxf(0.0,delta)
	return catch_time>=0.40

func sync_pose(course: Node3D) -> void:
	visible = bool(course.call("has_distance", front_s))
	if visible:
		transform = course.call("sample", front_s)
