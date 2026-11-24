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
	course.set("showcase_layout", true)
	game.call("_restart")
	if not bool(runner.call("can_slide_on_grade", 0.25)):
		_fail("Uphill sliding must be available.")
		return
	if float(runner.call("step_speed", 80.0, 0.2, true, true, 1.0)) >= 75.0 or float(runner.call("step_speed", 80.0, 0.2, true, true, 1.0)) < 60.0:
		_fail("Uphill sliding must drain momentum without excessive braking.")
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
	# Pause freezes all simulation state, including storm and timer.
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	var before_distance: float = runner.get("distance")
	var before_storm: float = storm.get("front_s")
	var before_time: float = game.get("run_time")
	game.call("_input", escape)
	game.call("_physics_process", 1.0)
	if not bool(game.get("paused")) or float(runner.get("distance")) != before_distance or float(storm.get("front_s")) != before_storm or float(game.get("run_time")) != before_time:
		_fail("Pause did not freeze simulation.")
		return
	game.call("_show_options", true)
	game.call("_set_units", 1, false)
	if str(game.call("_speed_units")) != "MPH" or int(game.call("_speed_display", 10.0)) != 22 or str(game.call("_distance_display", 100.0)) != "328 ft" or str(game.call("_distance_display", 1609.344)) != "1.00 mi":
		_fail("Imperial conversion failed.")
		return
	game.call("_input", escape)
	var options_control: Control = game.get("options_page")
	if options_control.visible or not bool(game.get("paused")):
		_fail("Escape in options must return to pause menu.")
		return
	game.call("_set_units", 0, false)
	if str(game.call("_speed_units")) != "KM/H" or int(game.call("_speed_display", 10.0)) != 36 or str(game.call("_distance_display", 100.0)) != "100 m":
		_fail("Metric conversion failed.")
		return
	game.call("_input", escape)
	if bool(game.get("paused")):
		_fail("Escape did not resume the run.")
		return
	# Controller menu and camera actions must work for any device index.
	var pad := InputEventJoypadButton.new()
	pad.device = 2
	pad.pressed = true
	pad.button_index = JOY_BUTTON_START
	game.call("_input", pad)
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	game.call("_input", pad)
	pad.button_index = JOY_BUTTON_A
	game.call("_input", pad)
	if not bool(game.get("paused")) or not options_control.visible:
		_fail("Controller could not navigate pause menu.")
		return
	pad.button_index = JOY_BUTTON_DPAD_RIGHT
	game.call("_input", pad)
	if not bool(game.get("imperial")):
		_fail("Controller could not change units.")
		return
	pad.button_index = JOY_BUTTON_DPAD_LEFT
	game.call("_input", pad)
	pad.button_index = JOY_BUTTON_B
	game.call("_input", pad)
	pad.button_index = JOY_BUTTON_START
	game.call("_input", pad)
	if bool(game.get("paused")) or bool(game.get("imperial")):
		_fail("Controller could not back out and resume.")
		return
	var view_before: bool = game.get("first_person")
	pad.button_index = JOY_BUTTON_Y
	game.call("_input", pad)
	if bool(game.get("first_person")) == view_before:
		_fail("Controller camera toggle failed.")
		return
	game.call("_input", pad)
	if absf(float(runner.call("pad_axis", 0.1))) > 0.001 or absf(float(runner.call("pad_axis", -1.0)) + 1.0) > 0.001:
		_fail("Controller deadzone failed.")
		return
	# Controls must remain independent: C slides, Tab toggles camera.
	for code in [KEY_SHIFT, KEY_CTRL, KEY_C]:
		if not bool(runner.call("is_slide_key", code)):
			_fail("A required slide key is missing.")
			return
	if bool(runner.call("is_slide_key", KEY_TAB)):
		_fail("Tab must not slide.")
		return
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_C
	var original_view: bool = game.get("first_person")
	game.call("_input", key)
	if bool(game.get("first_person")) != original_view:
		_fail("C still toggles the camera.")
		return
	key.keycode = KEY_TAB
	game.call("_input", key)
	if bool(game.get("first_person")) == original_view:
		_fail("Tab does not toggle camera.")
		return
	game.call("_input", key)
	if float(runner.call("step_speed", 22.0, 0.0, true, true, 1.0)) < 29.9 or float(runner.call("step_speed", 22.0, -0.2, true, true, 1.0)) < 49.9:
		_fail("Slide acceleration is weaker than the revised target.")
		return
	# Sustained grounded sliding must always retain full effectiveness.
	var continuous_speed := 25.0
	for i in range(600):
		continuous_speed = float(runner.call("step_speed", continuous_speed, -0.2, true, true, 1.0 / 60.0))
	if continuous_speed < 150.0:
		_fail("Continuous downhill sliding incorrectly loses grip.")
		return
	# The opening hill has negative normal curvature at 16 m.
	# Slow players follow it, fast players leave the track without jumping.
	var slow_normal: float = runner.call("relative_normal_acceleration", course, 16.0, 0.0, 22.0)
	var fast_normal: float = runner.call("relative_normal_acceleration", course, 16.0, 0.0, 65.0)
	var lift: float = runner.call("natural_lift_impulse", fast_normal, 65.0)
	if slow_normal >= 0.0 or fast_normal <= 1.5 or lift <= 0.0 or lift > 2.6:
		_fail("Terrain curvature did not distinguish low-speed contact from high-speed lift-off.")
		return
	runner.set("distance", 16.0)
	runner.set("lane", 0.0)
	runner.set("height", 0.0)
	runner.set("speed", 65.0)
	runner.set("vertical_speed", 0.0)
	runner.set("queued_jump", false)
	runner.call("sync_pose", course)
	var peak := 0.0
	var airborne_frames := 0
	for i in range(30):
		runner.call("tick", 1.0 / 60.0, course)
		peak = maxf(peak, float(runner.get("height")))
		if not bool(runner.call("is_grounded")):
			airborne_frames += 1
	if peak < 0.1 or peak > 6.0 or airborne_frames < 6:
		_fail("Natural takeoff is missing or excessively strong.")
		return
	if float(runner.call("landing_speed", 80.0, 35.0)) >= 70.0 or absf(float(runner.call("landing_speed", 80.0, 4.0)) - 80.0) > 0.001:
		_fail("Hard landings must lose momentum while gentle landings preserve it.")
		return
	# Flight retains its world-space orientation even when the road rolls.
	game.call("_restart")
	runner.set("distance", 784.0)
	runner.set("speed", 40.0)
	runner.call("sync_pose", course)
	var takeoff_basis: Basis = runner.transform.basis
	runner.call("request_jump")
	for i in range(18):
		runner.call("tick", 1.0 / 60.0, course)
		if bool(runner.call("is_grounded")) or runner.transform.basis.y.dot(takeoff_basis.y) < 0.999:
			_fail("Airborne body was rotated by a changing bank.")
			return
	# Ground contact is immediate while the landing orientation eases in.
	game.call("_restart")
	runner.set("distance", 864.0)
	runner.set("lane", 0.0)
	runner.set("grounded", false)
	var landing_frame: Transform3D = course.call("sample", 864.0)
	# A deliberately mismatched flight pose makes a snap easy to detect.
	var pre_contact := landing_frame.basis.rotated(-landing_frame.basis.z, PI * 0.5)
	runner.set("air_basis", pre_contact)
	runner.transform = Transform3D(pre_contact, landing_frame.origin + landing_frame.basis.y * 0.01)
	game.call("_update_camera", 1.0 / 60.0)
	runner.call("_finish_landing", course)
	if not bool(runner.call("is_grounded")) or runner.position.distance_to(landing_frame.origin) > 0.01 or runner.transform.basis.y.dot(pre_contact.y) < 0.999:
		_fail("Landing snapped the body orientation or delayed physical contact.")
		return
	runner.set("landing_blend", 0.25)
	runner.call("sync_pose", course)
	var midway_up := runner.transform.basis.y
	if midway_up.dot(pre_contact.y) < 0.65 or midway_up.dot(landing_frame.basis.y) < 0.65:
		_fail("Landing blend did not interpolate between flight and ground.")
		return
	game.call("_update_camera", 1.0 / 60.0)
	runner.set("landing_blend", 0.0)
	runner.call("sync_pose", course)
	if runner.transform.basis.y.dot(landing_frame.basis.y) < 0.999:
		_fail("Landing blend did not finish aligned to the track.")
		return
	# Head-first contact with a ceiling is blocked before the feet cross.
	game.call("_restart")
	var ceiling: Transform3D = course.call("surface_frame", 864.0, 0.0, 1)
	var head_first := ceiling.basis.rotated(-ceiling.basis.z, PI)
	runner.set("distance", 864.0)
	runner.set("lane", 0.0)
	runner.set("grounded", false)
	runner.set("air_basis", head_first)
	runner.set("air_velocity", -ceiling.basis.z * 22.0 - ceiling.basis.y * 10.0)
	runner.transform = Transform3D(head_first, ceiling.origin + ceiling.basis.y * 2.3)
	runner.call("_advance_flight", 0.1, course, 0.0)
	var head_projection: Vector3 = course.call("project_position", runner.position + head_first.y * 1.5 - head_first.z * 0.15, float(runner.get("distance")))
	var head_gap: float = course.call("surface_clearance", head_projection.x, head_projection.y, head_projection.z, 1)
	if bool(runner.call("is_grounded")) or head_gap < 0.34:
		_fail("Head-first collision passed through the ceiling.")
		return
	# Jump on both sides of a fast twisting bank. No foot may cross
	# through the slab even when the local normal rotates during flight.
	for bank_side: int in [1, -1]:
		game.call("_restart")
		runner.set("distance", 1010.0)
		runner.set("lane", 0.0)
		runner.set("speed", 90.0)
		runner.set("surface_side", bank_side)
		runner.call("sync_pose", course)
		runner.call("request_jump")
		for jump_tick in range(36):
			runner.call("tick", 1.0 / 60.0, course)
			if bool(runner.get("fallen")):
				break
			if not bool(runner.call("is_grounded")):
				var p: Vector3 = course.call("project_position", runner.position, float(runner.get("distance")))
				if bool(course.call("support_at", p.x, p.y)):
					var top_gap: float = course.call("surface_clearance", p.x, p.y, p.z, 1)
					var bottom_gap: float = course.call("surface_clearance", p.x, p.y, p.z, -1)
					if top_gap < -0.04 and bottom_gap < -0.04:
						_fail("Jump through twisting bank penetrated track slab.")
						return
	# A 180-bank underside is a real rideable face, not a visual duplicate.
	game.call("_restart")
	var underside: Transform3D = course.call("surface_frame", 864.0, 0.0, -1)
	var topside: Transform3D = course.call("surface_frame", 864.0, 0.0, 1)
	if underside.basis.y.dot(topside.basis.y) > -0.999 or underside.origin.distance_to(topside.origin) < 0.4:
		_fail("Track faces are not separate opposing surfaces.")
		return
	runner.set("distance", 864.0)
	runner.set("lane", 0.0)
	runner.set("grounded", false)
	runner.set("air_basis", underside.basis)
	runner.set("air_velocity", -underside.basis.z * 22.0 - underside.basis.y * 10.0)
	runner.transform = Transform3D(underside.basis, underside.origin + underside.basis.y * 0.5)
	runner.call("_advance_flight", 0.1, course, 0.0)
	if not bool(runner.call("is_grounded")) or int(runner.get("surface_side")) != -1:
		_fail("Runner cannot attach to the underside.")
		return
	game.call("_update_camera", 1.0 / 60.0)
	if float(game.get("camera_track_clearance")) < 0.5:
		_fail("Camera clips through the underside.")
		return
	# The preceding underside test streamed to chunk 4, recycling chunk 1.
	# Reload the opening course so we actually test a loaded ramp.
	game.call("_restart")
	# Ramp only occupies a side lane; centre and opposite side stay flat.
	var ramp_s := 192.0 + 99.0
	if not bool(course.call("has_distance", ramp_s)):
		_fail("Ramp test did not load its target chunk.")
		return
	var ramp_lane: float = course.call("ramp_center", 1)
	if float(course.call("surface_lift", ramp_s, ramp_lane)) < 5.0 or absf(float(course.call("surface_lift", ramp_s, -ramp_lane))) > 0.001 or absf(float(course.call("surface_lift", ramp_s, 0.0))) > 0.001:
		_fail("Partial-width ramp does not leave a flat bypass.")
		return
	# At takeoff the camera retains its previous offset instead of snapping.
	game.call("_restart")
	game.call("_update_camera", 1.0 / 60.0)
	var previous_arm: Vector3 = game.get("camera_offset")
	runner.call("request_jump")
	runner.call("tick", 1.0 / 60.0, course)
	game.call("_update_camera", 1.0 / 60.0)
	var new_arm: Vector3 = game.get("camera_offset")
	if new_arm.distance_to(previous_arm) > 0.2:
		_fail("Camera arm snapped at takeoff.")
		return
	# First-person sliding has a distinct visual cue and lowered eye height.
	game.call("_restart")
	game.set("first_person", true)
	runner.set("is_sliding", true)
	game.call("_update_camera", 1.0)
	game.call("_update_hud")
	var cue: Control = game.get("slide_indicator")
	if not cue.visible or float(game.get("slide_eye_height")) > 0.9:
		_fail("First-person slide indication is missing.")
		return
	runner.set("is_sliding", false)
	game.call("_update_camera", 1.0)
	game.call("_update_hud")
	if cue.visible or float(game.get("slide_eye_height")) < 1.5:
		_fail("Slide indication did not clear after standing.")
		return
	game.set("first_person", false)
	# Crossing a road edge must detach instead of clamping the lane.
	game.call("_restart")
	runner.set("lane", float(course.call("half_width_at", 8.0)) - 0.1)
	runner.set("touch_axis", 1.0)
	runner.set("lateral_speed", 25.0)
	runner.call("sync_pose", course)
	runner.call("tick", 1.0 / 60.0, course)
	if bool(runner.call("is_grounded")):
		_fail("Player remained tethered at the road edge.")
		return
	for i in range(240):
		runner.call("tick", 1.0 / 60.0, course)
		if bool(runner.get("fallen")):
			break
	if not bool(runner.get("fallen")):
		_fail("Leaving the track did not eventually cause a fall.")
		return
	game.call("_physics_process", 1.0 / 60.0)
	if not bool(game.get("run_finished")):
		_fail("Falling off must end the run.")
		return
	game.call("_restart")
	# Roll curvature is not a launch ramp, even near the edge at high speed.
	for s in [780.0, 810.0, 864.0, 1000.0, 1056.0, 1100.0]:
		for edge: float in [-20.0, 20.0]:
			if float(runner.call("relative_normal_acceleration", course, s, edge, 250.0, 25.0)) > 0.0:
				_fail("High-degree banking generates false lift.")
				return
	game.call("_restart")
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
	# Roll progression must retain full rotations with a lower peak rate.
	var max_roll_step := 0.0
	for i in range(1, 193):
		var before_roll: Transform3D = course.call("sample", 768.0 + float(i - 1))
		var after_roll: Transform3D = course.call("sample", 768.0 + float(i))
		max_roll_step = maxf(max_roll_step, before_roll.basis.y.angle_to(after_roll.basis.y))
	if max_roll_step > 0.047:
		_fail("180 bank rotates too abruptly per metre.")
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
	if float(course.call("lane_limit")) < 59.0:
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
	# Stream the new terrain showcase in order, verifying geometry and width.
	for index in range(6, 16):
		course.call("stream", float(index) * 192.0)
		var kind: String = course.call("section_name", float(index) * 192.0 + 96.0)
		var start_s := float(index) * 192.0
		var expected: Array[String] = ["LONG DESCENT", "S CURVE", "NARROW BRIDGE", "ROLLING RIDGES", "CAMBER WAVE", "STEEP CLIMB", "DROP AND RECOVERY", "BANKED DESCENT", "WIDE BASIN", "CHICANE"]
		if kind != expected[index - 6]:
			_fail("Missing terrain profile: " + expected[index - 6])
			return
		var middle: Transform3D = course.call("sample", start_s + 96.0)
		if kind == "LONG DESCENT" and -middle.basis.z.y > -0.25:
			_fail("Descent has no downhill grade.")
			return
		if kind == "STEEP CLIMB":
			if -middle.basis.z.y < 0.19 or -middle.basis.z.y > 0.33:
				_fail("Climb has no uphill grade.")
				return
			var bypass: float = course.call("bypass_center", index)
			var alternate: Transform3D = course.call("surface_frame", start_s + 96.0, bypass, 1)
			if -alternate.basis.z.y > 0.025 or float(course.call("recovery_accel", start_s + 96.0, bypass, 1)) < 17.9 or float(course.call("recovery_accel", start_s + 96.0, 0.0, 1)) > 0.001:
				_fail("Climb bypass or marked recovery lane is missing.")
				return
		var width: float = course.call("lane_limit", start_s + 96.0)
		if (kind == "NARROW BRIDGE" and (width < 29.0 or width > 30.0)) or (kind == "WIDE BASIN" and width < 77.0):
			_fail("Variable width terrain was not generated.")
			return
		var left: Transform3D = course.call("sample", start_s - 0.01)
		var right: Transform3D = course.call("sample", start_s + 0.01)
		if left.origin.distance_to(right.origin) > 0.1 or left.basis.y.dot(right.basis.y) < 0.99:
			_fail("New profile has a discontinuous seam.")
			return
	# Sustained sideways and upside-down straights retain an exact roll
	# for a full chunk and across the adjacent transition seams.
	for entry_index in [16, 19]:
		var entry_s := float(entry_index) * 192.0
		course.call("stream", entry_s + 192.0)
		var expected_kind := "WALL RUN" if entry_index == 16 else "CEILING RUN"
		var held: Transform3D = course.call("sample", entry_s + 192.0)
		for offset in range(192, 385, 12):
			var s := entry_s + float(offset)
			var frame: Transform3D = course.call("sample", s)
			if frame.basis.y.dot(held.basis.y) < 0.9999 or (entry_index == 16 and absf(frame.basis.y.y) > 0.001) or (entry_index == 19 and frame.basis.y.y > -0.999):
				_fail("Sustained roll orientation was not held.")
				return
		if str(course.call("section_name", entry_s + 288.0)) != expected_kind:
			_fail("Sustained roll section is missing.")
			return
		for boundary in [192.0, 384.0, 576.0]:
			var before: Transform3D = course.call("sample", entry_s + boundary - 0.01)
			var after: Transform3D = course.call("sample", entry_s + boundary + 0.01)
			if before.origin.distance_to(after.origin) > 0.1 or before.basis.y.dot(after.basis.y) < 0.999:
				_fail("Wall/ceiling transition seam is discontinuous.")
				return
		runner.set("distance", entry_s + 220.0)
		runner.set("lane", 0.0)
		runner.set("surface_side", 1)
		runner.set("grounded", true)
		runner.set("speed", 40.0)
		runner.call("sync_pose", course)
		for i in range(30):
			runner.call("tick", 1.0 / 60.0, course)
		if not bool(runner.call("is_grounded")) or runner.transform.basis.y.dot(held.basis.y) < 0.999:
			_fail("Player cannot remain attached on sustained wall/ceiling run.")
			return
		for fp in [false, true]:
			game.set("first_person", fp)
			game.call("_update_camera", 1.0 / 60.0)
			var camera: Camera3D = game.get("view_camera")
			if absf(camera.basis.x.y) > 0.001 or camera.basis.y.y < 0.0:
				_fail("Camera rolled with the sustained wall/ceiling.")
				return
			if float(game.get("camera_track_clearance")) < 0.8:
				_fail("Camera crossed a sustained wall/ceiling surface.")
				return
	game.set("first_person", false)
	course.call("stream", 6500.0)
	chunks = course.get("chunks")
	if chunks.size() > 8 or not bool(course.call("has_distance", 6700.0)) or chunks.has(0):
		_fail("Endless streaming failed to recycle old track chunks.")
		return
	game.call("_restart")
	var original_speed: float = storm.get("speed")
	var original_s: float = storm.get("front_s")
	storm.call("advance", 10.0)
	if absf(float(storm.get("speed")) - (original_speed + 11.1)) > 0.01 or float(storm.get("front_s")) <= original_s:
		_fail("Storm must advance at the revised gentler acceleration rate.")
		return
	game.call("_lose", "TEST")
	if not bool(game.get("run_finished")):
		_fail("Storm failure did not finish the run.")
		return
	game.call("_restart")
	if bool(game.get("run_finished")) or absf(float(storm.get("speed")) - original_speed) > 0.001 or absf(float(storm.get("front_s")) - original_s) > 0.001:
		_fail("Restart did not restore the storm.")
		return
	# Reserve builds from sliding and covers uphill loss without adding speed.
	runner.set("speed", 22.0)
	runner.set("momentum_reserve", 0.0)
	runner.call("_banked_slide", 0.0, 1.0)
	var reserve: float = runner.get("momentum_reserve")
	if reserve <= 0.0:
		_fail("Clean sliding did not earn momentum reserve.")
		return
	runner.set("momentum_reserve", 30.0)
	runner.set("speed", 60.0)
	runner.call("_banked_slide", 0.2, 1.0)
	if absf(float(runner.get("speed")) - 60.0) > 0.01 or float(runner.get("momentum_reserve")) >= 30.0:
		_fail("Uphill momentum reserve did not absorb the speed loss.")
		return
	runner.set("grounded", false)
	runner.set("air_basis", Basis.IDENTITY)
	runner.set("air_velocity", Vector3(0, -8, -40))
	if not bool(runner.call("_double_jump")) or bool(runner.call("_double_jump")):
		_fail("Double jump must be available exactly once per flight.")
		return
	var double_velocity: Vector3 = runner.get("air_velocity")
	if double_velocity.y <= 0.0 or absf(double_velocity.z + 40.0) > 0.01:
		_fail("Double jump injected forward speed or failed to lift.")
		return
	game.call("_restart")
	var shortcut_lane: float = course.call("shortcut_center", 0)
	var center_hill: Transform3D = course.call("surface_frame", 145.0, 0.0, 1)
	var side_hill: Transform3D = course.call("surface_frame", 145.0, shortcut_lane, 1)
	if not bool(course.call("shortcut_at", 145.0, shortcut_lane)) or -side_hill.basis.z.y >= -center_hill.basis.z.y:
		_fail("Shortcut did not reduce the hill grade.")
		return
	var gate_chunks: Dictionary = course.get("chunks")
	var reward_gate: Dictionary = {}
	for piece in gate_chunks[2]["hazards"]:
		if bool(piece["group"].get("gate", false)):
			reward_gate = piece
			break
	if reward_gate.is_empty():
		_fail("Reward gate is absent.")
		return
	var reward_s: float = reward_gate["s"]
	var reward_lane: float = reward_gate["group"]["opening"]
	if int(course.call("collect_clean_gates", reward_s - 3.0, reward_s + 3.0, reward_lane, reward_lane, 0.0, 0.0)) != 1 or int(course.call("collect_clean_gates", reward_s - 3.0, reward_s + 3.0, reward_lane, reward_lane, 0.0, 0.0)) != 0:
		_fail("Clean gate reward is missing or repeatable.")
		return
	var map_control: Control = game.get("minimap")
	var low_color: Color = map_control.call("elevation_color", -35.0)
	var high_color: Color = map_control.call("elevation_color", 35.0)
	if low_color.is_equal_approx(high_color):
		_fail("Hypsometric minimap has no elevation distinction.")
		return
	# Exercise adaptive generation independently of the fixed-speed intro.
	if float(course.call("bank_length", "360 BANK", 195.0)) < 575.0 or float(course.call("bank_length", "HILLS", 195.0)) != 192.0:
		_fail("High-speed banking length does not scale.")
		return
	course.call("stream", 384.0, 195.0)
	var starts: Array[float] = course.get("chunk_starts")
	# Index 7 is an S-curve generated at the higher speed.
	if starts[8] - starts[7] < 575.0:
		_fail("New high-speed bank did not stretch.")
		return
	var seam_s: float = starts[8]
	var before_seam: Transform3D = course.call("sample", seam_s - 0.01)
	var after_seam: Transform3D = course.call("sample", seam_s + 0.01)
	if before_seam.origin.distance_to(after_seam.origin) > 0.1 or before_seam.basis.y.dot(after_seam.basis.y) < 0.999:
		_fail("Stretched bank seam is discontinuous.")
		return
	# After the showcase, a demanding sequence is followed by recovery.
	game.call("_restart")
	course.call("stream", 21.0 * 192.0)
	var all_chunks: Dictionary = course.get("chunks")
	var found_recovery := false
	for data in all_chunks.values():
		if str(data["kind"]) == "RECOVERY RUN":
			found_recovery = true
			if not data["hazards"].is_empty():
				_fail("Recovery section contains forced obstacles.")
				return
		if not data.has("forecast") or not data["forecast"].has("min_gap"):
			_fail("Generated section has no route validation result.")
			return
	if not found_recovery:
		_fail("Momentum-aware generation did not schedule a recovery run.")
		return
	# Validate the actual special track surfaces and skill-based rewards.
	game.call("_restart")
	course.call("stream", 25.0 * 192.0)
	var split_s := 23.0 * 192.0 + 96.0
	var gap_s := 24.0 * 192.0 + 84.0
	if bool(course.call("support_at", split_s, 0.0)) or not bool(course.call("support_at", split_s, -28.0)) or bool(course.call("support_at", gap_s, 32.0)) or not bool(course.call("support_at", gap_s, -32.0)):
		_fail("Split and gap routes lack an open, supported bypass.")
		return
	var tunnel_s := 25.0 * 192.0 + 96.0
	var tunnel_mid: Transform3D = course.call("surface_frame", tunnel_s, 0.0, 1)
	var tunnel_wall: Transform3D = course.call("surface_frame", tunnel_s, 54.0, 1)
	if tunnel_wall.basis.y.dot(tunnel_mid.basis.y) > -0.7:
		_fail("Corkscrew tunnel does not wrap around the runner.")
		return
	# The inverted curled wall extends far below the centerline.
	# A player only two meters off that wall must not falsely lose.
	runner.set("distance", tunnel_s)
	runner.set("lane", 54.0)
	runner.set("surface_side", 1)
	runner.set("grounded", false)
	runner.set("fallen", false)
	runner.set("air_time", 0.0)
	runner.set("air_basis", tunnel_wall.basis)
	runner.set("speed", 40.0)
	runner.set("air_velocity", -tunnel_wall.basis.z * 40.0)
	runner.transform = Transform3D(tunnel_wall.basis, tunnel_wall.origin + tunnel_wall.basis.y * 2.0)
	var tunnel_projection: Vector3 = course.call("project_position", runner.position, tunnel_s)
	if float(course.call("distance_to_rideable_surface", runner.position, tunnel_projection)) > 3.0:
		_fail("Tunnel proximity uses the centerline instead of its curved wall.")
		return
	runner.call("_advance_flight", 1.0 / 60.0, course, 0.0)
	if bool(runner.get("fallen")):
		_fail("Corkscrew falsely reports a fall near its rideable wall.")
		return
	var pipe_s := 26.0 * 192.0 + 96.0
	var pipe_center: Transform3D = course.call("surface_frame", pipe_s, 0.0, 1)
	var pipe_edge: Transform3D = course.call("surface_frame", pipe_s, 50.0, 1)
	if pipe_edge.origin.y - pipe_center.origin.y < 15.0:
		_fail("Halfpipe has no curved elevated wall.")
		return
	var stacked_s := 27.0 * 192.0 + 96.0
	var upper: Transform3D = course.call("surface_frame", stacked_s, -30.0, 1)
	var lower: Transform3D = course.call("surface_frame", stacked_s, 30.0, 1)
	if upper.origin.y - lower.origin.y < 20.0 or Vector2(upper.origin.x - lower.origin.x, upper.origin.z - lower.origin.z).length() > 1.0:
		_fail("Stacked routes do not physically overlap.")
		return
	var stream_s := 28.0 * 192.0 + 96.0
	var stream_lane: float = course.call("slipstream_center", 28, 96.0)
	if float(course.call("slipstream_accel", stream_s, stream_lane)) < 13.0:
		_fail("Slipstream does not accelerate the runner.")
		return
	runner.set("speed", 40.0)
	var slope := Transform3D(Basis(Vector3.RIGHT, -0.40), Vector3.ZERO)
	var result: Dictionary = runner.call("landing_result", slope, Vector3(0.0, -24.0, -40.0), true, 0.3)
	if float(result["transfer"]) <= 0.0 or float(result["dive_bonus"]) <= 0.0:
		_fail("Downhill dive does not transfer momentum.")
		return
	if str(course.call("biome_name", 0.0)) == str(course.call("biome_name", 2500.0)):
		_fail("Terrain biomes do not change.")
		return
	# Daily seeds, challenge rules and practice record exclusion.
	var extras = game.get("extras")
	var seed_a: int = extras.daily_seed("2026-11-23")
	if seed_a != int(extras.daily_seed("2026-11-23")) or seed_a == int(extras.daily_seed("2026-11-24")):
		_fail("Daily seed does not follow the UTC date.")
		return
	game.set("mode", 1)
	game.call("_restart")
	var daily_seed: int = game.get("run_seed")
	game.call("_restart")
	if int(game.get("run_seed")) != daily_seed or not bool(course.get("fixed_daily_layout")):
		_fail("Daily run did not preserve its deterministic course.")
		return
	game.set("mode", 2)
	game.call("_restart")
	runner.call("request_jump")
	if bool(runner.get("queued_jump")):
		_fail("No-jump challenge permits jumping.")
		return
	game.set("mode", 5)
	game.call("_restart")
	var storm_before_practice: float = storm.get("front_s")
	game.call("_physics_process", 0.1)
	if float(storm.get("front_s")) != storm_before_practice:
		_fail("Practice mode advances the storm.")
		return
	game.set("mode", 0)
	game.call("_restart")
	# Replay captures actual adaptive geometry and interpolated recorded
	# motion. Playback and seeking must never run gameplay simulation.
	var recorder = game.get("replay")
	var recorded_seed: int = game.get("run_seed")
	var start_pose: Transform3D = runner.transform
	for i in range(12):
		game.call("_physics_process", 1.0 / 60.0)
	var final_pose: Transform3D = runner.transform
	game.call("_lose", "REPLAY TEST")
	if not bool(recorder.available()) or int(recorder.archived["seed"]) != recorded_seed:
		_fail("Completed run was not recorded.")
		return
	game.call("_start_replay")
	if not bool(game.get("replay_active")) or runner.position.distance_to(start_pose.origin) > 0.15:
		_fail("Replay did not begin at the recorded pose.")
		return
	game.call("_seek_replay", float(recorder.duration()))
	if runner.position.distance_to(final_pose.origin) > 0.15 or not bool(course.get("replay_layout")):
		_fail("Replay seeking did not reproduce recorded motion and layout.")
		return
	var frozen: Vector3 = runner.position
	game.call("_physics_process", 1.0)
	if runner.position.distance_to(frozen) > 0.001:
		_fail("Replay unexpectedly runs live gameplay physics.")
		return
	game.call("_restart")
	if bool(game.get("replay_active")) or bool(course.get("replay_layout")):
		_fail("Replay exit did not restore normal generation.")
		return
	# Live runs use seeded varied terrain from the beginning, rather
	# than the old fixed regression sequence.
	course.set("showcase_layout", false)
	course.set("fixed_daily_layout", true)
	var signatures: Dictionary = {}
	var first_signature := ""
	for seed_value: int in [4731, 9127, 18304, 28419, 4731]:
		course.call("reset_course", seed_value)
		var recipes: Array = course.get("replay_recipes")
		var signature := ""
		for recipe in recipes:
			signature += str(recipe["kind"]) + ":" + str(snappedf(float(recipe["length"]), 0.01)) + "|"
		if seed_value == 4731:
			if first_signature.is_empty():
				first_signature = signature
			elif signature != first_signature:
				_fail("Same daily seed did not reproduce the generated route.")
				return
		signatures[signature] = true
	if signatures.size() < 4:
		_fail("Different seeds generate repeating opening courses.")
		return
	print("PASS: slide-only acceleration, unlimited speed, hazards, and advancing storm")
	print("PASS: wide tessellated banks, continuous distance colors, ten obstacle shapes, seamless streaming")
	game.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	push_error("GAMEPLAY REGRESSION: " + reason)
	quit(1)
