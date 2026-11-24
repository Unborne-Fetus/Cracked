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
	"recovery": {"name": "Second Wind", "detail": "+1 attempt (maximum 5)", "cost": 28}
}
const ROUTES := ["Flow meadow", "Rift crossing", "High ridges"]
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

func terrain_seed() -> int:
	return seed_value + shard * 7919 + world * 104729 + route * 15485863

func guardian() -> bool:
	return world == 3

func collect(amount: int) -> void:
	pending_currency += maxi(0, amount)

func fail_world() -> void:
	pending_currency = 0
	attempts = maxi(0, attempts - 1)

func finish_world(distance: float, time: float, perfect: int) -> void:
	currency += pending_currency + 16 + mini(perfect * 2, 16)
	pending_currency = 0
	total_distance += distance
	total_time += time
	offers.clear()
	if guardian():
		complete = true
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed() + 337
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
	var cost: int = ITEMS[id]["cost"]
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
	if complete or world >= 3:
		return false
	world += 1
	route = clampi(choice, 0, ROUTES.size() - 1)
	offers.clear()
	return true

func title() -> String:
	return "SHARD %02d  /  %s" % [shard, SHARD_NAMES[shard - 1]]
