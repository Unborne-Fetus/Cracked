extends Node3D

const CourseScript = preload("res://scripts/course.gd")
const RunnerScript = preload("res://scripts/runner.gd")
const StormScript = preload("res://scripts/storm.gd")

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
	_create_hud()
	_create_pause_menu()
	_load_options()
	var record := ConfigFile.new()
	if record.load("user://endless_records.cfg") == OK:
		best_distance = float(record.get_value("records", "best_distance", 0.0))
	_restart()

func _restart() -> void:
	_set_paused(false)
	run_finished = false
	run_time = 0.0
	camera_rotation_ready = false
	camera_height = 0.0
	slide_eye_height = 1.55
	camera_offset = Vector3.ZERO
	camera_was_grounded = true
	run_seed = randi()
	course.reset_course(run_seed)
	runner.reset_run(course)
	runner.set_first_person(first_person)
	storm.reset(runner.distance)
	storm.sync_pose(course)
	message_label.visible = false
	restart_button.visible = false
	_update_camera(1.0)
	_update_hud()

func _physics_process(delta: float) -> void:
	if paused or run_finished:
		return
	run_time += delta
	course.set_pursuit_context(runner.distance, runner.lane, runner.speed, storm.gap_to(runner.distance), storm.speed, storm.elapsed)
	runner.tick(delta, course)
	if runner.fallen:
		_lose("FELL OFF THE TRACK")
		return
	storm.advance(delta)
	storm.sync_pose(course)
	if storm.gap_to(runner.distance) <= 1.0:
		_lose("THE STORM CAUGHT YOU")

func _process(delta: float) -> void:
	if paused:
		return
	_update_camera(delta)
	_update_hud()

func _camera_line_clear(a: Vector3, b: Vector3, from_s: float, to_s: float) -> bool:
	# Check the actual bank frame along the sightline, not world-up.
	# This also works during origin rebases and before physics colliders sync.
	for i in range(1, 16):
		var t := float(i) / 16.0
		var frame: Transform3D = course.sample(lerpf(from_s, to_s, t))
		var point := a.lerp(b, t) - frame.origin
		var across := point.dot(frame.basis.x)
		var clearance: float = course.surface_clearance(lerpf(from_s, to_s, t), across, point.dot(frame.basis.y), int(runner.surface_side))
		if absf(across) <= float(course.lane_limit(lerpf(from_s, to_s, t))) + 1.0 and clearance < 0.55:
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
	record_label.text = "BEST  " + _distance_display(maxf(best_distance, runner.distance - 8.0))
	camera_label.text = "CAMERA  " + ("FIRST PERSON" if first_person else "THIRD PERSON")
	section_label.text = "TRACK  //  " + str(course.section_name(runner.distance))
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
	storm_label.text = "STORM  %s  //  %d %s" % [_distance_display(gap), _speed_display(storm.speed), _speed_units()]
	storm_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.35) if gap < 40.0 else Color(0.96, 0.53, 0.72))
	if not run_finished:
		message_label.visible = runner.hit_timer > 0.0 or runner.gate_timer > 0.0
		message_label.text = "IMPACT  //  MOMENTUM LOST" if runner.hit_timer > 0.0 else "CLEAN GATE  //  MOMENTUM REWARD"

func _lose(reason: String) -> void:
	if run_finished:
		return
	run_finished = true
	var meters: float = maxf(0.0, runner.distance - 8.0)
	if meters > best_distance:
		best_distance = meters
		var record := ConfigFile.new()
		record.set_value("records", "best_distance", best_distance)
		record.save("user://endless_records.cfg")
	message_label.text = reason + "  //  " + _distance_display(meters)
	message_label.visible = true
	restart_button.visible = true

func _toggle_camera() -> void:
	first_person = not first_person
	camera_rotation_ready = false
	runner.set_first_person(first_person)
	_update_camera(1.0)

func _pad_focus() -> void:
	if not paused:
		return
	if options_page.visible:
		if pad_menu_index == 0:
			units_picker.grab_focus()
		else:
			back_button.grab_focus()
	elif pad_menu_index == 0:
		resume_button.grab_focus()
	else:
		options_button.grab_focus()

func _pad_direction(x: int, y: int) -> void:
	if y != 0:
		pad_menu_index = 1 - pad_menu_index
		_pad_focus()
	elif x != 0 and options_page.visible and pad_menu_index == 0:
		_set_units(1 if x > 0 else 0)

func _pad_button(button: int) -> bool:
	if button == JOY_BUTTON_START:
		if paused and options_page.visible:
			_show_options(false)
		else:
			_set_paused(not paused)
		return true
	if paused:
		match button:
			JOY_BUTTON_B, JOY_BUTTON_BACK:
				if options_page.visible:
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
				if options_page.visible:
					if pad_menu_index == 0:
						_set_units(0 if imperial else 1)
					else:
						_show_options(false)
				elif pad_menu_index == 0:
					_set_paused(false)
				else:
					_show_options(true)
		return true
	if button == JOY_BUTTON_Y:
		_toggle_camera()
		return true
	if button == JOY_BUTTON_X or (run_finished and button == JOY_BUTTON_A):
		_restart()
		return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		if pad.pressed:
			controls_hint.text = "STICK steer  ·  A jump x2  ·  B / TRIGGERS slide  ·  R3 dive  ·  Y view  ·  START pause  ·  X retry"
			if _pad_button(pad.button_index):
				get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) > 0.35:
			controls_hint.text = "STICK steer  ·  A jump x2  ·  B / TRIGGERS slide  ·  R3 dive  ·  Y view  ·  START pause  ·  X retry"
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
	controls_hint.text = "A/D steer  ·  SPACE jump x2  ·  SHIFT slide  ·  F dive  ·  TAB view  ·  ESC pause  ·  R retry"
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if paused and options_page.visible:
			_show_options(false)
		else:
			_set_paused(not paused)
		return
	if paused:
		return
	if key.keycode == KEY_TAB:
		# Consume Tab before UI focus navigation; C is exclusively slide.
		get_viewport().set_input_as_handled()
		_toggle_camera()
	elif key.keycode == KEY_R:
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
	var hint := _label("A/D steer  ·  SPACE jump x2  ·  SHIFT slide  ·  F dive  ·  TAB view  ·  ESC pause  ·  R retry", 15, Color(0.7, 0.83, 0.96))
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
	var dive := _button("DIVE", -266, -148, 124, true)
	root.add_child(dive)
	dive.button_down.connect(func() -> void: runner.touch_dive = true)
	dive.button_up.connect(func() -> void: runner.touch_dive = false)
	restart_button = Button.new()
	restart_button.text = "RUN AGAIN"
	restart_button.focus_mode = Control.FOCUS_NONE
	root.add_child(restart_button)
	restart_button.set_anchors_preset(Control.PRESET_CENTER)
	restart_button.offset_left = -90
	restart_button.offset_right = 90
	restart_button.offset_top = 8
	restart_button.offset_bottom = 65
	restart_button.visible = false
	restart_button.pressed.connect(_restart)

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
	_show_options(false)
	pause_overlay.visible = false
