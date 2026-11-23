extends SceneTree
## Headless regression: terrain must exist as an actual physics surface and
## CharacterBody3D must land on it, not visually pass through the wireframe.

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Could not load the main game scene.")
		return
	var game := packed.instantiate() as Node3D
	root.add_child(game)
	await physics_frame
	await physics_frame
	var course := game.get("course") as Node3D
	var runner := game.get("runner") as CharacterBody3D
	if course == null or runner == null:
		_fail("Course or player missing from the running scene.")
		return
	var ground_y: float = float(course.call("surface_height", 8.0, 0.0))
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(8.0, ground_y + 8.0, 0.0),
		Vector3(8.0, ground_y - 8.0, 0.0),
		1
	)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		_fail("Raycast failed: the visible terrain has no working collision at spawn.")
		return
	var grounded_frames := 0
	for frame in range(100):
		await physics_frame
		if runner.is_on_floor():
			grounded_frames += 1
	if grounded_frames < 12:
		_fail("Player never landed reliably on terrain (grounded frames: %d)." % grounded_frames)
		return
	print("PASS: terrain raycast hit and player grounded for %d/100 frames." % grounded_frames)
	game.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	push_error("GROUND COLLISION REGRESSION: " + reason)
	quit(1)
