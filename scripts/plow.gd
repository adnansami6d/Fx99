extends "res://scripts/implement.gd"
# Disc plow (4 discs on a diagonal frame). It extends implement.gd - read that file to make new machines.
# Hooked on : frame is lifted, 55 km/h allowed (transport).
# WORK ON   : frame goes down, the discs spin and turn the soil, 20 km/h allowed.
# The plow hangs behind the tractor: this node's origin = hitch point, the plow extends to +Z.

const DISC_R := 0.42
const DISC_SPACING := Vector2(0.55, 0.75)   # x, z step between the discs (diagonal frame)
const TILL_RADIUS := 0.62                   # meters of soil each disc turns

var lift: Node3D                 # whole frame, pivots around the hitch (up = transport, down = work)
var discs: Array = []            # [spin node, global position holder]
var disc_spin := 0.0
var support_wheel: Node3D

# trailed behavior: the plow pivots on the hitch and is pulled behind, so it swings wide in turns
const TRAIL_LEN := 3.2     # hitch -> middle of the plow (m); smaller = reacts faster
const MAX_SWING := 0.9     # max angle (rad) between tractor and plow
var _dir := Vector3.BACK   # direction hitch -> plow (flat)
var _trail_ready := false
var _prev_hitch := Vector3.ZERO


func _init() -> void:
	label = "PLOW"
	side = "rear"
	transport_kmh = 55.0   # <- max speed when only hooked on
	work_kmh = 20.0        # <- max speed while plowing


func _build() -> void:
	var paint := Util.mat(Color(0.88, 0.45, 0.08), 0.55, 0.2)
	var steel := Util.mat(Color(0.32, 0.34, 0.38), 0.45, 0.7)
	var disc_mat := Util.mat(Color(0.78, 0.8, 0.84), 0.3, 0.85)
	var dark := Util.mat(Color(0.12, 0.12, 0.13), 0.7)
	var rim := Util.mat(Color(0.5, 0.52, 0.56), 0.4, 0.8)

	# fixed part at the tractor: headstock (does not move when the frame lifts)
	Util.part(self, Vector3(1.0, 0.18, 0.14), Vector3(0, 0.5, 0.1), paint)
	Util.part(self, Vector3(0.14, 0.7, 0.14), Vector3(0, 0.85, 0.1), paint)
	Util.part(self, Vector3(0.1, 0.1, 0.1), Vector3(0, 1.22, 0.1), steel)
	for sx in [-0.5, 0.5]:
		var pin := Util.mim(Util.cyl(0.07, 0.2, 10), steel)
		pin.position = Vector3(sx, 0.5, 0.1)
		pin.rotation_degrees.x = 90.0
		add_child(pin)

	lift = Node3D.new()
	lift.position = Vector3(0, 0.5, 0)
	add_child(lift)

	var p0 := Vector3(-0.83, 0.45, 1.1)                       # first disc leg top (relative to the pivot)
	var step := Vector3(DISC_SPACING.x, 0.0, DISC_SPACING.y)
	var p3 := p0 + step * 3.0

	# frame: cross bar at the headstock, brace to the first disc, long diagonal beam
	Util.part(lift, Vector3(1.2, 0.16, 0.16), Vector3(0, 0.0, 0.2), paint)
	_beam(lift, Vector3(0, 0.0, 0.2), p0, 0.15, paint)
	_beam(lift, p0, p3 + step * 0.0, 0.17, paint)

	for i in 4:
		var c := p0 + step * float(i)
		# leg from the beam down to the disc axle
		Util.part(lift, Vector3(0.09, 0.62, 0.09), c + Vector3(0, -0.31, 0), steel)
		var holder := Node3D.new()                 # axle position (disc center)
		holder.position = c + Vector3(0, -0.57, 0.0)
		holder.rotation_degrees = Vector3(0, 40.0, 14.0)   # cut angle + tilt of the disc
		lift.add_child(holder)
		var spin := Node3D.new()
		holder.add_child(spin)
		var disc := Util.mim(Util.cyl(DISC_R, 0.025, 24), disc_mat)
		disc.rotation_degrees.z = 90.0
		spin.add_child(disc)
		var hub := Util.mim(Util.cyl(0.075, 0.14, 10), steel)
		hub.rotation_degrees.z = 90.0
		spin.add_child(hub)
		# 3 dark bars across the disc + teeth on the edge: they make the turning visible
		for k in 3:
			var bar := Util.mim(Util.box(Vector3(0.04, DISC_R * 2.0 - 0.06, 0.055)), dark)
			bar.rotation_degrees.x = 60.0 * k
			spin.add_child(bar)
		var teeth: Array = []
		for k in 12:
			var a := TAU * float(k) / 12.0
			var b := Basis(Vector3.RIGHT, a)
			teeth.append(Transform3D(b, b * Vector3(0, 0, DISC_R)))
		Util.multi(spin, Util.box(Vector3(0.05, 0.05, 0.1)), rim, teeth)
		discs.append([spin, holder])

	# small support wheel at the back
	support_wheel = Node3D.new()
	support_wheel.position = p3 + Vector3(0.75, -0.75, 0.55)
	lift.add_child(support_wheel)
	Util.part(lift, Vector3(0.07, 0.5, 0.07), p3 + Vector3(0.75, -0.5, 0.55), steel)
	Util.part(lift, Vector3(0.9, 0.07, 0.07), p3 + Vector3(0.35, -0.25, 0.55), steel)
	var w := Util.mim(Util.cyl(0.2, 0.1, 14), dark)
	w.rotation_degrees.z = 90.0
	support_wheel.add_child(w)
	var w_rim := Util.mim(Util.cyl(0.11, 0.12, 10), rim)
	w_rim.rotation_degrees.z = 90.0
	support_wheel.add_child(w_rim)
	Util.part(support_wheel, Vector3(0.13, 0.03, 0.34), Vector3.ZERO, steel)

	lift.rotation.x = -0.2   # starts raised


# a box between two points (frame beams)
func _beam(parent: Node3D, a: Vector3, b: Vector3, t: float, m: Material) -> void:
	var d := b - a
	var n := Util.mim(Util.box(Vector3(t, t, d.length())), m)
	n.position = (a + b) * 0.5
	n.rotation.y = atan2(d.x, d.z)
	parent.add_child(n)


func _on_work_changed(_on: bool) -> void:
	pass   # the lift / spin are animated in _animate


func hooked(on: bool) -> void:
	_trail_ready = false
	super.hooked(on)


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
		_dir = (_dir - perp / TRAIL_LEN * delta).normalized()
		var ang := clampf(_dir.signed_angle_to(back, Vector3.UP), -MAX_SWING, MAX_SWING)
		_dir = back.rotated(Vector3.UP, -ang)
	_prev_hitch = hp
	global_transform = Transform3D(Basis(Vector3.UP, atan2(_dir.x, _dir.z)), hp)


func _animate(delta: float) -> void:
	if attached:
		_trail(delta)
	var target := 0.0 if working else -0.2
	lift.rotation.x = lerpf(lift.rotation.x, target, clampf(4.0 * delta, 0.0, 1.0))
	var want := (6.0 + absf(ground_speed) / DISC_R * 0.6) if working else 0.0
	disc_spin = lerpf(disc_spin, want, clampf(2.5 * delta, 0.0, 1.0))
	for d in discs:
		d[0].rotation.x -= disc_spin * delta
	support_wheel.rotation.x -= ground_speed / 0.2 * delta   # rolls with the ground


# every frame while WORK is ON: turn the soil under each disc
func _work(_delta: float, gs: float) -> void:
	if gs < 0.3:
		return   # standing still or reversing: nothing happens
	if field_map == null:
		field_map = get_tree().get_first_node_in_group("field_map")
		if field_map == null:
			return
	if lift.rotation.x < -0.05:
		return   # frame not down yet
	for d in discs:
		field_map.till_at(d[1].global_position, TILL_RADIUS)
