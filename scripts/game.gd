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
var distance_label: Label
var clock_label: Label
var record_label: Label
var camera_label: Label
var slide_label: Label
var storm_label: Label
var section_label: Label
var message_label: Label
var restart_button: Button

func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.008, 0.028)
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
	view_camera.far = 1600.0
	add_child(view_camera)
	_create_hud()
	var record := ConfigFile.new()
	if record.load("user://endless_records.cfg") == OK:
		best_distance = float(record.get_value("records", "best_distance", 0.0))
	_restart()

func _restart() -> void:
	run_finished = false
	run_time = 0.0
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
	if run_finished:
		return
	run_time += delta
	runner.tick(delta, course)
	storm.advance(delta)
	storm.sync_pose(course)
	if storm.gap_to(runner.distance) <= 1.0:
		_lose("THE STORM CAUGHT YOU")

func _process(delta: float) -> void:
	_update_camera(delta)
	_update_hud()

func _update_camera(delta: float) -> void:
	var frame: Transform3D = runner.transform
	var forward: Vector3 = -frame.basis.z
	var up: Vector3 = frame.basis.y
	var pos: Vector3 = frame.origin
	if first_person:
		view_camera.global_position = pos + up * 1.45 + forward * 0.3
		view_camera.look_at(pos + up * 1.45 + forward * 25.0, up)
	else:
		view_camera.global_position = pos - forward * 11.0 + up * 5.0
		view_camera.look_at(pos + forward * 13.0 + up * 1.2, up)
	view_camera.fov = lerpf(view_camera.fov, clampf(78.0 + runner.speed * 0.15, 78.0, 108.0), minf(delta * 7.0, 1.0))

func _update_hud() -> void:
	speed_label.text = "%d" % int(runner.speed * 3.6)
	distance_label.text = "DISTANCE  %d m" % int(maxf(0.0, runner.distance - 8.0))
	clock_label.text = "TIME  %02d:%05.2f" % [int(run_time / 60.0), fmod(run_time, 60.0)]
	record_label.text = "BEST  %d m" % int(maxf(best_distance, runner.distance - 8.0))
	camera_label.text = "CAMERA  " + ("FIRST PERSON" if first_person else "THIRD PERSON")
	section_label.text = "TRACK  //  " + str(course.section_name(runner.distance))
	if runner.is_sliding:
		if runner.uphill:
			slide_label.text = "LOOP SLIDE  //  MOMENTUM RETAINED" if runner.in_inversion else "UPHILL SLIDE  //  LOSING SPEED"
		else:
			slide_label.text = "SLIDING  //  GAINING SPEED"
	else:
		slide_label.text = "HOLD SHIFT / S TO SLIDE"
	var gap: float = maxf(float(storm.gap_to(runner.distance)), 0.0)
	storm_label.text = "STORM  %d m  //  %d km/h" % [int(gap), int(storm.speed * 3.6)]
	storm_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.35) if gap < 40.0 else Color(0.96, 0.53, 0.72))
	if not run_finished:
		message_label.visible = runner.hit_timer > 0.0
		message_label.text = "IMPACT  //  MOMENTUM LOST"

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
	message_label.text = reason + "  //  %d m" % int(meters)
	message_label.visible = true
	restart_button.visible = true

func _toggle_camera() -> void:
	first_person = not first_person
	runner.set_first_person(first_person)
	_update_camera(1.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_V or key.keycode == KEY_C:
		_toggle_camera()
	elif key.keycode == KEY_R:
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
	var stack := VBoxContainer.new()
	stack.position = Vector2(22, 18)
	stack.add_theme_constant_override("separation", 2)
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
	section_label = _label("", 17, Color(0.1, 0.9, 0.95))
	stack.add_child(section_label)
	slide_label = _label("", 16, Color(0.4, 0.96, 0.9))
	stack.add_child(slide_label)
	storm_label = _label("", 18, Color(1.0, 0.33, 0.50))
	stack.add_child(storm_label)
	message_label = _label("", 25, Color(1.0, 0.84, 0.3))
	root.add_child(message_label)
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.offset_left = -260
	message_label.offset_right = 260
	message_label.offset_top = 65
	message_label.offset_bottom = 112
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.visible = false
	var hint := _label("A / D steer  ·  SPACE jump  ·  HOLD SHIFT / S slide  ·  V view  ·  R retry", 15, Color(0.7, 0.83, 0.96))
	root.add_child(hint)
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
	restart_button = Button.new()
	restart_button.text = "RUN AGAIN"
	root.add_child(restart_button)
	restart_button.set_anchors_preset(Control.PRESET_CENTER)
	restart_button.offset_left = -90
	restart_button.offset_right = 90
	restart_button.offset_top = 8
	restart_button.offset_bottom = 65
	restart_button.visible = false
	restart_button.pressed.connect(_restart)
