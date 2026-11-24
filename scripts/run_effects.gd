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
var clock := 0.0
var streaks: Control

# Shared by drawing and headless regression checks.
static func streak_intensity(v: float) -> float:
	return smoothstep(15.0, 110.0, v)

static func soundtrack_gain(enabled: bool, adaptive: bool, v: float) -> float:
	if not enabled:
		return 0.0
	return lerpf(0.34, 0.62, smoothstep(20.0, 180.0, v)) if adaptive else 0.42

class SpeedStreaks extends Control:
	var source: Node
	func _draw() -> void:
		if not is_instance_valid(source) or not source.trails_enabled or source.paused:
			return
		var amount: float = source.streak_intensity(float(source.speed))
		if amount <= 0.002 or size.x < 2.0 or size.y < 2.0:
			return
		var center := size * 0.5
		var half := center - Vector2(3.0, 3.0)
		var scale_value := minf(size.x, size.y) / 720.0
		var count := 36
		for i in range(count):
			var angle := TAU * float(i) / float(count) + 0.08 * sin(float(i) * 2.1)
			var axis := Vector2(cos(angle), sin(angle))
			var edge_distance := minf(half.x / maxf(absf(axis.x), 0.001), half.y / maxf(absf(axis.y), 0.001))
			var phase := fposmod(float(i) * 0.371 + float(source.clock) * (0.48 + amount * 1.65), 1.0)
			var start_fraction := 0.37 + 0.45 * phase
			var end_fraction := minf(0.995, start_fraction + 0.09 + amount * 0.25)
			var start := center + axis * edge_distance * start_fraction
			var end := center + axis * edge_distance * end_fraction
			var fade := smoothstep(0.0, 0.14, phase) * (1.0 - smoothstep(0.82, 1.0, phase))
			var alpha := (0.12 + 0.65 * amount) * fade * smoothstep(0.002, 0.12, amount)
			draw_line(start, end, Color(0.32, 0.76, 1.0, alpha * 0.22), maxf(2.0, 5.5 * scale_value), true)
			draw_line(start, end, Color(0.78, 0.96, 1.0, alpha), maxf(1.5, 2.4 * scale_value), true)

func set_trails_enabled(value: bool) -> void:
	trails_enabled = value
	if is_instance_valid(streaks):
		streaks.visible = value
		streaks.queue_redraw()

func make_trails() -> Control:
	streaks = SpeedStreaks.new()
	streaks.source = self
	streaks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	streaks.resized.connect(streaks.queue_redraw)
	streaks.visible = trails_enabled
	return streaks

func reset_run() -> void:
	speed = 0.0
	paused = false
	clock = 0.0
	browser_speed_clock = 0.0
	if is_instance_valid(streaks):
		streaks.queue_redraw()

func set_paused(value: bool) -> void:
	paused = value
	# Only pause transitions change transport. Death/restart never seek.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.velocityMusic?.setPaused(" + ("true" if value else "false") + ")", true)
	elif is_instance_valid(audio) and audio.stream_paused != value:
		audio.stream_paused = value
	if is_instance_valid(streaks):
		streaks.queue_redraw()

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
	if not paused:
		clock += delta
		if is_instance_valid(streaks):
			streaks.queue_redraw()
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
