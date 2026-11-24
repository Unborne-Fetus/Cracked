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
	runner.call("request_jump")
	runner.call("tick", 0.016, course)
	if bool(runner.get("grounded")):
		_fail("Jump did not launch.")
		return
	for i in range(900):
		runner.call("tick", 1.0 / 60.0, course)
		course.call("stream", float(runner.call("progress")))
		if not runner.position.is_finite() or not is_finite(float(runner.get("speed"))):
			_fail("Nonfinite movement.")
			return
	if float(runner.call("progress")) <= 50.0:
		_fail("Runner did not advance.")
		return
	print("PASS: flow movement, slopes, landings and streaming")
	quit(0)

func _fail(message: String) -> void:
	push_error("FLOW REGRESSION: " + message)
	quit(1)
