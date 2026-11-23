extends SceneTree
## Regression tests for slide-only speed, hazards, and accelerating storm.
## Runs with: godot --headless --path . --script res://tests/gameplay_rules.gd

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		_fail("Main scene could not load.")
		return
	var game := scene.instantiate() as Node3D
	root.add_child(game)
	await physics_frame
	var runner := game.get("runner") as CharacterBody3D
	var storm := game.get("storm") as Node3D
	if runner == null or storm == null:
		_fail("Player or storm was not created.")
		return
	
	# Holding slide uphill must NOT give any speed.
	if bool(runner.call("can_slide_on_grade", 0.10)):
		_fail("Sliding is incorrectly available on an uphill incline.")
		return
	if not bool(runner.call("can_slide_on_grade", -0.10)):
		_fail("Descending terrain incorrectly blocks sliding.")
		return
	if float(runner.call("step_speed", 25.0, -0.20, true, false, 1.0)) >= 25.0:
		_fail("Walking downhill increases speed without sliding.")
		return
	if float(runner.call("step_speed", 25.0, 0.10, true, true, 1.0)) >= 25.0:
		_fail("Holding slide while going uphill increases speed.")
		return
	if float(runner.call("step_speed", 25.0, -0.20, false, true, 1.0)) >= 25.0:
		_fail("Sliding in midair increases speed.")
		return
	if float(runner.call("step_speed", 25.0, -0.20, true, true, 1.0)) <= 25.0:
		_fail("Downhill sliding fails to gain speed.")
		return
	if float(runner.call("step_speed", 100000.0, 0.0, true, true, 1.0)) <= 100000.0:
		_fail("Speed unexpectedly has an upper limit.")
		return
	
	var hazards := get_nodes_in_group("obstacle_hazards")
	if hazards.size() < 15:
		_fail("Expected a course with multiple real obstacles; found %d." % hazards.size())
		return
	
	# Make the baseline deterministic: _process has already advanced the storm one frame.
	game.call("_restart")
	var original_speed: float = float(storm.get("speed"))
	var original_x: float = float(storm.get("front_x"))
	storm.call("advance", 10.0)
	if float(storm.get("speed")) <= original_speed or float(storm.get("front_x")) <= original_x:
		_fail("Storm must move forward and accelerate over time.")
		return
	
	# An obstacle must actually end a run, and restart must reset the storm.
	game.call("_on_hazard_hit", runner)
	if not bool(game.get("run_finished")):
		_fail("Hazard collision did not end the run.")
		return
	game.call("_restart")
	if bool(game.get("run_finished")) or absf(float(storm.get("speed")) - original_speed) > 0.001:
		_fail("Restart state mismatch: run_finished=%s, storm start=%.6f, actual=%.6f" % [str(game.get("run_finished")), original_speed, float(storm.get("speed"))])
		return
	
	print("PASS: slide-only acceleration, unlimited speed, hazards, and advancing storm")
	game.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	push_error("GAMEPLAY REGRESSION: " + reason)
	quit(1)
