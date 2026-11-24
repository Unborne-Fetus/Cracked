extends Node3D
var active := false
var next_s := 300.0
var lane := 0.0
var cleared := 0
var hit_count := 0
var seed_value := 0
var shard := 1
var phase := 0
var pattern := 0
var safe_center := 0.0
var warning: MeshInstance3D
var second_warning: MeshInstance3D
var guardian: MeshInstance3D
var warning_mat: StandardMaterial3D
var cleared_clean := 0
var clean_chain := 0
var best_clean_chain := 0
var next_distance := 0.0
const EFFECTS := [0, 4, 1, 2, 3, 2, 4, 1, 3, 0]
const EFFECT_NAMES := ["MOMENTUM LOSS", "ENERGY DRAIN", "CROSSWIND", "ABILITY JAM", "DOWNDRAFT"]
const NAMES := ["Rift Warden", "Sky Weaver", "Pulse Engine", "Crown of Wind", "The Divide", "Storm Loom", "Glass Serpent", "Horizon Breaker", "Twin Echo", "Last Sentinel"]
const PROGRAMS := [[0,1,0,2,1,4], [3,0,3,5,1,3], [2,0,2,4,2,1], [1,3,1,5,3,4], [1,2,1,4,1,5], [0,5,2,5,3,4], [3,2,3,1,5,0], [4,1,4,3,4,2], [2,5,2,0,5,1], [0,1,2,3,4,5]]
const PATTERN_NAMES := ["LANE WAVE", "SAFE CORRIDOR", "SPLIT WAVE", "AERIAL FIELD", "LOW BARRIER", "CROSSWIND"]

func _ready() -> void:
	warning_mat = StandardMaterial3D.new()
	warning_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warning_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warning_mat.albedo_color = Color(1.0, 0.43, 0.2, 0.8)
	warning = _warning()
	second_warning = _warning()
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

func _warning() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.5, 9.0)
	mesh.mesh = box
	mesh.material_override = warning_mat
	add_child(mesh)
	return mesh

func reset(enabled: bool, seed_input: int, shard_value: int = 1) -> void:
	active = enabled
	seed_value = seed_input
	shard = shard_value
	next_s = 300.0
	cleared = 0
	cleared_clean = 0
	clean_chain = 0
	best_clean_chain = 0
	next_distance = next_s
	hit_count = 0
	phase = 0
	pattern = 0
	lane = lane_for(0)
	visible = active
	second_warning.hide()

func lane_for(index: int) -> float:
	return float(posmod(seed_value + index * 7, 3) - 1) * 47.0

static func wave_hits(x: float, height: float, center: float) -> bool:
	return absf(x - center) < 21.0 and height < 5.0

static func pattern_hits(kind: int, x: float, height: float, center: float) -> bool:
	match kind:
		0:
			return wave_hits(x, height, center)
		1:
			return absf(x - center) > 24.0 and height < 6.0
		2:
			return (absf(x - 52.0) < 26.0 or absf(x + 52.0) < 26.0) and height < 8.0
		3:
			return absf(x - center) < 34.0 and height > 7.0
		4:
			return absf(x - center) < 43.0 and height < 11.0
		_:
			return absf(x - center) > 38.0 and height > 3.0

func boss_name() -> String:
	return NAMES[posmod(shard - 1, NAMES.size())]

func _plan(limit: float, course: Node3D) -> void:
	phase = clampi(int(next_s / maxf(1.0, limit) * 3.0), 0, 2)
	var program: Array = PROGRAMS[clampi(shard - 1, 0, PROGRAMS.size() - 1)]
	pattern = int(program[posmod(cleared + phase, mini(program.size(), 2 + phase * 2))])
	lane = lane_for(cleared)
	# Never put a corridor-only wave across the only supported bypass.
	var gap: Rect2 = course.call("gap_rect", int(floor(next_s / 160.0)))
	if gap.has_area() and next_s >= gap.position.y - 12.0 and next_s <= gap.end.y + 12.0:
		var bypass: float = course.call("safe_lane", gap)
		if pattern in [1, 5]:
			lane = bypass
		elif pattern == 2:
			pattern = 0
			lane = -bypass
		elif pattern in [0, 3, 4]:
			lane = -bypass
	safe_center = lane

func _place(mesh: MeshInstance3D, course: Node3D, center: float, width: float, height: float) -> void:
	mesh.visible = width > 0.1
	mesh.scale = Vector3(maxf(0.1, width), 1.0, 1.0)
	mesh.position = Vector3(center, float(course.call("elevation", center, next_s)) + height, -next_s)
	var slope: Vector2 = course.call("grade", center, next_s)
	mesh.rotation.x = atan(slope.y)
	mesh.rotation.z = atan(slope.x)

func tick(course: Node3D, runner: Node3D, old: Vector3) -> void:
	if not active:
		return
	var s: float = runner.call("progress")
	var limit: float = course.get("length")
	if next_s > limit - 60.0:
		hide()
		return
	_plan(limit, course)
	while s >= next_s and next_s <= limit - 60.0:
		var ratio := clampf((next_s + old.z) / maxf(0.001, s + old.z), 0.0, 1.0)
		var crossing := old.lerp(runner.position, ratio)
		var height := crossing.y - float(course.call("elevation", crossing.x, next_s))
		if pattern_hits(pattern, crossing.x, height, lane) and float(runner.get("protected_time")) <= 0.0:
			runner.call("apply_guardian_hit", effect_for(), -signf(crossing.x) if absf(crossing.x) > 1.0 else 1.0)
			hit_count += 1
			clean_chain = 0
		else:
			cleared_clean += 1
			clean_chain += 1
			best_clean_chain = maxi(best_clean_chain, clean_chain)
			runner.set("energy", minf(100.0, float(runner.get("energy")) + 8.0 + minf(6.0, float(clean_chain))))
		cleared += 1
		next_s += maxf(115.0, 220.0 - float(phase) * 35.0 - float(shard - 1) * 3.0 + (30.0 if pattern == 4 else 0.0))
		_plan(limit, course)
	if next_s > limit - 60.0:
		hide()
		return
	var distance := next_s - s
	next_distance = maxf(0.0, distance)
	guardian.position = Vector3(lane * 0.65, float(course.call("elevation", lane * 0.65, s + 125.0)) + 34.0, -(s + 125.0))
	guardian.rotation.z += 0.025
	warning_mat.albedo_color = Color(0.70, 0.38, 1.0, 0.85) if pattern in [3, 5] else Color(1.0, 0.34, 0.2, 0.85 if distance < 70.0 else 0.50)
	second_warning.hide()
	match pattern:
		0:
			_place(warning, course, lane, 42.0, 0.9)
		1:
			var left := lane - 24.0
			var right := lane + 24.0
			_place(warning, course, (-110.0 + left) * 0.5, left + 110.0, 0.9)
			_place(second_warning, course, (right + 110.0) * 0.5, 110.0 - right, 0.9)
		2:
			_place(warning, course, -52.0, 52.0, 0.9)
			_place(second_warning, course, 52.0, 52.0, 0.9)
		3:
			_place(warning, course, lane, 68.0, 8.0)
		4:
			_place(warning, course, lane, 86.0, 2.0)
		5:
			var left := lane - 38.0
			var right := lane + 38.0
			_place(warning, course, (-110.0 + left) * 0.5, left + 110.0, 5.0)
			_place(second_warning, course, (right + 110.0) * 0.5, 110.0 - right, 5.0)
	if distance > 320.0:
		warning.hide()
		second_warning.hide()

func instruction() -> String:
	return PATTERN_NAMES[clampi(pattern, 0, PATTERN_NAMES.size() - 1)]

func effect_for() -> int:
	return posmod(cleared + phase, EFFECT_NAMES.size()) if shard == 10 else int(EFFECTS[clampi(shard - 1, 0, EFFECTS.size() - 1)])

func grade() -> String:
	if cleared == 0:
		return "C"
	var ratio := float(cleared_clean) / float(cleared)
	return "S" if ratio >= 0.90 else ("A" if ratio >= 0.75 else ("B" if ratio >= 0.50 else "C"))

func instruction_detail() -> String:
	return "%s  •  %s  •  %dm" % [instruction(), EFFECT_NAMES[effect_for()], int(next_distance)]
