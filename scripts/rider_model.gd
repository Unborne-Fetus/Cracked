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

func pose(crouch: float, steer: float, airborne: bool, flip: float, phase: float = 0.0, landing: float = 0.0, impact: float = 0.0, dive: bool = false, dive_blend: float = 0.0, trick_clock: float = 0.0, trick_mix: float = 0.0, flourish: float = 0.0, bank: float = 0.0, brace: float = 0.0) -> void:
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
	var cycle := posmod(int(floor(trick_clock/1.15)),3)
	var progress := fposmod(trick_clock,1.15)/1.15
	var trick := sin(PI*progress)*idle
	var shifty := trick if cycle == 0 else 0.0
	var grab := trick if cycle == 1 else 0.0
	var one_foot := trick if cycle == 2 else 0.0
	var cheer := clampf(flourish,0.0,1.0) * (1.0-clampf(crouch,0.0,1.0)*0.6) if not airborne else 0.0
	var compression := clampf(landing, 0.0, 1.0)
	var recoil := clampf(impact, 0.0, 1.0)
	var bend := clampf(crouch + compression * 0.45 + recoil * 0.18 + grab*0.35 + brace*0.30, 0.0, 1.0)
	var lean := clampf(steer, -1.0, 1.0) * 0.19 - bank*0.09 + shifty*0.08
	var balance := sin(phase * 4.2) * 0.035 * (1.0 - bend) if not airborne else 0.0
	# Taller neutral stance (about 2.2m including the deck). Longer legs
	# stay visibly bent during the low speed tuck rather than scaling down.
	var hip := Vector3(lean + balance, lerpf(1.29, 0.80, bend) + tuck * 0.10 + dive_amount * 0.10, lerpf(0.02, 0.23, bend) + recoil * 0.08)
	var chest := hip + Vector3(lean * 0.38, lerpf(0.55, 0.42, bend)*(1.0-0.64*dive_amount), -0.31*bend-0.40*dive_amount)
	var shoulder := chest + Vector3(0, 0.22*(1.0-0.75*dive_amount), -0.05*bend-0.24*dive_amount)
	torso.position = chest
	torso.rotation.x = -0.52*bend-0.85*dive_amount+recoil*0.23
	torso.rotation.z = -lean * 1.25
	torso.rotation.y = -steer * 0.12 - shifty * 0.55 + grab * 0.25
	hips.position = hip
	hips.rotation.z = -lean * 0.5
	head.position = shoulder + Vector3(0,0.32*(1.0-0.62*dive_amount),-0.11*bend-0.23*dive_amount)
	head.rotation.x = -0.12*bend-0.48*dive_amount+recoil*0.10
	head.rotation.z = -lean * 0.40
	head.rotation.y = -steer * 0.09 + shifty*0.30 - bank*0.15
	# The board leaves the feet, rotates around its longitudinal axis,
	# then returns to level at the catch. No bank is added to the root.
	board.position.y = 0.13 - tuck * 0.24
	board.rotation.z = TAU * smoothstep(0.0, 1.0, flip) if flipping else 0.0
	board.rotation.x = (-0.18 * _pulse(flip, 0.0, 0.16, 0.40) + 0.10 * catch_pose) if flipping else -0.58*dive_amount+grab*0.29-one_foot*0.12
	board.rotation.y = shifty*0.75-grab*0.20
	if not flipping:
		board.rotation.z = shifty*0.18 + grab*0.15
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
		hand.y += brace*0.15 + sign_value*bank*0.12
		var elbow := _joint(arm_start, hand, Vector3(sign_value * 0.7, 0, 0.65), ARM_LENGTH)
		_segment(upper_arms[i], arm_start, elbow)
		_segment(lower_arms[i], elbow, hand)
