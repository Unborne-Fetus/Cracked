extends Node
## Local, state-recorded replay. No simulation, scoring or network calls.
const FILE_PATH := "user://velocity_last_replay.dat"
const FORMAT := 1
const INTERVAL := 0.05
const MAX_FRAMES := 36001
var frames: Array[Dictionary] = []
var archived: Dictionary = {}
var elapsed_since_sample := 0.0
var truncated := false

func load_last() -> void:
	if not FileAccess.file_exists(FILE_PATH):
		return
	var file := FileAccess.open(FILE_PATH, FileAccess.READ)
	if file == null or file.get_length() > 48 * 1024 * 1024:
		return
	var data = file.get_var(false)
	if data is Dictionary and int(data.get("format", 0)) == FORMAT and data.get("frames", []) is Array and data.get("recipes", []) is Array:
		if not data["frames"].is_empty() and not data["recipes"].is_empty():
			archived = data

func reset_recording() -> void:
	frames.clear()
	elapsed_since_sample = 0.0
	truncated = false

func record(t: float, delta: float, runner: Node3D, course: Node3D, storm: Node3D, force: bool = false) -> void:
	if truncated:
		return
	var recipes: Array = course.get("replay_recipes")
	var index: int = course.call("chunk_index_at", float(runner.get("distance")))
	if frames.size() >= MAX_FRAMES or index >= recipes.size():
		truncated = true
		return
	elapsed_since_sample += delta
	if not force and elapsed_since_sample < INTERVAL:
		return
	elapsed_since_sample = fmod(elapsed_since_sample, INTERVAL)
	var shift: Vector3 = course.get("origin_shift")
	var pose := runner.transform
	pose.origin += shift
	var frame := {"t": t, "pose": pose, "shift": shift, "s": runner.get("distance"), "lane": runner.get("lane"), "side": runner.get("surface_side"), "speed": runner.get("speed"), "grounded": runner.get("grounded"), "sliding": runner.get("is_sliding"), "diving": runner.get("diving"), "height": runner.get("height"), "air_time": runner.get("air_time"), "kickflip": runner.get("kickflip_progress"), "rider_crouch": runner.get("rider_crouch"), "rider_phase": runner.get("rider_phase"), "rider_steer": runner.get("rider_steer"), "rider_landing": runner.get("rider_landing"), "rider_impact": runner.get("rider_impact"), "rider_clearance": runner.get("rider_clearance"), "rider_dive": runner.get("rider_dive"), "rider_flourish": runner.get("rider_flourish"), "rider_bank": runner.get("rider_bank"), "rider_brace": runner.get("rider_brace"), "rider_trick_mix": runner.get("rider_trick_mix"), "rider_trick_clock": runner.get("rider_trick_clock"), "steering_heading":runner.get("steering_heading"), "rider_ground_idle":runner.get("rider_ground_idle"), "rider_inverted":runner.get("rider_inverted"), "rider_glider":runner.get("rider_glider"), "rider_glider_return":runner.get("rider_glider_return"),"rider_glider_entry":runner.get("rider_glider_entry"),"rider_glider_gyro":runner.get("rider_glider_gyro"), "rider_glider_spin":runner.get("rider_glider_spin"),"glider_trick_clock":runner.get("glider_trick_clock"),"gyro_trick_clock":runner.get("gyro_trick_clock"), "drift_amount":runner.get("drift_amount"), "rider_ground_variant":runner.get("rider_ground_variant"),"cycle_fall":runner.get("cycle_fall"), "reserve": runner.get("momentum_reserve"), "double_jump": runner.get("double_jump_available"), "storm_s": storm.get("front_s"), "storm_speed": storm.get("speed"), "storm_time": storm.get("elapsed"), "storm_visible": storm.visible}
	if not frames.is_empty() and t <= float(frames[-1]["t"]):
		frames[-1] = frame
	else:
		frames.append(frame)

func finish(course: Node3D, seed_value: int, mode_value: int, cosmetic_value: int, reason: String = "", final_gap: float = 0.0) -> void:
	if frames.size() < 2:
		return
	archived = {"format": FORMAT, "seed": seed_value, "mode": mode_value, "cosmetic": cosmetic_value, "truncated": truncated, "reason":reason,"final_gap":final_gap,"frames": frames.duplicate(true), "recipes": course.get("replay_recipes").duplicate(true)}
	var file := FileAccess.open(FILE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_var(archived, false)

func available() -> bool:
	return not archived.is_empty() and archived.get("frames", []).size() >= 2

func duration() -> float:
	if not available():
		return 0.0
	return float(archived["frames"][-1]["t"])

func sample(t: float) -> Dictionary:
	var samples: Array = archived["frames"]
	var time := clampf(t, 0.0, duration())
	var lo := 0
	var hi := samples.size() - 1
	while lo + 1 < hi:
		var mid := (lo + hi) / 2
		if float(samples[mid]["t"]) <= time:
			lo = mid
		else:
			hi = mid
	var a: Dictionary = samples[lo]
	var b: Dictionary = samples[hi]
	var blend := clampf((time - float(a["t"])) / maxf(0.00001, float(b["t"]) - float(a["t"])), 0.0, 1.0)
	var result: Dictionary = (a if blend < 0.5 else b).duplicate()
	var pose_a: Transform3D = a["pose"]
	var pose_b: Transform3D = b["pose"]
	result["pose"] = pose_a.interpolate_with(pose_b, blend)
	for key in ["s", "lane", "speed", "height", "air_time", "reserve", "storm_s", "storm_speed", "storm_time"]:
		result[key] = lerpf(float(a[key]), float(b[key]), blend)
	for key in ["rider_crouch", "rider_phase", "rider_steer", "rider_landing", "rider_impact", "rider_clearance", "rider_dive", "rider_flourish", "rider_bank", "rider_brace", "rider_trick_mix", "rider_trick_clock", "steering_heading", "rider_ground_idle", "rider_inverted", "drift_amount","rider_glider","glider_trick_clock","gyro_trick_clock","cycle_fall"]:
		result[key] = lerpf(float(a.get(key, 0.0)), float(b.get(key, 0.0)), blend)
	result["rider_ground_variant"] = int((a if blend<0.5 else b).get("rider_ground_variant",0))
	for phase_key:String in ["rider_glider_entry","rider_glider_gyro"]:
		var phase_a:=float(a.get(phase_key,-1.0))
		var phase_b:=float(b.get(phase_key,-1.0))
		result[phase_key]=lerpf(phase_a,phase_b,blend) if phase_a>=0.0 and phase_b>=0.0 else (phase_a if blend<0.5 else phase_b)
	var return_a:=float(a.get("rider_glider_return",-1.0))
	var return_b:=float(b.get("rider_glider_return",-1.0))
	result["rider_glider_return"]=lerpf(return_a,return_b,blend) if return_a>=0.0 and return_b>=0.0 else (return_a if blend<0.5 else return_b)
	var spin_a:=float(a.get("rider_glider_spin",1.0))
	var spin_b:=float(b.get("rider_glider_spin",1.0))
	result["rider_glider_spin"]=lerpf(spin_a,spin_b,blend) if spin_b>=spin_a else (spin_a if blend<0.5 else spin_b)
	var flip_a := float(a.get("kickflip", 1.0))
	var flip_b := float(b.get("kickflip", 1.0))
	if flip_b >= flip_a:
		result["kickflip"] = lerpf(flip_a, flip_b, blend)
	else:
		result["kickflip"] = flip_a if blend < 0.5 else flip_b
	result["t"] = time
	return result
