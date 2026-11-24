extends Node
## Original procedural soundtrack, controller feedback and speed streaks.

var music_enabled := true
var adaptive_music := true
var trails_enabled := true
var vibration_enabled := true
var speed := 0.0
var paused := false
var audio: AudioStreamPlayer
var browser_music_configured := false
var previous_music_enabled := true
var previous_adaptive_music := true
var browser_speed_clock := 0.0
const MUSIC_PATH := "res://audio/generated/soundtrack.ogg"
var trail: MeshInstance3D
var trail_mesh := ImmediateMesh.new()
var trail_material := StandardMaterial3D.new()
var trail_points: Array[Dictionary] = []
var trail_clock := 0.0
const TRAIL_LIFETIME := 0.65
const TRAIL_LIMIT := 72

# Shared by drawing and headless regression checks.
static func streak_intensity(v: float) -> float:
	return smoothstep(15.0, 110.0, v)

static func soundtrack_gain(enabled: bool, adaptive: bool, v: float) -> float:
	if not enabled:
		return 0.0
	return lerpf(0.34, 0.62, smoothstep(20.0, 180.0, v)) if adaptive else 0.42

func make_trails() -> void:
	trail = MeshInstance3D.new()
	trail.name = "RiderSpeedTrail"
	trail.mesh = trail_mesh
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_material.vertex_color_use_as_albedo = true
	trail_material.albedo_color = Color.WHITE
	add_child(trail)
	trail.visible = trails_enabled

func clear_trail() -> void:
	trail_points.clear()
	trail_mesh.clear_surfaces()
	trail_clock = 0.0

func set_trails_enabled(value: bool) -> void:
	trails_enabled = value
	clear_trail()
	if is_instance_valid(trail):
		trail.visible = value

# Store absolute positions; render relative to the current floating origin.
func sample_trail(pose: Transform3D, shift: Vector3, v: float, delta: float) -> void:
	if not trails_enabled or not is_instance_valid(trail):
		return
	trail_clock += maxf(0.0, delta)
	var amount := streak_intensity(v)
	var point := pose.origin + shift
	if not trail_points.is_empty():
		var last: Vector3 = trail_points[-1]["p"]
		if last.distance_to(point) > maxf(30.0, v * maxf(delta, 0.016) * 3.0 + 5.0):
			clear_trail()
	while not trail_points.is_empty() and (trail_clock - float(trail_points[0]["t"]) > TRAIL_LIFETIME or trail_points.size() >= TRAIL_LIMIT):
		trail_points.pop_front()
	if amount > 0.002:
		if trail_points.is_empty() or (trail_points[-1]["p"] as Vector3).distance_to(point) > 0.10:
			trail_points.append({"p": point, "t": trail_clock, "x": pose.basis.x.normalized(), "y": pose.basis.y.normalized(), "a": amount})
	trail_mesh.clear_surfaces()
	if trail_points.size() < 2:
		return
	trail.position = pose.origin
	# Two intersecting, tapered ribbons stay visible from any camera angle.
	# Alpha and width decay towards the tail; ordinary world depth occludes it.
	for axis_key in ["x", "y"]:
		trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, trail_material)
		for sample in trail_points:
			var age := clampf((trail_clock - float(sample["t"])) / TRAIL_LIFETIME, 0.0, 1.0)
			var strength := float(sample["a"])
			var fade := (1.0 - age) * (1.0 - age)
			var width := (0.10 + 0.34 * strength) * (0.15 + 0.85 * fade)
			var offset: Vector3 = sample[axis_key] * width
			var local: Vector3 = sample["p"] - point
			var tint := Color(0.22, 0.94, 1.0, fade * (0.20 + 0.72 * strength))
			trail_mesh.surface_set_color(tint)
			trail_mesh.surface_add_vertex(local - offset)
			trail_mesh.surface_set_color(tint)
			trail_mesh.surface_add_vertex(local + offset)
		trail_mesh.surface_end()

func reset_run() -> void:
	speed = 0.0
	paused = false
	browser_speed_clock = 0.0
	clear_trail()

func set_paused(value: bool) -> void:
	paused = value
	# Only pause transitions change transport. Death/restart never seek.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.velocityMusic?.setPaused(" + ("true" if value else "false") + ")", true)
	elif is_instance_valid(audio) and audio.stream_paused != value:
		audio.stream_paused = value

func configure_music() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.velocityMusic?.configure(" + ("true" if music_enabled else "false") + "," + ("true" if adaptive_music else "false") + "," + str(speed) + ")", true)
		browser_music_configured = true
	previous_music_enabled = music_enabled
	previous_adaptive_music = adaptive_music

func activate_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if OS.has_feature("web"):
		if not browser_music_configured or music_enabled != previous_music_enabled or adaptive_music != previous_adaptive_music:
			configure_music()
		# The HTML page also listens for real browser gestures. Once
		# playback starts, this is a no-op for every subsequent input.
		if music_enabled:
			JavaScriptBridge.eval("window.velocityMusic?.start()", true)
		return
	if not music_enabled or is_instance_valid(audio):
		return
	if not ResourceLoader.exists(MUSIC_PATH):
		return
	var clip := load(MUSIC_PATH) as AudioStreamOggVorbis
	if clip == null:
		return
	clip.loop = true
	clip.loop_offset = 0.0
	audio = AudioStreamPlayer.new()
	audio.stream = clip
	audio.volume_db = linear_to_db(maxf(0.0001, soundtrack_gain(music_enabled, adaptive_music, speed)))
	audio.stream_paused = paused
	add_child(audio)
	audio.play()

func update_run(v: float, hit: bool, landing: bool) -> void:
	speed = v
	if vibration_enabled and (hit or landing):
		for id_value in Input.get_connected_joypads():
			Input.start_joy_vibration(id_value, 0.35 if hit else 0.10, 0.72 if hit else 0.22, 0.20 if hit else 0.07)

func _process(delta: float) -> void:
	if music_enabled != previous_music_enabled or adaptive_music != previous_adaptive_music:
		configure_music()
	if OS.has_feature("web") and browser_music_configured and adaptive_music and music_enabled:
		browser_speed_clock -= delta
		if browser_speed_clock <= 0.0:
			browser_speed_clock = 0.15
			JavaScriptBridge.eval("window.velocityMusic?.setSpeed(" + str(speed) + ")", true)
	if is_instance_valid(audio):
		var gain := soundtrack_gain(music_enabled, adaptive_music, speed)
		var target_db := linear_to_db(maxf(0.0001, gain))
		audio.volume_db = lerpf(audio.volume_db, target_db, 1.0 - exp(-delta * 3.0))
