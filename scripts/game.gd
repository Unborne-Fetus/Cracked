extends Node3D
const Terrain = preload("res://scripts/course.gd")
const Runner = preload("res://scripts/runner.gd")
var course: Node3D
var runner: Node3D
var camera: Camera3D
var collapse: MeshInstance3D
var gate: Node3D
var stage := 1
var elapsed := 0.0
var best := 0.0
var storm_s := -130.0
var storm_speed := 17.0
var caught := 0.0
var status := "ready"
var camera_arm := Vector3.ZERO
var camera_ready := false
var distance_label: Label
var time_label: Label
var best_label: Label
var cue_label: Label
var overlay: ColorRect
var heading: Label
var subtitle: Label
var action_button: Button
var menu_button: Button
var music_button: CheckButton
var touch_controls: Control
var music_enabled := true
var audio: AudioStreamPlayer
var pad_jump := false
var pad_pause := false
var touch_mode := false

func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.51, 0.71, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.88, 1.0)
	env.ambient_light_energy = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.75, 0.85)
	env.fog_density = 0.0017
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.88, 0.72)
	sun.light_energy = 1.2
	add_child(sun)
	course = Terrain.new()
	add_child(course)
	runner = Runner.new()
	add_child(runner)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 80.0
	camera.far = 1250.0
	add_child(camera)
	collapse = MeshInstance3D.new()
	var wall := QuadMesh.new()
	wall.size = Vector2(220.0, 160.0)
	collapse.mesh = wall
	var storm_mat := StandardMaterial3D.new()
	storm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	storm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	storm_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	storm_mat.albedo_color = Color(0.76, 0.18, 0.35, 0.64)
	collapse.material_override = storm_mat
	add_child(collapse)
	gate = Node3D.new()
	add_child(gate)
	_make_gate()
	var config := ConfigFile.new()
	if config.load("user://velocity_flow.cfg") == OK:
		best = float(config.get_value("record", "distance", 0.0))
		music_enabled = bool(config.get_value("options", "music", true))
	_make_ui()
	_configure_music()
	_reset_stage()
	_show("ready", "VECTOR VELOCITY", "Run fast. Launch over hills. Dive into descents.", "START RUN")

func _make_gate() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.84, 0.39)
	for x in [-12.0, 12.0]:
		var pillar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.1, 15.0, 1.1)
		pillar.mesh = mesh
		pillar.material_override = mat
		pillar.position = Vector3(x, 7.0, 0.0)
		gate.add_child(pillar)
	var bar := MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(25.0, 0.8, 0.8)
	bar.mesh = beam
	bar.material_override = mat
	bar.position.y = 14.0
	gate.add_child(bar)

func _reset_stage() -> void:
	elapsed = 0.0
	storm_s = -130.0
	storm_speed = 17.0 + float(stage - 1) * 0.8
	caught = 0.0
	course.call("reset", randi(), stage)
	runner.call("reset", course)
	var length: float = course.get("length")
	gate.position = Vector3(0.0, float(course.call("elevation", 0.0, length)), -length)
	camera_ready = false
	_update_camera(1.0)
	_update_hud()

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("record", "distance", best)
	config.set_value("options", "music", music_enabled)
	config.save("user://velocity_flow.cfg")

func _configure_music() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.velocityMusic?.configure(" + ("true" if music_enabled else "false") + ",false,0)", true)
		if music_enabled:
			JavaScriptBridge.eval("window.velocityMusic?.start()", true)
	elif DisplayServer.get_name() != "headless":
		if not is_instance_valid(audio) and ResourceLoader.exists("res://audio/generated/soundtrack.ogg"):
			var clip := load("res://audio/generated/soundtrack.ogg") as AudioStreamOggVorbis
			if clip != null:
				clip.loop = true
				audio = AudioStreamPlayer.new()
				audio.stream = clip
				add_child(audio)
				audio.play()
		if is_instance_valid(audio):
			audio.volume_db = -8.0 if music_enabled else -80.0

func _physics_process(delta: float) -> void:
	var jump := false
	var pause_input := false
	for id in Input.get_connected_joypads():
		jump = jump or Input.is_joy_button_pressed(id, JOY_BUTTON_A)
		pause_input = pause_input or Input.is_joy_button_pressed(id, JOY_BUTTON_START)
	if pause_input and not pad_pause:
		_toggle_pause()
	if jump and not pad_jump:
		if status == "running":
			runner.call("request_jump")
		elif status in ["ready", "lost", "complete"]:
			_primary()
	pad_jump = jump
	pad_pause = pause_input
	if status != "running":
		return
	elapsed += delta
	runner.call("tick", delta, course)
	var s: float = runner.call("progress")
	course.call("stream", s)
	storm_speed += delta * (0.85 + 0.018 * elapsed)
	storm_s += storm_speed * delta
	collapse.position = Vector3(0.0, float(course.call("elevation", 0.0, storm_s)) + 25.0, -storm_s)
	caught = caught + delta if storm_s >= s else 0.0
	if bool(runner.get("fallen")) or caught > 0.35:
		best = maxf(best, s)
		_save()
		_show("lost", "RUN ENDED", "The collapse caught you." if caught > 0.35 else "You left the world.", "TRY AGAIN")
	elif s >= float(course.get("length")):
		best = maxf(best, s)
		_save()
		_show("complete", "WORLD CLEARED", "Stage %d complete." % stage, "NEXT WORLD")

func _process(delta: float) -> void:
	if status == "running":
		_update_camera(delta)
		_update_hud()

func _update_camera(delta: float) -> void:
	var p := runner.position
	var v: float = runner.get("speed")
	var lateral: float = runner.get("lateral")
	var forward := Vector3(lateral * 0.25, 0.0, -v).normalized()
	var pullback := lerpf(8.5, 15.0, smoothstep(25.0, 145.0, v))
	var target_arm := -forward * pullback + Vector3.UP * lerpf(4.5, 7.2, smoothstep(25.0, 145.0, v))
	camera_arm = camera_arm.lerp(target_arm, 1.0 - exp(-delta * 5.0)) if camera_ready else target_arm
	camera_ready = true
	camera.position = p + camera_arm
	camera.position.y = maxf(camera.position.y, float(course.call("elevation", camera.position.x, -camera.position.z)) + 2.4)
	var target := p + forward * 9.0 + Vector3.UP * 1.3
	var direction := (target - camera.position).normalized()
	var desired := Basis.looking_at(direction, Vector3.UP)
	camera.basis = camera.basis.slerp(desired, 1.0 - exp(-delta * 8.0)).orthonormalized()
	camera.fov = lerpf(camera.fov, lerpf(76.0, 104.0, smoothstep(20.0, 155.0, v)), 1.0 - exp(-delta * 3.0))

func _label(text_value: String, size_value: int) -> Label:
	var l := Label.new()
	l.text = text_value
	l.add_theme_font_size_override("font_size", size_value)
	l.add_theme_color_override("font_color", Color(0.98, 0.98, 0.96))
	l.add_theme_color_override("font_shadow_color", Color(0.10, 0.12, 0.20, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(text_value: String) -> Button:
	var b := Button.new()
	b.text = text_value
	b.custom_minimum_size = Vector2(260, 50)
	b.add_theme_font_size_override("font_size", 21)
	return b

func _make_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stats := VBoxContainer.new()
	stats.position = Vector2(24, 20)
	root.add_child(stats)
	distance_label = _label("", 23)
	time_label = _label("", 19)
	best_label = _label("", 19)
	best_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.46))
	for item in [distance_label, time_label, best_label]:
		stats.add_child(item)
	cue_label = _label("", 24)
	root.add_child(cue_label)
	cue_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cue_label.offset_left = -240
	cue_label.offset_right = 240
	cue_label.offset_top = -125
	cue_label.offset_bottom = -85
	cue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	touch_controls = HBoxContainer.new()
	root.add_child(touch_controls)
	touch_controls.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	touch_controls.offset_left = -220
	touch_controls.offset_right = 220
	touch_controls.offset_top = -70
	touch_controls.offset_bottom = -12
	for name_value in ["LEFT", "RIGHT", "JUMP", "DIVE", "II"]:
		var b := Button.new()
		b.text = name_value
		b.custom_minimum_size = Vector2(84, 52)
		touch_controls.add_child(b)
		match name_value:
			"LEFT":
				b.button_down.connect(func() -> void: runner.set("touch_steer", -1.0))
				b.button_up.connect(func() -> void: runner.set("touch_steer", 0.0))
			"RIGHT":
				b.button_down.connect(func() -> void: runner.set("touch_steer", 1.0))
				b.button_up.connect(func() -> void: runner.set("touch_steer", 0.0))
			"JUMP":
				b.pressed.connect(func() -> void: runner.call("request_jump"))
			"DIVE":
				b.button_down.connect(func() -> void: runner.set("touch_dive", true))
				b.button_up.connect(func() -> void: runner.set("touch_dive", false))
			"II":
				b.pressed.connect(_toggle_pause)
	touch_mode = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	touch_controls.visible = false
	overlay = ColorRect.new()
	overlay.color = Color(0.04, 0.08, 0.15, 0.82)
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	center.add_child(stack)
	heading = _label("", 46)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(heading)
	subtitle = _label("", 20)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(subtitle)
	action_button = _button("START")
	stack.add_child(action_button)
	action_button.pressed.connect(_primary)
	menu_button = _button("RESTART RUN")
	stack.add_child(menu_button)
	menu_button.pressed.connect(func() -> void: stage = 1; _reset_stage(); _start())
	music_button = CheckButton.new()
	music_button.text = "Soundtrack"
	music_button.set_pressed_no_signal(music_enabled)
	music_button.toggled.connect(func(v: bool) -> void: music_enabled = v; _configure_music(); _save())
	stack.add_child(music_button)
	var hint := _label("A / D  STEER    ·    SPACE  JUMP    ·    HOLD SHIFT  DIVE", 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(hint)

func _update_hud() -> void:
	var s: float = runner.call("progress")
	distance_label.text = "DISTANCE  %d m / %d m" % [maxi(0, int(s)), int(course.get("length"))]
	time_label.text = "TIME  %02d:%05.2f" % [int(elapsed / 60.0), fmod(elapsed, 60.0)]
	best_label.text = "BEST  %d m" % int(maxf(best, s))
	cue_label.text = str(runner.get("cue"))
	cue_label.visible = float(runner.get("cue_time")) > 0.0 and status == "running"

func _show(value: String, title: String, detail: String, action: String) -> void:
	status = value
	overlay.show()
	heading.text = title
	subtitle.text = detail
	action_button.text = action
	menu_button.visible = value != "ready"
	touch_controls.hide()
	cue_label.hide()
	action_button.grab_focus()

func _start() -> void:
	status = "running"
	overlay.hide()
	touch_controls.visible = touch_mode
	_configure_music()
	_update_hud()

func _primary() -> void:
	match status:
		"ready", "paused":
			_start()
		"lost":
			_reset_stage()
			_start()
		"complete":
			stage += 1
			_reset_stage()
			_start()

func _toggle_pause() -> void:
	if status == "running":
		runner.set("touch_steer", 0.0)
		runner.set("touch_dive", false)
		_show("paused", "PAUSED", "Keep your flow.", "RESUME")
	elif status == "paused":
		_start()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		touch_mode = true
		if status == "running":
			touch_controls.show()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				if status == "running":
					runner.call("request_jump")
				else:
					_primary()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_toggle_pause()
				get_viewport().set_input_as_handled()
			KEY_R:
				_reset_stage()
				_start()
				get_viewport().set_input_as_handled()
