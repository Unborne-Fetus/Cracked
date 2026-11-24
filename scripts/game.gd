extends Node3D

const CourseScript = preload("res://scripts/course.gd")
const RunnerScript = preload("res://scripts/runner.gd")
const StormScript = preload("res://scripts/storm.gd")
const ExtrasScript = preload("res://scripts/run_extras.gd")
const EffectsScript = preload("res://scripts/run_effects.gd")
const ReplayScript = preload("res://scripts/replay.gd")
var replay
var replay_active := false
var replay_playing := false
var replay_time := 0.0
var replay_rate := 1.0
var replay_panel: PanelContainer
var replay_slider: HSlider
var replay_clock: Label
var replay_play_button: Button
var replay_speed_button: Button
var watch_replay_button: Button
var profile_replay_button: Button
const MODES: Array[String] = ["Endless", "Daily seeded", "No jumping", "First person", "Fast storm", "Practice"]
var extras
var effects
var mode := 0
var run_day := ""
var extras_page: VBoxContainer
var extras_button: Button
var extra_items: Array[Control] = []
var mode_picker: OptionButton
var profile_label: Label
var stats_label: Label
var binding_action := ""
var binding_kind := ""
var binding_picker: OptionButton
var keyboard_rebind: Button
var pad_rebind: Button
var audio_toggle: CheckButton
var trails_toggle: CheckButton
var vibration_toggle: CheckButton
var board_request: HTTPRequest
var board_status := "Online leaderboard not configured"
var leaderboard_url := ""

var course
var runner
var storm
var view_camera: Camera3D
var first_person := false
var run_finished := false
var run_time := 0.0
var best_distance := 0.0
var run_seed := 0
var speed_label: Label
var speed_unit_label: Label
var paused := false
var imperial := false
var pause_overlay: Control
var pause_page: VBoxContainer
var options_page: VBoxContainer
var units_picker: OptionButton
var resume_button: Button
var options_button: Button
var back_button: Button
var controls_hint: Label
var pad_menu_index := 0
var pad_menu_axis := Vector2.ZERO
var distance_label: Label
var clock_label: Label
var record_label: Label
var camera_label: Label
var slide_label: Label
var reserve_meter: ProgressBar
var reserve_label: Label
var minimap: Control
var camera_track_s := 0.0
var camera_track_clearance := 0.0
var camera_rotation_ready := false
var orbit_yaw := 0.0
var orbit_pitch := 0.0
var orbit_zoom := 1.0
var orbit_drag := false
var camera_goal := Basis.IDENTITY
var camera_height := 0.0
var slide_eye_height := 1.55
var slide_indicator: PanelContainer
var camera_offset := Vector3.ZERO
var takeoff_camera_offset := Vector3.ZERO
var camera_was_grounded := true
const TAKEOFF_CAMERA_TIME := 0.45
var storm_label: Label
var section_label: Label
var message_label: Label
var restart_button: Button

func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	# A world-fixed sky makes vertical orientation visible even on an empty ribbon.
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.012, 0.022, 0.065)
	sky_mat.sky_horizon_color = Color(0.036, 0.072, 0.115)
	sky_mat.ground_horizon_color = Color(0.036, 0.072, 0.115)
	sky_mat.ground_bottom_color = Color(0.003, 0.004, 0.012)
	sky_mat.sun_angle_max = 0.0
	sky.sky_material = sky_mat
	env.sky = sky
	world.environment = env
	add_child(world)
	course = CourseScript.new()
	add_child(course)
	runner = RunnerScript.new()
	add_child(runner)
	storm = StormScript.new()
	add_child(storm)
	view_camera = Camera3D.new()
	view_camera.current = true
	view_camera.fov = 82.0
	view_camera.near = 0.075
	view_camera.far = 1600.0
	add_child(view_camera)
	extras = ExtrasScript.new()
	add_child(extras)
	effects = EffectsScript.new()
	add_child(effects)
	replay = ReplayScript.new()
	add_child(replay)
	replay.load_last()
	_create_hud()
	_create_replay_panel()
	_create_pause_menu()
	_load_extras()
	board_request = HTTPRequest.new()
	add_child(board_request)
	board_request.request_completed.connect(_board_completed)
	_load_options()
	var record := ConfigFile.new()
	if record.load("user://endless_records.cfg") == OK:
		best_distance = float(record.get_value("records", "best_distance", 0.0))
	_restart()

func _restart() -> void:
	replay_active = false
	replay_playing = false
	replay_panel.visible = false
	watch_replay_button.visible = false
	replay.reset_recording()
	_set_paused(false)
	run_finished = false
	run_time = 0.0
	camera_rotation_ready = false
	orbit_yaw = 0.0
	orbit_pitch = 0.0
	orbit_zoom = 1.0
	orbit_drag = false
	camera_height = 0.0
	slide_eye_height = 1.55
	camera_offset = Vector3.ZERO
	camera_was_grounded = true
	run_day = Time.get_date_string_from_system(true)
	run_seed = ExtrasScript.daily_seed(run_day) if mode == 1 else randi()
	course.fixed_daily_layout = mode == 1
	course.reset_course(run_seed)
	runner.reset_run(course)
	runner.jumps_disabled = mode == 2
	if mode == 3:
		first_person = true
	runner.set_first_person(first_person)
	runner.apply_cosmetic(extras.cosmetic)
	extras.reset_stats()
	stats_label.visible = false
	effects.reset_run()
	storm.reset(runner.distance)
	storm.sync_pose(course)
	storm.visible = mode != 5 and storm.visible
	replay.record(0.0, 0.0, runner, course, storm, true)
	message_label.visible = false
	restart_button.visible = false
	_update_camera(1.0)
	_update_hud()

func _physics_process(delta: float) -> void:
	if replay_active or paused or run_finished:
		return
	run_time += delta
	course.set_pursuit_context(runner.distance, runner.lane, runner.speed, storm.gap_to(runner.distance), storm.speed, storm.elapsed)
	var previous_hits: int = runner.hits
	var was_grounded: bool = runner.is_grounded()
	var previous_speed: float = runner.speed
	runner.tick(delta, course)
	extras.track(delta, runner, previous_speed)
	effects.update_run(runner.speed, runner.hits > previous_hits, not was_grounded and runner.is_grounded())
	if runner.fallen:
		replay.record(run_time, delta, runner, course, storm, true)
		_lose("FELL OFF THE TRACK")
		return
	if mode != 5:
		storm.advance(delta * (1.28 if mode == 4 else 1.0))
		storm.sync_pose(course)
		if storm.gap_to(runner.distance) <= 1.0:
			replay.record(run_time, delta, runner, course, storm, true)
			_lose("THE STORM CAUGHT YOU")
			return
	replay.record(run_time, delta, runner, course, storm)

func _process(delta: float) -> void:
	if not paused and (not run_finished or replay_active):
		_poll_camera_stick(delta)
	if replay_active:
		if replay_playing:
			_seek_replay(minf(replay.duration(), replay_time + delta * replay_rate), false)
			if replay_time >= replay.duration():
				_set_replay_playing(false)
		_update_camera(delta)
		_update_hud()
		return
	if paused:
		return
	_update_camera(delta)
	_update_hud()

func _camera_line_clear(a: Vector3, b: Vector3, from_s: float, to_s: float) -> bool:
	# Check the actual bank frame along the sightline, not world-up.
	# This also works during origin rebases and before physics colliders sync.
	for i in range(1, 16):
		var t := float(i) / 16.0
		var s := lerpf(from_s, to_s, t)
		var projection: Vector3 = course.project_position(a.lerp(b, t), s)
		var clearance: float = course.surface_clearance(projection.x, projection.y, projection.z, int(runner.surface_side))
		if bool(course.support_at(projection.x, projection.y)) and clearance < 0.55:
			return false
	return true

func _level_camera_basis(direction: Vector3) -> Basis:
	var heading := direction.normalized()
	# Keep the horizon world-up even while the camera is physically beside
	# or underneath the track. Avoid a singularity for steep viewing angles.
	if absf(heading.y) > 0.94:
		var horizontal := Vector3(heading.x, 0.0, heading.z)
		if horizontal.length_squared() < 0.0001:
			horizontal = Vector3(-view_camera.basis.z.x, 0.0, -view_camera.basis.z.z)
		if horizontal.length_squared() < 0.0001:
			horizontal = Vector3.FORWARD
		heading = (horizontal.normalized() * 0.342 + Vector3.UP * signf(heading.y) * 0.94).normalized()
	return Basis.looking_at(heading, Vector3.UP)

func _aim_camera(target: Vector3, _up: Vector3) -> void:
	var direction := target - view_camera.position
	if direction.length_squared() > 0.0001:
		camera_goal = _level_camera_basis(direction)

func _update_camera(delta: float) -> void:
	var player_s: float = runner.distance
	var player_lane: float = runner.lane
	var frame: Transform3D = course.surface_frame(player_s, player_lane, int(runner.surface_side))
	var up := frame.basis.y
	var forward := -frame.basis.z
	var pos: Vector3 = runner.position
	var actively_sliding: bool = runner.is_grounded() and runner.is_sliding
	slide_eye_height = lerpf(slide_eye_height, 0.85 if actively_sliding else 1.55, 1.0 - exp(-delta * 10.0))
	# Camera stays on the correct side of the road; only orientation and
	# the additional chase height are damped, never the bank-relative base.
	camera_height = lerpf(camera_height, maxf(0.0, float(runner.height) * float(runner.surface_side)), 1.0 - exp(-delta * 8.0))
	if not runner.is_grounded():
		if camera_was_grounded:
			takeoff_camera_offset = camera_offset if camera_offset.length_squared() > 0.01 else (up * 1.55 if first_person else -forward * 11.0 + up * 5.4)
		camera_was_grounded = false
		# Follow the free player's own pose, not the twisting road below.
		var air_up: Vector3 = runner.transform.basis.y
		var air_forward: Vector3 = -runner.transform.basis.z
		camera_track_s = player_s
		if first_person:
			view_camera.position = pos + air_up * 1.55
			_aim_camera(view_camera.position + air_forward * 25.0, air_up)
		else:
			view_camera.position = pos - air_forward * 9.0 + air_up * 4.0
			_aim_camera(pos + air_up * 1.4 + air_forward * 4.0, air_up)
		# Retain the exact pre-takeoff camera arm, then ease toward flight.
		var blend := smoothstep(0.0, TAKEOFF_CAMERA_TIME, float(runner.air_time))
		view_camera.position = pos + takeoff_camera_offset.lerp(view_camera.position - pos, blend)
	elif first_person:
		camera_track_s = player_s
		view_camera.position = pos + up * slide_eye_height
		_aim_camera(view_camera.position + forward * 25.0, up)
	else:
		var focus := pos + up * 1.35
		# Sample the track AT the camera's trailing distance. Using the
		# player's up vector eleven metres behind it crossed twisting banks.
		# Shorten the arm if its sightline would cross the road.
		var selected := false
		for trail: float in [11.0, 8.0, 5.0, 3.0]:
			var s := maxf(0.0, player_s - trail)
			var rear_lane := clampf(player_lane, -float(course.lane_limit(s)), float(course.lane_limit(s)))
			var rear: Transform3D = course.surface_frame(s, rear_lane, int(runner.surface_side))
			var candidate := rear.origin + rear.basis.y * (5.4 + camera_height)
			if _camera_line_clear(candidate, focus, s, player_s):
				camera_track_s = s
				view_camera.position = candidate
				_aim_camera(focus + forward * 0.8, rear.basis.y)
				selected = true
				break
		if not selected:
			# Local fallback cannot be on the underside, even on a full roll.
			camera_track_s = player_s
			view_camera.position = pos + up * 3.6
			_aim_camera(view_camera.position + forward * 22.0, up)
	# Blend the flight camera's relative arm into the grounded arm, rather
	# than abruptly switching between two different camera positions.
	# The offset follows the moving player, so even extreme speeds do not
	# create positional lag. Clamp only when needed to avoid the ribbon.
	if runner.is_grounded() and runner.landing_blend > 0.0:
		var blend: float = runner.landing_fraction()
		var from_basis: Basis = runner.landing_from_basis
		var from_up := from_basis.y
		var from_forward := -from_basis.z
		var air_offset := from_up * 1.55 if first_person else -from_forward * 9.0 + from_up * 4.0
		var ground_offset := view_camera.position - pos
		var candidate := pos + air_offset.lerp(ground_offset, blend)
		var projected: Vector3 = course.project_position(candidate, lerpf(player_s, camera_track_s, blend))
		var surface: Transform3D = course.surface_frame(projected.x, projected.y, int(runner.surface_side))
		var clearance: float = course.surface_clearance(projected.x, projected.y, projected.z, int(runner.surface_side))
		if absf(projected.y) <= float(course.half_width_at(projected.x)) + 0.5 and clearance < 1.15:
			candidate += surface.basis.y * (1.15 - clearance)
		if first_person or _camera_line_clear(candidate, pos + up * 1.35, projected.x, player_s):
			view_camera.position = candidate
			camera_track_s = projected.x
		# Match the blended body orientation, preserving the pre-impact view.
		var air_look := from_forward if first_person else from_forward * 13.0 - from_up * 2.6
		var air_goal := _level_camera_basis(air_look)
		camera_goal = air_goal.slerp(camera_goal, blend).orthonormalized()
	_apply_camera_orbit(pos, up, forward, player_s)
	var camera_projection: Vector3 = course.project_position(view_camera.position, camera_track_s)
	camera_track_clearance = float(course.surface_clearance(camera_projection.x, camera_projection.y, camera_projection.z, int(runner.surface_side)))
	camera_offset = view_camera.position - pos
	camera_was_grounded = runner.is_grounded()
	# Quaternion interpolation avoids Euler flips near 180/360 degrees.
	# A short time constant removes sudden orientation kicks without a
	# long lag that would point the camera back through the ribbon.
	if not camera_rotation_ready:
		view_camera.basis = camera_goal
		camera_rotation_ready = true
	else:
		# Interpolate forward directions, then reconstruct a level basis.
		# Quaternion blending whole tilted frames can introduce unwanted roll.
		var heading := (-view_camera.basis.z).slerp(-camera_goal.z, 1.0 - exp(-delta * 11.0))
		view_camera.basis = _level_camera_basis(heading)
	view_camera.fov = lerpf(view_camera.fov, clampf(78.0 + runner.speed * 0.10, 78.0, 98.0), 1.0 - exp(-delta * 4.0))
	runner.update_rider_sprite(view_camera)

func _speed_display(meters_per_second: float) -> int:
	return int(meters_per_second * (2.2369362921 if imperial else 3.6))

func _speed_units() -> String:
	return "MPH" if imperial else "KM/H"

func _distance_display(meters: float) -> String:
	if imperial:
		if meters >= 1609.344:
			return "%.2f mi" % (meters / 1609.344)
		return "%d ft" % int(meters * 3.280839895)
	return "%d m" % int(meters)

func _update_hud() -> void:
	slide_indicator.visible = first_person and runner.is_grounded() and runner.is_sliding and not run_finished
	reserve_meter.value = runner.momentum_reserve
	reserve_label.text = "MOMENTUM RESERVE  %d%%" % int(round(runner.momentum_reserve / runner.RESERVE_MAX * 100.0))
	speed_label.text = "%d" % _speed_display(runner.speed)
	speed_unit_label.text = _speed_units()
	distance_label.text = "DISTANCE  " + _distance_display(maxf(0.0, runner.distance - 8.0))
	clock_label.text = "TIME  %02d:%05.2f" % [int(run_time / 60.0), fmod(run_time, 60.0)]
	record_label.text = MODES[mode].to_upper() + "  //  BEST " + _distance_display(maxf(extras.best_for(mode, run_day), runner.distance - 8.0))
	camera_label.text = "CAMERA  " + ("FIRST PERSON" if first_person else "THIRD PERSON")
	section_label.text = str(course.biome_name(runner.distance)) + "  //  " + str(course.section_name(runner.distance))
	if not runner.is_grounded():
		slide_label.text = "DIVING  //  CONTROLLED DESCENT" if runner.diving else ("AIRBORNE  //  DOUBLE JUMP READY" if runner.double_jump_available else "AIRBORNE  //  DOUBLE JUMP USED")
	elif runner.is_sliding:
		if float(course.recovery_accel(runner.distance, runner.lane, runner.surface_side)) > 0.1:
			slide_label.text = "RECOVERY LANE  //  EXTRA ACCELERATION"
		else:
			slide_label.text = "UPHILL SLIDE  //  LOSING SPEED" if runner.uphill else "SLIDING  //  BUILD MOMENTUM"
	else:
		slide_label.text = "HOLD SHIFT / CTRL / C TO SLIDE"
	var gap: float = maxf(float(storm.gap_to(runner.distance)), 0.0)
	storm_label.text = "PRACTICE  //  NO STORM" if mode == 5 else "STORM  %s  //  %d %s" % [_distance_display(gap), _speed_display(storm.speed), _speed_units()]
	storm_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.35) if gap < 40.0 else Color(0.96, 0.53, 0.72))
	if replay_active:
		message_label.visible = false
	elif not run_finished:
		message_label.visible = runner.hit_timer > 0.0 or runner.gate_timer > 0.0 or runner.landing_reward_timer > 0.0
		if runner.hit_timer > 0.0:
			message_label.text = "IMPACT  //  MOMENTUM LOST"
		elif runner.landing_reward_timer > 0.0:
			message_label.text = runner.landing_reward_text
		else:
			message_label.text = "CLEAN GATE  //  MOMENTUM REWARD"

func _lose(reason: String) -> void:
	if run_finished:
		return
	run_finished = true
	replay.record(run_time, 0.0, runner, course, storm, true)
	replay.finish(course, run_seed, mode, extras.cosmetic)
	watch_replay_button.visible = replay.available()
	var meters: float = maxf(0.0, runner.distance - 8.0)
	extras.finish(mode, run_day, run_seed, meters, run_time, runner)
	stats_label.text = extras.summary(_distance_display(meters), _speed_display(extras.top_speed), _speed_units())
	stats_label.visible = true
	if mode == 1:
		_submit_daily(meters)
	if mode == 0 and meters > best_distance:
		best_distance = meters
		var record := ConfigFile.new()
		record.set_value("records", "best_distance", best_distance)
		record.save("user://endless_records.cfg")
	message_label.text = reason + "  //  " + _distance_display(meters)
	message_label.visible = true
	restart_button.visible = true

func _orbit_input(amount: Vector2) -> void:
	orbit_yaw = wrapf(orbit_yaw - amount.x, -PI, PI)
	orbit_pitch = clampf(orbit_pitch + amount.y, deg_to_rad(-70.0), deg_to_rad(78.0))

func _poll_camera_stick(delta: float) -> void:
	var motion := Vector2.ZERO
	for device in Input.get_connected_joypads():
		var candidate: Vector2 = Vector2(runner.pad_axis(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X)), runner.pad_axis(Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)))
		if candidate.length_squared() > motion.length_squared():
			motion = candidate
	_orbit_input(motion * delta * 2.4)

func _apply_camera_orbit(pos: Vector3, track_up: Vector3, track_forward: Vector3, player_s: float) -> void:
	if absf(orbit_yaw) < 0.0001 and absf(orbit_pitch) < 0.0001 and absf(orbit_zoom - 1.0) < 0.0001:
		return
	var up: Vector3 = track_up if runner.is_grounded() else runner.transform.basis.y
	var forward: Vector3 = track_forward if runner.is_grounded() else -runner.transform.basis.z
	if first_person:
		var look: Vector3 = forward.rotated(up, orbit_yaw)
		var axis: Vector3 = look.cross(up).normalized()
		if axis.length_squared() > 0.001:
			look = look.rotated(axis, orbit_pitch)
		camera_goal = _level_camera_basis(look)
		return
	var focus: Vector3 = pos + up * 1.35
	# Orbit a track-relative hemisphere, allowing a full 360-degree yaw.
	# Limit downward pitch only when the actual track blocks the view.
	var base_arm: Vector3 = view_camera.position - focus
	var arm_length := clampf(base_arm.length() * orbit_zoom, 2.5, 30.0)
	var azimuth: Vector3 = (-forward).rotated(up, orbit_yaw)
	var base_pitch := atan2(base_arm.dot(up), maxf(0.01, (base_arm - up * base_arm.dot(up)).length()))
	var elevation := clampf(base_pitch + orbit_pitch, deg_to_rad(-70.0), deg_to_rad(85.0))
	var direction: Vector3 = azimuth * cos(elevation) + up * sin(elevation)
	for scale_value: float in [1.0, 0.75, 0.50, 0.30]:
		var candidate: Vector3 = focus + direction * arm_length * scale_value
		var projection: Vector3 = course.project_position(candidate, player_s)
		var clearance: float = course.surface_clearance(projection.x, projection.y, projection.z, int(runner.surface_side))
		if bool(course.support_at(projection.x, projection.y)) and clearance < 0.7:
			continue
		if _camera_line_clear(candidate, focus, projection.x, player_s):
			view_camera.position = candidate
			camera_track_s = projection.x
			_aim_camera(focus, up)
			return

func _recenter_camera() -> void:
	orbit_yaw = 0.0
	orbit_pitch = 0.0
	orbit_zoom = 1.0
	orbit_drag = false
	# Rebuild the chase arm and heading without changing camera mode,
	# player orientation, momentum or position. In flight use the actual
	# flight basis instead of the bank underneath the player.
	var pose: Basis = runner.transform.basis
	var up := pose.y
	var forward := -pose.z
	camera_rotation_ready = false
	camera_height = 0.0
	slide_eye_height = 0.85 if runner.is_grounded() and runner.is_sliding else 1.55
	camera_offset = up * 1.55 if first_person else -forward * 9.0 + up * 4.0
	takeoff_camera_offset = camera_offset
	camera_was_grounded = runner.is_grounded()
	_update_camera(1.0)

func _toggle_camera() -> void:
	if mode == 3 and not replay_active:
		return
	first_person = not first_person
	camera_rotation_ready = false
	runner.set_first_person(first_person)
	_update_camera(1.0)

func _pad_focus() -> void:
	if not paused:
		return
	if extras_page.visible:
		extra_items[clampi(pad_menu_index, 0, extra_items.size() - 1)].grab_focus()
	elif options_page.visible:
		if pad_menu_index == 0:
			units_picker.grab_focus()
		else:
			back_button.grab_focus()
	elif pad_menu_index == 0:
		resume_button.grab_focus()
	elif pad_menu_index == 1:
		options_button.grab_focus()
	else:
		extras_button.grab_focus()

func _pad_direction(x: int, y: int) -> void:
	if y != 0:
		var count := extra_items.size() if extras_page.visible else (2 if options_page.visible else 3)
		pad_menu_index = posmod(pad_menu_index + y, count)
		_pad_focus()
	elif x != 0 and extras_page.visible:
		var selected := extra_items[pad_menu_index]
		if selected is OptionButton:
			var picker := selected as OptionButton
			picker.select(posmod(picker.selected + x, picker.item_count))
			picker.item_selected.emit(picker.selected)
	elif x != 0 and options_page.visible and pad_menu_index == 0:
		_set_units(1 if x > 0 else 0)

func _pad_button(button: int) -> bool:
	if replay_active:
		match button:
			JOY_BUTTON_START, JOY_BUTTON_A:
				_set_replay_playing(not replay_playing)
			JOY_BUTTON_B, JOY_BUTTON_BACK:
				_restart()
			JOY_BUTTON_Y:
				_toggle_camera()
			JOY_BUTTON_LEFT_STICK:
				_recenter_camera()
			JOY_BUTTON_DPAD_LEFT:
				_seek_replay(replay_time - 5.0)
			JOY_BUTTON_DPAD_RIGHT:
				_seek_replay(replay_time + 5.0)
			JOY_BUTTON_DPAD_UP:
				_cycle_replay_speed()
		return true
	if run_finished and button == JOY_BUTTON_BACK and replay.available():
		_start_replay()
		return true
	if button == JOY_BUTTON_START:
		if paused and (options_page.visible or extras_page.visible):
			_show_options(false)
		else:
			_set_paused(not paused)
		return true
	if paused:
		match button:
			JOY_BUTTON_B, JOY_BUTTON_BACK:
				if options_page.visible or extras_page.visible:
					_show_options(false)
				else:
					_set_paused(false)
			JOY_BUTTON_DPAD_UP:
				_pad_direction(0, -1)
			JOY_BUTTON_DPAD_DOWN:
				_pad_direction(0, 1)
			JOY_BUTTON_DPAD_LEFT:
				_pad_direction(-1, 0)
			JOY_BUTTON_DPAD_RIGHT:
				_pad_direction(1, 0)
			JOY_BUTTON_A:
				if extras_page.visible:
					var control := extra_items[pad_menu_index]
					if control is OptionButton:
						_pad_direction(1, 0)
					elif control is CheckButton:
						control.button_pressed = not control.button_pressed
					elif control is Button and not control.disabled:
						control.pressed.emit()
				elif options_page.visible:
					if pad_menu_index == 0:
						_set_units(0 if imperial else 1)
					else:
						_show_options(false)
				elif pad_menu_index == 0:
					_set_paused(false)
				elif pad_menu_index == 1:
					_show_options(true)
				else:
					_show_extras()
		return true
	if _bound_pad("recenter", button, JOY_BUTTON_LEFT_STICK):
		_recenter_camera()
		return true
	if _bound_pad("camera", button, JOY_BUTTON_Y):
		_toggle_camera()
		return true
	if _bound_pad("restart", button, JOY_BUTTON_X) or (run_finished and button == JOY_BUTTON_A):
		_restart()
		return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if paused or (run_finished and not replay_active):
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_orbit_input(drag.relative * 0.006)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not paused and (not run_finished or replay_active):
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			orbit_drag = mouse.pressed
			get_viewport().set_input_as_handled()
			return
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			orbit_zoom = clampf(orbit_zoom * (0.88 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14), 0.55, 2.4)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and orbit_drag and not paused:
		var motion_event := event as InputEventMouseMotion
		_orbit_input(motion_event.relative * 0.006)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		if pad.pressed:
			if not binding_action.is_empty() and binding_kind == "pad":
				_capture_binding(pad.button_index)
				get_viewport().set_input_as_handled()
				return
			effects.activate_audio()
			controls_hint.text = "STICK steer  ·  A jump x2  ·  B / TRIGGERS slide  ·  R3 dive  ·  Y view  ·  RIGHT STICK look  ·  L3 center  ·  START pause  ·  X retry"
			if _pad_button(pad.button_index):
				get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) > 0.35:
			controls_hint.text = "STICK steer  ·  A jump x2  ·  B / TRIGGERS slide  ·  R3 dive  ·  Y view  ·  RIGHT STICK look  ·  L3 center  ·  START pause  ·  X retry"
		if paused and (motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_LEFT_Y):
			var value := signf(motion.axis_value) if absf(motion.axis_value) > 0.65 else 0.0
			var horizontal := motion.axis == JOY_AXIS_LEFT_X
			var prior := pad_menu_axis.x if horizontal else pad_menu_axis.y
			if horizontal:
				pad_menu_axis.x = value
			else:
				pad_menu_axis.y = value
			if value != 0.0 and value != prior:
				_pad_direction(int(value) if horizontal else 0, 0 if horizontal else int(value))
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if replay_active:
		match key.keycode:
			KEY_ESCAPE:
				_restart()
			KEY_SPACE:
				_set_replay_playing(not replay_playing)
			KEY_LEFT:
				_seek_replay(replay_time - 5.0)
			KEY_RIGHT:
				_seek_replay(replay_time + 5.0)
			KEY_TAB:
				_toggle_camera()
			KEY_G:
				_recenter_camera()
			KEY_UP:
				_cycle_replay_speed()
		get_viewport().set_input_as_handled()
		return
	if run_finished and key.keycode == KEY_V and replay.available():
		_start_replay()
		get_viewport().set_input_as_handled()
		return
	if not binding_action.is_empty() and binding_kind == "keyboard":
		if key.keycode == KEY_ESCAPE:
			binding_action = ""
			_refresh_profile()
		else:
			_capture_binding(key.keycode)
		get_viewport().set_input_as_handled()
		return
	effects.activate_audio()
	controls_hint.text = "A/D steer  ·  SPACE jump x2  ·  SHIFT slide  ·  F dive  ·  TAB view  ·  RMB look / wheel zoom  ·  G center  ·  ESC pause  ·  R retry"
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if paused and options_page.visible:
			_show_options(false)
		else:
			_set_paused(not paused)
		return
	if paused:
		return
	if _bound_key("recenter", key.keycode, KEY_G):
		get_viewport().set_input_as_handled()
		_recenter_camera()
	elif _bound_key("camera", key.keycode, KEY_TAB):
		# Consume Tab before UI focus navigation; C is exclusively slide.
		get_viewport().set_input_as_handled()
		_toggle_camera()
	elif _bound_key("restart", key.keycode, KEY_R):
		get_viewport().set_input_as_handled()
		_restart()

func _label(value: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(title: String, x_left: float, x_right: float, bottom: float, right: bool = false) -> Button:
	var b := Button.new()
	b.text = title
	b.focus_mode = Control.FOCUS_NONE
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	if right:
		b.anchor_left = 1.0
		b.anchor_right = 1.0
	b.offset_left = x_left
	b.offset_right = x_right
	b.offset_top = -bottom
	b.offset_bottom = -bottom + 64.0
	b.add_theme_font_size_override("font_size", 21)
	return b

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	var streaks: Control = effects.make_trails()
	root.add_child(streaks)
	streaks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slide_indicator = PanelContainer.new()
	root.add_child(slide_indicator)
	slide_indicator.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	slide_indicator.offset_left = -120
	slide_indicator.offset_right = 120
	slide_indicator.offset_top = -104
	slide_indicator.offset_bottom = -62
	slide_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slide_style := StyleBoxFlat.new()
	slide_style.bg_color = Color(0.015, 0.09, 0.15, 0.87)
	slide_style.border_color = Color(0.1, 0.95, 1.0)
	slide_style.set_border_width_all(2)
	slide_style.set_corner_radius_all(5)
	slide_indicator.add_theme_stylebox_override("panel", slide_style)
	var slide_text := _label("»  SLIDING  «", 23, Color(0.25, 0.98, 1.0))
	slide_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slide_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slide_indicator.add_child(slide_text)
	slide_indicator.visible = false
	var stack := VBoxContainer.new()
	stack.position = Vector2(22, 18)
	stack.add_theme_constant_override("separation", 2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)
	stack.add_child(_label("VECTOR // VELOCITY", 23, Color(0.96, 0.19, 0.65)))
	speed_label = _label("0", 58, Color(0.1, 0.95, 1.0))
	stack.add_child(speed_label)
	speed_unit_label = _label("KM/H", 15, Color(0.62, 0.85, 0.95))
	stack.add_child(speed_unit_label)
	distance_label = _label("", 19, Color(0.8, 0.93, 0.99))
	stack.add_child(distance_label)
	clock_label = _label("", 19, Color(0.8, 0.93, 0.99))
	stack.add_child(clock_label)
	record_label = _label("", 17, Color(0.99, 0.79, 0.41))
	stack.add_child(record_label)
	camera_label = _label("", 14, Color(0.68, 0.74, 0.95))
	stack.add_child(camera_label)
	section_label = _label("", 17, Color(0.1, 0.9, 0.95))
	stack.add_child(section_label)
	slide_label = _label("", 16, Color(0.4, 0.96, 0.9))
	stack.add_child(slide_label)
	storm_label = _label("", 18, Color(1.0, 0.33, 0.50))
	stack.add_child(storm_label)
	reserve_label = _label("MOMENTUM RESERVE", 15, Color(0.99, 0.79, 0.41))
	stack.add_child(reserve_label)
	reserve_meter = ProgressBar.new()
	reserve_meter.max_value = 30.0
	reserve_meter.custom_minimum_size = Vector2(220, 12)
	reserve_meter.show_percentage = false
	reserve_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reserve_fill := StyleBoxFlat.new()
	reserve_fill.bg_color = Color(0.98, 0.68, 0.21)
	reserve_meter.add_theme_stylebox_override("fill", reserve_fill)
	stack.add_child(reserve_meter)
	minimap = preload("res://scripts/elevation_map.gd").new()
	minimap.clip_contents = true
	root.add_child(minimap)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -266.0
	minimap.offset_right = -16.0
	minimap.offset_top = 38.0
	minimap.offset_bottom = 278.0
	minimap.call("setup", course, runner, storm)
	message_label = _label("", 25, Color(1.0, 0.84, 0.3))
	root.add_child(message_label)
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.offset_left = -260
	message_label.offset_right = 260
	message_label.offset_top = 65
	message_label.offset_bottom = 112
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.visible = false
	var hint := _label("A/D steer  ·  SPACE jump x2  ·  SHIFT slide  ·  F dive  ·  TAB view  ·  RMB look / wheel zoom  ·  G center  ·  ESC pause  ·  R retry", 15, Color(0.7, 0.83, 0.96))
	root.add_child(hint)
	controls_hint = hint
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.anchor_right = 1.0
	hint.offset_left = 10
	hint.offset_right = -10
	hint.offset_top = -33
	hint.offset_bottom = -7
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var left := _button("◀", 20, 100, 124)
	root.add_child(left)
	left.button_down.connect(func() -> void: runner.touch_axis = -1.0)
	left.button_up.connect(func() -> void: runner.touch_axis = 0.0)
	var right := _button("▶", 110, 190, 124)
	root.add_child(right)
	right.button_down.connect(func() -> void: runner.touch_axis = 1.0)
	right.button_up.connect(func() -> void: runner.touch_axis = 0.0)
	var slide := _button("SLIDE", 20, 190, 202)
	root.add_child(slide)
	slide.button_down.connect(func() -> void: runner.touch_slide = true)
	slide.button_up.connect(func() -> void: runner.touch_slide = false)
	var jump := _button("JUMP", -138, -20, 124, true)
	root.add_child(jump)
	jump.pressed.connect(func() -> void: runner.request_jump())
	var view := _button("VIEW", -138, -20, 202, true)
	root.add_child(view)
	view.pressed.connect(_toggle_camera)
	var recenter := _button("CENTER", -394, -276, 202, true)
	root.add_child(recenter)
	recenter.pressed.connect(_recenter_camera)
	var dive := _button("DIVE", -266, -148, 124, true)
	root.add_child(dive)
	dive.button_down.connect(func() -> void: runner.touch_dive = true)
	dive.button_up.connect(func() -> void: runner.touch_dive = false)
	restart_button = Button.new()
	restart_button.text = "RUN AGAIN"
	restart_button.focus_mode = Control.FOCUS_NONE
	root.add_child(restart_button)
	restart_button.set_anchors_preset(Control.PRESET_CENTER)
	restart_button.offset_left = -180
	restart_button.offset_right = -6
	restart_button.offset_top = 8
	restart_button.offset_bottom = 65
	restart_button.visible = false
	restart_button.pressed.connect(_restart)
	watch_replay_button = Button.new()
	watch_replay_button.text = "WATCH REPLAY"
	watch_replay_button.focus_mode = Control.FOCUS_NONE
	root.add_child(watch_replay_button)
	watch_replay_button.set_anchors_preset(Control.PRESET_CENTER)
	watch_replay_button.offset_left = 6
	watch_replay_button.offset_right = 180
	watch_replay_button.offset_top = 8
	watch_replay_button.offset_bottom = 65
	watch_replay_button.visible = false
	watch_replay_button.pressed.connect(_start_replay)
	stats_label = _label("", 17, Color(0.81, 0.96, 1.0))
	root.add_child(stats_label)
	stats_label.set_anchors_preset(Control.PRESET_CENTER)
	stats_label.offset_left = -270
	stats_label.offset_right = 270
	stats_label.offset_top = 85
	stats_label.offset_bottom = 250
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.visible = false

func _load_options() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://velocity_options.cfg") == OK:
		imperial = bool(settings.get_value("display", "imperial", false))
	units_picker.select(1 if imperial else 0)

func _set_units(index: int, persist: bool = true) -> void:
	imperial = index == 1
	units_picker.select(1 if imperial else 0)
	if persist:
		var settings := ConfigFile.new()
		settings.set_value("display", "imperial", imperial)
		settings.save("user://velocity_options.cfg")
	_update_hud()
	if run_finished:
		# Preserve the original defeat reason while updating its distance.
		var reason := message_label.text.get_slice("  //  ", 0)
		message_label.text = reason + "  //  " + _distance_display(maxf(0.0, runner.distance - 8.0))

func _set_paused(value: bool) -> void:
	paused = value
	if value:
		orbit_drag = false
	effects.set_paused(value)
	pause_overlay.visible = value
	pad_menu_axis = Vector2.ZERO
	_show_options(false)
	if not value:
		var focused := get_viewport().gui_get_focus_owner()
		if is_instance_valid(focused):
			focused.release_focus()
	if value:
		# Avoid a stuck touch button if it was held when Escape was pressed.
		runner.touch_slide = false
		runner.touch_dive = false
		runner.touch_axis = 0.0
		runner.queued_jump = false

func _show_options(value: bool) -> void:
	pause_page.visible = not value
	options_page.visible = value
	if is_instance_valid(extras_page):
		extras_page.visible = false
	binding_action = ""
	pad_menu_index = 0
	_pad_focus()

func _menu_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(260, 52)
	button.add_theme_font_size_override("font_size", 20)
	button.focus_mode = Control.FOCUS_ALL
	return button

func _create_pause_menu() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	pause_overlay = Control.new()
	layer.add_child(pause_overlay)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.008, 0.025, 0.84)
	pause_overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	pause_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.026, 0.045, 0.086, 0.98)
	style.border_color = Color(0.12, 0.77, 0.94)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var pages := VBoxContainer.new()
	pages.add_theme_constant_override("separation", 12)
	panel.add_child(pages)
	pause_page = VBoxContainer.new()
	pause_page.add_theme_constant_override("separation", 14)
	pages.add_child(pause_page)
	var title := _label("PAUSED", 34, Color(0.1, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_page.add_child(title)
	resume_button = _menu_button("RESUME")
	pause_page.add_child(resume_button)
	resume_button.pressed.connect(func() -> void: _set_paused(false))
	resume_button.focus_entered.connect(func() -> void: pad_menu_index = 0)
	options_button = _menu_button("OPTIONS")
	pause_page.add_child(options_button)
	options_button.pressed.connect(func() -> void: _show_options(true))
	options_button.focus_entered.connect(func() -> void: pad_menu_index = 1)
	extras_button = _menu_button("RUN / PROFILE / CONTROLS")
	pause_page.add_child(extras_button)
	extras_button.pressed.connect(_show_extras)
	extras_button.focus_entered.connect(func() -> void: pad_menu_index = 2)
	options_page = VBoxContainer.new()
	options_page.add_theme_constant_override("separation", 14)
	pages.add_child(options_page)
	var options_title := _label("OPTIONS", 30, Color(0.1, 0.9, 1.0))
	options_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_page.add_child(options_title)
	options_page.add_child(_label("MEASUREMENT UNITS", 17, Color(0.75, 0.9, 1.0)))
	units_picker = OptionButton.new()
	units_picker.custom_minimum_size = Vector2(260, 48)
	units_picker.add_theme_font_size_override("font_size", 19)
	units_picker.add_item("Metric (km/h, m)")
	units_picker.add_item("Imperial (mph, ft, mi)")
	units_picker.item_selected.connect(func(index: int) -> void: _set_units(index))
	options_page.add_child(units_picker)
	units_picker.focus_entered.connect(func() -> void: pad_menu_index = 0)
	back_button = _menu_button("BACK")
	options_page.add_child(back_button)
	back_button.pressed.connect(func() -> void: _show_options(false))
	back_button.focus_entered.connect(func() -> void: pad_menu_index = 1)
	var pad_hint := _label("STICK / D-PAD  ·  A SELECT  ·  B BACK", 14, Color(0.55, 0.84, 0.96))
	pad_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pages.add_child(pad_hint)
	_create_extras_page(pages)
	_show_options(false)
	pause_overlay.visible = false

func _create_extras_page(pages: VBoxContainer) -> void:
	extras_page = VBoxContainer.new()
	extras_page.add_theme_constant_override("separation", 5)
	pages.add_child(extras_page)
	extras_page.add_child(_label("RUN & PROFILE", 24, Color(0.1, 0.9, 1.0)))
	mode_picker = OptionButton.new()
	for name_value in MODES:
		mode_picker.add_item(name_value)
	mode_picker.item_selected.connect(func(_i: int) -> void: _refresh_profile())
	_add_extra(mode_picker)
	var start := _menu_button("START SELECTED RUN")
	start.custom_minimum_size.y = 36
	start.pressed.connect(func() -> void: mode = mode_picker.selected; _restart())
	_add_extra(start)
	profile_replay_button = _menu_button("WATCH LAST REPLAY (NEW RUN ON EXIT)")
	profile_replay_button.custom_minimum_size.y = 36
	profile_replay_button.pressed.connect(_start_replay)
	_add_extra(profile_replay_button)
	# Cosmetic unlock data stays in the profile. The first approved rider
	# is a single white sprite set, so defer palette selection for now.
	extras_page.add_child(_label("RIDER  //  WHITE SILHOUETTE", 14, Color(0.76, 0.94, 1.0)))
	binding_picker = OptionButton.new()
	for name_value in ["left", "right", "slide", "jump", "dive", "camera", "recenter", "restart"]:
		binding_picker.add_item(name_value)
	binding_picker.item_selected.connect(func(_i: int) -> void: _refresh_profile())
	_add_extra(binding_picker)
	keyboard_rebind = _menu_button("REBIND KEY")
	keyboard_rebind.custom_minimum_size.y = 34
	keyboard_rebind.pressed.connect(func() -> void: _begin_binding("keyboard"))
	_add_extra(keyboard_rebind)
	pad_rebind = _menu_button("REBIND PAD BUTTON")
	pad_rebind.custom_minimum_size.y = 34
	pad_rebind.pressed.connect(func() -> void: _begin_binding("pad"))
	_add_extra(pad_rebind)
	var reset_bind := _menu_button("RESET BINDINGS")
	reset_bind.custom_minimum_size.y = 34
	reset_bind.pressed.connect(func() -> void: extras.keys.clear(); extras.pads.clear(); _apply_bindings(); extras.save_profile(); _refresh_profile())
	_add_extra(reset_bind)
	audio_toggle = CheckButton.new()
	audio_toggle.text = "Adaptive soundtrack"
	audio_toggle.toggled.connect(func(v: bool) -> void: extras.music = v; effects.music_enabled = v; effects.configure_music(); extras.save_profile(); effects.activate_audio())
	_add_extra(audio_toggle)
	trails_toggle = CheckButton.new()
	trails_toggle.text = "Speed streaks"
	trails_toggle.toggled.connect(func(v: bool) -> void: extras.trails = v; effects.trails_enabled = v; extras.save_profile())
	_add_extra(trails_toggle)
	vibration_toggle = CheckButton.new()
	vibration_toggle.text = "Controller vibration"
	vibration_toggle.toggled.connect(func(v: bool) -> void: extras.vibration = v; effects.vibration_enabled = v; extras.save_profile())
	_add_extra(vibration_toggle)
	profile_label = _label("", 14, Color(0.76, 0.94, 1.0))
	extras_page.add_child(profile_label)
	var back := _menu_button("BACK")
	back.custom_minimum_size.y = 36
	back.pressed.connect(func() -> void: _show_options(false))
	_add_extra(back)
	extras_page.visible = false

func _add_extra(control: Control) -> void:
	extras_page.add_child(control)
	var idx := extra_items.size()
	extra_items.append(control)
	control.focus_entered.connect(func() -> void: pad_menu_index = idx)

func _load_extras() -> void:
	extras.load_profile()
	_apply_bindings()
	effects.music_enabled = extras.music
	effects.configure_music()
	effects.trails_enabled = extras.trails
	effects.vibration_enabled = extras.vibration
	leaderboard_url = str(ProjectSettings.get_setting("velocity/leaderboard_url", ""))
	audio_toggle.set_pressed_no_signal(extras.music)
	trails_toggle.set_pressed_no_signal(extras.trails)
	vibration_toggle.set_pressed_no_signal(extras.vibration)

func _show_extras() -> void:
	pause_page.visible = false
	options_page.visible = false
	extras_page.visible = true
	mode_picker.select(mode)
	profile_replay_button.disabled = not replay.available()
	pad_menu_index = 0
	_refresh_profile()
	_pad_focus()

func _refresh_profile() -> void:
	if not is_instance_valid(profile_label):
		return
	var action := binding_picker.get_item_text(binding_picker.selected)
	var key_text := str(extras.keys.get(action, []))
	var pad_text := str(extras.pads.get(action, []))
	profile_label.text = ("Press a new " + binding_kind + " input for " + binding_action if not binding_action.is_empty() else "Unlocked %d / 8  |  Daily best %s\n%s\n%s: key %s  /  pad %s" % [extras.achievements.size(), _distance_display(extras.best_for(1, Time.get_date_string_from_system(true))), board_status, action, key_text if key_text != "[]" else "default", pad_text if pad_text != "[]" else "default"])

func _begin_binding(kind: String) -> void:
	binding_kind = kind
	binding_action = binding_picker.get_item_text(binding_picker.selected)
	_refresh_profile()

func _capture_binding(code: int) -> void:
	if binding_kind == "pad" and code in [JOY_BUTTON_START, JOY_BUTTON_BACK]:
		binding_action = ""
		_refresh_profile()
		return
	var target: Dictionary = extras.keys if binding_kind == "keyboard" else extras.pads
	target[binding_action] = [code]
	binding_action = ""
	_apply_bindings()
	extras.save_profile()
	_refresh_profile()

func _apply_bindings() -> void:
	runner.key_bindings = extras.keys
	runner.pad_bindings = extras.pads

func _bound_key(action: String, code: int, default_value: int) -> bool:
	return extras.keys.get(action, [default_value]).has(code)

func _bound_pad(action: String, code: int, default_value: int) -> bool:
	return extras.pads.get(action, [default_value]).has(code)

func _submit_daily(meters: float) -> void:
	if leaderboard_url.is_empty() or not is_instance_valid(board_request):
		return
	var body := {"day": run_day, "seed": run_seed, "distance": meters, "speed": extras.top_speed, "seconds": run_time, "player": extras.player_id}
	board_status = "Submitting daily score..."
	var error := board_request.request(leaderboard_url.trim_suffix("/") + "/scores", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		board_status = "Leaderboard unavailable"

func _board_completed(_result: int, response: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response != 200:
		board_status = "Leaderboard unavailable"
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary:
		board_status = "Daily global rank: %s" % str(data.get("rank", "?"))
	else:
		board_status = "Leaderboard unavailable"
	_refresh_profile()

func _create_replay_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay_panel = PanelContainer.new()
	root.add_child(replay_panel)
	replay_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	replay_panel.offset_left = -300
	replay_panel.offset_right = 300
	replay_panel.offset_top = -176
	replay_panel.offset_bottom = -50
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.03, 0.08, 0.96)
	style.border_color = Color(0.12, 0.8, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	replay_panel.add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	replay_panel.add_child(stack)
	replay_clock = _label("REPLAY", 18, Color(0.24, 0.95, 1.0))
	stack.add_child(replay_clock)
	replay_slider = HSlider.new()
	replay_slider.step = 0.05
	replay_slider.custom_minimum_size.y = 24
	stack.add_child(replay_slider)
	replay_slider.value_changed.connect(func(value: float) -> void: _seek_replay(value))
	var row := HBoxContainer.new()
	stack.add_child(row)
	for caption_text in ["-5 SEC", "PAUSE", "+5 SEC", "1x", "CAMERA", "CENTER", "EXIT"]:
		var button := Button.new()
		button.text = caption_text
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
		match caption_text:
			"-5 SEC":
				button.pressed.connect(func() -> void: _seek_replay(replay_time - 5.0))
			"PAUSE":
				replay_play_button = button
				button.pressed.connect(func() -> void: _set_replay_playing(not replay_playing))
			"+5 SEC":
				button.pressed.connect(func() -> void: _seek_replay(replay_time + 5.0))
			"1x":
				replay_speed_button = button
				button.pressed.connect(_cycle_replay_speed)
			"CAMERA":
				button.pressed.connect(_toggle_camera)
			"CENTER":
				button.pressed.connect(_recenter_camera)
			"EXIT":
				button.pressed.connect(_restart)
	stack.add_child(_label("SPACE play/pause   ·   ← / → seek   ·   TAB camera   ·   G center   ·   ESC exit", 13, Color(0.75, 0.86, 1.0)))
	replay_panel.visible = false

func _start_replay() -> void:
	if not replay.available():
		return
	_set_paused(false)
	replay_active = true
	run_finished = true
	replay_time = 0.0
	replay_rate = 1.0
	replay_speed_button.text = "1x"
	camera_rotation_ready = false
	orbit_yaw = 0.0
	orbit_pitch = 0.0
	orbit_zoom = 1.0
	orbit_drag = false
	camera_was_grounded = true
	camera_offset = Vector3.ZERO
	camera_height = 0.0
	first_person = false
	runner.set_first_person(false)
	runner.apply_cosmetic(int(replay.archived.get("cosmetic", 0)))
	course.begin_replay_layout(replay.archived["recipes"])
	stats_label.visible = false
	watch_replay_button.visible = false
	restart_button.visible = false
	message_label.visible = false
	replay_panel.visible = true
	replay_slider.max_value = replay.duration()
	_set_replay_playing(true)
	_seek_replay(0.0)

func _set_replay_playing(value: bool) -> void:
	if value and replay_time >= replay.duration():
		_seek_replay(0.0)
	replay_playing = value
	replay_play_button.text = "PAUSE" if value else "PLAY"
	effects.set_paused(not value)

func _cycle_replay_speed() -> void:
	replay_rate = 1.0 if replay_rate >= 2.0 else (2.0 if replay_rate >= 1.0 else 1.0)
	# Cycle 0.5x, 1x, 2x.
	if replay_speed_button.text == "2x":
		replay_rate = 0.5
	replay_speed_button.text = "%gx" % replay_rate

func _seek_replay(value: float, snap_camera: bool = true) -> void:
	if not replay_active:
		return
	replay_time = clampf(value, 0.0, replay.duration())
	var state: Dictionary = replay.sample(replay_time)
	var shift: Vector3 = state["shift"]
	course.replay_stream(float(state["s"]), shift)
	var pose: Transform3D = state["pose"]
	pose.origin -= shift
	runner.transform = pose
	runner.distance = float(state["s"])
	runner.lane = float(state["lane"])
	runner.surface_side = int(state["side"])
	runner.speed = float(state["speed"])
	runner.grounded = bool(state["grounded"])
	runner.is_sliding = bool(state["sliding"])
	runner.diving = bool(state["diving"])
	runner.height = float(state["height"])
	runner.air_time = float(state["air_time"])
	runner.kickflip_progress = float(state.get("kickflip", 1.0))
	runner.rider_crouch = float(state.get("rider_crouch", 0.85 if runner.is_sliding else 0.0))
	runner.rider_phase = float(state.get("rider_phase", 0.0))
	runner.rider_steer = float(state.get("rider_steer", 0.0))
	runner.rider_landing = float(state.get("rider_landing", 0.0))
	runner.rider_impact = float(state.get("rider_impact", 0.0))
	runner.rider_clearance = float(state.get("rider_clearance",0.0))
	runner.rider_dive = float(state.get("rider_dive",1.0 if runner.diving else 0.0))
	runner.momentum_reserve = float(state["reserve"])
	runner.double_jump_available = bool(state["double_jump"])
	runner.landing_blend = 0.0
	if runner.grounded:
		runner.sync_pose(course)
	else:
		runner.air_basis = pose.basis
	runner.avatar.position = Vector3.ZERO
	runner.avatar.scale.y = 0.55 if runner.is_sliding else 1.0
	storm.front_s = float(state["storm_s"])
	storm.speed = float(state["storm_speed"])
	storm.elapsed = float(state["storm_time"])
	storm.sync_pose(course)
	storm.visible = bool(state["storm_visible"]) and storm.visible
	run_time = replay_time
	effects.speed = runner.speed
	replay_slider.set_value_no_signal(replay_time)
	replay_clock.text = "REPLAY   %.1f / %.1f s   %s" % [replay_time, replay.duration(), "(recording limit)" if bool(replay.archived.get("truncated", false)) else ""]
	if snap_camera:
		camera_rotation_ready = false
		camera_was_grounded = runner.is_grounded()
		camera_offset = Vector3.ZERO
		_update_camera(1.0)
