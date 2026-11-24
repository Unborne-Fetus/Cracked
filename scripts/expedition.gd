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
	"float": {"name": "Featherweight", "detail": "Slow fall near the end of boost", "cost": 20}
}
const ROUTES := ["Flow meadow", "Rift crossing", "High ridges", "Rest route", "Trial route"]
const WORLDS_PER_SHARD := 5
const ABILITIES := ["Burst", "Glide", "Surge", "Phase"]
const ABILITY_DETAILS := ["Instant speed and short sustained acceleration", "Extended low-gravity flight", "Powerful dive and landing acceleration", "Short hazard protection and speed recovery"]
var ability := 0
var encounter_resolved := false
var rerolls := 0
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

func terrain_seed() -> int:
	return seed_value + shard * 7919 + world * 104729 + route * 15485863

func guardian() -> bool:
	return world == WORLDS_PER_SHARD

func collect(amount: int) -> void:
	pending_currency += maxi(0, amount)

func fail_world() -> void:
	currency += int(float(pending_currency) * minf(0.6, float(rank_of("insurance")) * 0.2))
	pending_currency = 0
	attempts = maxi(0, attempts - 1)

func finish_world(distance: float, time: float, perfect: int, energy: float = 0.0) -> void:
	currency += pending_currency + 16 + mini(perfect * 2, 16) + rank_of("income") * 5 + int(energy * float(rank_of("bank")) * 0.08)
	if route == 4:
		currency += 12 + rank_of("challenge") * 6
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
	if complete or world >= WORLDS_PER_SHARD:
		return false
	world += 1
	route = clampi(choice, 0, ROUTES.size() - 1)
	encounter_resolved = false
	offers.clear()
	return true

func title() -> String:
	return "SHARD %02d  /  %s" % [shard, SHARD_NAMES[shard - 1]]

func rank_of(id: String) -> int:
	return clampi(int(items.get(id, 0)), 0, 3)

func item_cost(id: String) -> int:
	return maxi(8, int(ITEMS[id]["cost"]) - rank_of("thrift") * 3)

func reroll() -> bool:
	var cost := 6 + rerolls * 3
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
