extends Node
## Local profile and competitive run records, separate from practice.

var achievements: Dictionary = {}
var records: Dictionary = {}
var cosmetic := 0
var keys: Dictionary = {}
var pads: Dictionary = {}
var music := true # Legacy key now controls adaptation only.
var soundtrack := true
var trails := true
var vibration := true
var player_id := ""
var top_speed := 0.0
var airtime := 0.0
var slide_time := 0.0
var momentum_lost := 0.0

static func daily_seed(day: String) -> int:
	return int(("VECTOR-VELOCITY-DAILY-" + day).hash())

func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://velocity_profile.cfg") == OK:
		achievements = cfg.get_value("profile", "achievements", {})
		records = cfg.get_value("profile", "records", {})
		cosmetic = int(cfg.get_value("profile", "cosmetic", 0))
		keys = cfg.get_value("controls", "keys", {})
		pads = cfg.get_value("controls", "pads", {})
		music = bool(cfg.get_value("effects", "music", true))
		soundtrack = bool(cfg.get_value("effects", "soundtrack", true))
		trails = bool(cfg.get_value("effects", "trails", true))
		vibration = bool(cfg.get_value("effects", "vibration", true))
		player_id = str(cfg.get_value("profile", "player_id", ""))
	if player_id.is_empty():
		player_id = "Runner-" + Crypto.new().generate_random_bytes(6).hex_encode()
	if not cosmetic_unlocked(cosmetic):
		cosmetic = 0

func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "achievements", achievements)
	cfg.set_value("profile", "records", records)
	cfg.set_value("profile", "cosmetic", cosmetic)
	cfg.set_value("profile", "player_id", player_id)
	cfg.set_value("controls", "keys", keys)
	cfg.set_value("controls", "pads", pads)
	cfg.set_value("effects", "music", music)
	cfg.set_value("effects", "soundtrack", soundtrack)
	cfg.set_value("effects", "trails", trails)
	cfg.set_value("effects", "vibration", vibration)
	cfg.save("user://velocity_profile.cfg")

func reset_stats() -> void:
	top_speed = 0.0
	airtime = 0.0
	slide_time = 0.0
	momentum_lost = 0.0

func track(delta: float, runner: Node3D, previous_speed: float) -> void:
	var v: float = runner.get("speed")
	top_speed = maxf(top_speed, v)
	if not bool(runner.call("is_grounded")):
		airtime += delta
	if bool(runner.get("is_sliding")):
		slide_time += delta
	momentum_lost += maxf(0.0, previous_speed - v)

func record_key(mode: int, day: String) -> String:
	return "daily:" + day if mode == 1 else "mode:" + str(mode)

func best_for(mode: int, day: String) -> float:
	return float(records.get(record_key(mode, day), {}).get("distance", 0.0))

func cosmetic_unlocked(index: int) -> bool:
	return index == 0 or (index == 1 and achievements.has("First kilometer")) or (index == 2 and achievements.has("Velocity 100")) or (index == 3 and achievements.has("Five kilometers"))

func finish(mode: int, day: String, seed_value: int, distance: float, seconds: float, runner: Node3D) -> void:
	if mode == 5:
		return
	var key := record_key(mode, day)
	if distance >= best_for(mode, day):
		records[key] = {"distance": distance, "speed": top_speed, "seconds": seconds, "seed": seed_value}
	var checks := {"First kilometer": distance >= 1000.0, "Five kilometers": distance >= 5000.0, "Velocity 100": top_speed >= 100.0, "Velocity 200": top_speed >= 200.0, "Gate master": int(runner.get("clean_gates")) >= 3}
	for title in checks:
		if bool(checks[title]):
			achievements[title] = true
	save_profile()

func summary(distance_text: String, display_speed: int, units: String) -> String:
	return "DISTANCE %s    |    TOP SPEED %d %s\nSLIDING %.1f s\nMOMENTUM LOST %.1f m/s" % [distance_text, display_speed, units, slide_time, momentum_lost]
