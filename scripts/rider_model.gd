extends Node3D
## Blocky, track-relative articulated rider. No billboard or camera-facing art.
var board: Node3D
var lightcycle: Node3D
var cycle_frame: Node3D
var cycle_forks: Array[Node3D] = []
var cycle_wheels: Array[Node3D] = []
var cycle_grips: Array[Node3D] = []
var cycle_body_mat: StandardMaterial3D
var cycle_tire_mat: StandardMaterial3D
var cycle_amount := 0.0
var cycle_fold := 0.0
var cycle_antigrav := 0.0
var cycle_hover_discs: Array[MeshInstance3D]=[]
var cycle_hover_mat: StandardMaterial3D
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
var jet_mat: StandardMaterial3D
var cosmetic_index := 0
var visual_lift := 0.0
var visual_pivot := 0.0
var handles: Node3D
var wings: Node3D
var treads: Node3D
var spider_upper: Array[MeshInstance3D]=[]
var spider_lower: Array[MeshInstance3D]=[]
var spider_feet: Array[MeshInstance3D]=[]
var engines: Array[Node3D]=[]
var exhausts: Array[MeshInstance3D]=[]
var gyro: Node3D
var gyro_rotor: Node3D
var gyro_panels: Array[Node3D]=[]
var gyro_axle: Node3D
const GYRO_SEGMENTS := 12
const GYRO_RADIUS := 1.10
const GYRO_CENTER := 1.16
var gyro_deploy := 0.0
var tread_deploy := 0.0
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
	jet_mat = _mat(Color(0.35,0.92,1.0))
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
	_build_lightcycle()
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
	wings=Node3D.new()
	wings.name="GliderWings"
	board.add_child(wings)
	for wing_side: float in [-1.0,1.0]:
		var wing:=SurfaceTool.new()
		wing.begin(Mesh.PRIMITIVE_TRIANGLES)
		var root_a:=Vector3(wing_side*0.48,0.09,-0.60)
		var tip_a:=Vector3(wing_side*3.0,0.17,0.30)
		var tip_b:=Vector3(wing_side*2.85,0.17,0.58)
		var root_b:=Vector3(wing_side*0.48,0.09,0.72)
		_quad(wing,root_a,root_b,tip_a,tip_b)
		var panel:=MeshInstance3D.new()
		panel.mesh=wing.commit()
		panel.material_override=deck_mat
		wings.add_child(panel)
		var line:=SurfaceTool.new()
		line.begin(Mesh.PRIMITIVE_LINES)
		for vertex: Vector3 in [root_a,tip_a,tip_a,tip_b,tip_b,root_b,root_b,root_a,root_a,tip_b]:
			line.add_vertex(vertex+Vector3.UP*0.012)
		var trim:=MeshInstance3D.new()
		trim.mesh=line.commit()
		trim.material_override=edge_mat
		wings.add_child(trim)
		var nacelle:=Node3D.new()
		nacelle.name="JetNacelle"
		nacelle.position=Vector3(wing_side*1.72,0.28,0.16)
		wings.add_child(nacelle)
		engines.append(nacelle)
		var cylinder:=CylinderMesh.new()
		cylinder.top_radius=0.27
		cylinder.bottom_radius=0.22
		cylinder.height=0.96
		cylinder.radial_segments=10
		var casing:=MeshInstance3D.new()
		casing.mesh=cylinder
		casing.material_override=deck_mat
		casing.rotation.x=PI*0.5
		nacelle.add_child(casing)
		var nozzle:=_block(nacelle,Vector3(0.37,0.37,0.17),edge_mat)
		nozzle.position.z=0.50
		var exhaust:=_block(nacelle,Vector3(0.17,0.17,0.85),jet_mat)
		exhaust.position.z=0.98
		exhausts.append(exhaust)
	wings.visible=false
	# Empty compatibility anchors: the old spider and gyro meshes are removed.
	treads=Node3D.new()
	board.add_child(treads)
	treads.hide()
	gyro=Node3D.new()
	add_child(gyro)
	gyro_rotor=Node3D.new()
	gyro.add_child(gyro_rotor)
	gyro_axle=Node3D.new()
	gyro.add_child(gyro_axle)
	gyro.hide()
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

func apply_cosmetic(index: int) -> void:
	cosmetic_index=clampi(index,0,3)
	var accents: Array[Color]=[Color(0.12,0.95,1.0),Color(1.0,0.64,0.12),Color(0.77,0.32,1.0),Color(0.17,1.0,0.49)]
	var accent:=accents[cosmetic_index]
	edge_mat.albedo_color=accent
	deck_mat.albedo_color=Color(0.12,0.24,0.36) if cosmetic_index==0 else Color(0.045,0.055,0.085).lerp(accent,0.26)
	white.albedo_color=Color(0.98,0.99,1.0).lerp(accent,0.19 if cosmetic_index!=0 else 0.0)
	shadow.albedo_color=Color(0.70,0.79,0.86).lerp(accent,0.42 if cosmetic_index!=0 else 0.0)
	jet_mat.albedo_color=Color(0.35,0.92,1.0) if cosmetic_index==0 else accent.lerp(Color.WHITE,0.32)
	cycle_body_mat.albedo_color=Color(0.035,0.055,0.085).lerp(accent,0.09)
	cycle_hover_mat.albedo_color=accent
	cycle_hover_mat.emission=accent

func set_first_person(enabled: bool) -> void:
	first_person_view=enabled
	head.visible = not enabled
	torso.visible = not enabled
	for part in upper_arms:
		part.visible = not enabled
	for part in lower_arms:
		part.visible = not enabled

# The cycle is an independent visual rig; no new collision body or forces.
# All coordinates are local to the current rider surface frame (-Z forward).
func _build_lightcycle() -> void:
	lightcycle=Node3D.new()
	lightcycle.name="Lightcycle"
	add_child(lightcycle)
	cycle_body_mat=_mat(Color(0.035,0.055,0.085))
	cycle_tire_mat=_mat(Color(0.012,0.018,0.027))
	cycle_hover_mat=_mat(Color(0.16,0.93,1.0))
	cycle_hover_mat.emission_enabled=true
	cycle_hover_mat.emission=Color(0.12,0.75,1.0)
	cycle_hover_mat.emission_energy_multiplier=1.8
	cycle_frame=Node3D.new()
	lightcycle.add_child(cycle_frame)
	# Sleek monocoque, sloped nose/tail and narrow saddle.
	_cycle_shell(cycle_frame,cycle_body_mat)
	var seat:=_block(cycle_frame,Vector3(0.48,0.12,0.68),cycle_tire_mat)
	seat.position=Vector3(0,0.86,0.28)
	var spine:=_block(cycle_frame,Vector3(0.20,0.06,1.38),edge_mat)
	spine.position=Vector3(0,0.74,-0.25)
	for side:float in [-1.0,1.0]:
		var rail:=_block(cycle_frame,Vector3(0.045,0.055,1.48),edge_mat)
		rail.position=Vector3(side*0.30,0.60,-0.04)
		var peg:=_block(cycle_frame,Vector3(0.28,0.08,0.21),edge_mat)
		peg.position=Vector3(side*0.43,0.39,0.43)
		var grip:=Node3D.new()
		cycle_frame.add_child(grip)
		grip.position=Vector3(side*0.36,1.02,-0.62)
		cycle_grips.append(grip)
		var bar:=_block(grip,Vector3(0.28,0.085,0.11),cycle_tire_mat)
		bar.position=Vector3.ZERO
		var tip:=_block(grip,Vector3(0.055,0.10,0.13),edge_mat)
		tip.position.x=side*0.12
	var rear_axle:=_block(cycle_frame,Vector3(1.40,0.18,0.25),cycle_body_mat)
	rear_axle.position=Vector3(0,0.53,1.08)
	for side: float in [-1.0,1.0]:
		var rear_trim:=_block(cycle_frame,Vector3(0.39,0.07,0.44),edge_mat)
		rear_trim.position=Vector3(side*0.47,0.65,0.98)
	for index in range(3):
		var fork:=Node3D.new()
		fork.name=["FrontWheel","RearLeftWheel","RearRightWheel"][index]
		lightcycle.add_child(fork)
		cycle_forks.append(fork)
		var wheel:=Node3D.new()
		fork.add_child(wheel)
		cycle_wheels.append(wheel)
		# Hubless dark tire and two luminous rings, axis along X.
		var tire:=TorusMesh.new()
		tire.inner_radius=0.34
		tire.outer_radius=0.52
		tire.rings=32
		tire.ring_segments=10
		var tire_part:=MeshInstance3D.new()
		tire_part.mesh=tire
		tire_part.material_override=cycle_tire_mat
		tire_part.rotation.z=PI*0.5
		tire_part.scale.y=1.5
		wheel.add_child(tire_part)
		for side:float in [-1.0,1.0]:
			var ring:=TorusMesh.new()
			ring.inner_radius=0.37
			ring.outer_radius=0.46
			ring.rings=32
			ring.ring_segments=8
			var ring_part:=MeshInstance3D.new()
			ring_part.mesh=ring
			ring_part.material_override=edge_mat
			ring_part.rotation.z=PI*0.5
			ring_part.position.x=side*0.115
			wheel.add_child(ring_part)
			# Visible animated radial markings make rotation legible.
			for mark_index in range(4):
				var mark:=_block(wheel,Vector3(0.035,0.07,0.14),edge_mat)
				var angle:=float(mark_index)*PI*0.5
				mark.position=Vector3(side*0.15,cos(angle)*0.42,sin(angle)*0.42)
				mark.rotation.x=angle
		var axle:=_block(fork,Vector3(0.36,0.13,0.13),cycle_body_mat)
		axle.position=Vector3.ZERO
		var disc_mesh:=CylinderMesh.new()
		disc_mesh.top_radius=0.30
		disc_mesh.bottom_radius=0.30
		disc_mesh.height=0.045
		disc_mesh.radial_segments=24
		var disc:=MeshInstance3D.new()
		disc.mesh=disc_mesh
		disc.material_override=cycle_hover_mat
		disc.rotation.z=PI*0.5
		disc.position.x=0.16 if index==1 else -0.16
		wheel.add_child(disc)
		disc.hide()
		cycle_hover_discs.append(disc)
	lightcycle.hide()

func _cycle_shell(parent: Node3D, material: StandardMaterial3D) -> void:
	var tool:=SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# z, half-width, lower edge and upper edge.
	var stations:Array[Vector4]=[
		Vector4(-1.48,0.13,0.45,0.69),
		Vector4(-1.02,0.28,0.34,0.91),
		Vector4(-0.48,0.36,0.29,0.83),
		Vector4(0.32,0.32,0.30,0.85),
		Vector4(0.91,0.27,0.33,0.71),
		Vector4(1.46,0.13,0.43,0.60)]
	for i in range(stations.size()-1):
		var a:=stations[i]
		var b:=stations[i+1]
		var al:=Vector3(-a.y,a.z,a.x)
		var ar:=Vector3(a.y,a.z,a.x)
		var atl:=Vector3(-a.y*0.68,a.w,a.x)
		var atr:=Vector3(a.y*0.68,a.w,a.x)
		var bl:=Vector3(-b.y,b.z,b.x)
		var br:=Vector3(b.y,b.z,b.x)
		var btl:=Vector3(-b.y*0.68,b.w,b.x)
		var btr:=Vector3(b.y*0.68,b.w,b.x)
		_quad(tool,atl,atr,btl,btr)
		_quad(tool,ar,al,br,bl)
		_quad(tool,al,atl,bl,btl)
		_quad(tool,atr,ar,btr,br)
		if i==0:
			_quad(tool,al,ar,atl,atr)
		if i==stations.size()-2:
			_quad(tool,br,bl,btr,btl)
	var shell:=MeshInstance3D.new()
	shell.mesh=tool.commit()
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	shell.material_override=material
	parent.add_child(shell)

# The old board remains the glider/gyro/ceiling platform. The cycle
# folds its wheel carriers into that platform at a surface/flight handoff.
func _cycle_pose(amount: float, steer: float, crouch: float, airborne: bool, flip: float, phase: float, landing: float, impact: float, dive_amount: float, speed_factor: float, idle_phase: float, idle_variant: int, drift: float, traveled: float, fall_amount: float, anti_amount: float) -> void:
	cycle_amount=amount
	cycle_fold=1.0-amount
	cycle_antigrav=clampf(anti_amount,0.0,1.0)
	lightcycle.visible=amount>0.015
	if amount<=0.015:
		return
	var speed_mix:=clampf(speed_factor,0.0,1.0)
	var falling:=clampf(fall_amount,0.0,1.0) if airborne else 0.0
	var drift_float:=falling*sin(phase*3.5)
	var idle:=sin(PI*idle_phase) if not airborne else 0.0
	var turn:=clampf(steer+drift*0.65,-1.0,1.0)
	var lean:=-turn*(0.15+0.30*speed_mix)*lerpf(1.0,0.24,cycle_antigrav)
	var jump_pitch:=0.0
	if airborne:
		jump_pitch=lerpf(0.25*sin(PI*clampf(flip,0.0,1.0)),-0.32+0.08*drift_float,falling)-0.40*dive_amount
		lean+=drift_float*0.13
	elif idle_variant in [1,2]:
		jump_pitch=idle*(0.10 if idle_variant==1 else -0.10)
	var bounce:=idle*0.045+0.012*sin(phase*7.0)*(1.0-speed_mix)
	var compression:=clampf(landing*0.16+impact*0.08+crouch*0.10,0.0,0.26)*(1.0-falling*0.85)
	# Lean about the tire contact plane; keep the tire off the track.
	var target_rotation:=Vector3(jump_pitch,turn*0.055,lean)
	var lift:=0.52*(1.0-cos(lean))+absf(sin(jump_pitch))*1.08+0.025+0.13*cycle_antigrav
	lightcycle.position=Vector3(0,lift+bounce-falling*0.15,falling*0.10)
	lightcycle.rotation=target_rotation
	cycle_frame.position=Vector3(0,-compression+falling*0.06,0)
	cycle_frame.scale=Vector3(1.0,lerpf(0.24,1.0,amount),lerpf(0.74,1.0,amount))
	for i in range(3):
		var fork:=cycle_forks[i]
		var z:float=-1.08 if i==0 else 1.08
		var side:float=0.0 if i==0 else (-1.0 if i==1 else 1.0)
		var swivel_sign:float=-1.0 if i==1 else 1.0
		var swivel:=lerpf(cycle_antigrav,1.0,cycle_fold)
		var spread:=side*lerpf(0.51,0.90,cycle_antigrav)*lerpf(0.28,1.0,amount)
		var wheel_y:=lerpf(0.52,0.30,cycle_antigrav)
		fork.position=Vector3(spread,lerpf(0.17,wheel_y,amount),z*lerpf(0.46,1.0,amount))
		fork.rotation=Vector3(0,turn*0.18*(1.0-cycle_antigrav) if i==0 else 0.0,swivel_sign*PI*0.5*swivel)
		cycle_wheels[i].rotation.x=fposmod(-traveled/0.52,TAU)
		cycle_hover_discs[i].visible=cycle_antigrav>0.45 and amount>0.50
		cycle_hover_discs[i].scale=Vector3.ONE*lerpf(0.3,1.0,smoothstep(0.45,1.0,cycle_antigrav))
	# Fade from the former rig pose to a real seated pose; hands and feet
	# are solved against the bike's current steering/compression transforms.
	var strength:=smoothstep(0.12,0.85,amount)
	var hip_target:=lightcycle.transform*(cycle_frame.transform*Vector3(0,0.98+falling*0.20,0.32+falling*0.08))
	var chest_target:=lightcycle.transform*(cycle_frame.transform*Vector3(0,1.29-speed_mix*0.15-crouch*0.12+falling*0.24,-0.08-speed_mix*0.18+falling*0.12))
	var shoulder_target:=chest_target+lightcycle.basis*Vector3(0,0.13,-0.06)
	var head_target:=shoulder_target+lightcycle.basis*Vector3(0,0.25,-0.10)
	var hip_value:=hips.position.lerp(hip_target,strength)
	var shoulder_value:=shoulder_target
	hips.position=hip_value
	hips.rotation=hips.rotation.lerp(target_rotation,strength)
	torso.position=torso.position.lerp(chest_target,strength)
	torso.rotation=torso.rotation.lerp(Vector3(-0.65-speed_mix*0.30-crouch*0.20+falling*0.34,turn*0.06,lean),strength)
	head.position=head.position.lerp(head_target,strength)
	head.rotation=head.rotation.lerp(Vector3(-0.12-dive_amount*0.20,-turn*0.17,lean*0.65),strength)
	for i in range(2):
		var side:float=-1.0 if i==0 else 1.0
		var foot_target:=lightcycle.transform*(cycle_frame.transform*Vector3(side*(0.43+falling*0.18),0.43+falling*0.10,0.43+falling*0.17))
		var foot:=boots[i].position.lerp(foot_target,strength)
		var hip_joint:=hip_value+lightcycle.basis*Vector3(side*0.16,0,0)
		var knee:=_joint(hip_joint,foot,lightcycle.basis*Vector3(side*0.52,0,-1),LEG_LENGTH)
		_segment(thighs[i],hip_joint,knee)
		_segment(shins[i],knee,foot)
		boots[i].position=foot
		boots[i].rotation=boots[i].rotation.lerp(Vector3(jump_pitch,side*0.08,lean),strength)
		var arm_start:=shoulder_value+lightcycle.basis*Vector3(side*0.24,0,0)
		var grip:=cycle_grips[i]
		grip.rotation.y=turn*0.22
		var grip_target:=lightcycle.transform*(cycle_frame.transform*grip.position)
		var old_hand:=lower_arms[i].position+lower_arms[i].basis.y*0.5
		var hand:=old_hand.lerp(grip_target,strength)
		var elbow:=_joint(arm_start,hand,lightcycle.basis*Vector3(side*0.65,-0.1,0.6),ARM_LENGTH)
		_segment(upper_arms[i],arm_start,elbow)
		_segment(lower_arms[i],elbow,hand)

func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for vertex: Vector3 in [a,c,b,b,c,d]:
		tool.add_vertex(vertex)

func _segment(part: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var delta := b - a
	var length := delta.length()
	# Folded mechanical joints can share the same endpoint. Quaternion
	# requires nonzero UNIT vectors; never normalize a collapsed limb.
	if length < 0.0001:
		part.transform = Transform3D(Basis.IDENTITY,a)
		part.scale=Vector3(1.0,0.001,1.0)
		return
	var direction:=delta/length
	var rotation_basis:=Basis(Quaternion(Vector3.UP,direction))
	part.transform=Transform3D(rotation_basis,(a+b)*0.5)
	part.scale=Vector3(1.0,maxf(0.001,length),1.0)

func _joint(a: Vector3, b: Vector3, bend: Vector3, segment_length: float) -> Vector3:
	# Two-bone IK with constant limb lengths for reachable targets.
	var delta := b - a
	var reach := delta.length()
	if reach < 0.0001:
		return a + bend.normalized() * segment_length
	var axis := delta / reach
	var perpendicular := bend - axis * bend.dot(axis)
	if perpendicular.length_squared() < 0.0001:
		perpendicular=axis.cross(Vector3.RIGHT if absf(axis.x)<0.95 else Vector3.UP)
	return (a + b) * 0.5 + perpendicular.normalized() * sqrt(maxf(0.0, segment_length * segment_length - reach * reach * 0.25))

func _pose_gyro_panels(deploy: float, phase: float, gyro_trick: float, gyro_cycle: int, gyro_progress: float) -> void:
	# The rotor stays full-sized. First slide the rail cassettes out,
	# then articulate each curved segment upward, then engage the rim.
	# Reversing deployment naturally unlocks and folds in reverse.
	gyro.scale=Vector3.ONE
	gyro.position=Vector3(0,GYRO_CENTER,0)
	var extension:=smoothstep(0.0,0.30,deploy)
	var locking:=smoothstep(0.82,1.0,deploy)
	var roll_angle:=lerp_angle(0.0,phase*3.2+(TAU*smoothstep(0.0,1.0,gyro_progress) if gyro_cycle==0 else 0.0),locking)
	gyro_rotor.rotation=Vector3(roll_angle,gyro_trick*locking*0.28 if gyro_cycle==1 else 0.0,gyro_trick*locking*0.20 if gyro_cycle==2 else 0.0)
	for panel_index in range(gyro_panels.size()):
		var panel:=gyro_panels[panel_index]
		var side:float=-1.0 if panel_index<GYRO_SEGMENTS else 1.0
		var index:=panel_index%GYRO_SEGMENTS
		# Lowest arcs unfold first, crown arcs last. Curved pieces remain
		# rigid and retain their full dimensions throughout the motion.
		var arc_order:=absi(index-int(GYRO_SEGMENTS/2))
		var unfold:=smoothstep(0.18+float(arc_order)*0.045,0.67+float(arc_order)*0.045,deploy)
		var angle:=TAU*float(index)/float(GYRO_SEGMENTS)
		var stowed:=Vector3(side*0.52,-GYRO_CENTER+0.17+floorf(float(index)/4.0)*0.15,-0.78+float(index%4)*0.52)
		var extended:=stowed+Vector3(side*0.23,0.12,0.0)
		var locked:=Vector3(side*0.36,cos(angle)*GYRO_RADIUS,sin(angle)*GYRO_RADIUS)
		var position_value:=stowed.lerp(extended,extension).lerp(locked,unfold)
		var folded_basis:=Basis(Vector3.RIGHT,PI*0.5 if index%2==0 else -PI*0.5)
		var locked_basis:=Basis(Vector3.RIGHT,angle)
		panel.transform=Transform3D(folded_basis.slerp(locked_basis,unfold),position_value)
	gyro_axle.position=Vector3(0,-0.75*(1.0-extension),0)
	gyro_axle.visible=extension>0.05

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
	var glide:=clampf(float(extra.get("glider",0.0)),0.0,1.0)
	var return_progress:=float(extra.get("glider_return",-1.0))
	var entry_progress:=float(extra.get("glider_entry",-1.0))
	var legacy_transfer:=float(extra.get("glider_gyro",-1.0))
	if legacy_transfer>=0.0:
		return_progress=lerpf(0.60,1.0,legacy_transfer)
	var gyro_transfer:=-1.0
	if entry_progress>=0.0:
		return_progress=1.0-entry_progress
	var returning:=return_progress>=0.0
	var transferring:=gyro_transfer>=0.0
	var transfer_settle:=smoothstep(0.0,0.44,gyro_transfer) if transferring else 0.0
	var return_arc:=smoothstep(0.02,0.20,return_progress) if returning else 0.0
	var release:=smoothstep(0.015,0.16,return_progress) if returning else 0.0
	var wing_fold:=smoothstep(0.76,1.0,return_progress) if returning else 0.0
	var catch_blend:=smoothstep(0.60,0.72,return_progress) if returning else 0.0
	var freefall:=release*(1.0-catch_blend) if returning else 0.0
	var gliding:=glide>0.01 or returning
	var glide_clock:=float(extra.get("glider_clock",0.0))
	var glide_cycle:=posmod(int(floor(glide_clock/2.2)),8)
	var glide_progress:=fposmod(glide_clock,2.2)/2.2
	var glider_dive:=dive_amount if gliding and not returning and not transferring else 0.0
	var glide_trick:=sin(PI*glide_progress)*smoothstep(0.85,1.0,glide)*(1.0-glider_dive) if not returning and not transferring and not bool(extra.get("fp",false)) else 0.0
	var gyro_clock:=float(extra.get("gyro_clock",0.0))
	var gyro_cycle:=posmod(int(floor(gyro_clock/1.8)),6)
	var gyro_progress:=fposmod(gyro_clock,1.8)/1.8
	var gyro_trick:=sin(PI*gyro_progress) if not airborne and not gliding and not bool(extra.get("fp",false)) else 0.0
	var flipping := airborne and flip < 1.0 and not gliding
	var tuck := sin(PI * clampf(flip, 0.0, 1.0)) if flipping else 0.0
	var flick := _pulse(flip, 0.03, 0.24, 0.50) if flipping else 0.0
	var catch_pose := _pulse(flip, 0.64, 0.83, 1.0) if flipping else 0.0
	# Each 1.15-second airborne idle is a different board trick.
	# The endpoints ease back to neutral so they can blend/cancel cleanly.
	var idle := clampf(trick_mix,0.0,1.0)*(1.0-dive_amount) if airborne and not flipping and not gliding else 0.0
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
	var loop_cycle:=bool(extra.get("loop_cycle",false)) and not airborne
	var raw_inverted:=clampf(float(extra.get("inverted",0.0)),0.0,1.0)
	var raw_side:=absf(float(extra.get("sideways",0.0)))
	var anti_target:=maxf(raw_inverted,smoothstep(0.40,0.86,raw_side)) if not airborne and not loop_cycle else 0.0
	var anti_amount:=0.0 if loop_cycle else clampf(float(extra.get("cycle_antigrav",anti_target)),0.0,1.0)
	var inverted:=0.0
	var hang:=maxf(inverted if not airborne else 0.0,glide*(1.0-release)*(1.0-transfer_settle))
	var wing_span:=glide*(1.0-wing_fold)*(1.0-smoothstep(0.10,0.48,gyro_transfer) if transferring else 1.0)
	wings.visible=wing_span>0.015
	wings.scale.x=maxf(0.01,wing_span)
	var side_ride:=0.0
	var sideways:=0.0 if loop_cycle else smoothstep(0.50,0.90,absf(side_ride))
	if loop_cycle:
		side_ride=0.0
	if transferring:
		sideways=smoothstep(0.42,1.0,gyro_transfer)
	# Hardware is tied to contact, not the hanging animation. Airborne
	# gliders never show ceiling treads, even during a blended pose.
	tread_deploy=lerpf(tread_deploy,inverted if not airborne else 0.0,blend)
	treads.hide()
	# Eight long articulated legs spread out to the contact plane.
	# Feet stride in alternating groups; the body/board physics stays
	# fixed, with the enlarged legs wrapping out along the ceiling.
	treads.scale=Vector3.ONE
	for leg_index in range(spider_upper.size()):
		var sign_value:float=-1.0 if leg_index<4 else 1.0
		var z:float=-0.98+float(leg_index%4)*0.65
		var gait:=phase*7.5+float((leg_index+leg_index/4)%2)*PI
		var stride:=sin(gait)*0.82
		var lift_foot:=maxf(0.0,cos(gait))*0.48
		var anchor:=Vector3(sign_value*0.48,-0.09,z)
		var fan:=float(leg_index%4)-1.5
		var knee:=Vector3(sign_value*2.65,-0.72,z+fan*0.45)
		# Board hangs 2.5 m away from the contact plane. Feet
		# reach back to the ceiling while the knees fan outward.
		var toe:=Vector3(sign_value*4.25,-2.75+lift_foot,z+fan*0.65+stride)
		knee=anchor.lerp(knee,tread_deploy)
		toe=anchor.lerp(toe,tread_deploy)
		_segment(spider_upper[leg_index],anchor,knee)
		_segment(spider_lower[leg_index],knee,toe)
		spider_feet[leg_index].position=toe
		spider_feet[leg_index].scale=Vector3.ONE*maxf(0.01,tread_deploy)
	for exhaust_index in range(exhausts.size()):
		var exhaust:=exhausts[exhaust_index]
		var jet_length:=0.65+0.27*sin(phase*16.0+float(exhaust_index))+0.75*clampf(float(extra.get("speed_factor",0.0)),0.0,1.0)+glider_dive*0.65
		exhaust.scale.z=jet_length
		exhaust.position.z=0.52+0.43*jet_length
	gyro_deploy=0.0 if loop_cycle else lerpf(gyro_deploy,sideways,blend)
	gyro.hide()
	_pose_gyro_panels(gyro_deploy,phase,gyro_trick,gyro_cycle,gyro_progress)
	# The hoverboard remains full-size as the pilot's inner platform.
	# Its rails become the wheel, not a disappearing scaled copy.
	for mesh_index in range(2):
		var deck_piece:=board.get_child(mesh_index) as Node3D
		deck_piece.scale=Vector3.ONE
		deck_piece.visible=not (first_person_view and (gyro_deploy>0.1 or gliding))
	# Avoid deploying wings through a still-folding rim. Wing motion
	# resumes as the mechanical panels return to their rail cassettes.
	var wing_clearance:=1.0-smoothstep(0.08,0.55,gyro_deploy)
	wings.scale.x=maxf(0.01,wing_span*wing_clearance)
	wings.visible=wings.visible and wings.scale.x>0.015
	handles.visible=hang>0.015 and not first_person_view
	if first_person_view:
		for part in lower_arms:
			part.visible=false
		var special_view:=gliding or gyro_deploy>0.10
		hips.visible=not special_view
		for part in thighs:
			part.visible=not special_view
		for part in shins:
			part.visible=not special_view
		for part in boots:
			part.visible=not special_view
		# Engines and wing tips are seen from a clear cockpit rather
		# than looking through a rotating character/wing assembly.
		for engine in engines:
			engine.visible=false
		wings.visible=false
	else:
		hips.visible=true
		for part in thighs:
			part.visible=true
		for part in shins:
			part.visible=true
		for part in boots:
			part.visible=true
		for engine in engines:
			engine.visible=true
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
	if gliding:
		# The glider trick spins the ENTIRE visual rig, including the
		# character, grips and wings. It never spins the deck alone.
		var spin_progress:=clampf(float(extra.get("glider_spin",1.0)),0.0,1.0)
		var whole_spin:=TAU*smoothstep(0.0,1.0,spin_progress) if not returning and spin_progress<1.0 else 0.0
		rotation=Vector3(-0.82*glider_dive,0.0,PI*glide*(1.0-return_arc)*(1.0-transfer_settle)+whole_spin)
		if not returning and not transferring and spin_progress>=1.0 and glider_dive<0.05:
			match glide_cycle:
				0: rotation.z+=0.40*glide_trick # wing rock
				1: rotation.y+=0.55*glide_trick # yaw sweep
				2: rotation.x+=0.36*glide_trick # pitch stall
				3: rotation.x-=TAU*smoothstep(0.12,0.88,glide_progress)*smoothstep(0.90,1.0,glide) if glide_trick>0.001 else 0.0
				4: rotation.z+=TAU*smoothstep(0.12,0.88,glide_progress)*smoothstep(0.90,1.0,glide) if glide_trick>0.001 else 0.0
				5: rotation.y-=0.48*glide_trick # opposite swing
				6: rotation.x-=0.25*glide_trick # tuck
				7: rotation.z-=0.35*glide_trick # scissor sway
		visual_pivot=0.95
		visual_lift=glide*0.55*(1.0-return_arc)*(1.0-transfer_settle)
	if not airborne and not gliding:
		visual_lift+=2.50*tread_deploy
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
	# Gyro stance: tucked pilot inside the rolling cage, feet on the
	# inner platform and both hands on stationary side grips.
	hip=hip.lerp(Vector3(0.0,0.76+0.18*gyro_trick*float(gyro_cycle==3),0.14),gyro_deploy)
	chest=chest.lerp(Vector3(0.0,1.10,-0.08),gyro_deploy)
	shoulder=shoulder.lerp(Vector3(0.0,1.26,-0.08),gyro_deploy)
	hip=hip.lerp(Vector3(0.0,1.65,0.10),hang)
	chest=chest.lerp(Vector3(0.0,1.13,0.04),hang)
	shoulder=shoulder.lerp(Vector3(0.0,0.89,0.0),hang)
	# Detached rider spreads limbs and tucks just before the catch.
	hip=hip.lerp(Vector3(0,1.10,0.10),freefall)
	chest=chest.lerp(Vector3(0,1.52,-0.28),freefall)
	shoulder=shoulder.lerp(Vector3(0,1.68,-0.38),freefall)
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
	head.rotation.y+=gyro_trick*gyro_deploy*0.45 if gyro_cycle==4 else 0.0
	# The board leaves the feet, rotates around its longitudinal axis,
	# then returns to level at the catch. No bank is added to the root.
	board.position=Vector3(0,0.13-tuck*0.24+0.14*(inverted if not airborne else 0.0)+0.32*smoothstep(0.45,0.95,gyro_deploy),0)
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
	if gliding:
		# No separate kickflip during gliding. The board remains attached
		# to the whole-rig rotation until the release phase.
		board.rotation=Vector3.ZERO
		if transferring:
			# Direct wall handoff: swing from the overhead grips into
			# the inner platform as wings fold, then assemble the rim.
			board.position=Vector3(0,lerpf(0.13,0.45,smoothstep(0.40,1.0,gyro_transfer)),0)
			board.rotation.x=0.32*sin(PI*transfer_settle)
		elif returning:
			# World-relative arc: glide wing overhead -> free glide around
			# the rider -> feet. Convert back to the animated root basis.
			var root_basis:=Basis.from_euler(rotation)
			var correction:=Vector3.UP*visual_pivot-root_basis*Vector3.UP*visual_pivot+Vector3.UP*visual_lift
			# First fly AWAY, leaving a clear interval of unsupported
			# free fall. Then swoop below the rider and rise to the feet.
			var fly_away:=smoothstep(0.06,0.29,return_progress)
			var swoop:=smoothstep(0.36,0.60,return_progress)
			var catch_up:=smoothstep(0.60,0.72,return_progress)
			var overhead:=Vector3(0,2.32,0)
			var away:=Vector3(3.6,2.7,-2.6)
			var below:=Vector3(0,-1.15,0.9)
			var caught:=Vector3(0,0.13,0)
			var arc_position:=overhead.lerp(away,fly_away).lerp(below,swoop).lerp(caught,catch_up)
			board.position=root_basis.inverse()*(arc_position-correction)
			board.rotation.z=PI*(1.0-swoop)-rotation.z+sin(PI*swoop)*0.65
			board.rotation.x=-0.38*sin(PI*swoop)+0.28*sin(PI*catch_up)
			if return_progress>=0.72:
				board.position=Vector3(0,0.13,0)
				board.rotation=Vector3.ZERO
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
		foot=foot.lerp(Vector3(sign_value*0.23,board.position.y+0.075,sign_value*0.24),gyro_deploy)
		if returning:
			# Feet are free during the transfer, then settle on the deck.
			foot=foot.lerp(Vector3(sign_value*0.51,0.36,0.45+sign_value*0.25),freefall)
			foot=foot.lerp(board.position+board.basis*Vector3(sign_value*0.30,0.075,-0.34 if front else 0.34),catch_blend)
		foot=foot.lerp(Vector3(sign_value*0.22,2.27,0.20+sign_value*0.09),hang)
		# A glider dive uses the same grips, but trails both legs
		# aft in a streamlined pose while the entire rig noses down.
		foot=foot.lerp(Vector3(sign_value*0.12,2.10,0.78),glider_dive)
		if gliding and not returning:
			if glide_cycle==5:
				foot.x+=sign_value*glide_trick*0.48
			elif glide_cycle==6:
				foot.y-=glide_trick*0.48
				foot.z+=glide_trick*0.24
			elif glide_cycle==7:
				foot.z+=sign_value*glide_trick*0.48
		if gyro_cycle==5:
			foot.y+=gyro_deploy*gyro_trick*0.13*(1.0 if i==0 else 0.0)
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
		hand=hand.lerp(Vector3(sign_value*0.35,1.17,-0.34),gyro_deploy)
		if returning:
			hand=hand.lerp(Vector3(sign_value*0.87,1.44,-0.05),freefall)
		hand=hand.lerp(board.position+board.basis*Vector3(sign_value*0.37,0.36,0.0),hang)
		if gyro_cycle==4 and i==1:
			hand.y+=gyro_deploy*gyro_trick*0.24
		if glide_cycle==2 and i==0 and not returning:
			hand=hand.lerp(board.position+board.basis*Vector3(-0.72,0.16,0.1),glide_trick*0.5)
		var elbow := _joint(arm_start, hand, Vector3(sign_value * 0.7, 0, 0.65), ARM_LENGTH)
		_segment(upper_arms[i], arm_start, elbow)
		_segment(lower_arms[i], elbow, hand)
	# Live runner opts into the cycle; the legacy deck solver is still
	# available for the three other vehicle rigs and geometry fixtures.
	var use_cycle:=bool(extra.get("lightcycle",false))
	var cycle_target:=0.0
	if use_cycle:
		cycle_target=1.0
		if gliding:
			if entry_progress>=0.0:
				cycle_target*=1.0-smoothstep(0.0,0.34,entry_progress)
			elif returning and not transferring:
				cycle_target*=smoothstep(0.72,1.0,return_progress)
			else:
				cycle_target=0.0
		# Old skate spins and ground hops are not suitable for the bike.
		# Wheelies, steering and suspension replace them instead.
		if cycle_target>0.0:
			rotation=rotation.lerp(Vector3.ZERO,smoothstep(0.0,0.75,cycle_target))
			visual_lift*=1.0-cycle_target
			visual_pivot*=1.0-cycle_target
	if loop_cycle and use_cycle:
		cycle_target=1.0
		wings.hide()
		treads.hide()
		gyro.hide()
		rotation=Vector3.ZERO
		visual_lift=0.0
		visual_pivot=0.0
	_cycle_pose(cycle_target,steer,crouch,airborne,flip,phase,landing,impact,dive_amount,float(extra.get("speed_factor",0.0)),ground_idle,ground_variant,drift,float(extra.get("cycle_distance",phase*4.0)),float(extra.get("cycle_fall",0.0)),anti_amount)
	if cycle_target>0.5:
		for mesh_index in range(2):
			(board.get_child(mesh_index) as Node3D).visible=false
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
