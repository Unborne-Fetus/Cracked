extends Node3D
## Single-scene game orchestrator: HUD, checkpoint course, camera and best time.

const CourseScript = preload("res://scripts/course.gd")
const RunnerScript = preload("res://scripts/runner.gd")

var course: Node3D
var runner: CharacterBody3D
var view_camera: Camera3D
var first_person := false
var run_finished := false
var run_time := 0.0
var best_time := 0.0
var speed_label: Label
var distance_label: Label
var clock_label: Label
var record_label: Label
var camera_label: Label
var message_label: Label
var restart_button: Button

func _ready() -> void:
	_create_world()
	course = CourseScript.new()
	add_child(course)
	runner = RunnerScript.new()
	add_child(runner)
	view_camera = Camera3D.new()
	view_camera.current = true
	view_camera.fov = 82.0
	add_child(view_camera)
	_create_hud()
	var record := ConfigFile.new()
	if record.load("user://records.cfg") == OK:
		best_time = float(record.get_value("records", "best_time", 0.0))
	_restart()
	_update_camera(1.0)

func _create_world() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.008, 0.028)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.17, 0.28)
	env.ambient_light_energy = 0.7
	world.environment = env
	add_child(world)

func _restart() -> void:
	run_finished = false
	run_time = 0.0
	runner.reset_run(Vector3(8.0, course.surface_height(8.0, 0.0) + 2.6, 0.0))
	runner.set_first_person(first_person)
	if message_label != null:
		message_label.visible = false
	if restart_button != null:
		restart_button.visible = false

func _process(delta: float) -> void:
	if not run_finished:
		run_time += delta
		if runner.global_position.y < course.surface_height(clampf(runner.global_position.x, 0, course.LENGTH), 0.0) - 32.0 or absf(runner.global_position.z) > 48.0:
			_restart()
		if runner.global_position.x >= course.LENGTH - 15.0:
			_finish()
	_update_camera(delta)
	_update_hud()

func _update_camera(delta: float) -> void:
	var pos := runner.global_position
	var desired: Vector3
	var target: Vector3
	if first_person:
		desired = pos + Vector3(0.55, 0.70, 0)
		target = pos + Vector3(25.0, 0.7, 0)
	else:
		var behind_x := pos.x - 14.0
		var terrain_y: float = course.surface_height(clampf(behind_x, 0.0, course.LENGTH), pos.z)
		desired = Vector3(behind_x, maxf(pos.y + 5.8, terrain_y + 3.5), pos.z)
		target = pos + Vector3(12.0, 1.6, 0)
	var blend := clampf(delta * (16.0 if first_person else 6.0), 0.0, 1.0)
	view_camera.global_position = view_camera.global_position.lerp(desired, blend)
	view_camera.look_at(target, Vector3.UP)
	view_camera.fov = lerpf(view_camera.fov, clampf(76.0 + runner.speed * 0.14, 78.0, 104.0), blend)

func _update_hud() -> void:
	speed_label.text = "%d" % int(runner.speed * 3.6)
	distance_label.text = "%d / %d m" % [int(clampf(runner.global_position.x, 0.0, course.LENGTH - 15.0)), int(course.LENGTH - 15.0)]
	clock_label.text = "TIME  " + _clock(run_time)
	record_label.text = "BEST  " + ("--:--" if best_time <= 0.0 else _clock(best_time))
	camera_label.text = "CAMERA  " + ("FIRST PERSON" if first_person else "THIRD PERSON")
	if not run_finished and runner.gameplay_seconds - runner.last_boost_time < 1.1:
		message_label.visible = true
		message_label.text = "BOOST +18"
	elif not run_finished:
		message_label.visible = false

func _clock(seconds: float) -> String:
	return "%02d:%05.2f" % [int(seconds / 60.0), fmod(seconds, 60.0)]

func _finish() -> void:
	run_finished = true
	runner.set_physics_process(false)
	if best_time <= 0.0 or run_time < best_time:
		best_time = run_time
		var record := ConfigFile.new()
		record.set_value("records", "best_time", best_time)
		record.save("user://records.cfg")
	message_label.text = "COURSE COMPLETE  " + _clock(run_time)
	message_label.visible = true
	restart_button.visible = true

func _toggle_camera() -> void:
	first_person = not first_person
	runner.set_first_person(first_person)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_V or event.keycode == KEY_C:
		_toggle_camera()
	elif event.keycode == KEY_R:
		_restart()

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(title: String, x_left: float, x_right: float, bottom: float) -> Button:
	var b := Button.new()
	b.text = title
	b.focus_mode = Control.FOCUS_NONE
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = x_left
	b.offset_right = x_right
	b.offset_top = -bottom
	b.offset_bottom = -bottom + 66.0
	b.add_theme_font_size_override("font_size", 21)
	return b

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	
	var stack := VBoxContainer.new()
	stack.position = Vector2(22, 18)
	stack.add_theme_constant_override("separation", 1)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)
	stack.add_child(_label("VECTOR // VELOCITY", 23, Color(0.96, 0.19, 0.65)))
	speed_label = _label("0", 58, Color(0.1, 0.95, 1.0))
	stack.add_child(speed_label)
	stack.add_child(_label("KM/H", 15, Color(0.62, 0.85, 0.95)))
	distance_label = _label("", 19, Color(0.8, 0.93, 0.99))
	stack.add_child(distance_label)
	clock_label = _label("", 19, Color(0.8, 0.93, 0.99))
	stack.add_child(clock_label)
	record_label = _label("", 17, Color(0.99, 0.79, 0.41))
	stack.add_child(record_label)
	camera_label = _label("", 14, Color(0.68, 0.74, 0.95))
	stack.add_child(camera_label)
	
	message_label = _label("", 27, Color(1.0, 0.84, 0.30))
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.offset_left = -190
	message_label.offset_top = 45
	message_label.offset_right = 240
	message_label.offset_bottom = 100
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.visible = false
	root.add_child(message_label)
	
	var hint := _label("A / D or arrows · steer     SPACE / A · jump     V · camera     R · restart     S / B · brake", 15, Color(0.70, 0.83, 0.96))
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.anchor_right = 1.0
	hint.offset_left = 16
	hint.offset_right = -12
	hint.offset_top = -33
	hint.offset_bottom = -7
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)
	
	var left_button := _button("◀", 20, 100, 124)
	root.add_child(left_button)
	left_button.button_down.connect(func() -> void: runner.touch_axis -= 1.0)
	left_button.button_up.connect(func() -> void: runner.touch_axis += 1.0)
	var right_button := _button("▶", 110, 190, 124)
	root.add_child(right_button)
	right_button.button_down.connect(func() -> void: runner.touch_axis += 1.0)
	right_button.button_up.connect(func() -> void: runner.touch_axis -= 1.0)
	var jump_button := _button("JUMP", -138, -20, 124)
	jump_button.anchor_left = 1.0
	jump_button.anchor_right = 1.0
	root.add_child(jump_button)
	jump_button.pressed.connect(func() -> void: runner.request_jump())
	var view_button := _button("VIEW", -138, -20, 204)
	view_button.anchor_left = 1.0
	view_button.anchor_right = 1.0
	root.add_child(view_button)
	view_button.pressed.connect(_toggle_camera)
	
	restart_button = Button.new()
	restart_button.text = "RUN AGAIN  ↻"
	restart_button.set_anchors_preset(Control.PRESET_CENTER)
	restart_button.offset_left = -90
	restart_button.offset_right = 90
	restart_button.offset_top = 5
	restart_button.offset_bottom = 56
	restart_button.visible = false
	root.add_child(restart_button)
	restart_button.pressed.connect(_restart)
