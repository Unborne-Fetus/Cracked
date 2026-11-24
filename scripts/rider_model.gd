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
		Vector3(0.40, 0.00, 1.10), Vector3(0.62, 0.00, 0.86),
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
	torso = _block(self, Vector3(0.56, 0.62, 0.34), white)
	head = _block(self, Vector3(0.45, 0.46, 0.43), white)
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

func pose(crouch: float, steer: float, airborne: bool, flip: float) -> void:
	var lean := clampf(steer, -1.0, 1.0) * 0.12
	var hip := Vector3(lean, lerpf(0.91, 0.57, crouch), lerpf(0.0, 0.24, crouch))
	var chest := hip + Vector3(lean * 0.45, lerpf(0.45, 0.32, crouch), -0.27*crouch)
	var shoulder := chest + Vector3(0, 0.19, -0.06*crouch)
	torso.position = chest
	torso.rotation.x = -0.46*crouch
	torso.rotation.z = -lean
	hips.position = hip
	head.position = shoulder + Vector3(0, 0.30, -0.13*crouch)
	head.rotation.x = -0.15*crouch
	head.rotation.z = -lean*0.4
	var flipping := airborne and flip < 1.0
	board.position.y = 0.13 - (sin(PI*flip)*0.26 if flipping else 0.0)
	board.rotation.z = TAU*smoothstep(0.0,1.0,flip) if flipping else 0.0
	for i in range(2):
		var sign_value := -1.0 if i == 0 else 1.0
		var foot := Vector3(sign_value*0.33, 0.23 + (0.10 if flipping else 0.0), sign_value*0.24)
		var knee := Vector3(sign_value*0.32+lean*0.5, lerpf(0.56,0.40,crouch), foot.z-0.24*crouch)
		var hip_joint := hip + Vector3(sign_value*0.15,0,0)
		_segment(thighs[i], hip_joint, knee)
		_segment(shins[i], knee, foot)
		boots[i].position = foot
		var arm_start := shoulder+Vector3(sign_value*0.27,0,0)
		var elbow := arm_start+Vector3(sign_value*lerpf(0.23,0.35,crouch),-0.26,-0.04)
		var hand := elbow+Vector3(sign_value*0.14,-0.15,-0.10-0.10*crouch)
		_segment(upper_arms[i],arm_start,elbow)
		_segment(lower_arms[i],elbow,hand)
