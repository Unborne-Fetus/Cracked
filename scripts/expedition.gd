extends RefCounted
## A three-world shard: opening, a branching route, then guardian escape.
const SHARD_COUNT := 10
const SHARD_NAMES := ["Verdant Reach", "Amber Divide", "Glass Tundra", "Sunken Sky", "Crimson Dunes", "Violet Rift", "Cloud Ruins", "Silver Expanse", "Broken Horizon", "Last Light"]
const ITEMS := {
	"stride": {"name": "Tailwind", "detail": "+8% ground acceleration per rank", "cost": 18},
	"landing": {"name": "Softstep", "detail": "Retain more speed on rough landings", "cost": 20},
	"charge": {"name": "Kinetic Cell", "detail": "+6 energy per good/perfect landing", "cost": 18},
	"boost": {"name": "Overdrive", "detail": "Stronger boost, lower energy cost", "cost": 22},
	"glide": {"name": "Airfoil", "detail": "Lower free-flight gravity", "cost": 20},
	"steer": {"name": "Quickstep", "detail": "Faster lateral response", "cost": 16},
	"recovery": {"name": "Second Wind", "detail": "+1 attempt (maximum 5)", "cost": 28},
	"launch": {"name": "Crestspring", "detail": "Extra lift at natural takeoff", "cost": 18},
	"dive": {"name": "Downforce", "detail": "Stronger dive gravity", "cost": 17},
	"drag": {"name": "Slipstream", "detail": "Reduce airborne speed loss", "cost": 15},
	"cap": {"name": "Redline", "detail": "Increase maximum speed by 15", "cost": 24},
	"start": {"name": "Running Start", "detail": "Begin worlds 8 m/s faster", "cost": 15},
	"battery": {"name": "Reserve Cell", "detail": "Start worlds with 15 extra energy", "cost": 17},
	"perfect": {"name": "Precision", "detail": "More speed on perfect landings", "cost": 24},
	"good": {"name": "Cadence", "detail": "More speed on good landings", "cost": 18},
	"chain": {"name": "Flow State", "detail": "Energy for consecutive clean landings", "cost": 22},
	"impact": {"name": "Shock Absorber", "detail": "Reduce obstacle slowdown", "cost": 20},
	"guardian": {"name": "Pulse Dampener", "detail": "Reduce guardian wave slowdown", "cost": 20},
	"magnet": {"name": "Spark Magnet", "detail": "Collect sparks from further away", "cost": 17},
	"fortune": {"name": "Prospector", "detail": "Extra sparks per pickup", "cost": 22},
	"thrift": {"name": "Bargain", "detail": "Discount future shop purchases", "cost": 18},
	"income": {"name": "Dividend", "detail": "Extra sparks for clearing worlds", "cost": 18},
	"aircharge": {"name": "Sky Battery", "detail": "Generate energy during airtime", "cost": 22},
	"boosttime": {"name": "Long Burn", "detail": "Extend ability duration", "cost": 22},
	"divecharge": {"name": "Rebound", "detail": "Energy from successful dive landings", "cost": 20},
	"recoveryrun": {"name": "Resilience", "detail": "Faster recovery at low speed", "cost": 16},
	"launchcharge": {"name": "Lift Cell", "detail": "Gain energy when leaving terrain", "cost": 18},
	"apex": {"name": "Apex", "detail": "Extra speed when boosting in the air", "cost": 23},
	"guard": {"name": "Afterimage", "detail": "Brief hazard protection during ability", "cost": 24},
	"composure": {"name": "Composure", "detail": "Energy even on rough landings", "cost": 16},
	"saver": {"name": "Efficient Circuit", "detail": "Reduce energy cost of every ability", "cost": 22},
	"momentum": {"name": "Momentum Link", "detail": "Consecutive clean landings add speed", "cost": 24},
	"wind": {"name": "Wind Reader", "detail": "Stronger airborne steering", "cost": 19},
	"sprint": {"name": "Sprint Coil", "detail": "Extra acceleration on level ground", "cost": 17},
	"bank": {"name": "Reserve Dividend", "detail": "Bank a portion of unspent energy on clear", "cost": 20},
	"insurance": {"name": "Safety Net", "detail": "Retain some sparks after a failed world", "cost": 23},
	"rest": {"name": "Camp Kit", "detail": "Gain extra sparks at rest stops", "cost": 16},
	"challenge": {"name": "Risk Premium", "detail": "Extra reward on challenge routes", "cost": 19},
	"synergy": {"name": "Conductor", "detail": "Boost effectiveness scales with other items", "cost": 25},
	"float": {"name": "Featherweight", "detail": "Slow fall near the end of boost", "cost": 20},
	"launchspeed": {"name": "Sky Kick", "detail": "Natural takeoffs grant speed", "cost": 21},
	"coast": {"name": "Coasting", "detail": "Retain more speed uphill", "cost": 18},
	"heat": {"name": "Heat Sink", "detail": "Shorter ability cooldown", "cost": 20},
	"first": {"name": "First Strike", "detail": "First clean landing grants extra energy", "cost": 18},
	"storm": {"name": "Storm Anchor", "detail": "Slow collapse acceleration", "cost": 24},
	"purity": {"name": "Clean Run", "detail": "Bonus sparks for avoiding obstacles", "cost": 23},
	"lastchance": {"name": "Last Light", "detail": "One void recovery per world", "cost": 35},
	"trialboost": {"name": "Trial Crest", "detail": "Extra energy on trial routes", "cost": 17},
	"shopgift": {"name": "Gift of Wind", "detail": "Free first reroll at each shop", "cost": 25},
	"guardianreward": {"name": "Warden's Token", "detail": "Extra sparks for clean guardian waves", "cost": 20},
	"restspeed": {"name": "Fresh Legs", "detail": "Start faster after a rest", "cost": 15},
	"threshold": {"name": "Breakthrough", "detail": "More acceleration at high speed", "cost": 23}
}
const ROUTES := ["Flow meadow", "Rift crossing", "High ridges", "Rest route", "Trial route"]
const WORLDS_PER_SHARD := 5
const ABILITIES := ["Burst", "Glide", "Surge", "Phase"]
const ABILITY_DETAILS := ["Instant speed and short sustained acceleration", "Extended low-gravity flight", "Powerful dive and landing acceleration", "Short hazard protection and speed recovery"]
var ability := 0
var encounter_resolved := false
var rerolls := 0
var world_cleared := false
var trial_kind := 0
var trial_success := false
var best_chain := 0
const TRIAL_NAMES := ["Precision trial", "Velocity trial", "Spark trial", "Flow trial"]
const ROUTE_DETAILS := ["Gentler hills and ordinary rewards", "Wide ravines and narrow bypasses", "Steeper hills and longer flights", "Short course + one recovery choice", "Harder course + optional bonus objective"]
var shard := 1
var world := 1
var route := 0
var seed_value := 0
var currency := 0
var pending_currency := 0
var items: Dictionary = {}
var offers: Array[String] = []
var attempts := 3
var complete := false
var total_distance := 0.0
var total_time := 0.0

func begin(shard_value: int, seed_input: int) -> void:
	shard = clampi(shard_value, 1, SHARD_COUNT)
	world = 1
	route = 0
	seed_value = seed_input
	currency = 0
	pending_currency = 0
	items.clear()
	offers.clear()
	attempts = 3
	complete = false
	total_distance = 0.0
	total_time = 0.0
	ability = 0
	encounter_resolved = false
	rerolls = 0
	world_cleared = false
	trial_kind = 0
	trial_success = false
	best_chain = 0

func terrain_seed() -> int:
	return seed_value + shard * 7919 + world * 104729 + route * 15485863

func guardian() -> bool:
	return world == WORLDS_PER_SHARD

func collect(amount: int) -> void:
	pending_currency += maxi(0, amount)

func fail_world() -> void:
	if world_cleared or complete:
		return
	currency += int(float(pending_currency) * minf(0.6, float(rank_of("insurance")) * 0.2))
	pending_currency = 0
	attempts = maxi(0, attempts - 1)

func finish_world(distance: float, time: float, perfect: int, energy: float = 0.0, peak_speed: float = 0.0, chain: int = 0) -> void:
	if world_cleared or complete:
		return
	world_cleared = true
	best_chain = maxi(best_chain, chain)
	trial_success = route == 4 and trial_met(perfect, peak_speed, pending_currency, chain)
	currency += pending_currency + 16 + mini(perfect * 2, 16) + rank_of("income") * 5 + int(energy * float(rank_of("bank")) * 0.08)
	if trial_success:
		currency += 30 + rank_of("challenge") * 8
	pending_currency = 0
	total_distance += distance
	total_time += time
	offers.clear()
	if guardian():
		complete = true
		return
	rerolls = 0
	_generate_offers()

func _generate_offers() -> void:
	offers.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed() + 337 + rerolls * 967
	var candidates: Array[String] = []
	for key in ITEMS.keys():
		var id: String = key
		if id == "recovery":
			if attempts < 5:
				candidates.append(id)
		elif int(items.get(id, 0)) < 3:
			candidates.append(id)
	while not candidates.is_empty() and offers.size() < 3:
		var at := rng.randi_range(0, candidates.size() - 1)
		offers.append(candidates.pop_at(at))

func buy(id: String) -> bool:
	if not offers.has(id) or not ITEMS.has(id):
		return false
	var cost := item_cost(id)
	if currency < cost:
		return false
	if id == "recovery":
		if attempts >= 5:
			return false
		attempts += 1
	else:
		var rank := int(items.get(id, 0))
		if rank >= 3:
			return false
		items[id] = rank + 1
	currency -= cost
	offers.erase(id)
	return true

func advance(choice: int) -> bool:
	if complete or not world_cleared or world >= WORLDS_PER_SHARD:
		return false
	world += 1
	route = clampi(choice, 0, ROUTES.size() - 1)
	encounter_resolved = false
	world_cleared = false
	trial_success = false
	trial_kind = posmod(terrain_seed(), TRIAL_NAMES.size())
	offers.clear()
	return true

func title() -> String:
	return "SHARD %02d  /  %s" % [shard, SHARD_NAMES[shard - 1]]

func rank_of(id: String) -> int:
	return clampi(int(items.get(id, 0)), 0, 3)

func item_cost(id: String) -> int:
	return maxi(8, int(ITEMS[id]["cost"]) - rank_of("thrift") * 3)

func reroll_cost() -> int:
	return 0 if rerolls == 0 and rank_of("shopgift") > 0 else 6 + rerolls * 3

func reroll() -> bool:
	var cost := reroll_cost()
	if offers.is_empty() or currency < cost or rerolls >= 3:
		return false
	currency -= cost
	rerolls += 1
	_generate_offers()
	return true

# Once per inter-world stop; no reward can be farmed by retrying.
func encounter(choice: int) -> bool:
	if encounter_resolved or complete or world <= 1 or route != 3:
		return false
	encounter_resolved = true
	if choice == 0:
		attempts = mini(5, attempts + 1)
	else:
		currency += 18 + rank_of("rest") * 6
	return true

func trial_target() -> int:
	match trial_kind:
		0: return 3 + mini(3, shard / 3)
		1: return 100 + mini(50, shard * 5)
		2: return 12 + mini(8, shard)
		_: return 3 + mini(2, shard / 4)

func trial_met(perfect: int, peak: float, sparks: int, chain: int) -> bool:
	var achieved: float = [perfect, peak, sparks, chain][trial_kind]
	return achieved >= trial_target()

func trial_text() -> String:
	var unit: String = ["perfect landings", "m/s peak speed", "sparks collected", "consecutive clean landings"][trial_kind]
	return "%s  /  %d %s" % [TRIAL_NAMES[trial_kind], trial_target(), unit]

func checkpoint() -> Dictionary:
	return {"version": 1, "shard": shard, "world": world, "route": route, "seed": seed_value, "currency": currency, "items": items.duplicate(), "offers": offers.duplicate(), "attempts": attempts, "complete": complete, "distance": total_distance, "time": total_time, "ability": ability, "encounter": encounter_resolved, "rerolls": rerolls, "cleared": world_cleared, "trial": trial_kind, "trial_success": trial_success, "chain": best_chain}

func restore(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 1:
		return false
	var sh := int(data.get("shard", 0))
	var wo := int(data.get("world", 0))
	if sh < 1 or sh > SHARD_COUNT or wo < 1 or wo > WORLDS_PER_SHARD:
		return false
	begin(sh, int(data.get("seed", 0)))
	world = wo
	route = clampi(int(data.get("route", 0)), 0, ROUTES.size() - 1)
	currency = maxi(0, int(data.get("currency", 0)))
	attempts = clampi(int(data.get("attempts", 3)), 0, 5)
	ability = clampi(int(data.get("ability", 0)), 0, ABILITIES.size() - 1)
	var saved_items: Variant = data.get("items", {})
	if saved_items is Dictionary:
		for key in saved_items:
			if ITEMS.has(key) and key != "recovery":
				items[key] = clampi(int(saved_items[key]), 1, 3)
	var saved_offers: Variant = data.get("offers", [])
	if saved_offers is Array:
		for key in saved_offers:
			if key is String and ITEMS.has(key) and not offers.has(key) and offers.size() < 3:
				offers.append(key)
	total_distance = maxf(0.0, float(data.get("distance", 0.0)))
	total_time = maxf(0.0, float(data.get("time", 0.0)))
	encounter_resolved = bool(data.get("encounter", false))
	rerolls = clampi(int(data.get("rerolls", 0)), 0, 3)
	world_cleared = bool(data.get("cleared", false))
	complete = guardian() and world_cleared and bool(data.get("complete", false))
	trial_kind = clampi(int(data.get("trial", 0)), 0, TRIAL_NAMES.size() - 1)
	trial_success = bool(data.get("trial_success", false))
	best_chain = maxi(0, int(data.get("chain", 0)))
	return true

func set_bonus(values: Array) -> bool:
	for id in values:
		if rank_of(str(id)) == 0:
			return false
	return true

func active_sets() -> Array[String]:
	var names: Array[String] = []
	if set_bonus(["stride", "sprint", "coast"]): names.append("RUNNER")
	if set_bonus(["glide", "launch", "wind"]): names.append("SKYBOUND")
	if set_bonus(["charge", "boost", "saver"]): names.append("DYNAMO")
	if set_bonus(["landing", "impact", "guardian"]): names.append("RESILIENT")
	return names
