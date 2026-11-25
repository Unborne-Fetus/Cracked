extends SceneTree

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate() as Node3D
	root.add_child(game)
	await physics_frame
	game.set_physics_process(false)
	game.set_process(false)
	var map_view: Control = game.get("minimap")
	map_view.set_process(false)
	map_view.hide()
	var runner: Node3D = game.get("runner")
	var storm: Node3D = game.get("storm")
	var course: Node3D = game.get("course")
	course.set("showcase_layout", true)
	game.call("_restart")
	await process_frame
	# Trail samples are world-space, not HUD lines, and respect the toggle.
	var run_effects: Node = game.get("effects")
	var rider_trail: MeshInstance3D = run_effects.get("trail")
	run_effects.call("set_trails_enabled", true)
	run_effects.call("sample_trail", Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3.ZERO, 90.0, 0.02)
	run_effects.call("sample_trail", Transform3D(Basis.IDENTITY, Vector3(2,1,-4)), Vector3.ZERO, 90.0, 0.02)
	if not rider_trail.visible or rider_trail.mesh.get_surface_count() != 2:
		_fail("World-space rider trail failed to generate.")
		return
	run_effects.call("sample_trail", Transform3D(Basis.IDENTITY, Vector3(-998,1,-8)), Vector3(1000,0,0), 90.0, 0.02)
	if (run_effects.get("trail_points") as Array).size() != 3:
		_fail("Rider trail broke during origin shift.")
		return
	run_effects.call("set_trails_enabled", false)
	if rider_trail.visible or rider_trail.mesh.get_surface_count() != 0:
		_fail("Rider trail toggle does not clear the mesh.")
		return
	run_effects.call("set_trails_enabled", bool(game.get("extras").get("trails")))
	var settings_page: Control = game.get("options_page")
	var controls_menu: Control = game.get("controls_page")
	if (game.get("cosmetic_picker") as Control).get_parent() != settings_page or (game.get("trails_toggle") as Control).get_parent() != settings_page or (game.get("binding_picker") as Control).get_parent() != controls_menu:
		_fail("Settings are not grouped under Options.")
		return
	if absf(float(run_effects.call("soundtrack_gain", true, false, 0.0)) - 0.42) > 0.001 or absf(float(run_effects.call("soundtrack_gain", true, false, 200.0)) - 0.42) > 0.001 or float(run_effects.call("soundtrack_gain", false, true, 200.0)) != 0.0 or float(run_effects.call("soundtrack_gain", true, true, 200.0)) <= float(run_effects.call("soundtrack_gain", true, true, 20.0)):
		_fail("Soundtrack mute and adaptive gain are not independent.")
		return
	# Normal run stats expose exactly distance, time and best.
	var stats_stack: Node = (game.get("distance_label") as Label).get_parent()
	if stats_stack.get_child_count() != 3 or (game.get("minimap") as Control).visible or not (game.get("record_label") as Label).text.begins_with("BEST"):
		_fail("Normal run HUD contains extra stats.")
		return
	# The avatar is articulated geometry, with a separate curved deck.
	var model: Node3D = runner.get("rider_model")
	var flip_board: Node3D = runner.get("board_pivot")
	if model == null or flip_board == null or model.get_child_count() < 10 or flip_board.get_child_count() != 5:
		_fail("Block rider or curved board geometry is missing.")
		return
	var sprite_camera: Camera3D = game.get("view_camera")
	var model_head: MeshInstance3D = model.get("head")
	var model_boots: Array = model.get("boots")
	model.call("pose",0.0,0.0,false,1.0)
	var neutral_head := model_head.position.y
	var neutral_foot: Vector3 = model_boots[0].position
	if neutral_head < 2.0:
		_fail("Taller rider stance is missing.")
		return
	model.call("pose", 0.6, 0.0, true, 0.24)
	var flick_foot: Vector3 = model_boots[0].position
	if flick_foot.y < neutral_foot.y + 0.15 or flick_foot.z > neutral_foot.z - 0.20:
		_fail("Kickflip is missing the leg tuck and front foot flick.")
		return
	model.call("pose", 0.6, 0.0, true, 0.98)
	var catch_foot: Vector3 = model_boots[0].position
	if catch_foot.distance_to(neutral_foot) > 0.15:
		_fail("Kickflip catch does not bring the foot back to the board.")
		return
	model.call("pose", 0.0, 0.0, false, 1.0, 0.0, 1.0)
	if model_head.position.y >= neutral_head - 0.12:
		_fail("Landing animation does not compress the knees.")
		return
	# All 24 air tricks must have independent signatures at mid-pose.
	var air_signatures: Dictionary = {}
	for trick_index in range(24):
		model.call("pose",0.5,0.0,true,1.0,0.0,0.0,0.0,false,0.0,float(trick_index)*1.15+0.575,1.0,0.0,0.0,0.0,{"flip_clear":true})
		var boot_a: Vector3 = model_boots[0].position
		var boot_b: Vector3 = model_boots[1].position
		var trick_signature := str(model.rotation.snapped(Vector3.ONE*0.01))+str(flip_board.rotation.snapped(Vector3.ONE*0.01))+str(boot_a.snapped(Vector3.ONE*0.01))+str(boot_b.snapped(Vector3.ONE*0.01))+str(model_head.position.snapped(Vector3.ONE*0.01))
		air_signatures[trick_signature] = true
	if air_signatures.size() < 20:
		_fail("Air idle library lacks at least twenty distinct poses.")
		return
	# Three autonomous air poses: shifty, grab, and one-foot.
	model.call("pose",0.5,0.0,true,1.0,0.0,0.0,0.0,false,0.0,0.575,1.0)
	if absf(flip_board.rotation.y) < 0.45:
		_fail("Air idle shifty does not move the board.")
		return
	model.call("pose",0.5,0.0,true,1.0,0.0,0.0,0.0,false,0.0,1.725,1.0)
	if absf(flip_board.rotation.x) < 0.2:
		_fail("Air idle grab has no deck tilt.")
		return
	model.call("pose",0.5,0.0,true,1.0,0.0,0.0,0.0,false,0.0,2.875,1.0)
	var trick_rear_foot: Vector3 = model_boots[1].position
	if trick_rear_foot.y < 0.45:
		_fail("One-foot idle trick does not lift the rear foot.")
		return
	model.call("pose",0.5,0.0,true,1.0,0.0,0.0,0.0,true,1.0,0.575,1.0)
	if absf(flip_board.rotation.y) > 0.01:
		_fail("Diving fails to override idle trick.")
		return
	model.call("pose",0.5,0.0,true,1.0,0.0,0.0,0.0,false,0.0,5.0*1.15+0.575,1.0,0.0,0.0,0.0,{"flip_clear":true})
	if absf(absf(model.rotation.x)-PI)>0.05:
		_fail("Air idle front flip missing.")
		return
	model.call("pose",0.0,0.0,false,1.0,0.0,0.0,0.0,false,0.0,0.0,0.0,0.0,0.0,0.0,{"ground_idle":0.5})
	if absf(absf(model.rotation.y)-PI)>0.05 or float(model.get("visual_lift"))<0.3:
		_fail("Ground idle hop/spin missing.")
		return
	var ceiling_treads: Node3D=model.get("treads")
	var gyro_probe: Node3D=model.get("gyro")
	if ceiling_treads.get_child_count()!=0 or gyro_probe.get_child_count()!=2:
		_fail("Obsolete surface vehicle geometry still exists.")
		return
	var glider_rig: Node3D=model.get("wings")
	model.call("pose",0.0,0.0,false,1.0,0.0,0.0,0.0,false,0.0,0.0,0.0,0.0,0.0,0.0,{"lightcycle":true,"glider":1.0,"glider_entry":0.5})
	if glider_rig.visible or glider_rig.get_child_count()!=0 or (model.get("engines") as Array).size()!=0:
		_fail("Removed glider can still deploy.")
		return
	# Loop branch reverses longitudinal direction at its crown, bypass
	# remains upright and forward. Test geometry independently of seeds.
	var loop_top: Transform3D = course.call("_loop_frame",Transform3D.IDENTITY,96.0,-30.0,640.0)
	var bypass_top: Transform3D = course.call("_loop_frame",Transform3D.IDENTITY,96.0,30.0,640.0)
	if loop_top.basis.y.y> -0.9 or bypass_top.basis.y.y<0.9 or loop_top.origin.y<bypass_top.origin.y+100.0:
		_fail("Optional loop has no inverted crest or separate bypass.")
		return
	runner.set("grounded", false)
	runner.set("kickflip_progress", 0.5)
	runner.call("update_rider_sprite", sprite_camera)
	if absf(absf(flip_board.rotation.z) - PI) > 0.02 or absf(model.rotation.z) > 0.01:
		_fail("Board-only kickflip rotated the rider or failed.")
		return
	runner.set("grounded", true)
	runner.set("kickflip_progress", 1.0)
	runner.call("update_rider_sprite", sprite_camera)
	if absf(flip_board.rotation.z) > 0.01:
		_fail("Board did not reset flat on landing.")
		return
	runner.call("set_first_person", true)
	var sprite_avatar: Node3D = runner.get("avatar")
	if not sprite_avatar.visible or model_head.visible or not flip_board.visible or not bool(model_boots[0].visible):
		_fail("First-person body must retain board and legs but hide the head.")
		return
	runner.call("set_first_person", bool(game.get("first_person")))
	# Test the actual lightcycle and its independent animation states.
	var cycle_rig: Node3D = model.get("lightcycle")
	var wheels: Array = model.get("cycle_wheels")
	var cycle_body: Node3D = model.get("cycle_frame")
	var cycle_opt := {"lightcycle":true,"speed_factor":0.8}
	model.call("pose",0.0,0.0,false,1.0,0.0,0.0,0.0,false,0.0,0.0,0.0,0.0,0.0,0.0,cycle_opt)
	if not cycle_rig.visible or wheels.size()!=3 or (flip_board.get_child(0) as Node3D).visible:
		_fail("Regular ground does not display the lightcycle instead of the deck.")
		return
	var seated_hip: Vector3 = (model.get("hips") as Node3D).position
	if seated_hip.y<0.75 or seated_hip.y>1.25:
		_fail("Lightcycle rider is not seated.")
		return
	var neutral_chassis:=cycle_body.position.y
	model.call("pose",0.8,0.9,false,1.0,0.4,1.0,0.0,false,0.0,0.0,0.0,0.0,0.0,0.0,cycle_opt)
	if absf(cycle_rig.rotation.z)<0.2 or cycle_body.position.y>=neutral_chassis-0.12:
		_fail("Lightcycle lean or suspension compression missing.")
		return
	model.call("pose",0.6,0.0,true,0.5,0.4,0.0,0.0,false,0.0,0.0,0.0,0.0,0.0,0.0,cycle_opt)
	if not cycle_rig.visible or cycle_rig.rotation.x<0.2:
		_fail("Short jump does not use a cycle takeoff pose.")
		return
	model.call("pose",0.0,0.0,false,1.0,0.0,0.0,0.0,false,0.0,0.0,0.0,0.0,0.0,0.0,{"lightcycle":true,"glider":1.0,"glider_return":0.9})
	if not cycle_rig.visible or glider_rig.visible or float(model.get("cycle_fold"))>0.001:
		_fail("Legacy glider data changed grounded vehicle.")
		return
	model.call("pose",0.0,0.0,false,1.0,0.0,0.0,0.0,false,0.0,0.0,0.0,0.0,0.0,0.0,{"lightcycle":true,"sideways":1.0})
	if not cycle_rig.visible or gyro_probe.visible or absf(float(model.get("cycle_antigrav"))-1.0)>0.001:
		_fail("Sidewall lightcycle did not enter anti-gravity mode.")
		return
	model.call("pose",0.0,0.0,false,1.0,0.0,0.0,0.0,false,0.0,0.0,0.0,0.0,0.0,0.0,{"lightcycle":true,"inverted":1.0})
	if not cycle_rig.visible or ceiling_treads.visible or absf(float(model.get("cycle_antigrav"))-1.0)>0.001:
		_fail("Ceiling lightcycle did not enter anti-gravity mode.")
		return
	var wheel_carriers: Array=model.get("cycle_forks")
	for carrier in wheel_carriers:
		if absf(absf((carrier as Node3D).rotation.z)-PI*0.5)>0.01:
			_fail("Anti-gravity wheels did not swivel ninety degrees.")
			return
	if (wheel_carriers[1] as Node3D).position.x>=-0.5 or (wheel_carriers[2] as Node3D).position.x<=0.5:
		_fail("Rear anti-gravity wheel pair did not spread.")
		return
	model.call("pose",0.0,0.0,false,1.0,0.0,0.0,0.0,false,0.0,0.0,0.0,0.0,0.0,0.0,{"lightcycle":true,"inverted":1.0,"loop_cycle":true})
	if absf(float(model.get("cycle_antigrav")))>0.01 or absf((wheel_carriers[0] as Node3D).rotation.z)>0.01:
		_fail("Ordinary rolling wheels must stay active in loops.")
		return
	# Combat must not exist in the active scene or run mode selector.
	for child in game.get_children():
		var script: Script = child.get_script()
		if script != null and script.resource_path.ends_with("arcade_combat.gd"):
			_fail("Combat node is still active.")
			return
	var mode_picker: OptionButton = game.get("mode_picker")
	for item_index in range(mode_picker.item_count):
		if mode_picker.get_item_text(item_index) == "Combat":
			_fail("Combat remains selectable.")
			return
	# Stalling on an uphill track must not permanently stop progress.
	for slide_test: bool in [false,true]:
		var restart_speed:=0.0
		for recovery_tick in range(60):
			restart_speed=float(runner.call("step_speed",restart_speed,0.35,true,slide_test,1.0/60.0))
		if restart_speed<6.9:
			_fail("Zero-speed recovery failed on an uphill surface.")
			return
	for view_up: Vector3 in [Vector3.UP,Vector3.DOWN]:
		var center_look: Vector3=game.call("_first_person_look",Vector3.FORWARD,view_up,0.0,0.0)
		var right_look: Vector3=game.call("_first_person_look",Vector3.FORWARD,view_up,-0.2,0.0)
		var down_look: Vector3=game.call("_first_person_look",Vector3.FORWARD,view_up,0.0,0.2)
		if right_look.x<=center_look.x or down_look.y>=center_look.y:
			_fail("First-person look controls invert on a bank.")
			return
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
	# Recenter must correct the camera without modifying gameplay state.
	var recenter_camera: Camera3D = game.get("view_camera")
	var before_recenter: Transform3D = runner.transform
	var before_recenter_speed: float = runner.get("speed")
	var before_recenter_mode: bool = game.get("first_person")
	recenter_camera.basis = Basis(Vector3.UP, PI)
	var center_key := InputEventKey.new()
	center_key.pressed = true
	center_key.keycode = KEY_G
	game.call("_input", center_key)
	for camera_tick in range(120):
		game.call("_update_camera",1.0/60.0)
	var centered_goal: Basis = game.get("camera_goal")
	if recenter_camera.basis.z.dot(centered_goal.z) < 0.999 or runner.transform != before_recenter or float(runner.get("speed")) != before_recenter_speed or bool(game.get("first_person")) != before_recenter_mode:
		_fail("Camera recenter did not restore view independently of movement.")
		return
	game.call("_orbit_input", Vector2(0.8, 0.3))
	game.call("_update_camera", 1.0)
	if absf(float(game.get("orbit_yaw"))) < 0.7 or absf(float(game.get("orbit_pitch"))) < 0.2:
		_fail("Free camera orbit input was ignored.")
		return
	game.call("_recenter_camera")
	if absf(float(game.get("orbit_yaw"))) > 0.001 or absf(float(game.get("orbit_pitch"))) > 0.001:
		_fail("Recenter failed to reset orbit offsets.")
		return
	# Changing board yaw at a fixed position cannot rotate the camera.
	game.call("_update_camera",1.0)
	var track_camera_goal: Basis=game.get("camera_goal")
	var saved_rider_pose: Transform3D=runner.transform
	runner.transform=Transform3D(saved_rider_pose.basis.rotated(saved_rider_pose.basis.y,0.6),saved_rider_pose.origin)
	game.call("_update_camera",1.0)
	var carved_camera_goal: Basis=game.get("camera_goal")
	runner.transform=saved_rider_pose
	if track_camera_goal.z.dot(carved_camera_goal.z)<0.999:
		_fail("Camera follows board yaw rather than track heading.")
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
	# High-speed crests and jump/dive inputs must never detach the bike.
	runner.set("distance",16.0)
	runner.set("lane",0.0)
	runner.set("speed",165.0)
	runner.call("sync_pose",course)
	for i in range(30):
		runner.call("request_jump")
		runner.set("touch_dive",true)
		runner.call("tick",1.0/60.0,course)
		if not bool(runner.get("grounded")) or absf(float(runner.get("height")))>0.001 or bool(runner.get("diving")):
			_fail("Crest or removed flight input detached the rider.")
			return
	if float(runner.call("landing_speed", 80.0, 35.0)) >= 70.0 or absf(float(runner.call("landing_speed", 80.0, 4.0)) - 80.0) > 0.001:
		_fail("Hard landings must lose momentum while gentle landings preserve it.")
		return
	# Banks stay attached to the current surface even with old jump input.
	game.call("_restart")
	await process_frame
	runner.set("distance",784.0)
	runner.set("speed",40.0)
	runner.call("sync_pose",course)
	for i in range(18):
		runner.call("request_jump")
		runner.call("tick",1.0/60.0,course)
		if not bool(runner.get("grounded")):
			_fail("Bank detached grounded bike.")
			return
	# Ground contact must clear a sideways flight pose immediately.
	game.call("_restart")
	await process_frame
	runner.set("distance", 864.0)
	runner.set("lane", 0.0)
	runner.set("grounded", false)
	var landing_frame: Transform3D = course.call("surface_frame", 864.0, 0.0, 1)
	var pre_contact := landing_frame.basis.rotated(-landing_frame.basis.z, PI * 0.5)
	runner.set("air_basis", pre_contact)
	runner.set("recover_air_roll", true)
	runner.set("air_time", 1.0)
	runner.transform = Transform3D(pre_contact, landing_frame.origin + landing_frame.basis.y * 0.01)
	game.call("_update_camera", 1.0 / 60.0)
	runner.call("_finish_landing", course)
	var landed_basis: Basis = runner.get("air_basis")
	if not bool(runner.call("is_grounded")) or runner.position.distance_to(landing_frame.origin) > 0.01 or runner.transform.basis.y.dot(landing_frame.basis.y) < 0.999 or landed_basis.y.dot(landing_frame.basis.y) < 0.999:
		_fail("Sideways landing did not immediately align to the riding surface.")
		return
	if float(runner.get("air_time")) != 0.0 or bool(runner.get("recover_air_roll")) or float(runner.get("landing_blend")) != 0.0:
		_fail("Sideways landing retained the old flight state.")
		return
	game.call("_update_camera", 1.0 / 60.0)
	# Simulate a sideways rider actually approaching an upright floor;
	# do not simply invoke the landing completion method.
	game.call("_restart")
	await process_frame
	var floor_s := 52.0
	var floor_frame: Transform3D = course.call("surface_frame", floor_s, 0.0, 1)
	var floor_sideways := floor_frame.basis.rotated(-floor_frame.basis.z, PI * 0.5)
	runner.set("distance", floor_s)
	runner.set("lane", 0.0)
	runner.set("grounded", false)
	runner.set("air_time", 0.35)
	runner.set("air_basis", floor_sideways)
	runner.set("air_velocity", -floor_frame.basis.z * 30.0 - floor_frame.basis.y * 4.0)
	runner.transform = Transform3D(floor_sideways, floor_frame.origin + floor_frame.basis.y * 0.23)
	runner.call("_advance_flight", 1.0 / 60.0, course, 0.0)
	if not bool(runner.get("grounded")) or runner.transform.basis.y.dot(floor_frame.basis.y) < 0.98:
		_fail("Sideways shallow floor contact failed to recover.")
		return
	# Upright airborne contact with the inverted rideable face should
	# reorient the board and attach without penetrating the slab.
	game.call("_restart")
	await process_frame
	var ceiling: Transform3D = course.call("surface_frame", 864.0, 0.0, 1)
	var head_first := ceiling.basis.rotated(-ceiling.basis.z, PI)
	runner.set("distance", 864.0)
	runner.set("lane", 0.0)
	runner.set("grounded", false)
	runner.set("air_basis", head_first)
	runner.set("air_velocity", -ceiling.basis.z * 22.0 - ceiling.basis.y * 10.0)
	runner.transform = Transform3D(head_first, ceiling.origin + ceiling.basis.y * 2.3)
	runner.call("_advance_flight", 0.1, course, 0.0)
	var attached_ceiling:Transform3D=course.call("surface_frame",float(runner.get("distance")),float(runner.get("lane")),int(runner.get("surface_side")))
	if not bool(runner.call("is_grounded")) or runner.transform.basis.y.dot(attached_ceiling.basis.y)<0.98:
		_fail("Upright rider did not attach to the contacted ceiling.")
		return
	# Jump on both sides of a fast twisting bank. No foot may cross
	# through the slab even when the local normal rotates during flight.
	for bank_side: int in [1, -1]:
		game.call("_restart")
		await process_frame
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
	# A shallow approaching bank contact should settle onto the board's
	# actual face, not enter a persistent airborne scrape.
	game.call("_restart")
	await process_frame
	var bank_recover_s:=1008.0
	var bank_recover_frame: Transform3D=course.call("surface_frame",bank_recover_s,0.0,1)
	runner.set("distance",bank_recover_s)
	runner.set("lane",0.0)
	runner.set("grounded",false)
	runner.set("surface_side",1)
	runner.set("air_time",0.4)
	runner.set("air_basis",bank_recover_frame.basis)
	runner.set("air_velocity",-bank_recover_frame.basis.z*20.0-bank_recover_frame.basis.y*0.5)
	var bank_old:=bank_recover_frame.origin+bank_recover_frame.basis.y*0.22
	var bank_new:=bank_recover_frame.origin+bank_recover_frame.basis.y*0.18
	if not bool(runner.call("_recover_bank_contact",course,bank_old,bank_new,bank_recover_s)) or not bool(runner.get("grounded")):
		_fail("Shallow bank contact did not recover.")
		return
	# A 180-bank underside is a real rideable face, not a visual duplicate.
	game.call("_restart")
	await process_frame
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
	await process_frame
	# Ramp only occupies a side lane; centre and opposite side stay flat.
	var ramp_s := 192.0 + 99.0
	if not bool(course.call("has_distance", ramp_s)):
		_fail("Ramp test did not load its target chunk.")
		return
	var ramp_lane: float = course.call("ramp_center", 1)
	if float(course.call("surface_lift", ramp_s, ramp_lane)) < 5.0 or absf(float(course.call("surface_lift", ramp_s, -ramp_lane))) > 0.001 or absf(float(course.call("surface_lift", ramp_s, 0.0))) > 0.001:
		_fail("Partial-width ramp does not leave a flat bypass.")
		return
	# First-person sliding lowers the camera without adding HUD clutter.
	game.call("_restart")
	await process_frame
	game.set("first_person", true)
	runner.set("is_sliding", true)
	game.call("_update_camera", 1.0)
	game.call("_update_hud")
	if float(game.get("slide_eye_height")) > 0.9:
		_fail("First-person sliding does not lower the camera.")
		return
	runner.set("is_sliding", false)
	game.call("_update_camera", 1.0)
	game.call("_update_hud")
	if float(game.get("slide_eye_height")) < 1.5:
		_fail("First-person camera did not rise after standing.")
		return
	game.set("first_person", false)
	# A high jump over the supported ribbon cannot expire on airtime.
	game.call("_restart")
	await process_frame
	var high_frame: Transform3D = course.call("surface_frame",52.0,0.0,1)
	var high_position := high_frame.origin + Vector3.UP*55.0
	runner.set("air_time",12.0)
	runner.set("air_velocity",Vector3(0,-15,0))
	var high_projection: Vector3 = course.call("project_position",high_position,52.0)
	runner.call("_check_fall",course,high_position,high_projection,0.5)
	var distant_high := high_position+Vector3(0,80,180)
	var distant_projection: Vector3 = course.call("project_position",distant_high,52.0)
	runner.set("air_velocity",Vector3(0,-10,100))
	runner.call("_check_fall",course,distant_high,distant_projection,0.5)
	if bool(runner.get("fallen")):
		_fail("Long airtime falsely killed a rider above the road.")
		return
	# Steering changes actual heading and produces a curved trajectory.
	runner.set("grounded",true)
	runner.set("distance",8.0)
	runner.set("lane",0.0)
	runner.set("speed",40.0)
	runner.set("touch_axis",1.0)
	runner.call("sync_pose",course)
	for turn_tick in range(12):
		runner.call("tick",1.0/60.0,course)
	var turn_surface: Transform3D = course.call("surface_frame",float(runner.get("distance")),float(runner.get("lane")),1)
	if float(runner.get("steering_heading")) < 0.25 or (-runner.transform.basis.z).dot(turn_surface.basis.x) < 0.20:
		_fail("Steering still strafes instead of turning the board.")
		return
	# Track edges are hard movement bounds; never enter free flight.
	game.call("_restart")
	await process_frame
	runner.set("lane",float(course.call("half_width_at",8.0))-0.1)
	runner.set("touch_axis",1.0)
	runner.set("lateral_speed",25.0)
	runner.call("sync_pose",course)
	for i in range(60):
		runner.call("tick",1.0/60.0,course)
		if not bool(runner.get("grounded")) or bool(runner.get("fallen")) or not bool(course.call("support_at",float(runner.get("distance")),float(runner.get("lane")))):
			_fail("Edge steering left rideable geometry.")
			return
	game.call("_restart")
	await process_frame
	# Roll curvature is not a launch ramp, even near the edge at high speed.
	for s in [780.0, 810.0, 864.0, 1000.0, 1056.0, 1100.0]:
		for edge: float in [-20.0, 20.0]:
			if float(runner.call("relative_normal_acceleration", course, s, edge, 250.0, 25.0)) > 0.0:
				_fail("High-degree banking generates false lift.")
				return
	game.call("_restart")
	await process_frame
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
	# All ten obstacle shapes must exist in the fixed opening sequence.
	var shapes := {}
	for data in chunks.values():
		if str(data["kind"]) == "INVERSION":
			_fail("Obsolete forced inversion appeared in the opening fixture.")
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
	# An already-hit obstacle stays solid, and a real collision stops
	# the board before its front face instead of merely draining speed.
	var contact_info: Dictionary = course.call("first_obstacle_contact",at-12.0,at+12.0,lane,lane,0.0,0.0,1.7)
	if contact_info.is_empty():
		_fail("Previously hit obstacle ceased to be solid.")
		return
	runner.set("grounded",true)
	runner.set("speed",120.0)
	runner.call("_obstacle_rebound",course,contact_info,at-12.0,at+12.0,lane,lane,0.0,0.0)
	if not bool(runner.get("grounded")) or float(runner.get("distance")) >= at or float(runner.get("speed")) >= 120.0:
		_fail("Obstacle did not stop the bike on the surface.")
		return
	# Stream the new terrain showcase in order, verifying geometry and width.
	for index in range(6, 16):
		course.call("stream", float(index) * 192.0)
		await process_frame
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
		await process_frame
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
	await process_frame
	chunks = course.get("chunks")
	if chunks.size() > 8 or not bool(course.call("has_distance", 6700.0)) or chunks.has(0):
		_fail("Endless streaming failed to recycle old track chunks.")
		return
	game.call("_restart")
	await process_frame
	# A projected catch at high altitude must not end the run.
	var saved_storm_front:float=storm.get("front_s")
	var saved_runner_pose:Transform3D=runner.transform
	var saved_grounded:bool=runner.get("grounded")
	storm.set("front_s",float(runner.get("distance"))+0.5)
	runner.set("grounded",false)
	runner.position+=Vector3.UP*100.0
	if bool(storm.call("confirms_catch",0.5,runner,course)):
		_fail("Storm falsely catches a high airborne rider.")
		return
	runner.transform=saved_runner_pose
	runner.set("grounded",true)
	if bool(storm.call("confirms_catch",0.05,runner,course)) or not bool(storm.call("confirms_catch",0.40,runner,course)):
		_fail("Storm catch confirmation did not debounce correctly.")
		return
	storm.set("front_s",saved_storm_front)
	storm.set("catch_time",0.0)
	runner.set("grounded",saved_grounded)
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
	await process_frame
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
	# Even stale airborne state cannot activate double jump.
	runner.set("grounded",false)
	runner.set("double_jump_available",true)
	runner.set("air_velocity",Vector3(0,-8,-40))
	if bool(runner.call("_double_jump")) or (runner.get("air_velocity") as Vector3)!=Vector3(0,-8,-40):
		_fail("Removed double jump still changes velocity.")
		return
	game.call("_restart")
	await process_frame
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
	await process_frame
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
	await process_frame
	course.call("stream", 21.0 * 192.0)
	await process_frame
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
	await process_frame
	course.call("stream", 25.0 * 192.0)
	await process_frame
	var split_s := 23.0 * 192.0 + 96.0
	var gap_s := 24.0 * 192.0 + 84.0
	if bool(course.call("support_at", split_s, 0.0)) or not bool(course.call("support_at", split_s, -28.0)) or not bool(course.call("support_at", gap_s, 32.0)) or not bool(course.call("support_at", gap_s, -32.0)):
		_fail("Split route lacks a bypass or former jump gap is not bridged.")
		return
	var fork_left: Transform3D = course.call("surface_frame", split_s, -28.0, 1)
	var fork_right: Transform3D = course.call("surface_frame", split_s, 28.0, 1)
	if fork_left.origin.distance_to(fork_right.origin) < 140.0:
		_fail("Fork branches are not physically separated.")
		return
	if fork_left.origin.y - fork_right.origin.y < 45.0:
		_fail("Fork routes do not have distinct terrain elevations.")
		return
	var narrow_edge: Transform3D = course.call("surface_frame",split_s,-52.0,1)
	var wide_edge: Transform3D = course.call("surface_frame",split_s,52.0,1)
	if narrow_edge.origin.distance_to(fork_left.origin) >= wide_edge.origin.distance_to(fork_right.origin):
		_fail("High ridge and low channel have identical widths.")
		return
	var guide_right: float = course.call("guided_fork_lane",split_s,15.0,0.0,0.0)
	var guide_left: float = course.call("guided_fork_lane",split_s,-15.0,0.0,0.0)
	if not bool(course.call("support_at",split_s,guide_right)) or not bool(course.call("support_at",split_s,guide_left)) or guide_right<=0.0 or guide_left>=0.0:
		_fail("Inner fork guidance failed to select supported branches.")
		return
	var middle_point := (fork_left.origin+fork_right.origin)*0.5
	var middle_projection := Vector3(split_s,0.0,0.0)
	if not bool(course.call("fork_gap_recoverable",middle_point,middle_projection)):
		_fail("Rider between branches cannot attempt a recovery.")
		return
	var fork_projected: Vector3 = course.call("project_position", fork_left.origin, split_s)
	if absf(fork_projected.y + 28.0) > 0.2:
		_fail("Separated branch projection does not recover its lane.")
		return
	var tunnel_s := 25.0 * 192.0 + 96.0
	var tunnel_mid: Transform3D = course.call("surface_frame", tunnel_s, 0.0, 1)
	var tunnel_wall: Transform3D = course.call("surface_frame",tunnel_s,54.0,1)
	var seam_left:Transform3D=course.call("surface_frame",tunnel_s,-60.0,1)
	var seam_right:Transform3D=course.call("surface_frame",tunnel_s,60.0,1)
	if seam_left.origin.distance_to(seam_right.origin)>0.001 or absf(float(course.call("wrap_pipe_lane",tunnel_s,61.0))+59.0)>0.001:
		_fail("Fullpipe seam is not closed and wrapping.")
		return
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
	# A curved-wall departure rights the rider in free flight without
	# forcing it to follow the changing track orientation underneath.
	runner.set("distance", pipe_s)
	runner.set("lane", 50.0)
	runner.set("surface_side", 1)
	runner.set("grounded", true)
	runner.set("speed", 40.0)
	runner.call("sync_pose", course)
	runner.call("_begin_flight", pipe_edge, 12.0, true)
	var pipe_launch_up: Vector3 = runner.transform.basis.y
	runner.position = pipe_edge.origin + pipe_edge.basis.y * 6.0 + Vector3.UP * 6.0
	runner.set("air_time", 0.3)
	runner.call("_advance_flight", 0.1, course, 0.0)
	var pipe_air_basis: Basis = runner.get("air_basis")
	if pipe_air_basis.y.dot(Vector3.UP) <= pipe_launch_up.dot(Vector3.UP):
		_fail("Halfpipe flight did not recover its sideways roll.")
		return
	var stacked_s := 27.0 * 192.0 + 96.0
	var upper: Transform3D = course.call("surface_frame", stacked_s, -30.0, 1)
	var lower: Transform3D = course.call("surface_frame", stacked_s, 30.0, 1)
	if upper.origin.y - lower.origin.y < 20.0 or Vector2(upper.origin.x - lower.origin.x, upper.origin.z - lower.origin.z).length() > 1.0:
		_fail("Stacked routes do not physically overlap.")
		return
	runner.set("air_basis",Basis.IDENTITY)
	var upper_hit:Dictionary=runner.call("_stacked_sweep",course,upper.origin+Vector3.UP*2.0,upper.origin-Vector3.UP*2.0,stacked_s,stacked_s)
	if upper_hit.is_empty() or float(upper_hit.get("lane",0.0))>=0.0 or int(upper_hit.get("side",0))!=1:
		_fail("Upper overpass crossing incorrectly selected lower deck.")
		return
	for offset: float in [12.0, 24.0, 48.0, 72.0, 96.0, 120.0, 144.0, 168.0]:
		var overpass_s := 27.0 * 192.0 + offset
		var normal_force: float = runner.call("relative_normal_acceleration", course, overpass_s, -30.0, 200.0)
		if float(runner.call("natural_lift_impulse", normal_force, 200.0)) > 0.0:
			_fail("Engineered overpass launches a grounded rider.")
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
	await process_frame
	var daily_seed: int = game.get("run_seed")
	game.call("_restart")
	await process_frame
	if int(game.get("run_seed")) != daily_seed or not bool(course.get("fixed_daily_layout")):
		_fail("Daily run did not preserve its deterministic course.")
		return
	game.set("mode", 2)
	game.call("_restart")
	await process_frame
	runner.call("request_jump")
	if bool(runner.get("queued_jump")):
		_fail("No-jump challenge permits jumping.")
		return
	game.set("mode", 5)
	game.call("_restart")
	await process_frame
	var storm_before_practice: float = storm.get("front_s")
	game.call("_physics_process", 0.1)
	if float(storm.get("front_s")) != storm_before_practice:
		_fail("Practice mode advances the storm.")
		return
	game.set("mode", 0)
	game.call("_restart")
	await process_frame
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
	# The button must update the real playback clock and label.
	var rate_button:Button=game.get("replay_speed_button")
	for expected_rate:float in [2.0,0.5,1.0]:
		rate_button.pressed.emit()
		game.call("_seek_replay",0.0)
		game.call("_process",0.025)
		if absf(float(game.get("replay_rate"))-expected_rate)>0.001 or absf(float(game.get("replay_time"))-0.025*expected_rate)>0.002:
			_fail("Replay speed button did not change playback time.")
			return
	# Cosmetic materials are shared by all mechanical forms.
	var cosmetic_edge:StandardMaterial3D=model.get("edge_mat")
	var default_color:=cosmetic_edge.albedo_color
	runner.call("apply_cosmetic",1)
	if cosmetic_edge.albedo_color.is_equal_approx(default_color):
		_fail("Cosmetics do not recolor the mechanical rider.")
		return
	runner.call("apply_cosmetic",0)
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
	await process_frame
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
		await process_frame
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
	# Directly exercise the branch cadence without expensive extra meshes.
	course.set("sections_since_split", 5)
	course.set("sections_since_sweep",0)
	course.set("sections_since_roll", 0)
	course.set("sections_since_loop", 0)
	course.set("demanding_sections", 0)
	course.set("last_kind", "TURN")
	course.set("route_forecast", {"gap": 100.0, "speed": 80.0, "storm_speed": 30.0})
	course.get("sustained_roll_queue").clear()
	var branch_kind: String = course.call("_kind", 8)
	if branch_kind not in ["SPLIT ROUTE", "STACKED ROUTES","LOOP ROUTE"]:
		_fail("Split route cadence did not produce a branching section.")
		return
	# A due loop outranks a new wall entry or ordinary branching route.
	course.set("sections_since_loop", 5)
	course.set("sections_since_roll", 5)
	course.set("last_kind", "TURN")
	course.get("sustained_roll_queue").clear()
	if str(course.call("_kind", 8)) != "LOOP ROUTE":
		_fail("Due loop did not receive independent priority.")
		return
	course.set("sections_since_loop", 0)
	course.set("sections_since_roll", 0)
	course.set("sections_since_split", 0)
	course.set("last_kind", "LOOP ROUTE")
	if str(course.call("_kind", 9)) == "LOOP ROUTE":
		_fail("Loops generated consecutively without spacing.")
		return
	course.get("sustained_roll_queue").clear()
	course.set("sections_since_loop", 5)
	course.set("demanding_sections", 2)
	if str(course.call("_kind", 10)) not in ["RECOVERY RUN", "LONG DESCENT", "SLIPSTREAM", "BANKED DESCENT"]:
		_fail("Loop cadence overrode recovery safety.")
		return
	var map_point: Vector3 = course.call("surface_position", 8.0, 12.0)
	var map_frame: Transform3D = course.call("surface_frame", 8.0, 12.0, 1)
	if map_point.distance_to(map_frame.origin) > 0.01:
		_fail("Fast map position differs from the rideable surface.")
		return
	# Deterministic full-sized loop fixture uses the actual mesh pipeline.
	var fixture_length:=640.0
	var fixture_points: Array=course.call("_make_points","LOOP ROUTE",0.0,0.0,1.0,1.0,fixture_length/192.0)
	var lead_points: Array=course.call("_make_points","RECOVERY RUN",0.0,0.0,1.0,1.0,fixture_length/192.0)
	var lead_end: Transform3D=lead_points[-1]
	var fixture_recipes: Array=[
		{"index":0,"start":0.0,"length":fixture_length,"kind":"RECOVERY RUN","origin":Vector3.ZERO,"points":lead_points,"layout":[]},
		{"index":1,"start":fixture_length,"length":fixture_length,"kind":"LOOP ROUTE","origin":lead_end.origin,"points":fixture_points,"layout":[]}]
	course.call("begin_replay_layout",fixture_recipes)
	course.call("replay_stream",fixture_length+20.0,Vector3.ZERO)
	for loop_u: float in [0.10,0.20,0.28,0.36,0.47,0.55,0.64,0.72,0.85]:
		var loop_at:=fixture_length*(1.0+loop_u)
		for loop_across: float in [-42.0,-26.0,26.0]:
			var loop_face: Transform3D=course.call("surface_frame",loop_at,loop_across,1)
			var loop_hit: Dictionary=course.call("loop_mesh_sweep",loop_face.origin+loop_face.basis.y*3.0,loop_face.origin-loop_face.basis.y*3.0)
			if loop_hit.is_empty() or absf(float(loop_hit["s"])-loop_at)>3.0 or absf(float(loop_hit["lane"])-loop_across)>2.0:
				_fail("Swept loop collision missed or chose a different arm.")
				return
			var physical_near: Dictionary=course.call("nearest_loop_surface",loop_face.origin+loop_face.basis.y*2.0,5.0)
			if physical_near.is_empty() or float(physical_near["distance"])>2.1:
				_fail("Loop world-space proximity failed.")
				return
			runner.set("grounded",false)
			runner.set("fallen",false)
			runner.set("fall_grace",0.44)
			runner.set("air_velocity",Vector3.DOWN*8.0)
			runner.call("_check_fall",course,loop_face.origin+loop_face.basis.y*2.0,Vector3(10.0,0.0,-100.0),0.06)
			if bool(runner.get("fallen")):
				_fail("False death near physical loop with incorrect progress.")
				return
			runner.set("distance",loop_at)
			runner.set("lane",loop_across)
			runner.set("grounded",true)
			runner.set("surface_side",1)
			runner.set("landing_blend",0.0)
			runner.call("sync_pose",course)
			game.set("first_person",false)
			game.call("_update_camera",1.0/60.0)
			if sprite_camera.position.distance_to(runner.position)<8.0:
				_fail("Loop chase camera collapsed into near first-person.")
				return
			var target_direction: Vector3=(runner.position+loop_face.basis.y*1.35-sprite_camera.position).normalized()
			if (-sprite_camera.basis.z).dot(target_direction)<0.98:
				_fail("Loop camera is not aimed at the rider.")
				return
			runner.call("_update_rider_animation",0.1)
			runner.call("update_rider_sprite",sprite_camera,1.0)
			var loop_model: Node3D=runner.get("rider_model")
			if not (loop_model.get("lightcycle") as Node3D).visible or (loop_model.get("treads") as Node3D).visible or (loop_model.get("gyro") as Node3D).visible:
				_fail("Loop changed the motorcycle to another vehicle.")
				return
	# Consecutive camera samples, not just independent crown snapshots.
	game.set("camera_arm_ready",false)
	game.set("loop_camera_ready",false)
	var previous_loop_right:=Vector3.ZERO
	for camera_step in range(181):
		var camera_at:=fixture_length*(1.20+0.60*float(camera_step)/180.0)
		runner.set("distance",camera_at)
		runner.set("lane",-32.0)
		runner.set("grounded",true)
		runner.set("surface_side",1)
		runner.call("sync_pose",course)
		game.call("_update_camera",1.0/60.0)
		if sprite_camera.position.distance_to(runner.position)<8.0:
			_fail("Loop camera collapsed during continuous traversal.")
			return
		if camera_step>0 and sprite_camera.basis.x.dot(previous_loop_right)<0.0:
			_fail("Loop camera rolled discontinuously.")
			return
		previous_loop_right=sprite_camera.basis.x
	# A player flying parallel to the entrance must not snap onto the loop.
	var air_at:=fixture_length*1.20
	var air_face: Transform3D=course.call("surface_frame",air_at,-32.0,1)
	runner.set("distance",air_at)
	runner.set("lane",-32.0)
	runner.set("grounded",false)
	runner.set("air_time",0.4)
	runner.set("fallen",false)
	runner.set("air_basis",air_face.basis)
	runner.set("air_velocity",-air_face.basis.z*30.0)
	runner.position=air_face.origin+air_face.basis.y*5.0
	var air_before: Vector3=runner.position
	runner.call("_flight_step",1.0/120.0,course,0.0)
	if bool(runner.get("grounded")) or runner.position.distance_to(air_before)>1.0:
		_fail("Airborne near miss teleported onto loop.")
		return
	var fall_cycle: Node3D=runner.get("rider_model")
	fall_cycle.call("pose",0.6,0.0,true,1.0,0.4,0.0,0.0,false,0.0,0.0,0.0,0.0,0.0,0.0,{"lightcycle":true,"cycle_fall":1.0,"speed_factor":0.6})
	var falling_bike: Node3D=fall_cycle.get("lightcycle")
	if not falling_bike.visible or falling_bike.rotation.x>=-0.2:
		_fail("Motorcycle freefall pose is missing.")
		return
	# Adjacent ordinary road uses the exact same collision path.
	var approach_face: Transform3D=course.call("surface_frame",fixture_length-12.0,24.0,1)
	var road_sweep: Dictionary=course.call("loop_mesh_sweep",approach_face.origin+approach_face.basis.y*3.0,approach_face.origin-approach_face.basis.y*3.0,true)
	if road_sweep.is_empty() or absf(float(road_sweep["s"])-(fixture_length-12.0))>2.0:
		_fail("Loop approach road is absent from exact collision.")
		return
	# A stale progress estimate cannot produce a storm loss near the loop.
	var storm_probe: Node3D=game.get("storm")
	storm_probe.set("front_s",60.0)
	runner.set("distance",8.0)
	runner.set("grounded",false)
	runner.set("loop_flight_guard",true)
	runner.position=air_face.origin+air_face.basis.y*7.0
	if bool(storm_probe.call("confirms_catch",0.6,runner,course)):
		_fail("Incorrect loop progress triggered storm death.")
		return
	var sweep_basis: Basis=course.call("_orientation","GRAND TURN",1.0,-1.0,1.0,1.0,1.0)
	var sweep_start: Basis=course.call("_orientation","GRAND TURN",0.0,-1.0,1.0,1.0,1.0)
	if (-sweep_start.z).angle_to(-sweep_basis.z)<1.8 or float(course.call("bank_length","GRAND TURN",180.0))<900.0:
		_fail("Grand turns are not sufficiently wide.")
		return
	print("PASS: actual loop triangle sweeps, motorcycle, flight and chase distance")
	print("PASS: slide-only acceleration, unlimited speed, hazards, and advancing storm")
	print("PASS: wide tessellated banks, continuous distance colors, ten obstacle shapes, seamless streaming")
	game.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	push_error("GAMEPLAY REGRESSION: " + reason)
	quit(1)
