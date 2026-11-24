extends Node
## Original procedural soundtrack, controller feedback and speed streaks.

var music_enabled := true
var trails_enabled := true
var vibration_enabled := true
var speed := 0.0
var paused := false
var audio: AudioStreamPlayer
var soundtrack: AudioStreamSynchronized
var music_intensity := 0.0
const MUSIC_PATHS: Array[String] = [
	"res://audio/generated/foundation.ogg",
	"res://audio/generated/harmony.ogg",
	"res://audio/generated/velocity.ogg"
]
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
	if is_instance_valid(audio):
		audio.stream_paused = value
	if is_instance_valid(streaks):
		streaks.queue_redraw()

func activate_audio() -> void:
	if not music_enabled or DisplayServer.get_name() == "headless":
		return
	if not is_instance_valid(audio):
		# Build-time rendered stereo stems share an identical sample count.
		# Synchronized playback avoids beat drift, pitch changes and runtime
		# sample generation stalls in the Web export.
		var synced := AudioStreamSynchronized.new()
		synced.stream_count = MUSIC_PATHS.size()
		for index in range(MUSIC_PATHS.size()):
			if not ResourceLoader.exists(MUSIC_PATHS[index]):
				push_warning("Soundtrack assets missing: run tools/render_soundtrack.py")
				return
			var clip := load(MUSIC_PATHS[index]) as AudioStreamOggVorbis
			if clip == null:
				return
			clip.loop = true
			clip.loop_offset = 0.0
			synced.set_sync_stream(index, clip)
		synced.set_sync_stream_volume(0, 0.0)
		synced.set_sync_stream_volume(1, -8.0)
		synced.set_sync_stream_volume(2, -45.0)
		soundtrack = synced
		audio = AudioStreamPlayer.new()
		audio.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		audio.stream = soundtrack
		audio.volume_db = -7.0
		add_child(audio)
		audio.play()
	audio.stream_paused = paused

func update_run(v: float, hit: bool, landing: bool) -> void:
	speed = v
	if vibration_enabled and (hit or landing):
		for id_value in Input.get_connected_joypads():
			Input.start_joy_vibration(id_value, 0.35 if hit else 0.10, 0.72 if hit else 0.22, 0.20 if hit else 0.07)

func _process(delta: float) -> void:
	if paused:
		return
	clock += delta
	if is_instance_valid(streaks):
		streaks.queue_redraw()
	if not is_instance_valid(audio):
		return
	# Smooth gain changes instead of accelerating the BPM, so the score
	# remains musically coherent even after sudden collisions.
	audio.volume_db = move_toward(audio.volume_db, -7.0 if music_enabled else -80.0, delta * 95.0)
	if soundtrack == null:
		return
	var target := smoothstep(25.0, 155.0, speed)
	music_intensity = lerpf(music_intensity, target, 1.0 - exp(-delta * 1.65))
	soundtrack.set_sync_stream_volume(0, 0.0)
	soundtrack.set_sync_stream_volume(1, lerpf(-9.0, 0.0, music_intensity))
	soundtrack.set_sync_stream_volume(2, linear_to_db(maxf(0.006, smoothstep(0.15, 0.88, music_intensity))))
