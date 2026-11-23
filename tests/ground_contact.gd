extends SceneTree

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate() as Node3D
	root.add_child(game)
	await physics_frame
	await physics_frame
	game.set_physics_process(false)
	var course: Node3D = game.get("course")
	var runner: Node3D = game.get("runner")
	var frame: Transform3D = course.call("sample", float(runner.get("distance")))
	var ray := PhysicsRayQueryParameters3D.create(frame.origin + frame.basis.y * 8.0, frame.origin - frame.basis.y * 8.0, 1)
	ray.hit_back_faces = true
	if game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		_fail("Generated track has no physical surface at the start.")
		return
	var frames := 0
	runner.call("request_jump")
	for i in range(120):
		runner.call("tick", 1.0 / 60.0, course)
		if bool(runner.call("is_grounded")):
			frames += 1
	if frames < 12:
		_fail("Runner did not land on the generated track.")
		return
	# Inverted midpoint of the 180 bank, not a vertical loop.
	runner.call("reset_run", course)
	runner.set("distance", 864.0)
	runner.set("height", 0.0)
	runner.call("sync_pose", course)
	frame = course.call("sample", 864.0)
	if frame.basis.y.y > -0.8 or runner.transform.basis.y.y > -0.8 or runner.position.distance_to(frame.origin + frame.basis.x * float(runner.get("lane"))) > 0.01:
		_fail("Runner failed to align with an actual inverted track.")
		return
	print("PASS: terrain raycast hit and player grounded for %d/120 frames." % frames)
	game.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	push_error("GROUND COLLISION REGRESSION: " + reason)
	quit(1)
