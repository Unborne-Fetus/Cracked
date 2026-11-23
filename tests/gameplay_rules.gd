extends SceneTree

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate() as Node3D
	root.add_child(game)
	await physics_frame
	game.set_physics_process(false)
	var runner: Node3D = game.get("runner")
	var storm: Node3D = game.get("storm")
	var course: Node3D = game.get("course")
	if not bool(runner.call("can_slide_on_grade", 0.25)):
		_fail("Uphill sliding must be available.")
		return
	if float(runner.call("step_speed", 80.0, 0.2, true, true, 1.0)) > 50.0:
		_fail("Uphill sliding must cause a substantial loss of speed.")
		return
	if float(runner.call("step_speed", 25.0, -0.2, true, false, 1.0)) >= 25.0:
		_fail("Non-sliding downhill movement must not increase speed.")
		return
	if float(runner.call("step_speed", 25.0, -0.2, false, true, 1.0)) >= 25.0:
		_fail("Airborne movement must not increase speed.")
		return
	if float(runner.call("step_speed", 100000.0, -0.2, true, true, 1.0)) <= 100000.0:
		_fail("Sliding unexpectedly has a maximum speed.")
		return
	# Inversions retain far more momentum than ordinary uphill slopes.
	var loop_speed: float = runner.call("step_speed", 80.0, 0.5, true, true, 1.0, true)
	var uphill_speed: float = runner.call("step_speed", 80.0, 0.5, true, true, 1.0, false)
	if loop_speed < 70.0 or loop_speed <= uphill_speed or loop_speed >= 80.0:
		_fail("Inversion uphill drag must be gentler without granting acceleration.")
		return
	# Faster launches produce higher jumps, without changing forward speed.
	var low_jump: float = runner.call("jump_impulse_for_speed", 22.0)
	var fast_jump: float = runner.call("jump_impulse_for_speed", 80.0)
	var extreme_jump: float = runner.call("jump_impulse_for_speed", 160.0)
	if low_jump <= 0.0 or fast_jump < low_jump * 1.5 or extreme_jump <= fast_jump:
		_fail("Jump launch strength does not increase sufficiently with speed.")
		return
	var bank: Transform3D = course.call("sample", 288.0)
	var inversion: Transform3D = course.call("sample", 480.0)
	var entry: Transform3D = course.call("sample", 192.0)
	var exit_frame: Transform3D = course.call("sample", 384.0)
	if absf(bank.basis.x.y) < 0.35 or inversion.basis.y.y > -0.8 or entry.basis.z.dot(exit_frame.basis.z) > 0.94:
		_fail("Bank, inversion, or turn geometry was not generated.")
		return
	# Verify both new roll geometries and their upright seams.
	var half_bank: Transform3D = course.call("sample", 864.0)
	var full_bank: Transform3D = course.call("sample", 1056.0)
	var full_quarter: Transform3D = course.call("sample", 1008.0)
	if str(course.call("section_name", 864.0)) != "180 BANK" or half_bank.basis.y.y > -0.9:
		_fail("180-degree bank did not become fully inverted.")
		return
	if str(course.call("section_name", 1056.0)) != "360 BANK" or full_bank.basis.y.y > -0.9 or absf(full_quarter.basis.x.y) < 0.6:
		_fail("360-degree barrel roll geometry is missing.")
		return
	for i in range(1, 6):
		var a: Transform3D = course.call("sample", float(i) * 192.0 - 0.01)
		var b: Transform3D = course.call("sample", float(i) * 192.0 + 0.01)
		if a.origin.distance_to(b.origin) > 0.1 or a.basis.z.dot(b.basis.z) < 0.99:
			_fail("Track seam is discontinuous.")
			return
	var chunks: Dictionary = course.get("chunks")
	var hazards: Array[Dictionary] = chunks[0]["hazards"]
	var hazard: Dictionary = hazards[0]
	var at: float = hazard["s"]
	var lane: float = hazard["lane"]
	if int(course.call("swept_obstacles", at - 8.0, at + 8.0, lane, lane, 0.0, 0.0)) != 1:
		_fail("High-speed obstacle sweep missed a hazard.")
		return
	if int(course.call("swept_obstacles", at - 8.0, at + 8.0, lane, lane, 0.0, 0.0)) != 0:
		_fail("One obstacle hit applied more than once.")
		return
	runner.set("speed", 80.0)
	runner.call("apply_obstacle_hit")
	if float(runner.get("speed")) >= 40.0 or bool(game.get("run_finished")):
		_fail("Obstacle should drain momentum without ending the run.")
		return
	course.call("stream", 6500.0)
	chunks = course.get("chunks")
	if chunks.size() > 8 or not bool(course.call("has_distance", 6700.0)) or chunks.has(0):
		_fail("Endless streaming failed to recycle old track chunks.")
		return
	game.call("_restart")
	var original_speed: float = storm.get("speed")
	var original_s: float = storm.get("front_s")
	storm.call("advance", 10.0)
	if float(storm.get("speed")) <= original_speed or float(storm.get("front_s")) <= original_s:
		_fail("Storm must advance and accelerate.")
		return
	game.call("_lose", "TEST")
	if not bool(game.get("run_finished")):
		_fail("Storm failure did not finish the run.")
		return
	game.call("_restart")
	if bool(game.get("run_finished")) or absf(float(storm.get("speed")) - original_speed) > 0.001 or absf(float(storm.get("front_s")) - original_s) > 0.001:
		_fail("Restart did not restore the storm.")
		return
	print("PASS: slide-only acceleration, unlimited speed, hazards, and advancing storm")
	print("PASS: banked turns, true inversions, seamless endless streaming, nonfatal obstacles")
	game.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	push_error("GAMEPLAY REGRESSION: " + reason)
	quit(1)
