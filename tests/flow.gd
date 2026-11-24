extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	var course: Node3D = game.get("course")
	var runner: Node3D = game.get("runner")
	var rules = preload("res://scripts/runner.gd")
	if rules.ground_speed(40.0, -0.4, 1.0) <= 40.0 or rules.ground_speed(40.0, 0.4, 1.0) >= 40.0:
		_fail("Slope must change momentum.")
		return
	var downhill := Vector3(0.0, 1.0, -0.5).normalized()
	if rules.landing_speed(Vector3(0.0, -25.0, -50.0), downhill, -0.5, true) <= rules.landing_speed(Vector3(0.0, -25.0, -50.0), Vector3.UP, 0.0, true):
		_fail("Downhill dive must beat a hard flat landing.")
		return
	for i in range(8):
		var s := float(i) * 160.0
		if absf(float(course.call("elevation", 0.0, s - 0.001)) - float(course.call("elevation", 0.0, s + 0.001))) > 0.01:
			_fail("Terrain seam.")
			return
	if not rules.should_launch(90.0, -0.02, 0.0) or rules.should_launch(20.0, -0.02, 0.0):
		_fail("Natural crest takeoff rule is incorrect.")
		return
	if rules.landing_quality(Vector3(0.0, -25.0, -50.0), downhill, -0.5) != "PERFECT":
		_fail("Tangent landing must be perfect.")
		return
	runner.set("energy", 50.0)
	var pre_boost: float = runner.get("speed")
	runner.call("request_boost")
	runner.call("tick", 0.016, course)
	if float(runner.get("energy")) >= 50.0 or float(runner.get("speed")) <= pre_boost:
		_fail("Boost did not consume energy and increase speed.")
		return
	runner.call("reset", course)
	var launch_s := -1.0
	for i in range(20, 300):
		var at := float(i)
		var slope: Vector2 = course.call("grade", 0.0, at)
		if rules.should_launch(110.0, float(course.call("curvature", 0.0, at)), slope.y):
			launch_s = at
			break
	if launch_s < 0.0:
		_fail("Terrain has no launchable crests.")
		return
	runner.position = Vector3(0.0, float(course.call("elevation", 0.0, launch_s)) + 0.08, -launch_s)
	runner.set("speed", 110.0)
	runner.call("tick", 1.0 / 120.0, course)
	if bool(runner.get("grounded")):
		_fail("Natural takeoff did not launch.")
		return
	runner.call("reset", course)
	for i in range(900):
		runner.call("tick", 1.0 / 60.0, course)
		course.call("stream", float(runner.call("progress")))
		if not runner.position.is_finite() or not is_finite(float(runner.get("speed"))):
			_fail("Nonfinite movement.")
			return
	if float(runner.call("progress")) <= 50.0:
		_fail("Runner did not advance.")
		return
	var gap: Rect2 = course.call("gap_rect", 3)
	if not gap.has_area() or bool(course.call("has_ground", gap.get_center().x, gap.get_center().y)):
		_fail("Ravine mesh and support rule disagree.")
		return
	var bypass := 80.0 if gap.position.x < -100.0 else -80.0
	if not bool(course.call("has_ground", bypass, gap.get_center().y)):
		_fail("Ravine has no safe bypass.")
		return
	runner.call("reset", course)
	var x := gap.get_center().x
	var s := gap.position.y - 0.4
	runner.position = Vector3(x, float(course.call("elevation", x, s)) + 0.08, -s)
	runner.set("speed", 30.0)
	runner.call("tick", 0.025, course)
	if bool(runner.get("grounded")):
		_fail("Unsupported ravine edge did not launch.")
		return
	runner.call("reset", course)
	runner.position = Vector3(0.0, float(course.call("elevation", 0.0, 60.0)) + 12.0, -60.0)
	runner.set("grounded", false)
	runner.set("speed", 30.0)
	runner.set("vy", -12.0)
	var prediction: Dictionary = runner.call("predict_landing", course, true)
	if prediction.is_empty():
		_fail("Landing prediction failed over continuous terrain.")
		return
	var predicted: Vector3 = prediction["point"]
	if not bool(course.call("has_ground", predicted.x, -predicted.z)):
		_fail("Landing marker predicts unsupported ground.")
		return
	var campaign = preload("res://scripts/expedition.gd").new()
	campaign.begin(2, 1234)
	var seed_before: int = campaign.terrain_seed()
	campaign.collect(12)
	campaign.fail_world()
	if campaign.pending_currency != 0 or campaign.attempts != 2 or campaign.terrain_seed() != seed_before:
		_fail("Retry changed seed or retained unbanked sparks.")
		return
	campaign.collect(40)
	campaign.finish_world(2200.0, 30.0, 2)
	var balance: int = campaign.currency
	var offer: String = campaign.offers[0]
	if not campaign.buy(offer) or campaign.currency >= balance or campaign.buy(offer):
		_fail("Shop purchase or duplicate protection failed.")
		return
	if not campaign.advance(1) or campaign.guardian():
		_fail("Branch selection failed.")
		return
	campaign.finish_world(2200.0, 30.0, 2)
	if not campaign.advance(3) or not campaign.encounter(1) or campaign.encounter(1):
		_fail("Rest encounter must resolve only once.")
		return
	campaign.finish_world(2200.0, 30.0, 2)
	if not campaign.advance(4) or campaign.guardian():
		_fail("Trial route not reached.")
		return
	campaign.finish_world(2200.0, 30.0, 2)
	if not campaign.advance(2) or not campaign.guardian():
		_fail("Guardian stage not reached.")
		return
	campaign.finish_world(2200.0, 30.0, 2)
	if not campaign.complete or campaign.advance(0):
		_fail("Shard completion failed.")
		return
	var guard_rules = preload("res://scripts/guardian.gd")
	if not guard_rules.wave_hits(0.0, 1.0, 0.0) or guard_rules.wave_hits(35.0, 1.0, 0.0) or guard_rules.wave_hits(0.0, 8.0, 0.0):
		_fail("Guardian wave avoidance failed.")
		return
	runner.call("apply_upgrades", {"boost": 2, "glide": 2})
	if float(runner.call("boost_cost")) >= 28.0 or float(runner.call("flight_gravity", false, 0.0)) >= 32.0:
		_fail("Upgrades did not affect gameplay.")
		return
	var data: Dictionary = course.get("chunks")
	var found := false
	for chunk in data.values():
		for spark in chunk["sparks"]:
			if bool(spark["used"]):
				continue
			var point: Vector3 = spark["point"]
			var gain: int = course.call("collect_sparks", point - Vector3.FORWARD, point + Vector3.FORWARD)
			if gain <= 0 or int(course.call("collect_sparks", point, point)) != 0:
				_fail("Spark pickup must only be collected once.")
				return
			found = true
			break
		if found:
			break
	if not found:
		_fail("No collectible sparks generated.")
		return
	var expedition_rules = preload("res://scripts/expedition.gd")
	if expedition_rules.ITEMS.size() < 40 or expedition_rules.ABILITIES.size() != 4:
		_fail("Expanded item and ability catalog missing.")
		return
	for kind in range(4):
		runner.call("reset", course)
		runner.call("apply_upgrades", {}, kind)
		runner.set("energy", 100.0)
		runner.set("grounded", false)
		runner.set("vy", -5.0)
		if not bool(runner.call("_activate_boost")) or float(runner.get("energy")) >= 100.0:
			_fail("Ability did not spend energy.")
			return
		if kind == 1 and float(runner.call("flight_gravity", false, 1.0)) >= 10.0:
			_fail("Glide does not reduce gravity.")
			return
		if kind == 2 and float(runner.get("vy")) > -22.0:
			_fail("Surge did not dive.")
			return
		if kind == 3 and float(runner.get("protected_time")) <= 0.0:
			_fail("Phase protection missing.")
			return
	if not guard_rules.pattern_hits(1, 60.0, 1.0, 0.0) or guard_rules.pattern_hits(1, 0.0, 1.0, 0.0) or not guard_rules.pattern_hits(3, 0.0, 10.0, 0.0):
		_fail("Guardian patterns have invalid safe zones.")
		return
	var economy = expedition_rules.new()
	economy.begin(1, 777)
	economy.collect(100)
	economy.finish_world(1000.0, 20.0, 1)
	var old_money: int = economy.currency
	if not economy.reroll() or economy.currency != old_money - 6:
		_fail("Shop reroll economy invalid.")
		return
	var checkpoint = expedition_rules.new()
	checkpoint.begin(4, 443)
	checkpoint.collect(40)
	checkpoint.finish_world(2200.0, 32.0, 4)
	var money: int = checkpoint.currency
	checkpoint.finish_world(2200.0, 32.0, 4)
	if checkpoint.currency != money:
		_fail("Repeated world completion awarded currency twice.")
		return
	var snapshot: Dictionary = checkpoint.checkpoint()
	var restored = expedition_rules.new()
	if not restored.restore(snapshot) or restored.currency != money or not restored.world_cleared or restored.terrain_seed() != checkpoint.terrain_seed():
		_fail("Expedition checkpoint round trip failed.")
		return
	if not restored.advance(4) or restored.advance(0):
		_fail("World advancement requires a completed world.")
		return
	for kind in range(4):
		restored.trial_kind = kind
		if restored.trial_met(0, 0.0, 0, 0) or not restored.trial_met(100, 300.0, 100, 100):
			_fail("Trial objective threshold invalid.")
			return
	if guard_rules.NAMES.size() != 10 or guard_rules.PROGRAMS.size() != 10:
		_fail("Distinct guardian programs missing.")
		return
	if not guard_rules.pattern_hits(4, 0.0, 6.0, 0.0) or guard_rules.pattern_hits(4, 60.0, 6.0, 0.0) or not guard_rules.pattern_hits(5, 60.0, 10.0, 0.0):
		_fail("New guardian pattern boundaries incorrect.")
		return
	var profiles: Array = []
	for i in range(10):
		if profiles.has(guard_rules.PROGRAMS[i]):
			_fail("Guardian program duplicated.")
			return
		profiles.append(guard_rules.PROGRAMS[i])
	runner.call("reset", course)
	runner.call("apply_upgrades", {"lastchance": 1})
	runner.position = Vector3(126.0, 0.0, -20.0)
	runner.call("_fail_or_rescue", course)
	if bool(runner.get("fallen")) or int(runner.get("void_rescues")) != 1:
		_fail("Last Light did not recover from void.")
		return
	runner.call("_fail_or_rescue", course)
	if not bool(runner.get("fallen")):
		_fail("Last Light can be used more than once.")
		return
	# Traverse a complete seeded rest route using the real 120 Hz physics.
	# Avoid visual updates for a fast, deterministic headless simulation.
	course.call("reset", 98765, 1, 3, false)
	runner.call("reset", course)
	runner.call("apply_upgrades", {}, 0)
	var traversal_time := 0.0
	var full_length: float = course.get("length")
	var last_chunk := -1
	for step in range(120 * 120):
		var forward: float = runner.call("progress")
		if forward >= full_length:
			break
		if bool(runner.get("fallen")):
			_fail("Runner fell on a continuous centerline.")
			return
		var chunk := int(floor(forward / 160.0))
		if chunk != last_chunk:
			course.call("stream", forward)
			last_chunk = chunk
		if float(runner.get("energy")) >= float(runner.call("boost_cost")) and float(runner.get("speed")) < 75.0 and float(runner.get("cooldown")) <= 0.0:
			runner.call("request_boost")
		var descent := not bool(runner.get("grounded")) and float(runner.get("vy")) < -6.0
		runner.call("_step", 1.0 / 120.0, course, 0.0, descent)
		traversal_time += 1.0 / 120.0
		if not runner.position.is_finite():
			_fail("Nonfinite position during full route traversal.")
			return
	if float(runner.call("progress")) < full_length:
		_fail("Full physics route traversal exceeded 120 seconds.")
		return
	print("Full physics route traversal: %.1f seconds" % traversal_time)
	# Test the scene's real state transitions with controlled finish positions,
	# rather than claiming a full human playthrough.
	game.call("_new_expedition")
	game.call("_start")
	var session = game.get("expedition")
	for world_index in range(expedition_rules.WORLDS_PER_SHARD):
		var length: float = course.get("length")
		runner.position = Vector3(0.0, float(course.call("elevation", 0.0, length)) + 0.08, -length)
		runner.set("grounded", true)
		runner.set("fallen", false)
		game.call("_physics_process", 1.0 / 60.0)
		if world_index < expedition_rules.WORLDS_PER_SHARD - 1:
			if str(game.get("status")) != "complete":
				_fail("Scene did not reach shop after finish.")
				return
			game.call("_choose_route", 0)
			if str(game.get("status")) != "running":
				_fail("Scene did not start next world.")
				return
		elif str(game.get("status")) != "shard_complete" or not session.complete:
			_fail("Scene did not finish shard.")
			return
	print("PASS: flow movement, slopes, landings and streaming")
	quit(0)

func _fail(message: String) -> void:
	push_error("FLOW REGRESSION: " + message)
	quit(1)
