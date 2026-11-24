extends Node
## Original procedural soundtrack, controller feedback and speed streaks.

var music_enabled := true
var trails_enabled := true
var vibration_enabled := true
var speed := 0.0
var paused := false
var audio: AudioStreamPlayer
var browser_music_configured := false
var previous_music_enabled := true
const MUSIC_PATH := "res://audio/generated/soundtrack.ogg"
var clock := 0.0
var streaks: Control

class SpeedStreaks extends Control:
	var source: Node
	func _draw() -> void:
		if not is_instance_valid(source) or not source.trails_enabled or source.paused:
			return
		var amount := smoothstep(35.0, 160.0, float(source.speed))
		if amount <= 0.01:
			return
		var center := size * 0.5
		for i in range(28):
			var angle := TAU * float(i) / 28.0 + 0.07 * sin(float(i) * 2.1)
			var axis := Vector2(cos(angle), sin(angle))
			var r := fposmod(float(i) * 0.371 + float(source.clock) * (0.35 + amount * 0.9), 1.0)
			var p := center + axis * (0.62 + 0.45 * r) * size * 0.5
			draw_line(p, p + axis * (18.0 + 92.0 * amount), Color(0.52, 0.90, 1.0, amount * 0.35 * r), 1.5, true)

func make_trails() -> Control:
	streaks = SpeedStreaks.new()
	streaks.source = self
	streaks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return streaks

func reset_run() -> void:
	speed = 0.0
	paused = false

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
		JavaScriptBridge.eval("window.velocityMusic?.setEnabled(" + ("true" if music_enabled else "false") + ")", true)
		browser_music_configured = true
	previous_music_enabled = music_enabled

func activate_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if OS.has_feature("web"):
		if not browser_music_configured or music_enabled != previous_music_enabled:
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
	audio.volume_db = -9.0
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
	if music_enabled != previous_music_enabled:
		configure_music()
	if is_instance_valid(audio):
		# Only the explicit music option changes loudness. Death, speed,
		# restarts and pause cannot interrupt the composition.
		audio.volume_db = lerpf(audio.volume_db, -9.0 if music_enabled else -80.0, 1.0 - exp(-delta * 3.0))
