extends Control
## Player-relative top-down route map, colored by actual elevation.

var course: Node3D
var runner: Node3D
var storm: Node3D
var refresh := 0.0
var map_center := Vector2.ZERO
var map_radius := 0.0
var circle_outline := PackedVector2Array()

func setup(c: Node3D, r: Node3D, s: Node3D) -> void:
	course = c
	runner = r
	storm = s
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _process(delta: float) -> void:
	refresh += delta
	if refresh >= 0.16:
		refresh = 0.0
		queue_redraw()

func elevation_color(relative_y: float) -> Color:
	# Fixed elevation bands (rather than arbitrary min/max colors).
	var low := Color(0.13, 0.55, 0.96)
	var middle := Color(0.30, 0.89, 0.56)
	var high := Color(1.0, 0.78, 0.30)
	var peak := Color(0.98, 0.40, 0.35)
	if relative_y < 0.0:
		return middle.lerp(low, clampf(-relative_y / 35.0, 0.0, 1.0))
	if relative_y < 35.0:
		return middle.lerp(high, relative_y / 35.0)
	return high.lerp(peak, clampf((relative_y - 35.0) / 35.0, 0.0, 1.0))

func _map_point(p: Vector3, origin: Vector3, right: Vector3, forward: Vector3, scale_value: float, anchor: Vector2) -> Vector2:
	var offset := p - origin
	return anchor + Vector2(offset.dot(right), -offset.dot(forward)) * scale_value

func _inside(point: Vector2, margin: float = 0.0) -> bool:
	return point.distance_squared_to(map_center) <= pow(maxf(0.0, map_radius - margin), 2.0)

func _map_polygon(polygon: PackedVector2Array, color: Color) -> void:
	var all_inside := true
	for point in polygon:
		if not _inside(point):
			all_inside = false
			break
	if all_inside:
		draw_colored_polygon(polygon, color)
		return
	# Only edge cells need clipping; never draw outside the circle.
	for clipped in Geometry2D.intersect_polygons(polygon, circle_outline):
		if clipped.size() >= 3:
			draw_colored_polygon(clipped, color)

func _map_line(a: Vector2, b: Vector2, color: Color) -> void:
	var offset := a - map_center
	var segment := b - a
	var length_sq := segment.length_squared()
	if length_sq < 0.00001:
		return
	var radius := map_radius - 1.0
	var q := offset.dot(segment)
	var disc := q * q - length_sq * (offset.length_squared() - radius * radius)
	if disc < 0.0:
		return
	var start := maxf(0.0, (-q - sqrt(disc)) / length_sq)
	var end := minf(1.0, (-q + sqrt(disc)) / length_sq)
	if start < end:
		draw_line(a + segment * start, a + segment * end, color, 1.2, true)

func _draw() -> void:
	if not is_instance_valid(course) or not is_instance_valid(runner):
		return
	map_center = Vector2(size.x * 0.5, (size.y - 22.0) * 0.5)
	map_radius = minf(size.x, size.y - 22.0) * 0.5 - 3.0
	circle_outline.clear()
	for i in range(64):
		circle_outline.append(map_center + Vector2.from_angle(TAU * float(i) / 64.0) * map_radius)
	draw_circle(map_center, map_radius + 1.0, Color(0.015, 0.026, 0.055, 0.94))
	var font := ThemeDB.fallback_font
	draw_arc(map_center, map_radius + 1.0, 0.0, TAU, 96, Color(0.20, 0.65, 0.78), 2.0, true)
	var at: float = runner.get("distance")
	var center_frame: Transform3D = course.call("sample", at)
	var forward := -center_frame.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var player_pos := runner.position
	var span := clampf(float(runner.get("speed")) * 5.0, 420.0, 1150.0)
	var scale_value := map_radius * 1.55 / span
	var anchor := map_center + Vector2(0.0, map_radius * 0.60)
	var first := maxf(0.0, at - span * 0.12)
	var last := at + span
	var samples := 48
	for i in range(samples):
		var s0 := lerpf(first, last, float(i) / float(samples))
		var s1 := lerpf(first, last, float(i + 1) / float(samples))
		if not bool(course.call("has_distance", s0)) or not bool(course.call("has_distance", s1)):
			continue
		var f0: Transform3D = course.call("sample", s0)
		var f1: Transform3D = course.call("sample", s1)
		# Draw across-track elevation bands as projected quads.
		var width0: float = course.call("half_width_at", s0)
		var width1: float = course.call("half_width_at", s1)
		for j in range(6):
			var a := lerpf(-1.0, 1.0, float(j) / 6.0)
			var b := lerpf(-1.0, 1.0, float(j + 1) / 6.0)
			if not bool(course.call("support_at", (s0 + s1) * 0.5, (a + b) * 0.25 * (width0 + width1))):
				continue
			var p0: Vector3 = course.call("surface_position", s0, a * width0)
			var p1: Vector3 = course.call("surface_position", s0, b * width0)
			var p2: Vector3 = course.call("surface_position", s1, b * width1)
			var p3: Vector3 = course.call("surface_position", s1, a * width1)
			var polygon := PackedVector2Array([_map_point(p0, player_pos, right, forward, scale_value, anchor), _map_point(p1, player_pos, right, forward, scale_value, anchor), _map_point(p2, player_pos, right, forward, scale_value, anchor), _map_point(p3, player_pos, right, forward, scale_value, anchor)])
			# Near-vertical walls project to nearly zero area. A centerline
			# still makes their direction visible.
			if absf((polygon[1] - polygon[0]).cross(polygon[3] - polygon[0])) > 0.05:
				_map_polygon(polygon, elevation_color((p0.y + p1.y + p2.y + p3.y) * 0.25 - player_pos.y))
		if bool(course.call("support_at", (s0 + s1) * 0.5, 0.0)):
			_map_line(_map_point(f0.origin, player_pos, right, forward, scale_value, anchor), _map_point(f1.origin, player_pos, right, forward, scale_value, anchor), elevation_color((f0.origin.y + f1.origin.y) * 0.5 - player_pos.y))
		var index: int = course.call("chunk_index_at", s0)
		var kind: String = course.call("section_name", s0)
		if bool(course.call("has_shortcut", kind)):
			var across: float = course.call("shortcut_center", index)
			var shortcut: Transform3D = course.call("surface_frame", s0, across, 1)
			var marker := _map_point(shortcut.origin, player_pos, right, forward, scale_value, anchor)
			if _inside(marker, 2.0):
				draw_circle(marker, 1.7, Color(0.78, 0.93, 1.0))
		if float(course.call("recovery_accel", s0, float(course.call("recovery_center", index)), 1)) > 0.1:
			var recovery: Transform3D = course.call("surface_frame", s0, float(course.call("recovery_center", index)), 1)
			var recovery_marker := _map_point(recovery.origin, player_pos, right, forward, scale_value, anchor)
			if _inside(recovery_marker, 2.0):
				draw_circle(recovery_marker, 1.7, Color(0.1, 1.0, 0.3))
	var storm_at: float = storm.get("front_s")
	if storm.visible and storm_at >= first and storm_at <= last and bool(course.call("has_distance", storm_at)):
		var storm_frame: Transform3D = course.call("sample", storm_at)
		var p := _map_point(storm_frame.origin, player_pos, right, forward, scale_value, anchor)
		if _inside(p, 4.0):
			draw_circle(p, 4.0, Color(1.0, 0.15, 0.35))
	draw_colored_polygon(PackedVector2Array([anchor + Vector2(0, -7), anchor + Vector2(-5, 5), anchor + Vector2(5, 5)]), Color.WHITE)
	draw_arc(map_center, map_radius + 1.0, 0.0, TAU, 96, Color(0.20, 0.65, 0.78), 1.5, true)
	var legend_y := size.y - 20.0
	for i in range(4):
		draw_rect(Rect2(12.0 + 28.0 * float(i), legend_y, 25.0, 6.0), elevation_color(-35.0 + 35.0 * float(i)))
	draw_string(font, Vector2(12, size.y - 3), "LOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.9, 1.0))
	draw_string(font, Vector2(90, size.y - 3), "HIGH", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.9, 1.0))
	draw_string(font, Vector2(139, legend_y + 6), "• BYPASS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.78, 0.93, 1.0))
	draw_string(font, Vector2(139, size.y - 3), "• RECOVERY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.1, 1.0, 0.3))
