extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	var course: Node3D = game.get("course")
	var runner: Node3D = game.get("runner")
	var rules = preload("res://scripts/runner.gd")
	if rules.ground_speed(40.0, -0.4, 1.0) <= 40.0 or rules.ground_speed(40.0, 0.4, 1.0) >= 40.0:
		_fail("Slope must change momentum.")
		return
	var downhill := Vector3(0.0, 1.0, -0.5).normalized()
	if rules.landing_speed(Vector3(0.0, -25.0, -50.0), downhill, -0.5, true) <= rules.landing_speed(Vector3(0.0, -25.0, -50.0), Vector3.UP, 0.0, true):
		_fail("Downhill dive must beat a hard flat landing.")
		return
	for i in range(8):
		var s := float(i) * 160.0
		if absf(float(course.call("elevation", 0.0, s - 0.001)) - float(course.call("elevation", 0.0, s + 0.001))) > 0.01:
			_fail("Terrain seam.")
			return
	if not rules.should_launch(90.0, -0.02, 0.0) or rules.should_launch(20.0, -0.02, 0.0):
		_fail("Natural crest takeoff rule is incorrect.")
		return
	if rules.landing_quality(Vector3(0.0, -25.0, -50.0), downhill, -0.5) != "PERFECT":
		_fail("Tangent landing must be perfect.")
		return
	runner.set("energy", 50.0)
	var pre_boost: float = runner.get("speed")
	runner.call("request_boost")
	runner.call("tick", 0.016, course)
	if float(runner.get("energy")) >= 50.0 or float(runner.get("speed")) <= pre_boost:
		_fail("Boost did not consume energy and increase speed.")
		return
	runner.call("reset", course)
	var launch_s := -1.0
	for i in range(20, 300):
		var at := float(i)
		var slope: Vector2 = course.call("grade", 0.0, at)
		if rules.should_launch(110.0, float(course.call("curvature", 0.0, at)), slope.y):
			launch_s = at
			break
	if launch_s < 0.0:
		_fail("Terrain has no launchable crests.")
		return
	runner.position = Vector3(0.0, float(course.call("elevation", 0.0, launch_s)) + 0.08, -launch_s)
	runner.set("speed", 110.0)
	runner.call("tick", 1.0 / 120.0, course)
	if bool(runner.get("grounded")):
		_fail("Natural takeoff did not launch.")
		return
	runner.call("reset", course)
	for i in range(900):
		runner.call("tick", 1.0 / 60.0, course)
		course.call("stream", float(runner.call("progress")))
		if not runner.position.is_finite() or not is_finite(float(runner.get("speed"))):
			_fail("Nonfinite movement.")
			return
	if float(runner.call("progress")) <= 50.0:
		_fail("Runner did not advance.")
		return
	var gap: Rect2 = course.call("gap_rect", 3)
	if not gap.has_area() or bool(course.call("has_ground", gap.get_center().x, gap.get_center().y)):
		_fail("Ravine mesh and support rule disagree.")
		return
	var bypass := 80.0 if gap.position.x < -100.0 else -80.0
	if not bool(course.call("has_ground", bypass, gap.get_center().y)):
		_fail("Ravine has no safe bypass.")
		return
	runner.call("reset", course)
	var x := gap.get_center().x
	var s := gap.position.y - 0.4
	runner.position = Vector3(x, float(course.call("elevation", x, s)) + 0.08, -s)
	runner.set("speed", 30.0)
	runner.call("tick", 0.025, course)
	if bool(runner.get("grounded")):
		_fail("Unsupported ravine edge did not launch.")
		return
	runner.call("reset", course)
	runner.position = Vector3(0.0, float(course.call("elevation", 0.0, 60.0)) + 12.0, -60.0)
	runner.set("grounded", false)
	runner.set("speed", 30.0)
	runner.set("vy", -12.0)
	var prediction: Dictionary = runner.call("predict_landing", course, true)
	if prediction.is_empty():
		_fail("Landing prediction failed over continuous terrain.")
		return
	var predicted: Vector3 = prediction["point"]
	if not bool(course.call("has_ground", predicted.x, -predicted.z)):
		_fail("Landing marker predicts unsupported ground.")
		return
	print("PASS: flow movement, slopes, landings and streaming")
	quit(0)

func _fail(message: String) -> void:
	push_error("FLOW REGRESSION: " + message)
	quit(1)
