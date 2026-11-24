extends Node3D

const CourseScript = preload("res://scripts/course.gd")
const RunnerScript = preload("res://scripts/runner.gd")
const StormScript = preload("res://scripts/storm.gd")
const ExtrasScript = preload("res://scripts/run_extras.gd")
const EffectsScript = preload("res://scripts/run_effects.gd")
const ReplayScript = preload("res://scripts/replay.gd")
var touch_buttons: Array[Button] = []
var touch_ui_active := false
var reactive_sky: ShaderMaterial
var mountain_mesh: MeshInstance3D
var mountain_material: ShaderMaterial
var sky_level := -1
var sky_clock := 0.0
var mountain_velocity := 0.0
var mountain_altitude := 0.0
var mountain_pose_ready := false
var replay
var replay_active := false
var replay_playing := false
var replay_time := 0.0
var replay_rate := 1.0
var replay_panel: PanelContainer
var replay_slider: HSlider
var replay_clock: Label
var replay_play_button: Button
var replay_speed_button: Button
var watch_replay_button: Button
var profile_replay_button: Button
var cosmetic_picker: OptionButton
const MODES: Array[String] = ["Endless", "Daily seeded", "No jumping", "First person", "Fast storm", "Practice"]
var extras
var effects
var mode := 0
var run_day := ""
var extras_page: VBoxContainer
var extras_button: Button
var extra_items: Array[Control] = []
var option_items: Array[Control] = []
var control_items: Array[Control] = []
var controls_page: VBoxContainer
var binding_label: Label
var mode_picker: OptionButton
var profile_label: Label
var stats_label: Label
var binding_action := ""
var binding_kind := ""
var binding_picker: OptionButton
var keyboard_rebind: Button
var pad_rebind: Button
var audio_toggle: CheckButton
var music_toggle: CheckButton
var trails_toggle: CheckButton
var vibration_toggle: CheckButton
var board_request: HTTPRequest
var board_status := "Online leaderboard not configured"
var leaderboard_url := ""

var course
var runner
var storm
var view_camera: Camera3D
var first_person := false
var run_finished := false
var run_time := 0.0
var best_distance := 0.0
var run_seed := 0
var paused := false
var imperial := false
var pause_overlay: Control
var pause_page: VBoxContainer
var options_page: VBoxContainer
var units_picker: OptionButton
var resume_button: Button
var options_button: Button
var back_button: Button
var pad_menu_index := 0
var pad_menu_axis := Vector2.ZERO
var distance_label: Label
var clock_label: Label
var record_label: Label
var minimap: Control
var camera_track_s := 0.0
var camera_track_clearance := 0.0
var camera_rotation_ready := false
var orbit_yaw := 0.0
var orbit_pitch := 0.0
var orbit_zoom := 1.0
var orbit_drag := false
var orbit_visual_yaw := 0.0
var orbit_visual_pitch := 0.0
var orbit_visual_zoom := 1.0
var last_camera_fp := false
var camera_arm_ready := false
const CAMERA_RESPONSE := 5.8
const CAMERA_ARM_RESPONSE := 6.5
var camera_goal := Basis.IDENTITY
var camera_height := 0.0
var slide_eye_height := 1.55
var camera_offset := Vector3.ZERO
var takeoff_camera_offset := Vector3.ZERO
var camera_was_grounded := true
const TAKEOFF_CAMERA_TIME := 0.45
var message_label: Label
var restart_button: Button

func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	# A world-fixed sky makes vertical orientation visible even on an empty ribbon.
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/neon_sky.gdshader")
	reactive_sky=sky_mat
	sky.process_mode=Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size=Sky.RADIANCE_SIZE_32
	sky.sky_material = sky_mat
	_create_mountains()
	env.sky = sky
	world.environment = env
	add_child(world)
	course = CourseScript.new()
	add_child(course)
	runner = RunnerScript.new()
	add_child(runner)
	storm = StormScript.new()
	add_child(storm)
	view_camera = Camera3D.new()
	view_camera.current = true
	view_camera.fov = 82.0
	view_camera.near = 0.075
	view_camera.far = 1600.0
	add_child(view_camera)
	extras = ExtrasScript.new()
	add_child(extras)
	effects = EffectsScript.new()
	add_child(effects)
	effects.make_trails()
	replay = ReplayScript.new()
	add_child(replay)
	replay.load_last()
	_create_hud()
	_create_replay_panel()
	_create_pause_menu()
	_load_extras()
	board_request = HTTPRequest.new()
	add_child(board_request)
	board_request.request_completed.connect(_board_completed)
	_load_options()
	var record := ConfigFile.new()
	if record.load("user://endless_records.cfg") == OK:
		best_distance = float(record.get_value("records", "best_distance", 0.0))
	_restart()

func _restart() -> void:
	replay_active = false
	replay_playing = false
	replay_panel.visible = false
	watch_replay_button.visible = false
	replay.reset_recording()
	_set_paused(false)
	run_finished = false
	run_time = 0.0
	camera_rotation_ready = false
	orbit_yaw = 0.0
	orbit_pitch = 0.0
	orbit_zoom = 1.0
	orbit_visual_yaw = 0.0
	orbit_visual_pitch = 0.0
	orbit_visual_zoom = 1.0
	camera_arm_ready = false
	orbit_drag = false
	camera_height = 0.0
	slide_eye_height = 1.55
	camera_offset = Vector3.ZERO
	camera_was_grounded = true
	run_day = Time.get_date_string_from_system(true)
	run_seed = ExtrasScript.daily_seed(run_day) if mode == 1 else randi()
	course.fixed_daily_layout = mode == 1
	course.reset_course(run_seed)
	runner.reset_run(course)
	mountain_pose_ready = false
	runner.jumps_disabled = mode == 2
	if mode == 3:
		first_person = true
	runner.set_first_person(first_person)
	runner.apply_cosmetic(extras.cosmetic)
	extras.reset_stats()
	stats_label.visible = false
	effects.reset_run()
	storm.reset(runner.distance)
	storm.sync_pose(course)
	storm.visible = mode != 5 and storm.visible
	replay.record(0.0, 0.0, runner, course, storm, true)
	message_label.visible = false
	restart_button.visible = false
	_update_camera(1.0)
	_update_hud()

func _physics_process(delta: float) -> void:
	if replay_active or paused or run_finished:
		return
	run_time += delta
	course.set_pursuit_context(runner.distance, runner.lane, runner.speed, storm.gap_to(runner.distance), storm.speed, storm.elapsed)
	var previous_hits: int = runner.hits
	var was_grounded: bool = runner.is_grounded()
	var previous_speed: float = runner.speed
	runner.tick(delta, course)
	extras.track(delta, runner, previous_speed)
	effects.update_run(runner.speed, runner.hits > previous_hits, not was_grounded and runner.is_grounded())
	if runner.fallen:
		replay.record(run_time, delta, runner, course, storm, true)
		_lose("FELL OFF THE TRACK")
		return
	if mode != 5:
		storm.advance(delta * (1.28 if mode == 4 else 1.0))
		storm.sync_pose(course)
		if storm.confirms_catch(delta,runner,course):
			replay.record(run_time, delta, runner, course, storm, true)
			_lose("THE STORM CAUGHT YOU")
			return
	replay.record(run_time, delta, runner, course, storm)

func _create_mountains() -> void:
	mountain_material=ShaderMaterial.new()
	mountain_material.shader=preload("res://shaders/neon_mountains.gdshader")
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(18):
		for sector in range(128):
			for corner:Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(0,1),Vector2(1,0),Vector2(1,1)]:
				var u:float=(float(sector)+corner.x)/128.0
				var v:float=(float(ring)+corner.y)/18.0
				var radius:=lerpf(380.0,1120.0,v)
				st.set_uv(Vector2(u,v))
				st.add_vertex(Vector3(cos(TAU*u)*radius,0,sin(TAU*u)*radius))
	mountain_mesh=MeshInstance3D.new()
	mountain_mesh.mesh=st.commit()
	mountain_mesh.material_override=mountain_material
	mountain_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mountain_mesh.custom_aabb=AABB(Vector3(-1200,-600,-1200),Vector3(2400,1800,2400))
	add_child(mountain_mesh)

func _process(delta: float) -> void:
	if is_instance_valid(mountain_mesh):
		# Follow the course altitude, not the rider's jumps, rolls or free fall.
		# Work in absolute altitude so floating-origin shifts cannot jerk the horizon.
		var floor_frame: Transform3D = course.surface_frame(float(runner.distance),0.0,1)
		var world_shift: Vector3 = course.origin_shift
		var target_altitude: float = floor_frame.origin.y+world_shift.y-90.0
		var target_velocity: float = clampf(float(runner.speed)/300.0,0.0,2.0)
		if not mountain_pose_ready:
			mountain_altitude=target_altitude
			mountain_velocity=target_velocity
			mountain_pose_ready=true
		elif not paused and (not run_finished or replay_active) and (not replay_active or replay_playing):
			mountain_altitude=lerpf(mountain_altitude,target_altitude,1.0-exp(-delta*0.65))
			mountain_velocity=lerpf(mountain_velocity,target_velocity,1.0-exp(-delta*0.85))
		mountain_mesh.position=Vector3(runner.position.x,mountain_altitude-world_shift.y,runner.position.z)
		mountain_material.set_shader_parameter("velocity",mountain_velocity)
		mountain_material.set_shader_parameter("progress",clampf(float(runner.distance)/18000.0,0.0,1.0))
	sky_clock-=delta
	if sky_clock<=0.0 and is_instance_valid(reactive_sky):
		sky_clock=0.25
		var level:=clampi(int(floor(float(runner.speed)/35.0)),0,12)
		if level!=sky_level:
			sky_level=level
			reactive_sky.set_shader_parameter("intensity",float(level)/12.0)
	if not paused and (not run_finished or replay_active):
		_poll_camera_stick(delta)
	if replay_active:
		if replay_playing:
			_seek_replay(minf(replay.duration(), replay_time + delta * replay_rate), false)
			_update_speed_trail(delta * replay_rate)
			if replay_time >= replay.duration():
				_set_replay_playing(false)
		_update_camera(delta)
		_update_hud()
		return
	if paused:
		return
	_update_camera(delta)
	if not run_finished:
		_update_speed_trail(delta)
	_update_hud()

func _update_speed_trail(delta: float) -> void:
	var pose: Transform3D = runner.global_transform
	# Attach just above and behind the rider, including when inverted.
	pose.origin += pose.basis.y * 0.75 + pose.basis.z * 0.95
	effects.sample_trail(pose, course.origin_shift, float(runner.speed), delta)

func _camera_line_clear(a: Vector3, b: Vector3, from_s: float, to_s: float) -> bool:
	# Check the actual bank frame along the sightline, not world-up.
	# This also works during origin rebases and before physics colliders sync.
	var sample_count:=16 if course.is_extreme_bank(course.section_name(to_s)) or course.is_curved_enclosure(to_s) else 8
	for i in range(1,sample_count):
		var t:=float(i)/float(sample_count)
		var s := lerpf(from_s, to_s, t)
		var projection: Vector3 = course.project_position(a.lerp(b, t), s)
		var clearance: float = course.surface_clearance(projection.x, projection.y, projection.z, int(runner.surface_side))
		if bool(course.support_at(projection.x, projection.y)) and clearance < 0.55:
			return false
	return true

func _level_camera_basis(direction: Vector3) -> Basis:
	var heading := direction.normalized()
	if heading.length_squared()<0.0001:
		heading=Vector3.FORWARD
	# Keep the horizon world-up even while the camera is physically beside
	# or underneath the track. Avoid a singularity for steep viewing angles.
	if absf(heading.y) > 0.94:
		var horizontal := Vector3(heading.x, 0.0, heading.z)
		if horizontal.length_squared() < 0.0001:
			horizontal = Vector3(-view_camera.basis.z.x, 0.0, -view_camera.basis.z.z)
		if horizontal.length_squared() < 0.0001:
			horizontal = Vector3.FORWARD
		heading = (horizontal.normalized() * 0.342 + Vector3.UP * signf(heading.y) * 0.94).normalized()
	return Basis.looking_at(heading, Vector3.UP)

func _aim_camera(target: Vector3, _up: Vector3) -> void:
	var direction := target - view_camera.position
	if direction.length_squared() > 0.0001:
		camera_goal = _level_camera_basis(direction)

func _update_camera(delta: float) -> void:
	var player_s: float = runner.distance
	var player_lane: float = runner.lane
	var frame: Transform3D = course.surface_frame(player_s, player_lane, int(runner.surface_side))
	var up := frame.basis.y
	var forward: Vector3 = -frame.basis.z
	var pos: Vector3 = runner.position
	var actively_sliding: bool = runner.is_grounded() and runner.is_sliding
	runner.set_first_person(first_person)
	var mode_changed := last_camera_fp != first_person
	last_camera_fp = first_person
	var orbit_alpha := 1.0-exp(-delta*8.0)
	orbit_visual_yaw = lerp_angle(orbit_visual_yaw,orbit_yaw,orbit_alpha)
	orbit_visual_pitch = lerpf(orbit_visual_pitch,orbit_pitch,orbit_alpha)
	orbit_visual_zoom = lerpf(orbit_visual_zoom,orbit_zoom,orbit_alpha)
	slide_eye_height = lerpf(slide_eye_height, 0.85 if actively_sliding else 1.55, 1.0 - exp(-delta * 10.0))
	# Camera stays on the correct side of the road; only orientation and
	# the additional chase height are damped, never the bank-relative base.
	camera_height = lerpf(camera_height,0.0 if runner.is_grounded() else clampf(float(runner.height)*float(runner.surface_side),0.0,2.0),1.0-exp(-delta*4.0))
	if not runner.is_grounded():
		if camera_was_grounded:
			takeoff_camera_offset = camera_offset if camera_offset.length_squared() > 0.01 else (up * 1.55 if first_person else -forward * 11.0 + up * 5.4)
		camera_was_grounded = false
		# Follow the free player's own pose, not the twisting road below.
		var air_up: Vector3 = runner.transform.basis.y
		var air_forward: Vector3 = -frame.basis.z
		camera_track_s = player_s
		if first_person:
			var glide_view:float=smoothstep(0.0,0.9,float(runner.rider_glider))
			var cockpit_up:=air_up.lerp(Vector3.UP,glide_view).normalized()
			if cockpit_up.length_squared()<0.01:
				cockpit_up=Vector3.UP
			view_camera.position=pos+cockpit_up*lerpf(1.90,1.30,glide_view)+air_forward*lerpf(0.65,1.10,glide_view)
			_aim_camera(view_camera.position+(air_forward-cockpit_up*lerpf(0.34,0.08,glide_view))*25.0,cockpit_up)
		else:
			view_camera.position = pos - air_forward * 9.0 + air_up * 4.0
			_aim_camera(pos + air_up * 1.4 + air_forward * 4.0, air_up)
		# Retain the exact pre-takeoff camera arm, then ease toward flight.
		var blend := smoothstep(0.0, TAKEOFF_CAMERA_TIME, float(runner.air_time))
		view_camera.position = pos + takeoff_camera_offset.lerp(view_camera.position - pos, blend)
	elif first_person:
		camera_track_s = player_s
		var hang_eye: float=lerpf(slide_eye_height+0.30,1.08,float(runner.rider_inverted))
		var gyro_view:=smoothstep(0.50,0.90,absf(frame.basis.x.y))*(1.0-float(runner.rider_inverted))
		view_camera.position=pos+up*lerpf(hang_eye,1.22,gyro_view)+forward*lerpf(0.68,1.15,gyro_view)
		_aim_camera(view_camera.position+(forward-up*0.34)*25.0,up)
	else:
		var focus := pos + up * 1.35
		# Sample the track AT the camera's trailing distance. Using the
		# player's up vector eleven metres behind it crossed twisting banks.
		# Shorten the arm if its sightline would cross the road.
		var selected := false
		for trail: float in [11.0, 8.0, 5.0, 3.0]:
			var s := maxf(0.0, player_s - trail)
			var rear_lane := clampf(player_lane, -float(course.lane_limit(s)), float(course.lane_limit(s)))
			var rear: Transform3D = course.surface_frame(s, rear_lane, int(runner.surface_side))
			var candidate := rear.origin + rear.basis.y * (5.4 + camera_height)
			if _camera_line_clear(candidate, focus, s, player_s):
				camera_track_s = s
				view_camera.position = candidate
				_aim_camera(focus + forward * 0.8, rear.basis.y)
				selected = true
				break
		if not selected:
			# Local fallback cannot be on the underside, even on a full roll.
			camera_track_s = player_s
			view_camera.position = pos + up * 3.6
			_aim_camera(view_camera.position + forward * 22.0, up)
	# Blend the flight camera's relative arm into the grounded arm, rather
	# than abruptly switching between two different camera positions.
	# The offset follows the moving player, so even extreme speeds do not
	# create positional lag. Clamp only when needed to avoid the ribbon.
	if runner.is_grounded() and runner.landing_blend > 0.0:
		var blend: float = runner.landing_fraction()
		var from_basis: Basis = runner.landing_from_basis
		var from_up := from_basis.y
		var from_forward := -from_basis.z
		var air_offset:=from_up*1.90+forward*0.65 if first_person else -forward*9.0+from_up*4.0
		var ground_offset := view_camera.position - pos
		var candidate := pos + air_offset.lerp(ground_offset, blend)
		var projected: Vector3 = course.project_position(candidate, lerpf(player_s, camera_track_s, blend))
		var surface: Transform3D = course.surface_frame(projected.x, projected.y, int(runner.surface_side))
		var clearance: float = course.surface_clearance(projected.x, projected.y, projected.z, int(runner.surface_side))
		if absf(projected.y) <= float(course.half_width_at(projected.x)) + 0.5 and clearance < 1.15:
			candidate += surface.basis.y * (1.15 - clearance)
		if first_person or _camera_line_clear(candidate, pos + up * 1.35, projected.x, player_s):
			view_camera.position = candidate
			camera_track_s = projected.x
		# Match the blended body orientation, preserving the pre-impact view.
		var air_look:=forward-up*0.34 if first_person else forward*13.0-from_up*2.6
		var air_goal := _level_camera_basis(air_look)
		camera_goal = air_goal.slerp(camera_goal, blend).orthonormalized()
	if first_person and runner.is_grounded():
		var eye_projection: Vector3=course.project_position(view_camera.position,player_s)
		var eye_gap: float=course.surface_clearance(eye_projection.x,eye_projection.y,eye_projection.z,int(runner.surface_side))
		if course.support_at(eye_projection.x,eye_projection.y) and eye_gap<1.22:
			var eye_surface: Transform3D=course.surface_frame(eye_projection.x,eye_projection.y,int(runner.surface_side))
			view_camera.position+=eye_surface.basis.y*(1.22-eye_gap)
	_apply_camera_orbit(pos, up, forward, player_s)
	# Damp the relative arm, not world coordinates (safe during rebases).
	var desired_arm := view_camera.position-pos
	if camera_arm_ready and not mode_changed and not first_person:
		var softened_arm := camera_offset.lerp(desired_arm,1.0-exp(-delta*CAMERA_ARM_RESPONSE))
		var softened_position: Vector3 = pos+softened_arm
		var soft_projection: Vector3 = course.project_position(softened_position,camera_track_s)
		var soft_clearance: float = course.surface_clearance(soft_projection.x,soft_projection.y,soft_projection.z,int(runner.surface_side))
		if not runner.is_grounded() or (soft_clearance>=1.05 and _camera_line_clear(softened_position,pos+up*1.35,soft_projection.x,player_s)):
			view_camera.position = softened_position
			camera_track_s = soft_projection.x
	camera_arm_ready = true
	var camera_projection: Vector3=course.project_position(view_camera.position,camera_track_s)
	camera_track_clearance=float(course.surface_clearance(camera_projection.x,camera_projection.y,camera_projection.z,int(runner.surface_side)))
	# All orbit, landing and damping adjustments must finish on the
	# correct side of the road. Project again after correcting position.
	if runner.is_grounded() and camera_track_clearance<1.15:
		var camera_surface:Transform3D=course.surface_frame(camera_projection.x,camera_projection.y,int(runner.surface_side))
		view_camera.position+=camera_surface.basis.y*(1.30-camera_track_clearance)
		camera_projection=course.project_position(view_camera.position,camera_projection.x)
		camera_track_clearance=float(course.surface_clearance(camera_projection.x,camera_projection.y,camera_projection.z,int(runner.surface_side)))
		if camera_track_clearance<1.05:
			# Same-face fallback at the actual player cross-section.
			view_camera.position=frame.origin+up*(1.55 if first_person else 3.6)
			camera_projection=course.project_position(view_camera.position,player_s)
			camera_track_clearance=float(course.surface_clearance(camera_projection.x,camera_projection.y,camera_projection.z,int(runner.surface_side)))
		camera_track_s=camera_projection.x
	camera_offset = view_camera.position - pos
	camera_was_grounded = runner.is_grounded()
	# Quaternion interpolation avoids Euler flips near 180/360 degrees.
	# A short time constant removes sudden orientation kicks without a
	# long lag that would point the camera back through the ribbon.
	if not camera_rotation_ready:
		view_camera.basis = camera_goal
		camera_rotation_ready = true
	else:
		# Interpolate forward directions, then reconstruct a level basis.
		# Quaternion blending whole tilted frames can introduce unwanted roll.
		var heading := (-view_camera.basis.z).slerp(-camera_goal.z, 1.0-exp(-delta*CAMERA_RESPONSE))
		view_camera.basis = _level_camera_basis(heading)
	view_camera.fov = lerpf(view_camera.fov,clampf((86.0 if first_person else 78.0)+runner.speed*0.045,78.0,98.0),1.0-exp(-delta*3.0))
	runner.update_rider_sprite(view_camera,1.0 if replay_active else delta)

func _speed_display(meters_per_second: float) -> int:
	return int(meters_per_second * (2.2369362921 if imperial else 3.6))

func _speed_units() -> String:
	return "MPH" if imperial else "KM/H"

func _distance_display(meters: float) -> String:
	if imperial:
		if meters >= 1609.344:
			return "%.2f mi" % (meters / 1609.344)
		return "%d ft" % int(meters * 3.280839895)
	return "%d m" % int(meters)

func _update_hud() -> void:
	var active: bool = not replay_active and not run_finished and not paused
	for touch_button in touch_buttons:
		touch_button.visible = touch_ui_active and active
	distance_label.text = "DISTANCE  " + _distance_display(maxf(0.0, runner.distance - 8.0))
	clock_label.text = "TIME  %02d:%05.2f" % [int(run_time / 60.0), fmod(run_time, 60.0)]
	var saved_best: float = extras.best_for(mode, run_day)
	if mode == 0:
		saved_best = maxf(saved_best, best_distance)
	record_label.text = "BEST  " + _distance_display(maxf(saved_best, runner.distance - 8.0))
	if replay_active or not run_finished:
		message_label.visible = false

func _lose(reason: String) -> void:
	if run_finished:
		return
	run_finished = true
	replay.record(run_time, 0.0, runner, course, storm, true)
	replay.finish(course,run_seed,mode,extras.cosmetic,reason,storm.gap_to(runner.distance))
	watch_replay_button.visible = replay.available()
	var meters: float = maxf(0.0, runner.distance - 8.0)
	extras.finish(mode, run_day, run_seed, meters, run_time, runner)
	stats_label.text = extras.summary(_distance_display(meters), _speed_display(extras.top_speed), _speed_units())
	stats_label.visible = true
	if mode == 1:
		_submit_daily(meters)
	if mode == 0 and meters > best_distance:
		best_distance = meters
		var record := ConfigFile.new()
		record.set_value("records", "best_distance", best_distance)
		record.save("user://endless_records.cfg")
	message_label.text = reason + "  //  " + _distance_display(meters)
	message_label.visible = true
	restart_button.visible = true

func _orbit_input(amount: Vector2) -> void:
	orbit_yaw = wrapf(orbit_yaw - amount.x, -PI, PI)
	orbit_pitch = clampf(orbit_pitch + amount.y, deg_to_rad(-70.0), deg_to_rad(78.0))

func _poll_camera_stick(delta: float) -> void:
	var motion := Vector2.ZERO
	for device in Input.get_connected_joypads():
		var candidate: Vector2 = Vector2(runner.pad_axis(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X)), runner.pad_axis(Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)))
		if candidate.length_squared() > motion.length_squared():
			motion = candidate
	_orbit_input(motion * delta * 2.4)

func _first_person_look(forward: Vector3,up: Vector3,yaw_offset: float,pitch_offset: float) -> Vector3:
	var baseline:=_level_camera_basis(forward-up*0.34)
	var look:=(-baseline.z).rotated(Vector3.UP,yaw_offset)
	var right:=look.cross(Vector3.UP).normalized()
	if right.length_squared()>0.001:
		look=look.rotated(right,-pitch_offset)
	return look.normalized()

func _apply_camera_orbit(pos: Vector3, track_up: Vector3, track_forward: Vector3, player_s: float) -> void:
	if absf(orbit_visual_yaw) < 0.0001 and absf(orbit_visual_pitch) < 0.0001 and absf(orbit_visual_zoom - 1.0) < 0.0001:
		return
	var up: Vector3 = track_up
	var forward: Vector3 = track_forward
	if first_person:
		# Mouse right/down always means screen right/down. World-up
		# yaw and camera-right pitch remain consistent upside down.
		var look: Vector3=_first_person_look(forward,up,orbit_visual_yaw,orbit_visual_pitch)
		camera_goal=_level_camera_basis(look)
		return
	var focus: Vector3 = pos + up * 1.35
	# Orbit a track-relative hemisphere, allowing a full 360-degree yaw.
	# Limit downward pitch only when the actual track blocks the view.
	var base_arm: Vector3 = view_camera.position - focus
	var arm_length := clampf(base_arm.length() * orbit_visual_zoom, 2.5, 30.0)
	var azimuth: Vector3 = (-forward).rotated(up, orbit_visual_yaw)
	var base_pitch := atan2(base_arm.dot(up), maxf(0.01, (base_arm - up * base_arm.dot(up)).length()))
	var elevation := clampf(base_pitch + orbit_visual_pitch, deg_to_rad(-70.0), deg_to_rad(85.0))
	var direction: Vector3 = azimuth * cos(elevation) + up * sin(elevation)
	for scale_value: float in [1.0, 0.75, 0.50, 0.30]:
		var candidate: Vector3 = focus + direction * arm_length * scale_value
		var projection: Vector3 = course.project_position(candidate, player_s)
		var clearance: float = course.surface_clearance(projection.x, projection.y, projection.z, int(runner.surface_side))
		if bool(course.support_at(projection.x, projection.y)) and clearance < 0.7:
			continue
		if _camera_line_clear(candidate, focus, projection.x, player_s):
			view_camera.position = candidate
			camera_track_s = projection.x
			_aim_camera(focus, up)
			return

func _recenter_camera() -> void:
	orbit_yaw = 0.0
	orbit_pitch = 0.0
	orbit_zoom = 1.0
	orbit_drag = false
	_update_camera(1.0/60.0)

func _toggle_camera() -> void:
	if mode == 3 and not replay_active:
		return
	first_person = not first_person
	runner.set_first_person(first_person)
	_update_camera(1.0/60.0)

func _active_menu_items() -> Array[Control]:
	if controls_page.visible:
		return control_items
	if extras_page.visible:
		return extra_items
	if options_page.visible:
		return option_items
	return [resume_button, options_button, extras_button]

func _pad_focus() -> void:
	if not paused:
		return
	var items := _active_menu_items()
	if not items.is_empty():
		items[clampi(pad_menu_index, 0, items.size() - 1)].grab_focus()

func _pad_direction(x: int, y: int) -> void:
	var items := _active_menu_items()
	if items.is_empty():
		return
	if y != 0:
		pad_menu_index = posmod(pad_menu_index + y, items.size())
		_pad_focus()
	elif x != 0:
		var selected := items[clampi(pad_menu_index, 0, items.size() - 1)]
		if selected == units_picker:
			_set_units(1 if x > 0 else 0)
		elif selected is OptionButton:
			var picker := selected as OptionButton
			for offset in range(1,picker.item_count+1):
				var candidate:=posmod(picker.selected+x*offset,picker.item_count)
				if not picker.is_item_disabled(candidate):
					picker.select(candidate)
					picker.item_selected.emit(candidate)
					break

func _back_menu() -> void:
	if controls_page.visible:
		_show_options(true)
	elif options_page.visible or extras_page.visible:
		_show_options(false)
	else:
		_set_paused(false)

func _pad_button(button: int) -> bool:
	if replay_active:
		match button:
			JOY_BUTTON_START, JOY_BUTTON_A:
				_set_replay_playing(not replay_playing)
			JOY_BUTTON_B, JOY_BUTTON_BACK:
				_restart()
			JOY_BUTTON_Y:
				_toggle_camera()
			JOY_BUTTON_LEFT_STICK:
				_recenter_camera()
			JOY_BUTTON_DPAD_LEFT:
				_seek_replay(replay_time - 5.0)
			JOY_BUTTON_DPAD_RIGHT:
				_seek_replay(replay_time + 5.0)
			JOY_BUTTON_DPAD_UP:
				_cycle_replay_speed()
		return true
	if run_finished and button == JOY_BUTTON_BACK and replay.available():
		_start_replay()
		return true
	if button == JOY_BUTTON_START:
		if paused:
			_back_menu()
		else:
			_set_paused(true)
		return true
	if paused:
		match button:
			JOY_BUTTON_B, JOY_BUTTON_BACK:
				_back_menu()
			JOY_BUTTON_DPAD_UP:
				_pad_direction(0, -1)
			JOY_BUTTON_DPAD_DOWN:
				_pad_direction(0, 1)
			JOY_BUTTON_DPAD_LEFT:
				_pad_direction(-1, 0)
			JOY_BUTTON_DPAD_RIGHT:
				_pad_direction(1, 0)
			JOY_BUTTON_A:
				var items := _active_menu_items()
				var control := items[clampi(pad_menu_index, 0, items.size() - 1)]
				if control == units_picker:
					_set_units(0 if imperial else 1)
				elif control is OptionButton:
					_pad_direction(1, 0)
				elif control is CheckButton:
					control.button_pressed = not control.button_pressed
				elif control is Button and not control.disabled:
					control.pressed.emit()
		return true
	if _bound_pad("recenter", button, JOY_BUTTON_LEFT_STICK):
		_recenter_camera()
		return true
	if _bound_pad("camera", button, JOY_BUTTON_Y):
		_toggle_camera()
		return true
	if _bound_pad("restart", button, JOY_BUTTON_X) or (run_finished and button == JOY_BUTTON_A):
		_restart()
		return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if paused or (run_finished and not replay_active):
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_orbit_input(drag.relative * 0.006)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		touch_ui_active = true
	if event is InputEventMouseButton and not paused and (not run_finished or replay_active):
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			orbit_drag = mouse.pressed
			get_viewport().set_input_as_handled()
			return
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			orbit_zoom = clampf(orbit_zoom * (0.88 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14), 0.55, 2.4)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and orbit_drag and not paused:
		var motion_event := event as InputEventMouseMotion
		_orbit_input(motion_event.relative * 0.006)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		if pad.pressed:
			if not binding_action.is_empty() and binding_kind == "pad":
				_capture_binding(pad.button_index)
				get_viewport().set_input_as_handled()
				return
			effects.activate_audio()
			if _pad_button(pad.button_index):
				get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if paused and (motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_LEFT_Y):
			var value := signf(motion.axis_value) if absf(motion.axis_value) > 0.65 else 0.0
			var horizontal := motion.axis == JOY_AXIS_LEFT_X
			var prior := pad_menu_axis.x if horizontal else pad_menu_axis.y
			if horizontal:
				pad_menu_axis.x = value
			else:
				pad_menu_axis.y = value
			if value != 0.0 and value != prior:
				_pad_direction(int(value) if horizontal else 0, 0 if horizontal else int(value))
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if replay_active:
		match key.keycode:
			KEY_ESCAPE:
				_restart()
			KEY_SPACE:
				_set_replay_playing(not replay_playing)
			KEY_LEFT:
				_seek_replay(replay_time - 5.0)
			KEY_RIGHT:
				_seek_replay(replay_time + 5.0)
			KEY_TAB:
				_toggle_camera()
			KEY_G:
				_recenter_camera()
			KEY_UP:
				_cycle_replay_speed()
		get_viewport().set_input_as_handled()
		return
	if run_finished and key.keycode == KEY_V and replay.available():
		_start_replay()
		get_viewport().set_input_as_handled()
		return
	if not binding_action.is_empty() and binding_kind == "keyboard":
		if key.keycode == KEY_ESCAPE:
			binding_action = ""
			_refresh_profile()
		else:
			_capture_binding(key.keycode)
		get_viewport().set_input_as_handled()
		return
	effects.activate_audio()
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if paused:
			_back_menu()
		else:
			_set_paused(true)
		return
	if paused:
		return
	if _bound_key("recenter", key.keycode, KEY_G):
		get_viewport().set_input_as_handled()
		_recenter_camera()
	elif _bound_key("camera", key.keycode, KEY_TAB):
		# Consume Tab before UI focus navigation; C is exclusively slide.
		get_viewport().set_input_as_handled()
		_toggle_camera()
	elif _bound_key("restart", key.keycode, KEY_R):
		get_viewport().set_input_as_handled()
		_restart()

func _label(value: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(title: String, x_left: float, x_right: float, bottom: float, right: bool = false) -> Button:
	var b := Button.new()
	b.text = title
	b.focus_mode = Control.FOCUS_NONE
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	if right:
		b.anchor_left = 1.0
		b.anchor_right = 1.0
	b.offset_left = x_left
	b.offset_right = x_right
	b.offset_top = -bottom
	b.offset_bottom = -bottom + 64.0
	b.add_theme_font_size_override("font_size", 21)
	return b

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stack := VBoxContainer.new()
	stack.position = Vector2(22, 18)
	stack.add_theme_constant_override("separation", 2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)
	stack.name = "RunStats"
	distance_label = _label("", 23, Color(0.84, 0.96, 1.0))
	stack.add_child(distance_label)
	clock_label = _label("", 19, Color(0.84, 0.96, 1.0))
	stack.add_child(clock_label)
	record_label = _label("", 19, Color(0.99, 0.79, 0.41))
	stack.add_child(record_label)
	for stat in [distance_label, clock_label, record_label]:
		stat.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		stat.add_theme_constant_override("shadow_offset_x", 1)
		stat.add_theme_constant_override("shadow_offset_y", 2)
	minimap = preload("res://scripts/elevation_map.gd").new()
	minimap.clip_contents = true
	root.add_child(minimap)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -266.0
	minimap.offset_right = -16.0
	minimap.offset_top = 38.0
	minimap.offset_bottom = 278.0
	minimap.call("setup", course, runner, storm)
	minimap.hide()
	minimap.set_process(false)
	message_label = _label("", 25, Color(1.0, 0.84, 0.3))
	root.add_child(message_label)
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.offset_left = -260
	message_label.offset_right = 260
	message_label.offset_top = 65
	message_label.offset_bottom = 112
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.visible = false
	var left := _button("◀", 20, 100, 124)
	root.add_child(left)
	left.button_down.connect(func() -> void: runner.touch_axis = -1.0)
	left.button_up.connect(func() -> void: runner.touch_axis = 0.0)
	var right := _button("▶", 110, 190, 124)
	root.add_child(right)
	right.button_down.connect(func() -> void: runner.touch_axis = 1.0)
	right.button_up.connect(func() -> void: runner.touch_axis = 0.0)
	var slide := _button("SLIDE", 20, 190, 202)
	root.add_child(slide)
	slide.button_down.connect(func() -> void: runner.touch_slide = true)
	slide.button_up.connect(func() -> void: runner.touch_slide = false)
	var jump := _button("JUMP", -138, -20, 124, true)
	root.add_child(jump)
	jump.pressed.connect(func() -> void: runner.request_jump())
	var view := _button("VIEW", -138, -20, 202, true)
	root.add_child(view)
	view.pressed.connect(_toggle_camera)
	var recenter := _button("CENTER", -394, -276, 202, true)
	root.add_child(recenter)
	recenter.pressed.connect(_recenter_camera)
	var dive := _button("DIVE", -266, -148, 124, true)
	root.add_child(dive)
	dive.button_down.connect(func() -> void: runner.touch_dive = true)
	dive.button_up.connect(func() -> void: runner.touch_dive = false)
	touch_buttons.assign([left, right, slide, jump, view, recenter, dive])
	touch_ui_active = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	for touch_button in touch_buttons:
		touch_button.visible = touch_ui_active
	restart_button = Button.new()
	restart_button.text = "RUN AGAIN"
	restart_button.focus_mode = Control.FOCUS_NONE
	root.add_child(restart_button)
	restart_button.set_anchors_preset(Control.PRESET_CENTER)
	restart_button.offset_left = -180
	restart_button.offset_right = -6
	restart_button.offset_top = 8
	restart_button.offset_bottom = 65
	restart_button.visible = false
	restart_button.pressed.connect(_restart)
	watch_replay_button = Button.new()
	watch_replay_button.text = "WATCH REPLAY"
	watch_replay_button.focus_mode = Control.FOCUS_NONE
	root.add_child(watch_replay_button)
	watch_replay_button.set_anchors_preset(Control.PRESET_CENTER)
	watch_replay_button.offset_left = 6
	watch_replay_button.offset_right = 180
	watch_replay_button.offset_top = 8
	watch_replay_button.offset_bottom = 65
	watch_replay_button.visible = false
	watch_replay_button.pressed.connect(_start_replay)
	stats_label = _label("", 17, Color(0.81, 0.96, 1.0))
	root.add_child(stats_label)
	stats_label.set_anchors_preset(Control.PRESET_CENTER)
	stats_label.offset_left = -270
	stats_label.offset_right = 270
	stats_label.offset_top = 85
	stats_label.offset_bottom = 250
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.visible = false

func _load_options() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://velocity_options.cfg") == OK:
		imperial = bool(settings.get_value("display", "imperial", false))
	units_picker.select(1 if imperial else 0)

func _set_units(index: int, persist: bool = true) -> void:
	imperial = index == 1
	units_picker.select(1 if imperial else 0)
	if persist:
		var settings := ConfigFile.new()
		settings.set_value("display", "imperial", imperial)
		settings.save("user://velocity_options.cfg")
	_update_hud()
	if run_finished:
		# Preserve the original defeat reason while updating its distance.
		var reason := message_label.text.get_slice("  //  ", 0)
		message_label.text = reason + "  //  " + _distance_display(maxf(0.0, runner.distance - 8.0))

func _set_paused(value: bool) -> void:
	paused = value
	if value:
		orbit_drag = false
	effects.set_paused(value)
	pause_overlay.visible = value
	pad_menu_axis = Vector2.ZERO
	_show_options(false)
	if not value:
		var focused := get_viewport().gui_get_focus_owner()
		if is_instance_valid(focused):
			focused.release_focus()
	if value:
		# Avoid a stuck touch button if it was held when Escape was pressed.
		runner.touch_slide = false
		runner.touch_dive = false
		runner.touch_axis = 0.0
		runner.queued_jump = false

func _show_options(value: bool) -> void:
	pause_page.visible = not value
	options_page.visible = value
	if is_instance_valid(extras_page):
		extras_page.visible = false
	if is_instance_valid(controls_page):
		controls_page.visible = false
	if value and is_instance_valid(cosmetic_picker):
		for index in range(cosmetic_picker.item_count):
			cosmetic_picker.set_item_disabled(index,not extras.cosmetic_unlocked(index))
		cosmetic_picker.select(extras.cosmetic)
	binding_action = ""
	pad_menu_index = 0
	_pad_focus()

func _menu_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(260, 52)
	button.add_theme_font_size_override("font_size", 20)
	button.focus_mode = Control.FOCUS_ALL
	return button

func _create_pause_menu() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	pause_overlay = Control.new()
	layer.add_child(pause_overlay)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.008, 0.025, 0.84)
	pause_overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	pause_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.026, 0.045, 0.086, 0.98)
	style.border_color = Color(0.12, 0.77, 0.94)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var pages := VBoxContainer.new()
	pages.add_theme_constant_override("separation", 12)
	panel.add_child(pages)
	pause_page = VBoxContainer.new()
	pause_page.add_theme_constant_override("separation", 14)
	pages.add_child(pause_page)
	var title := _label("PAUSED", 34, Color(0.1, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_page.add_child(title)
	resume_button = _menu_button("RESUME")
	pause_page.add_child(resume_button)
	resume_button.pressed.connect(func() -> void: _set_paused(false))
	resume_button.focus_entered.connect(func() -> void: pad_menu_index = 0)
	options_button = _menu_button("OPTIONS")
	pause_page.add_child(options_button)
	options_button.pressed.connect(func() -> void: _show_options(true))
	options_button.focus_entered.connect(func() -> void: pad_menu_index = 1)
	extras_button = _menu_button("RUN & PROFILE")
	pause_page.add_child(extras_button)
	extras_button.pressed.connect(_show_extras)
	extras_button.focus_entered.connect(func() -> void: pad_menu_index = 2)
	options_page = VBoxContainer.new()
	options_page.add_theme_constant_override("separation", 14)
	pages.add_child(options_page)
	var options_title := _label("OPTIONS", 30, Color(0.1, 0.9, 1.0))
	options_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_page.add_child(options_title)
	options_page.add_child(_label("MEASUREMENT UNITS", 17, Color(0.75, 0.9, 1.0)))
	units_picker = OptionButton.new()
	units_picker.custom_minimum_size = Vector2(260, 48)
	units_picker.add_theme_font_size_override("font_size", 19)
	units_picker.add_item("Metric (km/h, m)")
	units_picker.add_item("Imperial (mph, ft, mi)")
	units_picker.item_selected.connect(func(index: int) -> void: _set_units(index))
	_add_option(units_picker)
	var pad_hint := _label("STICK / D-PAD  ·  A SELECT  ·  B BACK", 14, Color(0.55, 0.84, 0.96))
	pad_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pages.add_child(pad_hint)
	_create_extras_page(pages)
	_create_settings_pages(pages)
	_show_options(false)
	pause_overlay.visible = false

func _create_extras_page(pages: VBoxContainer) -> void:
	extras_page = VBoxContainer.new()
	extras_page.add_theme_constant_override("separation", 5)
	pages.add_child(extras_page)
	extras_page.add_child(_label("RUN & PROFILE", 24, Color(0.1, 0.9, 1.0)))
	mode_picker = OptionButton.new()
	for name_value in MODES:
		mode_picker.add_item(name_value)
	mode_picker.item_selected.connect(func(_i: int) -> void: _refresh_profile())
	_add_extra(mode_picker)
	var start := _menu_button("START SELECTED RUN")
	start.custom_minimum_size.y = 36
	start.pressed.connect(func() -> void: mode = mode_picker.selected; _restart())
	_add_extra(start)
	profile_replay_button = _menu_button("WATCH LAST REPLAY (NEW RUN ON EXIT)")
	profile_replay_button.custom_minimum_size.y = 36
	profile_replay_button.pressed.connect(_start_replay)
	_add_extra(profile_replay_button)
	profile_label = _label("", 14, Color(0.76, 0.94, 1.0))
	extras_page.add_child(profile_label)
	var back := _menu_button("BACK")
	back.custom_minimum_size.y = 36
	back.pressed.connect(func() -> void: _show_options(false))
	_add_extra(back)
	extras_page.visible = false

func _create_settings_pages(pages: VBoxContainer) -> void:
	options_page.add_theme_constant_override("separation", 7)
	options_page.add_child(_label("APPEARANCE", 16, Color(0.75, 0.9, 1.0)))
	cosmetic_picker=OptionButton.new()
	for palette_name in ["Original // White & Cyan","Amber // 1 km","Violet // 100 m/s","Emerald // 5 km"]:
		cosmetic_picker.add_item(palette_name)
	cosmetic_picker.item_selected.connect(_select_cosmetic)
	_add_option(cosmetic_picker)
	options_page.add_child(_label("AUDIO & EFFECTS", 16, Color(0.75, 0.9, 1.0)))
	music_toggle = CheckButton.new()
	music_toggle.text = "Soundtrack"
	music_toggle.toggled.connect(func(v: bool) -> void: extras.soundtrack = v; effects.music_enabled = v; effects.configure_music(); extras.save_profile(); effects.activate_audio())
	_add_option(music_toggle)
	audio_toggle = CheckButton.new()
	audio_toggle.text = "Adaptive soundtrack"
	audio_toggle.toggled.connect(func(v: bool) -> void: extras.music = v; effects.adaptive_music = v; effects.configure_music(); extras.save_profile(); effects.activate_audio())
	_add_option(audio_toggle)
	trails_toggle = CheckButton.new()
	trails_toggle.text = "Rider speed trail"
	trails_toggle.toggled.connect(func(v: bool) -> void: extras.trails = v; effects.set_trails_enabled(v); extras.save_profile())
	_add_option(trails_toggle)
	vibration_toggle = CheckButton.new()
	vibration_toggle.text = "Controller vibration"
	vibration_toggle.toggled.connect(func(v: bool) -> void: extras.vibration = v; effects.vibration_enabled = v; extras.save_profile())
	_add_option(vibration_toggle)
	var control_button := _menu_button("CONTROLS")
	control_button.custom_minimum_size.y = 36
	control_button.pressed.connect(_show_controls)
	_add_option(control_button)
	var changelog_button := _menu_button("CHANGELOG")
	changelog_button.custom_minimum_size.y = 34
	changelog_button.pressed.connect(func() -> void: OS.shell_open("https://unborne-fetus.github.io/Cracked/changelog.html"))
	_add_option(changelog_button)
	back_button = _menu_button("BACK")
	back_button.custom_minimum_size.y = 36
	back_button.pressed.connect(func() -> void: _show_options(false))
	_add_option(back_button)
	controls_page = VBoxContainer.new()
	controls_page.add_theme_constant_override("separation", 8)
	pages.add_child(controls_page)
	controls_page.add_child(_label("CONTROLS", 28, Color(0.1, 0.9, 1.0)))
	binding_picker = OptionButton.new()
	for name_value in ["left", "right", "drift_left", "drift_right", "slide", "jump", "dive", "camera", "recenter", "restart"]:
		binding_picker.add_item(name_value)
	binding_picker.item_selected.connect(func(_i: int) -> void: _refresh_profile())
	_add_control(binding_picker)
	keyboard_rebind = _menu_button("REBIND KEY")
	keyboard_rebind.custom_minimum_size.y = 34
	keyboard_rebind.pressed.connect(func() -> void: _begin_binding("keyboard"))
	_add_control(keyboard_rebind)
	pad_rebind = _menu_button("REBIND PAD BUTTON")
	pad_rebind.custom_minimum_size.y = 34
	pad_rebind.pressed.connect(func() -> void: _begin_binding("pad"))
	_add_control(pad_rebind)
	var reset_bind := _menu_button("RESET BINDINGS")
	reset_bind.custom_minimum_size.y = 34
	reset_bind.pressed.connect(func() -> void: extras.keys.clear(); extras.pads.clear(); _apply_bindings(); extras.save_profile(); _refresh_profile())
	_add_control(reset_bind)
	binding_label = _label("", 14, Color(0.76, 0.94, 1.0))
	controls_page.add_child(binding_label)
	var controls_back := _menu_button("BACK TO OPTIONS")
	controls_back.custom_minimum_size.y = 36
	controls_back.pressed.connect(func() -> void: _show_options(true))
	_add_control(controls_back)
	controls_page.visible = false

func _add_option(control: Control) -> void:
	options_page.add_child(control)
	var idx := option_items.size()
	option_items.append(control)
	control.focus_entered.connect(func() -> void: pad_menu_index = idx)

func _add_control(control: Control) -> void:
	controls_page.add_child(control)
	var idx := control_items.size()
	control_items.append(control)
	control.focus_entered.connect(func() -> void: pad_menu_index = idx)

func _show_controls() -> void:
	pause_page.hide()
	options_page.hide()
	extras_page.hide()
	controls_page.show()
	pad_menu_index = 0
	binding_action = ""
	_refresh_profile()
	_pad_focus()

func _add_extra(control: Control) -> void:
	extras_page.add_child(control)
	var idx := extra_items.size()
	extra_items.append(control)
	control.focus_entered.connect(func() -> void: pad_menu_index = idx)

func _load_extras() -> void:
	extras.load_profile()
	_apply_bindings()
	effects.music_enabled = extras.soundtrack
	effects.adaptive_music = extras.music
	effects.configure_music()
	effects.set_trails_enabled(extras.trails)
	effects.vibration_enabled = extras.vibration
	leaderboard_url = str(ProjectSettings.get_setting("velocity/leaderboard_url", ""))
	music_toggle.set_pressed_no_signal(extras.soundtrack)
	audio_toggle.set_pressed_no_signal(extras.music)
	trails_toggle.set_pressed_no_signal(extras.trails)
	vibration_toggle.set_pressed_no_signal(extras.vibration)

func _show_extras() -> void:
	pause_page.visible = false
	options_page.visible = false
	extras_page.visible = true
	mode_picker.select(mode)
	controls_page.hide()
	profile_replay_button.disabled = not replay.available()
	pad_menu_index = 0
	_refresh_profile()
	_pad_focus()

func _select_cosmetic(index: int) -> void:
	if not extras.cosmetic_unlocked(index):
		cosmetic_picker.select(extras.cosmetic)
		return
	extras.cosmetic=index
	runner.apply_cosmetic(index)
	extras.save_profile()

func _refresh_profile() -> void:
	if not is_instance_valid(profile_label):
		return
	var action := binding_picker.get_item_text(binding_picker.selected)
	var key_text := str(extras.keys.get(action, []))
	var pad_text := str(extras.pads.get(action, []))
	profile_label.text = "Unlocked %d / 8  |  Daily best %s\n%s" % [extras.achievements.size(), _distance_display(extras.best_for(1, Time.get_date_string_from_system(true))), board_status]
	if is_instance_valid(binding_label):
		binding_label.text = ("Press a new " + binding_kind + " input for " + binding_action if not binding_action.is_empty() else "%s: key %s  /  pad %s" % [action, key_text if key_text != "[]" else "default", pad_text if pad_text != "[]" else "default"])

func _begin_binding(kind: String) -> void:
	binding_kind = kind
	binding_action = binding_picker.get_item_text(binding_picker.selected)
	_refresh_profile()

func _capture_binding(code: int) -> void:
	if binding_kind == "pad" and code in [JOY_BUTTON_START, JOY_BUTTON_BACK]:
		binding_action = ""
		_refresh_profile()
		return
	var target: Dictionary = extras.keys if binding_kind == "keyboard" else extras.pads
	target[binding_action] = [code]
	binding_action = ""
	_apply_bindings()
	extras.save_profile()
	_refresh_profile()

func _apply_bindings() -> void:
	runner.key_bindings = extras.keys
	runner.pad_bindings = extras.pads

func _bound_key(action: String, code: int, default_value: int) -> bool:
	return extras.keys.get(action, [default_value]).has(code)

func _bound_pad(action: String, code: int, default_value: int) -> bool:
	return extras.pads.get(action, [default_value]).has(code)

func _submit_daily(meters: float) -> void:
	if leaderboard_url.is_empty() or not is_instance_valid(board_request):
		return
	var body := {"day": run_day, "seed": run_seed, "distance": meters, "speed": extras.top_speed, "seconds": run_time, "player": extras.player_id}
	board_status = "Submitting daily score..."
	var error := board_request.request(leaderboard_url.trim_suffix("/") + "/scores", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		board_status = "Leaderboard unavailable"

func _board_completed(_result: int, response: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response != 200:
		board_status = "Leaderboard unavailable"
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary:
		board_status = "Daily global rank: %s" % str(data.get("rank", "?"))
	else:
		board_status = "Leaderboard unavailable"
	_refresh_profile()

func _create_replay_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 19
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay_panel = PanelContainer.new()
	root.add_child(replay_panel)
	replay_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	replay_panel.offset_left = -300
	replay_panel.offset_right = 300
	replay_panel.offset_top = -176
	replay_panel.offset_bottom = -50
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.03, 0.08, 0.96)
	style.border_color = Color(0.12, 0.8, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	replay_panel.add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	replay_panel.add_child(stack)
	replay_clock = _label("REPLAY", 18, Color(0.24, 0.95, 1.0))
	stack.add_child(replay_clock)
	replay_slider = HSlider.new()
	replay_slider.step = 0.05
	replay_slider.custom_minimum_size.y = 24
	stack.add_child(replay_slider)
	replay_slider.value_changed.connect(func(value: float) -> void: _seek_replay(value))
	var row := HBoxContainer.new()
	stack.add_child(row)
	for caption_text in ["-5 SEC", "PAUSE", "+5 SEC", "1x", "CAMERA", "CENTER", "EXIT"]:
		var button := Button.new()
		button.text = caption_text
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
		match caption_text:
			"-5 SEC":
				button.pressed.connect(func() -> void: _seek_replay(replay_time - 5.0))
			"PAUSE":
				replay_play_button = button
				button.pressed.connect(func() -> void: _set_replay_playing(not replay_playing))
			"+5 SEC":
				button.pressed.connect(func() -> void: _seek_replay(replay_time + 5.0))
			"1x":
				replay_speed_button = button
				button.pressed.connect(_cycle_replay_speed)
			"CAMERA":
				button.pressed.connect(_toggle_camera)
			"CENTER":
				button.pressed.connect(_recenter_camera)
			"EXIT":
				button.pressed.connect(_restart)
	stack.add_child(_label("SPACE play/pause   ·   ← / → seek   ·   TAB camera   ·   G center   ·   ESC exit", 13, Color(0.75, 0.86, 1.0)))
	replay_panel.visible = false

func _start_replay() -> void:
	if not replay.available():
		return
	_set_paused(false)
	replay_active = true
	run_finished = true
	replay_time = 0.0
	replay_rate = 1.0
	replay_speed_button.text = "1x"
	camera_rotation_ready = false
	orbit_yaw = 0.0
	orbit_pitch = 0.0
	orbit_zoom = 1.0
	orbit_drag = false
	camera_was_grounded = true
	camera_offset = Vector3.ZERO
	camera_height = 0.0
	first_person = false
	runner.set_first_person(false)
	runner.apply_cosmetic(int(replay.archived.get("cosmetic", 0)))
	course.begin_replay_layout(replay.archived["recipes"])
	stats_label.visible = false
	watch_replay_button.visible = false
	restart_button.visible = false
	message_label.visible = false
	replay_panel.visible = true
	replay_slider.max_value = replay.duration()
	_set_replay_playing(true)
	_seek_replay(0.0)

func _set_replay_playing(value: bool) -> void:
	if value and replay_time >= replay.duration():
		_seek_replay(0.0)
	replay_playing = value
	replay_play_button.text = "PAUSE" if value else "PLAY"
	effects.set_paused(not value)

func _cycle_replay_speed() -> void:
	# Use the actual playback rate, not a formatted label.
	if replay_rate>=2.0:
		replay_rate=0.5
		replay_speed_button.text="0.5x"
	elif replay_rate>=1.0:
		replay_rate=2.0
		replay_speed_button.text="2x"
	else:
		replay_rate=1.0
		replay_speed_button.text="1x"

func _seek_replay(value: float, snap_camera: bool = true) -> void:
	if not replay_active:
		return
	replay_time = clampf(value, 0.0, replay.duration())
	var state: Dictionary = replay.sample(replay_time)
	var shift: Vector3 = state["shift"]
	course.replay_stream(float(state["s"]), shift)
	var pose: Transform3D = state["pose"]
	pose.origin -= shift
	runner.transform = pose
	runner.distance = float(state["s"])
	runner.lane = float(state["lane"])
	runner.surface_side = int(state["side"])
	runner.speed = float(state["speed"])
	if snap_camera:
		mountain_pose_ready = false
		effects.clear_trail()
	runner.grounded = bool(state["grounded"])
	runner.is_sliding = bool(state["sliding"])
	runner.diving = bool(state["diving"])
	runner.height = float(state["height"])
	runner.air_time = float(state["air_time"])
	runner.kickflip_progress = float(state.get("kickflip", 1.0))
	runner.rider_crouch = float(state.get("rider_crouch", 0.85 if runner.is_sliding else 0.0))
	runner.rider_phase = float(state.get("rider_phase", 0.0))
	runner.rider_steer = float(state.get("rider_steer", 0.0))
	runner.rider_landing = float(state.get("rider_landing", 0.0))
	runner.rider_impact = float(state.get("rider_impact", 0.0))
	runner.rider_clearance = float(state.get("rider_clearance",0.0))
	runner.rider_dive = float(state.get("rider_dive",1.0 if runner.diving else 0.0))
	runner.rider_flourish = float(state.get("rider_flourish",0.0))
	runner.rider_bank = float(state.get("rider_bank",0.0))
	runner.rider_brace = float(state.get("rider_brace",0.0))
	runner.rider_trick_mix = float(state.get("rider_trick_mix",0.0))
	runner.rider_trick_clock = float(state.get("rider_trick_clock",0.0))
	runner.steering_heading = float(state.get("steering_heading",0.0))
	runner.rider_ground_idle = float(state.get("rider_ground_idle",0.0))
	runner.rider_inverted = float(state.get("rider_inverted",0.0))
	runner.rider_glider=float(state.get("rider_glider",0.0))
	runner.rider_glider_return=float(state.get("rider_glider_return",-1.0))
	runner.rider_glider_entry=float(state.get("rider_glider_entry",-1.0))
	runner.rider_glider_gyro=float(state.get("rider_glider_gyro",-1.0))
	runner.rider_glider_spin=float(state.get("rider_glider_spin",1.0))
	runner.glider_trick_clock=float(state.get("glider_trick_clock",0.0))
	runner.gyro_trick_clock=float(state.get("gyro_trick_clock",0.0))
	runner.drift_amount = float(state.get("drift_amount",0.0))
	runner.rider_ground_variant = int(state.get("rider_ground_variant",0))
	runner.momentum_reserve = float(state["reserve"])
	runner.double_jump_available = bool(state["double_jump"])
	runner.landing_blend = 0.0
	if runner.grounded:
		runner.sync_pose(course)
	else:
		runner.air_basis = pose.basis
	runner.avatar.position = Vector3.ZERO
	runner.avatar.scale.y = 0.55 if runner.is_sliding else 1.0
	storm.front_s = float(state["storm_s"])
	storm.speed = float(state["storm_speed"])
	storm.elapsed = float(state["storm_time"])
	storm.sync_pose(course)
	storm.visible = bool(state["storm_visible"]) and storm.visible
	run_time = replay_time
	effects.speed = runner.speed
	replay_slider.set_value_no_signal(replay_time)
	var replay_note: String="(recording limit)" if bool(replay.archived.get("truncated",false)) else ""
	if replay_time>=replay.duration()-0.01 and not bool(replay.archived.get("truncated",false)):
		replay_note=str(replay.archived.get("reason",""))
	replay_clock.text="REPLAY   %.1f / %.1f s   %s" % [replay_time,replay.duration(),replay_note]
	if snap_camera:
		camera_rotation_ready = false
		camera_arm_ready = false
		camera_was_grounded = runner.is_grounded()
		camera_offset = Vector3.ZERO
		_update_camera(1.0)
