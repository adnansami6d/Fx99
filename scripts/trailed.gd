extends "res://scripts/implement.gd"
# Base for machines that are PULLED behind the tractor (seeder, trailer): they pivot on the hitch and
# swing wide in turns, like plow.gd. Set trail_len (hitch -> middle of the machine) in _init().
# Put per-frame animation in _anim(delta) instead of _animate().

var trail_len := 3.2
var max_swing := 0.9
var _dir := Vector3.BACK
var _trail_ready := false
var _prev_hitch := Vector3.ZERO


func hooked(on: bool) -> void:
	_trail_ready = false
	super.hooked(on)


func _animate(delta: float) -> void:
	if attached:
		_trail(delta)
	_anim(delta)


func _anim(_delta: float) -> void:
	pass


func _trail(delta: float) -> void:
	var hp := global_position
	var back := global_transform.basis.z
	back.y = 0.0
	back = back.normalized()
	if not _trail_ready or delta <= 0.0:
		_dir = back
		_trail_ready = true
	else:
		var v := (hp - _prev_hitch) / delta
		v.y = 0.0
		var perp := v - _dir * v.dot(_dir)
		_dir = (_dir - perp / trail_len * delta).normalized()
		var ang := clampf(_dir.signed_angle_to(back, Vector3.UP), -max_swing, max_swing)
		_dir = back.rotated(Vector3.UP, -ang)
	_prev_hitch = hp
	global_transform = Transform3D(Basis(Vector3.UP, atan2(_dir.x, _dir.z)), hp)


# a box between two points
func _beam(parent: Node3D, a: Vector3, b: Vector3, t: float, m: Material) -> void:
	var d := b - a
	var n := Util.mim(Util.box(Vector3(t, t, d.length())), m)
	n.position = (a + b) * 0.5
	n.rotation.y = atan2(d.x, d.z)
	parent.add_child(n)


# a wheel that rolls with the ground (axle along X). Returns the node to spin around X.
func _wheel(pos: Vector3, r: float, w: float) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	var spin := Node3D.new()
	holder.add_child(spin)
	var tire := Util.mim(Util.cyl(r, w, 18), Util.mat(Color(0.07, 0.07, 0.07), 0.95))
	tire.rotation_degrees.z = 90.0
	spin.add_child(tire)
	var rim := Util.mim(Util.cyl(r * 0.55, w + 0.03, 12), Util.mat(Color(0.9, 0.7, 0.1), 0.5, 0.2))
	rim.rotation_degrees.z = 90.0
	spin.add_child(rim)
	var bar := Util.mim(Util.box(Vector3(w + 0.05, r * 1.6, 0.06)), Util.mat(Color(0.25, 0.25, 0.28)))
	spin.add_child(bar)
	return spin
