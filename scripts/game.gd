extends Node3D
const Terrain = preload("res://scripts/course.gd")
const Runner = preload("res://scripts/runner.gd")
const Expedition = preload("res://scripts/expedition.gd")
const Guardian = preload("res://scripts/guardian.gd")
var expedition = Expedition.new()
var guardian: Node3D
var selected_shard := 1
var unlocked_shard := 1
var shard_picker: OptionButton
var shop_box: VBoxContainer
var shop_label: Label
var shop_buttons: Array[Button] = []
var expedition_label: Label
var last_collected := 0
var ability_picker: OptionButton
var reroll_button: Button
var rest_box: HBoxContainer
var rest_label: Label
var boss_label: Label
var ability_setting := 0
var resume_button: Button
var checkpoint_data: Dictionary = {}
var build_label: Label
var trial_label: Label
var last_guardian_clean := 0
var paused_from := "running"
var navigation_label: Label
var title_button: Button
var guidance_enabled := true
var endless_unlocked := false
var endless_setting := false
var difficulty_setting := 1
var difficulty_picker: OptionButton
var endless_best := 0.0
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
var pad_boost := false
var energy_meter: ProgressBar
var energy_label: Label
var lives := 3
var world_seed := 0
var camera_initialized := false
var pad_pause := false
var touch_mode := false
var last_landing_serial := 0
var camera_impact := 0.0
var finish_marker: MeshInstance3D
var sky_environment: Environment
var world_choice: HBoxContainer
var next_route := 0
var route_name := "Meadow"
var route_buttons: Array[Button] = []

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
	sky_environment = env
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
	guardian = Guardian.new()
	add_child(guardian)
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
		unlocked_shard = clampi(int(config.get_value("campaign", "unlocked", 1)), 1, Expedition.SHARD_COUNT)
		endless_unlocked = bool(config.get_value("campaign", "endless_unlocked", false))
		endless_best = float(config.get_value("record", "endless", 0.0))
		difficulty_setting = clampi(int(config.get_value("options", "difficulty", 1)), 0, 2)
		var stored: Variant = config.get_value("campaign", "checkpoint", {})
		if stored is Dictionary:
			checkpoint_data = stored
	_make_ui()
	_configure_music()
	world_seed = randi()
	expedition.begin(selected_shard, world_seed)
	_reset_stage()
	_show("ready", "VECTOR VELOCITY", "Find the next downslope. Dive to land. Escape the collapse.", "START RUN")

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
	stage = expedition.stage_index()
	lives = expedition.attempts
	storm_speed = (17.0 + float(mini((expedition.world - 1) if expedition.endless else (stage - 1), 24)) * 0.65 + (3.0 if expedition.guardian() else 0.0)) * expedition.storm_factor()
	caught = 0.0
	course.call("reset", expedition.terrain_seed(), stage, expedition.route, expedition.guardian())
	runner.call("reset", course)
	runner.call("apply_upgrades", expedition.items, expedition.ability)
	runner.call("apply_start_bonuses")
	guardian.call("reset", expedition.guardian(), expedition.terrain_seed(), expedition.shard)
	last_collected = 0
	last_guardian_clean = 0
	var length: float = course.get("length")
	gate.position = Vector3(0.0, float(course.call("elevation", 0.0, length)), -length)
	last_landing_serial = 0
	camera_impact = 0.0
	var skies: Array[Color] = [Color(0.51, 0.71, 0.86), Color(0.88, 0.61, 0.53), Color(0.43, 0.53, 0.78)]
	sky_environment.background_color = skies[(stage - 1 + next_route) % skies.size()]
	sky_environment.fog_light_color = sky_environment.background_color.lerp(Color.WHITE, 0.18)
	camera_ready = false
	camera_initialized = false
	collapse.position = Vector3(0.0, float(course.call("elevation", 0.0, storm_s)) + 25.0, -storm_s)
	_update_camera(1.0)
	_update_hud()

func _save() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var config := ConfigFile.new()
	config.set_value("record", "distance", best)
	config.set_value("campaign", "unlocked", unlocked_shard)
	config.set_value("campaign", "endless_unlocked", endless_unlocked)
	config.set_value("record", "endless", endless_best)
	config.set_value("options", "difficulty", difficulty_setting)
	config.set_value("campaign", "checkpoint", checkpoint_data)
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
	var boost_input := false
	for id in Input.get_connected_joypads():
		jump = jump or Input.is_joy_button_pressed(id, JOY_BUTTON_A)
		pause_input = pause_input or Input.is_joy_button_pressed(id, JOY_BUTTON_START)
		boost_input = boost_input or Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER)
	if pause_input and not pad_pause:
		_toggle_pause()
	if jump and not pad_jump and status in ["ready", "lost", "paused", "shard_complete"]:
		_primary()
	if boost_input and not pad_boost and status == "running":
		runner.call("request_boost")
	pad_boost = boost_input
	pad_jump = jump
	pad_pause = pause_input
	if status != "running":
		return
	elapsed += delta
	var old := runner.position
	runner.call("tick", delta, course)
	guardian.call("tick", course, runner, old)
	var clean: int = guardian.get("cleared_clean")
	if clean > last_guardian_clean:
		expedition.collect((clean - last_guardian_clean) * expedition.rank_of("guardianreward") * 2)
		last_guardian_clean = clean
	var new_collected: int = runner.get("collected")
	if new_collected > last_collected:
		expedition.collect(new_collected - last_collected)
		last_collected = new_collected
	var s: float = runner.call("progress")
	course.call("stream", s)
	storm_speed += delta * (0.52 + 0.008 * elapsed) * (1.0 - float(expedition.rank_of("storm")) * 0.10) * expedition.storm_factor()
	course.call("collapse_behind", storm_s)
	storm_s += storm_speed * delta
	collapse.position = Vector3(0.0, float(course.call("elevation", 0.0, storm_s)) + 25.0, -storm_s)
	caught = caught + delta if storm_s >= s else 0.0
	if bool(runner.get("fallen")) or caught > 0.35:
		if not expedition.endless:
			best = maxf(best, s)
			_save()
		expedition.fail_world()
		if expedition.endless:
			endless_best = maxf(endless_best, expedition.total_distance + maxf(0.0, s))
			_store_checkpoint()
			lives = 0
			_show("lost", "ENDLESS RUN ENDED", "%.0f m  •  %d worlds cleared" % [expedition.total_distance + maxf(0.0, s), expedition.world - 1], "TRY AGAIN")
			return
		_store_checkpoint()
		lives = expedition.attempts
		var reason := "The collapse caught you." if caught > 0.35 else "You left the world."
		_show("lost", "WORLD LOST", reason + ("  •  %d attempts left" % lives if lives > 0 else "  •  Expedition ended"), "TRY AGAIN" if lives > 0 else "NEW EXPEDITION")
	elif s >= float(course.get("length")):
		if not expedition.endless:
			best = maxf(best, s)
			_save()
		var pace := float(course.get("length")) / maxf(elapsed, 0.01)
		var rank := "S" if pace >= 90.0 else ("A" if pace >= 65.0 else ("B" if pace >= 46.0 else "C"))
		if int(runner.get("impacts")) == 0:
			expedition.collect(expedition.rank_of("purity") * 8)
		expedition.finish_world(float(course.get("length")), elapsed, int(runner.get("perfect_landings")), float(runner.get("energy")), float(runner.get("peak_speed")), int(runner.get("peak_chain")))
		if expedition.endless:
			endless_best = maxf(endless_best, expedition.total_distance)
			var carry_speed: float = minf(95.0, float(runner.get("speed")))
			var carry_energy: float = runner.get("energy")
			expedition.advance(0)
			_reset_stage()
			runner.set("speed", maxf(float(runner.get("speed")), carry_speed))
			runner.set("energy", maxf(float(runner.get("energy")), carry_energy))
			_store_checkpoint()
			return
		_store_checkpoint()
		if expedition.complete:
			unlocked_shard = maxi(unlocked_shard, mini(expedition.shard + 1, Expedition.SHARD_COUNT))
			if expedition.shard == Expedition.SHARD_COUNT:
				endless_unlocked = true
			_save()
			_show("shard_complete", "SHARD CLEARED  /  " + rank, "%s  •  %.0f m in %.1f s  •  Guardian %s" % [expedition.title(), expedition.total_distance, expedition.total_time, guardian.call("grade")], "NEXT SHARD" if expedition.shard < Expedition.SHARD_COUNT else "START ENDLESS")
		else:
			_show("complete", "WORLD CLEARED  /  " + rank, "%d perfect landings  •  %d attempts left%s" % [runner.get("perfect_landings"), lives, ("  •  TRIAL " + ("PASSED" if expedition.trial_success else "MISSED")) if expedition.route == 4 else ""], "NEXT WORLD")

func _process(delta: float) -> void:
	if status == "running":
		var serial: int = runner.get("landing_serial")
		if serial != last_landing_serial:
			last_landing_serial = serial
			camera_impact = 0.32 if str(runner.get("last_landing")) == "BAD" else 0.12
		camera_impact = move_toward(camera_impact, 0.0, delta * 1.6)
		_update_camera(delta)
		_update_hud()

func _update_camera(delta: float) -> void:
	var p := runner.position
	var v: float = runner.get("speed")
	var lateral: float = runner.get("lateral")
	var forward := Vector3(lateral * 0.25, 0.0, -v).normalized()
	var pullback := lerpf(6.8, 12.5, smoothstep(25.0, 145.0, v))
	var target_arm := -forward * pullback + Vector3.UP * lerpf(3.5, 5.8, smoothstep(25.0, 145.0, v))
	camera_arm = camera_arm.lerp(target_arm, 1.0 - exp(-delta * 5.0)) if camera_ready else target_arm
	camera_ready = true
	camera.position = p + camera_arm + Vector3.DOWN * camera_impact
	camera.position.y = maxf(camera.position.y, float(course.call("elevation", camera.position.x, -camera.position.z)) + 2.4)
	var look_ahead := lerpf(10.0, 24.0, smoothstep(30.0, 150.0, v))
	var target := p + forward * look_ahead + Vector3.UP * 1.1
	if not bool(runner.get("grounded")):
		look_ahead += minf(v * 0.16, 19.0)
		target = p + forward * look_ahead + Vector3.UP * 0.8
	var ground_ahead: float = course.call("elevation", target.x, -target.z)
	target.y = lerpf(target.y, ground_ahead + 2.0, 0.25 if bool(runner.get("grounded")) else 0.48)
	var direction := (target - camera.position).normalized()
	var desired := Basis.looking_at(direction, Vector3.UP)
	camera.basis = camera.basis.slerp(desired, 1.0 - exp(-delta * 8.0)).orthonormalized() if camera_initialized else desired
	camera_initialized = true
	var boost_fov := 5.0 if float(runner.get("boost_time")) > 0.0 else 0.0
	camera.fov = lerpf(camera.fov, lerpf(76.0, 107.0, smoothstep(20.0, 155.0, v)) + boost_fov, 1.0 - exp(-delta * 4.0))

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
	energy_label = _label("BOOST", 14)
	stats.add_child(energy_label)
	energy_meter = ProgressBar.new()
	energy_meter.max_value = 100.0
	energy_meter.custom_minimum_size = Vector2(155.0, 9.0)
	energy_meter.show_percentage = false
	energy_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(energy_meter)
	expedition_label = _label("", 14)
	stats.add_child(expedition_label)
	boss_label = _label("", 15)
	stats.add_child(boss_label)
	trial_label = _label("", 15)
	stats.add_child(trial_label)
	navigation_label = _label("", 15)
	stats.add_child(navigation_label)
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
	for name_value in ["LEFT", "RIGHT", "BOOST", "DIVE", "II"]:
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
			"BOOST":
				b.pressed.connect(func() -> void: runner.call("request_boost"))
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
	var scroll := ScrollContainer.new()
	overlay.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
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
	resume_button = _button("CONTINUE EXPEDITION")
	resume_button.pressed.connect(_resume_checkpoint)
	stack.add_child(resume_button)
	resume_button.hide()
	world_choice = HBoxContainer.new()
	stack.add_child(world_choice)
	for i in range(Expedition.ROUTES.size()):
		var choice := _button(Expedition.ROUTES[i].to_upper())
		choice.add_theme_font_size_override("font_size", 15)
		choice.custom_minimum_size = Vector2(165, 42)
		choice.tooltip_text = Expedition.ROUTE_DETAILS[i]
		choice.pressed.connect(_choose_route.bind(i))
		world_choice.add_child(choice)
		route_buttons.append(choice)
	world_choice.hide()
	shop_box = VBoxContainer.new()
	stack.add_child(shop_box)
	shop_label = _label("", 17)
	shop_box.add_child(shop_label)
	build_label = _label("", 15)
	build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_label.custom_minimum_size.x = 600.0
	shop_box.add_child(build_label)
	for i in range(3):
		var item := _button("")
		item.add_theme_font_size_override("font_size", 16)
		item.pressed.connect(_buy_offer.bind(i))
		shop_box.add_child(item)
		shop_buttons.append(item)
	reroll_button = _button("REROLL")
	reroll_button.custom_minimum_size.y = 36
	reroll_button.pressed.connect(_reroll_shop)
	shop_box.add_child(reroll_button)
	shop_box.hide()
	rest_label = _label("REST STOP — CHOOSE ONE", 20)
	stack.add_child(rest_label)
	rest_label.hide()
	rest_box = HBoxContainer.new()
	stack.add_child(rest_box)
	for i in range(2):
		var rest_button := _button("RESTORE ATTEMPT" if i == 0 else "TAKE SPARKS")
		rest_button.pressed.connect(_rest_choice.bind(i))
		rest_box.add_child(rest_button)
	rest_box.hide()
	shard_picker = OptionButton.new()
	shard_picker.custom_minimum_size = Vector2(300, 40)
	stack.add_child(shard_picker)
	shard_picker.item_selected.connect(_select_shard)
	_refresh_shard_picker()
	difficulty_picker = OptionButton.new()
	for i in range(Expedition.DIFFICULTIES.size()):
		difficulty_picker.add_item(Expedition.DIFFICULTIES[i] + " — " + Expedition.DIFFICULTY_DETAILS[i])
	difficulty_picker.select(difficulty_setting)
	difficulty_picker.item_selected.connect(func(index: int) -> void: difficulty_setting = index)
	stack.add_child(difficulty_picker)
	ability_picker = OptionButton.new()
	for i in range(Expedition.ABILITIES.size()):
		ability_picker.add_item(Expedition.ABILITIES[i] + " — " + Expedition.ABILITY_DETAILS[i])
	ability_picker.item_selected.connect(func(index: int) -> void: ability_setting = index)
	stack.add_child(ability_picker)
	menu_button = _button("RESTART RUN")
	stack.add_child(menu_button)
	menu_button.pressed.connect(func() -> void: _new_expedition(); _start())
	title_button = _button("RETURN TO TITLE")
	title_button.pressed.connect(_return_to_title)
	stack.add_child(title_button)
	music_button = CheckButton.new()
	music_button.text = "Soundtrack"
	music_button.set_pressed_no_signal(music_enabled)
	music_button.toggled.connect(func(v: bool) -> void: music_enabled = v; _configure_music(); _save())
	stack.add_child(music_button)
	var hint := _label("A / D  STEER    ·    HOLD SPACE  DIVE    ·    F  ABILITY    ·    M  TITLE", 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(hint)

func _update_hud() -> void:
	var s: float = runner.call("progress")
	distance_label.text = "DISTANCE  %d m  •  WORLD %d" % [int(expedition.total_distance + maxf(0.0, s)), expedition.world] if expedition.endless else "DISTANCE  %d m / %d m" % [maxi(0, int(s)), int(course.get("length"))]
	var display_time: float = elapsed + (float(expedition.total_time) if expedition.endless else 0.0)
	time_label.text = "TIME  %02d:%05.2f" % [int(display_time / 60.0), fmod(display_time, 60.0)]
	best_label.text = "BEST  %d m" % int(maxf(endless_best, expedition.total_distance + s) if expedition.endless else maxf(best, s))
	energy_meter.value = float(runner.get("energy"))
	var able := energy_meter.value >= float(runner.call("boost_cost")) and float(runner.get("cooldown")) <= 0.0 and float(runner.get("energy_lock")) <= 0.0
	energy_label.text = str(Expedition.ABILITIES[expedition.ability]).to_upper() + (" READY" if able else "")
	boss_label.visible = expedition.guardian()
	boss_label.text = "%s  •  PHASE %d / 3  •  %s" % [guardian.call("boss_name"), int(guardian.get("phase")) + 1, guardian.call("instruction_detail")]
	trial_label.visible = expedition.route == 4
	var progress_values: Array = [runner.get("perfect_landings"), int(runner.get("peak_speed")), expedition.pending_currency, runner.get("peak_chain")]
	trial_label.text = expedition.trial_text() + "  •  %d/%d" % [int(progress_values[expedition.trial_kind]), expedition.trial_target()] if expedition.route == 4 else ""
	var gap: Rect2 = course.call("next_gap", s, 420.0)
	navigation_label.visible = guidance_enabled and gap.has_area() and status == "running"
	if navigation_label.visible:
		var side := "RIGHT" if float(course.call("safe_lane", gap)) > 0.0 else "LEFT"
		navigation_label.text = "RAVINE %dm  •  BYPASS %s" % [maxi(0, int(gap.position.y - s)), side]
	expedition_label.text = "ENDLESS  •  %s" % Expedition.DIFFICULTIES[expedition.difficulty] if expedition.endless else "SHARD %02d  •  %d/%d  •  %d sparks  •  %d attempts" % [expedition.shard, expedition.world, Expedition.WORLDS_PER_SHARD, expedition.currency + expedition.pending_currency, expedition.attempts]
	cue_label.text = str(runner.get("cue"))
	cue_label.visible = float(runner.get("cue_time")) > 0.0 and status == "running"

func _show(value: String, title: String, detail: String, action: String) -> void:
	status = value
	overlay.show()
	heading.text = title
	subtitle.text = detail
	action_button.text = action
	world_choice.visible = value == "complete"
	shop_box.visible = value == "complete"
	shard_picker.visible = value == "ready"
	ability_picker.visible = value == "ready"
	difficulty_picker.visible = value == "ready"
	resume_button.visible = value == "ready" and not checkpoint_data.is_empty() and int(checkpoint_data.get("attempts", 0)) > 0 and not bool(checkpoint_data.get("complete", false))
	rest_box.visible = value == "rest"
	rest_label.visible = value == "rest"
	if value == "complete":
		_refresh_shop()
		for i in range(route_buttons.size()):
			route_buttons[i].text = Expedition.ROUTES[i].to_upper()
			route_buttons[i].visible = expedition.world < Expedition.WORLDS_PER_SHARD - 1 or i < 3
	action_button.visible = value not in ["complete", "rest"]
	menu_button.visible = value != "ready"
	title_button.visible = value != "ready"
	navigation_label.hide()
	touch_controls.hide()
	cue_label.hide()
	if value == "complete":
		next_route = 0
		route_buttons[0].grab_focus()
	elif value == "rest":
		(rest_box.get_child(0) as Button).grab_focus()
	else:
		action_button.grab_focus()

func _start() -> void:
	status = "running"
	_store_checkpoint()
	overlay.hide()
	touch_controls.visible = touch_mode
	_configure_music()
	_update_hud()

func _primary() -> void:
	match status:
		"ready":
			_new_expedition()
			_start()
		"paused":
			_start()
		"lost":
			if lives <= 0:
				_new_expedition()
			else:
				_reset_stage()
			_start()
		"complete":
			if expedition.advance(next_route):
				_store_checkpoint()
				if expedition.route == 3 and not expedition.guardian():
					_show("rest", "REST STOP", "Recover an attempt or take sparks.", "")
				else:
					_reset_stage()
					_start()
		"shard_complete":
			endless_setting = expedition.shard == Expedition.SHARD_COUNT and endless_unlocked
			selected_shard = mini(expedition.shard + 1, Expedition.SHARD_COUNT)
			_new_expedition()
			_start()

func _new_expedition() -> void:
	world_seed = randi()
	next_route = 0
	expedition.begin(selected_shard, world_seed, difficulty_setting, endless_setting and endless_unlocked)
	expedition.ability = ability_setting
	_reset_stage()

func _toggle_pause() -> void:
	if status == "running":
		runner.set("touch_steer", 0.0)
		runner.set("touch_dive", false)
		_show("paused", "PAUSED", "Keep your flow.", "RESUME")
	elif status == "paused":
		_start()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and status == "running" and not touch_mode:
		runner.call("request_boost")
		get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch:
		touch_mode = true
		if status == "running":
			touch_controls.show()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				if status not in ["complete", "rest"]:
					if status != "running":
						_primary()
					get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_RIGHT:
				if status == "complete":
					next_route = posmod(next_route + (-1 if event.physical_keycode == KEY_LEFT else 1), 3 if expedition.world == Expedition.WORLDS_PER_SHARD - 1 else route_buttons.size())
					route_buttons[next_route].grab_focus()
			KEY_F:
				if status == "running":
					runner.call("request_boost")
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_toggle_pause()
				get_viewport().set_input_as_handled()
			KEY_M:
				_return_to_title()
				get_viewport().set_input_as_handled()
			KEY_R:
				_new_expedition()
				_start()
				get_viewport().set_input_as_handled()

func _choose_route(index: int) -> void:
	if status != "complete" or (expedition.world == Expedition.WORLDS_PER_SHARD - 1 and index >= 3):
		return
	next_route = index
	_primary()

func _refresh_shard_picker() -> void:
	shard_picker.clear()
	for i in range(Expedition.SHARD_COUNT):
		shard_picker.add_item("%02d  %s" % [i + 1, Expedition.SHARD_NAMES[i]])
		shard_picker.set_item_disabled(i, i + 1 > unlocked_shard)
	shard_picker.add_item("ENDLESS — continuous worlds" if endless_unlocked else "ENDLESS — clear shard 10 to unlock")
	shard_picker.set_item_disabled(Expedition.SHARD_COUNT, not endless_unlocked)
	shard_picker.select(Expedition.SHARD_COUNT if endless_setting and endless_unlocked else selected_shard - 1)

func _refresh_shop() -> void:
	shop_label.text = "UPGRADES  •  %d sparks  •  %d attempts" % [expedition.currency, expedition.attempts]
	var inventory: Array[String] = []
	for id in expedition.items:
		inventory.append(str(Expedition.ITEMS[id]["name"]) + " ×" + str(expedition.items[id]))
	build_label.text = "BUILD: " + (", ".join(inventory) if not inventory.is_empty() else "No items") + "\nSETS: " + (", ".join(expedition.active_sets()) if not expedition.active_sets().is_empty() else "None")
	for i in range(shop_buttons.size()):
		var b := shop_buttons[i]
		b.visible = i < expedition.offers.size()
		if b.visible:
			var id: String = expedition.offers[i]
			var item: Dictionary = Expedition.ITEMS[id]
			var cost: int = expedition.item_cost(id)
			b.text = "%s  /  %d sparks  —  %s" % [item["name"], cost, item["detail"]]
			b.disabled = expedition.currency < cost
	reroll_button.text = "REROLL  /  %d sparks" % expedition.reroll_cost()
	reroll_button.disabled = expedition.currency < expedition.reroll_cost() or expedition.rerolls >= 3 or expedition.offers.is_empty()

func _buy_offer(index: int) -> void:
	if status != "complete" or index >= expedition.offers.size():
		return
	var id: String = expedition.offers[index]
	if expedition.buy(id):
		_store_checkpoint()
		lives = expedition.attempts
		_refresh_shop()
		_update_hud()

func _rest_choice(index: int) -> void:
	if status != "rest" or not expedition.encounter(index):
		return
	_reset_stage()
	_start()

func _reroll_shop() -> void:
	if status == "complete" and expedition.reroll():
		_store_checkpoint()
		_refresh_shop()

func _store_checkpoint() -> void:
	checkpoint_data = expedition.checkpoint()
	_save()

func _resume_checkpoint() -> void:
	if not expedition.restore(checkpoint_data):
		return
	selected_shard = expedition.shard
	endless_setting = expedition.endless
	difficulty_setting = expedition.difficulty
	ability_setting = expedition.ability
	lives = expedition.attempts
	_reset_stage()
	if expedition.complete:
		_show("shard_complete", "SHARD CLEARED", expedition.title(), "NEXT SHARD")
	elif expedition.world_cleared:
		_show("complete", "WORLD CLEARED", "Choose upgrades and the next route.", "NEXT WORLD")
	elif expedition.route == 3 and not expedition.encounter_resolved:
		_show("rest", "REST STOP", "Recover an attempt or take sparks.", "")
	elif expedition.attempts > 0:
		_start()
	else:
		_show("lost", "EXPEDITION ENDED", "No attempts remaining.", "NEW EXPEDITION")

func _return_to_title() -> void:
	if status == "ready":
		return
	_store_checkpoint()
	_refresh_shard_picker()
	ability_picker.select(ability_setting)
	difficulty_picker.select(difficulty_setting)
	_show("ready", "VECTOR VELOCITY", "Continue your expedition or start a new one.", "START NEW RUN")

func _select_shard(index: int) -> void:
	endless_setting = index == Expedition.SHARD_COUNT and endless_unlocked
	if not endless_setting:
		selected_shard = clampi(index + 1, 1, unlocked_shard)
