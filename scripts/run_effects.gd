extends Node
## Original procedural soundtrack, controller feedback and speed streaks.

var music_enabled := true
var trails_enabled := true
var vibration_enabled := true
var speed := 0.0
var paused := false
var audio: AudioStreamPlayer
var phase := 0.0
var beat := 0.0
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
		audio = AudioStreamPlayer.new()
		var synth := AudioStreamGenerator.new()
		synth.mix_rate = 22050.0
		synth.buffer_length = 0.2
		audio.stream = synth
		audio.volume_db = -18.0
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
	audio.volume_db = -18.0 if music_enabled else -80.0
	if not music_enabled:
		return
	var playback := audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var intensity := smoothstep(20.0, 150.0, speed)
	var rate := lerpf(1.7, 3.4, intensity)
	var notes: Array[float] = [55.0, 65.406, 73.416, 82.407, 55.0, 65.406, 49.0, 73.416]
	for i in range(mini(playback.get_frames_available(), 2048)):
		beat += rate / 22050.0
		var fraction := fposmod(beat, 1.0)
		var note := notes[posmod(int(floor(beat)), notes.size())]
		phase = fposmod(phase + note / 22050.0, 1.0)
		var bass := (sin(TAU * phase) + 0.28 * sin(TAU * phase * 2.0)) * exp(-fraction * 3.0) * 0.45
		var lead := sin(TAU * phase * 4.0) * exp(-fposmod(beat * 2.0, 1.0) * 6.0) * intensity * 0.19
		var kick := sin(TAU * fraction * (24.0 - 10.0 * fraction)) * exp(-fraction * 15.0) * 0.22
		var sample_value := clampf(bass + lead + kick, -0.9, 0.9)
		playback.push_frame(Vector2(sample_value, sample_value))
