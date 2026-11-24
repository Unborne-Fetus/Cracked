extends Node3D
## Blocky, track-relative articulated rider. No billboard or camera-facing art.
var board: Node3D
var torso: MeshInstance3D
var head: MeshInstance3D
var hips: MeshInstance3D
var upper_arms: Array[MeshInstance3D] = []
var lower_arms: Array[MeshInstance3D] = []
var thighs: Array[MeshInstance3D] = []
var shins: Array[MeshInstance3D] = []
var boots: Array[MeshInstance3D] = []
var white: StandardMaterial3D
var shadow: StandardMaterial3D
var deck_mat: StandardMaterial3D
var edge_mat: StandardMaterial3D
var visual_lift := 0.0
var visual_pivot := 0.0
var handles: Node3D
var sideways_amount := 0.0
var first_person_view := false
# Visual dimensions only. The gameplay collision envelope is unchanged.
const LEG_LENGTH := 0.61
const ARM_LENGTH := 0.34

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func _block(parent: Node3D, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	part.mesh = box
	part.material_override = material
	parent.add_child(part)
	return part

func _ready() -> void:
	white = _mat(Color(0.98, 0.99, 1.0))
	shadow = _mat(Color(0.70, 0.79, 0.86))
	deck_mat = _mat(Color(0.12, 0.24, 0.36))
	edge_mat = _mat(Color(0.12, 0.95, 1.0))
	board = Node3D.new()
	board.name = "HoverboardFlip"
	add_child(board)
	# Eight cross-sections form a real upturned bobsled nose at -Z.
	# The dark blue deck and cyan rails separate it from the white rider.
	var stations := [
		Vector3(0.40, 0.13, 1.10), Vector3(0.62, 0.045, 0.86),
		Vector3(0.65, 0.00, 0.28), Vector3(0.65, 0.00, -0.44),
		Vector3(0.61, 0.035, -0.72), Vector3(0.54, 0.12, -0.94),
		Vector3(0.43, 0.25, -1.12), Vector3(0.26, 0.40, -1.24)]
	var solid := SurfaceTool.new()
	solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_LINES)
	for i in range(stations.size() - 1):
		var a: Vector3 = stations[i]
		var b: Vector3 = stations[i + 1]
		var al := Vector3(-a.x, a.y, a.z)
		var ar := Vector3(a.x, a.y, a.z)
		var bl := Vector3(-b.x, b.y, b.z)
		var br := Vector3(b.x, b.y, b.z)
		var drop := Vector3(0, 0.11, 0)
		_quad(solid, al, ar, bl, br)
		_quad(solid, ar-drop, al-drop, br-drop, bl-drop)
		_quad(solid, al-drop, al, bl-drop, bl)
		_quad(solid, ar, ar-drop, br, br-drop)
		for p: Vector3 in [al, bl, ar, br]:
			rails.add_vertex(p + Vector3.UP * 0.008)
		if i == 0:
			_quad(solid, ar, al, ar-drop, al-drop)
		if i == stations.size() - 2:
			_quad(solid, bl, br, bl-drop, br-drop)
	var deck := MeshInstance3D.new()
	deck.mesh = solid.commit()
	deck_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	deck.material_override = deck_mat
	board.add_child(deck)
	var outline := MeshInstance3D.new()
	outline.mesh = rails.commit()
	outline.material_override = edge_mat
	board.add_child(outline)
	handles=Node3D.new()
	handles.name="RetractableHandles"
	board.add_child(handles)
	for side: float in [-1.0,1.0]:
		var grip := _block(handles,Vector3(0.17,0.11,0.48),edge_mat)
		grip.position=Vector3(side*0.37,0.36,0.0)
		for z: float in [-0.21,0.21]:
			var post := _block(handles,Vector3(0.10,0.36,0.10),deck_mat)
			post.position=Vector3(side*0.37,0.18,z)
	handles.visible=false
	# Solid rectangular segmented limbs, not a flat sprite. Side and
	# rear views show the same model and actual depth.
	torso = _block(self, Vector3(0.56, 0.78, 0.34), white)
	head = _block(self, Vector3(0.45, 0.49, 0.43), white)
	hips = _block(self, Vector3(0.48, 0.24, 0.34), shadow)
	for i in range(2):
		upper_arms.append(_block(self, Vector3(0.18, 1.0, 0.20), white))
		lower_arms.append(_block(self, Vector3(0.17, 1.0, 0.19), shadow))
		thighs.append(_block(self, Vector3(0.24, 1.0, 0.25), white))
		shins.append(_block(self, Vector3(0.21, 1.0, 0.22), shadow))
		boots.append(_block(self, Vector3(0.27, 0.15, 0.39), white))
	pose(0.0, 0.0, false, 1.0)

func set_first_person(enabled: bool) -> void:
	first_person_view=enabled
	head.visible = not enabled
	torso.visible = not enabled
	for part in upper_arms:
		part.visible = not enabled
	for part in lower_arms:
		part.visible = not enabled

func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for vertex: Vector3 in [a,c,b,b,c,d]:
		tool.add_vertex(vertex)

func _segment(part: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var delta := b - a
	var length := maxf(0.001, delta.length())
	var rotation_basis := Basis(Quaternion(Vector3.UP, delta / length))
	part.transform = Transform3D(rotation_basis.scaled(Vector3.ONE), (a+b)*0.5)
	part.scale = Vector3(1.0, length, 1.0)

func _joint(a: Vector3, b: Vector3, bend: Vector3, segment_length: float) -> Vector3:
	# Two-bone IK with constant limb lengths for reachable targets.
	var delta := b - a
	var reach := delta.length()
	if reach < 0.0001:
		return a + bend.normalized() * segment_length
	var axis := delta / reach
	var perpendicular := bend - axis * bend.dot(axis)
	if perpendicular.length_squared() < 0.0001:
		perpendicular = axis.cross(Vector3.RIGHT)
	return (a + b) * 0.5 + perpendicular.normalized() * sqrt(maxf(0.0, segment_length * segment_length - reach * reach * 0.25))

func _pulse(value: float, start: float, peak: float, end: float) -> float:
	return smoothstep(start, peak, value) * (1.0 - smoothstep(peak, end, value))

func pose(crouch: float, steer: float, airborne: bool, flip: float, phase: float = 0.0, landing: float = 0.0, impact: float = 0.0, dive: bool = false, dive_blend: float = 0.0, trick_clock: float = 0.0, trick_mix: float = 0.0, flourish: float = 0.0, bank: float = 0.0, brace: float = 0.0, extra: Dictionary = {}) -> void:
	var blend := clampf(float(extra.get("pose_blend",1.0)),0.0,1.0)
	var previous_root := transform
	var previous_parts: Array[Transform3D]=[]
	for child in get_children():
		previous_parts.append((child as Node3D).transform)
	var previous_lift := visual_lift
	var previous_pivot := visual_pivot
	var dive_amount := maxf(dive_blend,1.0 if dive else 0.0) if airborne else 0.0
	# All phases are derived from recorded simulation time; camera orbit
	# and render rate never alter the animation or the player's physics.
	var flipping := airborne and flip < 1.0
	var tuck := sin(PI * clampf(flip, 0.0, 1.0)) if flipping else 0.0
	var flick := _pulse(flip, 0.03, 0.24, 0.50) if flipping else 0.0
	var catch_pose := _pulse(flip, 0.64, 0.83, 1.0) if flipping else 0.0
	# Each 1.15-second airborne idle is a different board trick.
	# The endpoints ease back to neutral so they can blend/cancel cleanly.
	var idle := clampf(trick_mix,0.0,1.0) * (1.0-dive_amount) if airborne and not flipping else 0.0
	var cycle := posmod(int(floor(trick_clock/1.15)),24)
	var progress := fposmod(trick_clock,1.15)/1.15
	var trick := sin(PI*progress)*idle
	var shifty := trick if cycle == 0 else 0.0
	var grab := trick if cycle == 1 else 0.0
	var one_foot := trick if cycle == 2 else 0.0
	var heel := trick if cycle == 3 else 0.0
	var shove := trick if cycle == 4 else 0.0
	var front_flip := trick if cycle == 5 else 0.0
	var back_flip := trick if cycle == 6 else 0.0
	var scissor := trick if cycle == 7 else 0.0
	var barrel := trick if cycle == 8 else 0.0
	var nose_grab := trick if cycle == 9 else 0.0
	var tail_grab := trick if cycle == 10 else 0.0
	var indy := trick if cycle == 11 else 0.0
	var method_grab := trick if cycle == 12 else 0.0
	var double_kick := trick if cycle == 13 else 0.0
	var varial := trick if cycle == 14 else 0.0
	var body_spin := trick if cycle == 15 else 0.0
	var rocket := trick if cycle == 16 else 0.0
	var split_kick := trick if cycle == 17 else 0.0
	var tuck_spin := trick if cycle == 18 else 0.0
	var nose_manual := trick if cycle == 19 else 0.0
	var tail_manual := trick if cycle == 20 else 0.0
	var cross_grab := trick if cycle == 21 else 0.0
	var cork := trick if cycle == 22 else 0.0
	var superman := trick if cycle == 23 else 0.0
	var grab_total := clampf(grab+nose_grab+tail_grab+indy+method_grab+cross_grab,0.0,1.0)
	var drift := clampf(float(extra.get("drift",0.0)),-1.0,1.0)
	var ground_variant := posmod(int(extra.get("ground_variant",0)),6)
	var inverted := clampf(float(extra.get("inverted",0.0)),0.0,1.0)
	var hang := inverted
	var side_ride := clampf(float(extra.get("sideways",0.0)),-1.0,1.0)*(1.0-hang)
	var sideways := absf(side_ride)
	handles.visible=hang>0.015
	if first_person_view:
		for part in lower_arms:
			part.visible=hang>0.45
	handles.scale.y=maxf(0.01,hang)
	var ground_idle := clampf(float(extra.get("ground_idle",0.0)),0.0,1.0) if not airborne else 0.0
	var ground_hop := sin(PI*ground_idle)
	# Idle rotations are isolated from the actual rider contact basis.
	var spin_angle := TAU*smoothstep(0.10,0.90,progress)
	var can_flip := bool(extra.get("flip_clear",false)) and idle>0.85 and absf(brace)<0.2
	rotation = Vector3.ZERO
	visual_pivot = 0.0
	visual_lift = 0.0
	if can_flip and cycle in [5,6,8,15,18,22]:
		visual_pivot = 0.95
		if cycle==8:
			rotation.z = spin_angle
		elif cycle==15 or cycle==18:
			rotation.y = spin_angle if cycle==15 else -spin_angle
		elif cycle==22:
			rotation = Vector3(spin_angle,0.0,sin(PI*progress)*0.75)
		else:
			rotation.x = spin_angle if cycle==5 else -spin_angle
	elif ground_idle>0.0:
		match ground_variant:
			0:
				rotation.y = TAU*smoothstep(0.12,0.88,ground_idle)
				visual_lift = ground_hop*0.42
			1:
				visual_lift = ground_hop*0.58
			2,3:
				visual_lift = ground_hop*0.12
			4:
				rotation.y = sin(TAU*ground_idle)*0.48
				visual_lift = ground_hop*0.30
			5:
				visual_lift = 0.0
	var cheer := clampf(flourish,0.0,1.0) * (1.0-clampf(crouch,0.0,1.0)*0.6) if not airborne else 0.0
	var compression := clampf(landing, 0.0, 1.0)
	var recoil := clampf(impact, 0.0, 1.0)
	var bend := clampf(crouch + compression * 0.45 + recoil * 0.18 + grab*0.35 + brace*0.30 + inverted*0.35 + (front_flip+back_flip+barrel)*0.20 + ground_hop*0.20+grab_total*0.23+tuck_spin*0.40+absf(drift)*0.25, 0.0, 1.0)
	var lean := clampf(steer,-1.0,1.0)*0.19-bank*0.09+shifty*0.08+drift*0.17+method_grab*0.12
	var balance := sin(phase * 4.2) * 0.035 * (1.0 - bend) if not airborne else 0.0
	# Taller neutral stance (about 2.2m including the deck). Longer legs
	# stay visibly bent during the low speed tuck rather than scaling down.
	var hip := Vector3(lean+balance-side_ride*0.13, lerpf(1.29, 0.80, bend) + tuck*0.10+dive_amount*0.10+rocket*0.16-superman*0.14, lerpf(0.02, 0.23, bend) + recoil * 0.08)
	var chest := hip + Vector3(lean * 0.38, lerpf(0.55, 0.42, bend)*(1.0-0.64*dive_amount), -0.31*bend-0.40*dive_amount)
	var shoulder := chest + Vector3(0, 0.22*(1.0-0.75*dive_amount), -0.05*bend-0.24*dive_amount)
	hip=hip.lerp(Vector3(0.0,1.65,0.10),hang)
	chest=chest.lerp(Vector3(0.0,1.13,0.04),hang)
	shoulder=shoulder.lerp(Vector3(0.0,0.89,0.0),hang)
	torso.position = chest
	torso.rotation.x = -0.52*bend-0.85*dive_amount+recoil*0.23
	torso.rotation.z = -lean * 1.25
	torso.rotation.y = -steer*0.12-shifty*0.55+grab*0.25+scissor*0.30
	torso.rotation.x += inverted*0.16-superman*0.85+nose_grab*0.35-tail_grab*0.28
	torso.rotation.z += -drift*0.28+method_grab*0.35-side_ride*0.32
	torso.rotation.x=lerpf(torso.rotation.x,PI,hang)
	torso.rotation.y += indy*0.36-cross_grab*0.45+body_spin*0.1
	hips.position = hip
	hips.rotation.z = -lean * 0.5
	head.position = shoulder + Vector3(0,0.32*(1.0-0.62*dive_amount),-0.11*bend-0.23*dive_amount)
	head.rotation.x = -0.12*bend-0.48*dive_amount+recoil*0.10
	head.rotation.z = -lean * 0.40
	head.rotation.y = -steer * 0.09 + shifty*0.30 - bank*0.15
	head.position=head.position.lerp(Vector3(0,0.67,0.03),hang)
	head.rotation.x=lerpf(head.rotation.x,PI,hang)
	# The board leaves the feet, rotates around its longitudinal axis,
	# then returns to level at the catch. No bank is added to the root.
	board.position.y = 0.13 - tuck * 0.24
	board.rotation.z = TAU * smoothstep(0.0, 1.0, flip) if flipping else 0.0
	board.rotation.x = (-0.18 * _pulse(flip, 0.0, 0.16, 0.40) + 0.10 * catch_pose) if flipping else -0.58*dive_amount+grab*0.29-one_foot*0.12
	board.rotation.y = shifty*0.75-grab*0.20+(spin_angle if cycle==4 and idle>0.85 else shove*0.40)+indy*0.32+method_grab*0.48+cross_grab*0.28-drift*0.16
	if cycle==14 and idle>0.85:
		board.rotation.y += spin_angle
	board.rotation.x += nose_grab*0.38-tail_grab*0.42+rocket*0.64+nose_manual*0.48-tail_manual*0.48-superman*0.20
	if ground_idle>0.0:
		if ground_variant==1:
			board.rotation.x += sin(TAU*ground_idle)*0.27
		elif ground_variant==2:
			board.rotation.x += ground_hop*0.23
		elif ground_variant==3:
			board.rotation.x -= ground_hop*0.23
	if not flipping:
		board.rotation.z = shifty*0.18+grab*0.15-(spin_angle if cycle==3 and idle>0.85 else heel*0.25)
		board.position.y -= heel*0.24+shove*0.16+double_kick*0.25+varial*0.25+superman*0.32
		board.rotation.z += (spin_angle*2.0 if cycle==13 and idle>0.85 else double_kick*0.2)+(spin_angle if cycle==14 and idle>0.85 else varial*0.18)+method_grab*0.34-indy*0.22
	for i in range(2):
		var sign_value := -1.0 if i == 0 else 1.0
		# Front (left) foot flicks diagonally over the nose. The back
		# foot lifts clear, both knees tuck, then feet return to the deck.
		var front := i == 0
		var foot := Vector3(sign_value * 0.30, 0.205, -0.34 if front else 0.34)
		if airborne:
			foot.y += 0.34 * tuck + (0.07 if not flipping else 0.0)
			if front:
				foot.x -= 0.34 * flick
				foot.z -= 0.37 * flick
				foot.y += 0.12 * flick
			else:
				foot.z += 0.13 * tuck
				foot.y += 0.09 * tuck
			foot.y -= 0.07 * catch_pose
		if dive_amount > 0.0 and not flipping:
			foot = foot.lerp(board.position + board.basis * Vector3(sign_value*0.30,0.075,-0.34 if front else 0.34),dive_amount)
		if idle > 0.0:
			# Keep planted feet aligned with the rotated deck; only the
			# deliberate one-foot trick removes the rear foot.
			var planted := board.position + board.basis * Vector3(sign_value*0.30,0.075,-0.34 if front else 0.34)
			foot = foot.lerp(planted, idle)
			if not front:
				foot += Vector3(one_foot*0.42,one_foot*0.33,one_foot*0.25)
			if heel>0.0 or shove>0.0:
				foot = Vector3(sign_value*(0.30+heel*0.32),0.205+maxf(heel,shove)*0.46,-0.34 if front else 0.34)
			if scissor>0.0:
				foot += Vector3(sign_value*scissor*0.38,scissor*0.27,-sign_value*scissor*0.48)
			foot.y += (front_flip+back_flip+barrel+tuck_spin+cork)*0.10
			if double_kick>0.0 or varial>0.0:
				foot = Vector3(sign_value*(0.30+double_kick*0.28),0.205+maxf(double_kick,varial)*0.52,-0.34 if front else 0.34)
			if split_kick>0.0:
				foot += Vector3(sign_value*split_kick*0.57,split_kick*0.34,sign_value*split_kick*0.34)
			if superman>0.0:
				foot += Vector3(sign_value*0.14,superman*0.35,superman*0.54)
			if rocket>0.0 and front:
				foot += Vector3(0.0,rocket*0.14,-rocket*0.25)
		if ground_idle>0.0 and ground_variant in [1,2,3]:
			foot = board.position+board.basis*Vector3(sign_value*0.30,0.075,-0.34 if front else 0.34)
		foot += Vector3(side_ride*0.12,sideways*0.10*(1.0 if sign_value*side_ride>0.0 else 0.0),-side_ride*sign_value*0.12)
		foot=foot.lerp(Vector3(sign_value*0.22,2.27,0.20+sign_value*0.09),hang)
		var hip_joint := hip + Vector3(sign_value * 0.16, 0, 0)
		var knee := _joint(hip_joint, foot, Vector3(sign_value * 0.30, 0.0, -1.0), LEG_LENGTH)
		_segment(thighs[i], hip_joint, knee)
		_segment(shins[i], knee, foot)
		boots[i].position = foot
		boots[i].rotation.x = (-0.38*flick if front else 0.20*tuck) - 0.58*dive_amount
		boots[i].rotation.z = -0.38 * flick if front else 0.0
		boots[i].rotation.y = sign_value * 0.13 + board.rotation.y * idle
		# Independent balancing arms: outward for carving, raised during
		# a trick, forward during a dive, briefly splayed on impact.
		var arm_start := shoulder + Vector3(sign_value * 0.27, 0, 0)
		var spread := 0.32 + absf(steer) * 0.14 + tuck * 0.20 + recoil * 0.14
		var arm_y := -0.43 + 0.27 * tuck + 0.18 * recoil
		var hand := arm_start + Vector3(sign_value*lerpf(spread,0.12,dive_amount),lerpf(arm_y+sign_value*steer*0.12,-0.10,dive_amount),lerpf(-0.16-0.29*bend+sign_value*balance,0.62,dive_amount))
		# A real reach toward the deck for the grab; counterbalancing
		# arms for shifty/one-foot, and a brief gate/landing salute.
		if i == 0:
			hand = hand.lerp(board.position+board.basis*Vector3(-0.46,0.12,-0.25), grab*0.78)
		else:
			hand += Vector3(0.04,cheer*0.48+shifty*0.14,0.10*one_foot)
		hand.y += brace*0.15+sign_value*bank*0.12+ground_hop*0.18
		hand = hand.lerp(arm_start+Vector3(sign_value*0.20,-0.42,0.28),inverted*0.80)
		hand.x += sign_value*(scissor*0.20+barrel*0.12)
		hand.z += (front_flip-back_flip)*0.18
		if i==0:
			hand = hand.lerp(board.position+board.basis*Vector3(-0.25,0.15,-0.95),nose_grab*0.85)
			hand = hand.lerp(board.position+board.basis*Vector3(0.40,0.12,0.24),cross_grab*0.85)
		else:
			hand = hand.lerp(board.position+board.basis*Vector3(0.26,0.15,0.94),tail_grab*0.85)
			hand = hand.lerp(board.position+board.basis*Vector3(0.58,0.13,0.0),indy*0.85)
			hand = hand.lerp(board.position+board.basis*Vector3(-0.45,0.13,0.32),method_grab*0.85)
			if ground_variant==5:
				hand.y += ground_hop*0.60
		hand.x += sign_value*(split_kick*0.22+drift*0.10)
		hand.y += rocket*0.22+tuck_spin*0.16
		hand.z -= superman*0.48
		hand += Vector3(side_ride*0.20,side_ride*sign_value*0.26,sideways*0.10)
		hand=hand.lerp(board.position+board.basis*Vector3(sign_value*0.37,0.36,0.0),hang)
		var elbow := _joint(arm_start, hand, Vector3(sign_value * 0.7, 0, 0.65), ARM_LENGTH)
		_segment(upper_arms[i], arm_start, elbow)
		_segment(lower_arms[i], elbow, hand)
	# Crossfade every joint, deck and visual root. A landing or dive can
	# interrupt a trick without teleporting limbs to a new pose.
	if blend<1.0:
		var goal_rotation := quaternion
		quaternion=previous_root.basis.get_rotation_quaternion().slerp(goal_rotation,blend)
		visual_lift=lerpf(previous_lift,visual_lift,blend)
		visual_pivot=lerpf(previous_pivot,visual_pivot,blend)
		for i in range(get_child_count()):
			var child := get_child(i) as Node3D
			child.transform=previous_parts[i].interpolate_with(child.transform,blend)
