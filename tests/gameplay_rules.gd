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
	# Holding slide drains traction; release restores it. Jumping cannot refill it.
	runner.set("slide_grip", 1.0)
	runner.call("update_slide_grip", 3.0, true, true)
	var empty_grip: float = runner.get("slide_grip")
	if empty_grip > 0.01 or float(runner.call("step_speed", 45.0, -0.2, true, true, 1.0, empty_grip)) >= 45.0:
		_fail("Permanent sliding must not provide permanent acceleration.")
		return
	runner.call("update_slide_grip", 1.0, false, true)
	if float(runner.get("slide_grip")) > 0.01:
		_fail("Jumping incorrectly restores grip.")
		return
	runner.call("update_slide_grip", 2.0, true, false)
	if float(runner.get("slide_grip")) < 0.99:
		_fail("Releasing slide must restore grip.")
		return
	# Faster launches produce higher jumps, without changing forward speed.
	var low_jump: float = runner.call("jump_impulse_for_speed", 22.0)
	var fast_jump: float = runner.call("jump_impulse_for_speed", 80.0)
	var extreme_jump: float = runner.call("jump_impulse_for_speed", 160.0)
	if low_jump <= 0.0 or fast_jump < low_jump * 1.5 or extreme_jump <= fast_jump:
		_fail("Jump launch strength does not increase sufficiently with speed.")
		return
	var bank: Transform3D = course.call("sample", 288.0)
	var entry: Transform3D = course.call("sample", 192.0)
	var exit_frame: Transform3D = course.call("sample", 384.0)
	if absf(bank.basis.x.y) < 0.35 or entry.basis.z.dot(exit_frame.basis.z) > 0.94:
		_fail("Bank or turn geometry was not generated.")
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
	# All ten shapes must exist in the opening sequence; no vertical loops.
	var shapes := {}
	for data in chunks.values():
		if str(data["kind"]) == "INVERSION":
			_fail("Vertical loops must no longer generate.")
			return
		for piece in data["hazards"]:
			shapes[int(piece["group"]["shape"])] = true
	if shapes.size() != 11:
		_fail("Opening sections did not introduce all ten obstacle shapes and route gates.")
		return
	if float(course.call("lane_limit")) < 20.0:
		_fail("Track steering width was not expanded.")
		return
	var color_a: Color = course.call("track_color", 191.99)
	var color_b: Color = course.call("track_color", 192.01)
	var color_far: Color = course.call("track_color", 3000.0)
	if absf(color_a.r - color_b.r) + absf(color_a.g - color_b.g) + absf(color_a.b - color_b.b) > 0.002 or color_a.is_equal_approx(color_far):
		_fail("Distance-based colors are discontinuous or do not change.")
		return
	# Check both camera modes through entire wide roll sections, at both edges.
	for s in range(768, 1152, 3):
		for lane_test: float in [-20.0, 0.0, 20.0]:
			runner.set("distance", float(s))
			runner.set("lane", lane_test)
			runner.call("sync_pose", course)
			for fp in [false, true]:
				game.set("first_person", fp)
				game.call("_update_camera", 1.0 / 60.0)
				if float(game.get("camera_track_clearance")) < 1.0:
					_fail("Camera crossed the running surface during a bank.")
					return
	game.set("first_person", false)
	var gate_parts: Array[Dictionary] = chunks[2]["hazards"]
	var gate: Dictionary = {}
	for piece in gate_parts:
		if bool(piece["group"].get("gate", false)):
			gate = piece
			break
	if gate.is_empty():
		_fail("A mandatory route gate is missing.")
		return
	var gate_s: float = gate["s"]
	var open_lane: float = gate["group"]["opening"]
	if int(course.call("swept_obstacles", gate_s - 3.0, gate_s + 3.0, open_lane, open_lane, 0.0, 0.0)) != 0:
		_fail("The route gate opening is not traversable.")
		return
	var blocked_lane: float = gate["lane"]
	if int(course.call("swept_obstacles", gate_s - 3.0, gate_s + 3.0, blocked_lane, blocked_lane, 0.0, 0.0)) != 1:
		_fail("The route gate wall failed to penalize a bad lane.")
		return
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
	print("PASS: wide tessellated banks, continuous distance colors, ten obstacle shapes, seamless streaming")
	game.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	push_error("GAMEPLAY REGRESSION: " + reason)
	quit(1)
