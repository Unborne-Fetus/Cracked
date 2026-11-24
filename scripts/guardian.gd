extends Node3D
const SPACING := 190.0
var active := false
var next_s := 320.0
var lane := 0.0
var lane_width := 42.0
var cleared := 0
var hit_count := 0
var seed_value := 0
var warning: MeshInstance3D
var guardian: MeshInstance3D
var warning_mat: StandardMaterial3D

func _ready() -> void:
	warning = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(lane_width, 0.5, 9.0)
	warning.mesh = box
	warning_mat = StandardMaterial3D.new()
	warning_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warning_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warning_mat.albedo_color = Color(1.0, 0.43, 0.2, 0.8)
	warning.material_override = warning_mat
	add_child(warning)
	guardian = MeshInstance3D.new()
	var shape := TorusMesh.new()
	shape.inner_radius = 7.0
	shape.outer_radius = 10.0
	guardian.mesh = shape
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.88, 0.34, 0.65)
	guardian.material_override = mat
	add_child(guardian)
	hide()

func reset(enabled: bool, seed_input: int) -> void:
	active = enabled
	seed_value = seed_input
	next_s = 320.0
	cleared = 0
	hit_count = 0
	lane = lane_for(0)
	visible = active

func lane_for(index: int) -> float:
	return float(posmod(seed_value + index * 7, 3) - 1) * 47.0

static func wave_hits(x: float, height: float, center: float) -> bool:
	return absf(x - center) < 21.0 and height < 5.0

func tick(course: Node3D, runner: Node3D, old: Vector3) -> void:
	if not active:
		return
	var s: float = runner.call("progress")
	var limit: float = course.get("length")
	if next_s > limit - 60.0:
		hide()
		return
	var distance := next_s - s
	guardian.position = Vector3(lane * 0.65, float(course.call("elevation", lane * 0.65, s + 125.0)) + 34.0, -(s + 125.0))
	guardian.rotation.z += 0.025
	warning.visible = distance < 260.0
	warning.position = Vector3(lane, float(course.call("elevation", lane, next_s)) + 0.9, -next_s)
	var slope: Vector2 = course.call("grade", lane, next_s)
	warning.rotation.x = atan(slope.y)
	warning.rotation.z = atan(slope.x)
	warning_mat.albedo_color = Color(1.0, 0.34, 0.2, 0.85 if distance < 70.0 else 0.50)
	while s >= next_s and next_s <= limit - 60.0:
		var ratio := clampf((next_s + old.z) / maxf(0.001, s + old.z), 0.0, 1.0)
		var crossing := old.lerp(runner.position, ratio)
		var height := crossing.y - float(course.call("elevation", crossing.x, next_s))
		if wave_hits(crossing.x, height, lane):
			runner.call("apply_guardian_hit")
			hit_count += 1
		cleared += 1
		next_s += SPACING
		lane = lane_for(cleared)
