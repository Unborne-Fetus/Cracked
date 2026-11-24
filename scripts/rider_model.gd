extends Node3D
## Original pre-flow-reboot white articulated rider, with on-foot animation.
## Body geometry, materials and two-bone IK are taken from the original rig.
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
	torso = _block(self, Vector3(0.56, 0.78, 0.34), white)
	head = _block(self, Vector3(0.45, 0.49, 0.43), white)
	hips = _block(self, Vector3(0.48, 0.24, 0.34), shadow)
	for i in range(2):
		upper_arms.append(_block(self, Vector3(0.18, 1.0, 0.20), white))
		lower_arms.append(_block(self, Vector3(0.17, 1.0, 0.19), shadow))
		thighs.append(_block(self, Vector3(0.24, 1.0, 0.25), white))
		shins.append(_block(self, Vector3(0.21, 1.0, 0.22), shadow))
		boots.append(_block(self, Vector3(0.27, 0.15, 0.39), white))
	pose_run(0.0, 36.0, 0.0, true, false, 0.0, 0.0, 1.0)

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

# The board, wings, ceiling legs and gyro are deliberately not instantiated.
# Keep the old body, but animate its original joints for the current movement.
func pose_run(phase: float, speed: float, steer: float, grounded: bool, dive: bool, compression: float, flight_pitch: float, blend: float) -> void:
	var old: Array[Transform3D] = []
	for child in get_children():
		old.append((child as Node3D).transform)
	var pace := smoothstep(22.0, 130.0, speed)
	var bob := (0.025 + 0.018 * pace) * cos(phase * 2.0) if grounded else 0.0
	var crouch := clampf(compression, 0.0, 1.0)
	var lean := steer * 0.12
	var hip := Vector3(lean, 1.12 + bob - crouch * 0.20, 0.0)
	if not grounded:
		hip.y = 1.05 if dive else 1.13
		hip.z = 0.10 if dive else 0.0
	var chest := hip + Vector3(lean * 0.20, 0.54 if not dive else 0.33, -0.20 - pace * 0.10 - (0.30 if dive else 0.0))
	var shoulder := chest + Vector3(0.0, 0.22 if not dive else 0.10, -0.04)
	hips.position = hip
	hips.rotation = Vector3(0.0, 0.0, -steer * 0.10)
	torso.position = chest
	torso.rotation = Vector3(-0.26 - pace * 0.16 - (0.52 if dive else 0.0) + clampf(flight_pitch, -0.35, 0.35) * 0.20, 0.0, -steer * 0.15)
	head.position = shoulder + Vector3(0.0, 0.30 if not dive else 0.16, -0.08)
	head.rotation = Vector3(-0.10 - (0.25 if dive else 0.0), -steer * 0.08, -steer * 0.08)
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var cycle := phase + float(i) * PI
		var foot := Vector3(side * 0.17, 0.085, sin(cycle) * lerpf(0.28, 0.45, pace))
		if grounded:
			foot.y += maxf(0.0, cos(cycle)) * lerpf(0.22, 0.40, pace)
		else:
			foot = Vector3(side * 0.20, 0.38 if dive else 0.23 + float(i) * 0.12, 0.49 if dive else side * 0.24)
		var hip_joint := hip + Vector3(side * 0.16, 0.0, 0.0)
		var reach := foot - hip_joint
		if reach.length() > LEG_LENGTH * 2.0 - 0.01:
			foot = hip_joint + reach.normalized() * (LEG_LENGTH * 2.0 - 0.01)
		var knee := _joint(hip_joint, foot, Vector3(side * 0.20, 0.0, -1.0), LEG_LENGTH)
		_segment(thighs[i], hip_joint, knee)
		_segment(shins[i], knee, foot)
		boots[i].position = foot
		boots[i].rotation = Vector3(-0.25 * maxf(0.0, cos(cycle)) if grounded else (-0.55 if dive else 0.05), side * 0.08, 0.0)
		var arm_start := shoulder + Vector3(side * 0.27, 0.0, 0.0)
		var hand := arm_start + Vector3(side * 0.12, -0.44, -sin(cycle) * 0.30 - 0.08)
		if not grounded:
			hand = arm_start + Vector3(side * (0.10 if dive else 0.34), -0.22, 0.40 if dive else -0.12)
		var elbow := _joint(arm_start, hand, Vector3(side * 0.65, 0.0, 0.65), ARM_LENGTH)
		_segment(upper_arms[i], arm_start, elbow)
		_segment(lower_arms[i], elbow, hand)
	for i in range(get_child_count()):
		var part := get_child(i) as Node3D
		part.transform = old[i].interpolate_with(part.transform, clampf(blend, 0.0, 1.0))
