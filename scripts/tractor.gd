extends CharacterBody3D
# Arcade tractor. main.gd sets gas / brake / steer from the touch buttons.
# Brake: slows down; once stopped, holding brake = reverse.
#
# SPEED: the tractor itself is limited to MAX_KMH (60). When a machine is hooked on, the machine's own
# numbers decide (see scripts/implement.gd): transport_kmh while only hooked, work_kmh while WORK is ON.
# The lowest limit wins. If you are faster than the limit the tractor slows down by itself.
#
# ATTACHMENTS (plow etc.): any node in group "attachment" that has
#   - a child Marker3D named "Hitch"
#   - meta "side" = "rear" or "front"
# (scripts that extend implement.gd get all of this automatically.)
# Connected / disconnected MANUALLY with the ATTACH button (nothing connects by itself).

const Util = preload("res://scripts/util.gd")
const FuelD = preload("res://scripts/farm_data.gd")
const MAX_KMH := 60.0
const MAX_FWD := MAX_KMH / 3.6      # m/s
const MAX_REV := 4.0
const ACCEL := 4.2
const BRAKE_FORCE := 16.0
const OVER_LIMIT_DECEL := 6.0       # how fast it slows down when above a machine's limit
const REV_ACCEL := 3.0
const DRAG := 3.0
const TURN := 1.0
const GRAVITY := 20.0
const ATTACH_RANGE := 2.5

var fuel := FuelD.FUEL_TANK_TRACTOR   # liters
var fuel_cap := FuelD.FUEL_TANK_TRACTOR
var gas := false
var brake := false
var steer := 0.0
var speed := 0.0

var seat: Marker3D
var hitch_rear: Marker3D
var hitch_front: Marker3D
var slots := {}
var spinners: Array = []   # [node, radius]
var steerers: Array = []


func _ready() -> void:
	add_to_group("tractor")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.0, 1.7, 3.8)
	cs.shape = sh
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)
	_build_body()


func _build_body() -> void:
	var green := Util.mat(Color(0.12, 0.52, 0.17), 0.4, 0.35)
	var green_dk := Util.mat(Color(0.08, 0.38, 0.12), 0.45, 0.3)
	var yellow := Util.mat(Color(0.95, 0.76, 0.1), 0.45, 0.2)
	var dark := Util.mat(Color(0.1, 0.1, 0.11), 0.6, 0.3)
	var steel := Util.mat(Color(0.4, 0.42, 0.46), 0.4, 0.7)
	var white := Util.mat(Color(0.93, 0.94, 0.92), 0.5)
	var glass := Util.mat(Color(0.55, 0.75, 0.9, 0.3), 0.1)
	var seat_m := Util.mat(Color(0.18, 0.2, 0.28), 0.9)
	var lamp := Util.glow(Color(1.0, 0.95, 0.7), 1.6)
	var tail := Util.glow(Color(0.9, 0.05, 0.05), 1.2)
	var amber := Util.glow(Color(1.0, 0.6, 0.05), 1.6)

	# --- frame, engine, hood ---
	Util.part(self, Vector3(0.9, 0.45, 3.0), Vector3(0, 0.85, 0), steel)
	Util.part(self, Vector3(1.05, 0.7, 1.7), Vector3(0, 1.4, -1.05), green)
	Util.part(self, Vector3(0.92, 0.12, 1.6), Vector3(0, 1.81, -1.05), green_dk)
	Util.part(self, Vector3(0.14, 0.02, 1.5), Vector3(0, 1.88, -1.05), yellow)
	Util.part(self, Vector3(1.07, 0.06, 1.72), Vector3(0, 1.08, -1.05), yellow)    # yellow skirt line under the hood
	# front: grille, lights, bumper weight
	Util.part(self, Vector3(0.95, 0.62, 0.06), Vector3(0, 1.38, -1.91), dark)
	for i in 5:
		Util.part(self, Vector3(0.8, 0.03, 0.03), Vector3(0, 1.17 + i * 0.1, -1.95), steel)
	for sx in [-1.0, 1.0]:
		Util.part(self, Vector3(0.24, 0.17, 0.05), Vector3(0.36 * sx, 1.66, -1.93), steel)
		Util.part(self, Vector3(0.19, 0.12, 0.07), Vector3(0.36 * sx, 1.66, -1.95), lamp)
	Util.part(self, Vector3(1.4, 0.3, 0.28), Vector3(0, 0.62, -2.0), dark)
	Util.part(self, Vector3(1.3, 0.04, 0.3), Vector3(0, 0.78, -2.0), yellow)
	# exhaust stack with rain cap
	var pipe := Util.mim(Util.cyl(0.05, 0.85, 8), dark)
	pipe.position = Vector3(0.38, 2.25, -1.5)
	add_child(pipe)
	Util.part(self, Vector3(0.14, 0.03, 0.14), Vector3(0.38, 2.7, -1.5), steel, Vector3(18, 0, 0))
	# axles
	Util.part(self, Vector3(1.9, 0.14, 0.14), Vector3(0, 0.5, -1.3), dark)
	Util.part(self, Vector3(2.1, 0.2, 0.2), Vector3(0, 0.75, 0.9), dark)

	# --- cab ---
	Util.part(self, Vector3(1.55, 0.08, 1.65), Vector3(0, 1.12, 0.45), dark)
	for px in [-0.78, 0.78]:
		for pz in [-0.35, 1.15]:
			Util.part(self, Vector3(0.07, 1.7, 0.07), Vector3(px, 1.95, pz), white)
	Util.part(self, Vector3(1.78, 0.1, 1.8), Vector3(0, 2.82, 0.4), white)
	Util.part(self, Vector3(1.6, 0.04, 1.6), Vector3(0, 2.76, 0.4), green_dk)
	Util.part(self, Vector3(1.5, 1.45, 0.03), Vector3(0, 1.95, -0.35), glass)     # windshield
	Util.part(self, Vector3(1.5, 1.3, 0.03), Vector3(0, 1.98, 1.15), glass)       # rear window
	for sx in [-0.78, 0.78]:
		Util.part(self, Vector3(0.03, 1.2, 1.4), Vector3(sx, 2.0, 0.4), glass)    # side windows
	# roof beacon + work lights
	var beacon := Util.mim(Util.cyl(0.06, 0.14, 8), amber)
	beacon.position = Vector3(0.55, 2.94, 0.95)
	add_child(beacon)
	for sx in [-0.5, 0.5]:
		Util.part(self, Vector3(0.22, 0.1, 0.08), Vector3(sx, 2.78, -0.5), lamp)

	# --- driver area ---
	Util.part(self, Vector3(0.62, 0.14, 0.55), Vector3(0, 1.2, 0.4), seat_m)
	Util.part(self, Vector3(0.62, 0.62, 0.12), Vector3(0, 1.55, 0.74), seat_m)
	var col := Util.mim(Util.cyl(0.035, 0.5, 6), dark)
	col.position = Vector3(0, 1.45, -0.12)
	col.rotation_degrees.x = -30.0
	add_child(col)
	var sw := TorusMesh.new()
	sw.inner_radius = 0.07
	sw.outer_radius = 0.17
	sw.rings = 12
	sw.ring_segments = 6
	var wheel_n := Util.mim(sw, dark)
	wheel_n.position = Vector3(0, 1.68, -0.24)
	wheel_n.rotation_degrees.x = -60.0
	add_child(wheel_n)

	# --- fenders, steps, rear lights ---
	for sx in [-1.0, 1.0]:
		Util.part(self, Vector3(0.66, 0.07, 1.4), Vector3(1.07 * sx, 1.68, 0.9), green)
		Util.part(self, Vector3(0.06, 0.18, 1.4), Vector3(1.38 * sx, 1.6, 0.9), green)
		Util.part(self, Vector3(0.42, 0.05, 0.85), Vector3(0.92 * sx, 1.04, -1.3), green)
		Util.part(self, Vector3(0.3, 0.05, 0.5), Vector3(0.9 * sx, 0.78, -0.15), steel)
		Util.part(self, Vector3(0.16, 0.1, 0.05), Vector3(0.68 * sx, 1.0, 1.52), tail)

	# --- rear linkage (the arms the plow hangs on) ---
	for sx in [-1.0, 1.0]:
		Util.part(self, Vector3(0.07, 0.07, 1.0), Vector3(0.55 * sx, 0.5, 1.5), steel)
	Util.part(self, Vector3(0.2, 0.15, 0.55), Vector3(0, 0.62, 1.72), dark)
	Util.part(self, Vector3(0.06, 0.06, 0.95), Vector3(0, 1.0, 1.6), steel, Vector3(8, 0, 0))

	# --- wheels: big at the back, small at the front (front ones steer) ---
	_wheel(Vector3(-1.05, 0.78, 0.9), 0.78, 0.56, false)
	_wheel(Vector3(1.05, 0.78, 0.9), 0.78, 0.56, false)
	_wheel(Vector3(-0.92, 0.5, -1.3), 0.5, 0.36, true)
	_wheel(Vector3(0.92, 0.5, -1.3), 0.5, 0.36, true)

	# invisible points
	seat = Marker3D.new()
	seat.name = "Seat"
	seat.position = Vector3(0, 1.34, 0.35)
	add_child(seat)
	hitch_rear = Marker3D.new()
	hitch_rear.name = "HitchRear"
	hitch_rear.position = Vector3(0, 0.5, 2.0)
	add_child(hitch_rear)
	hitch_front = Marker3D.new()
	hitch_front.name = "HitchFront"
	hitch_front.position = Vector3(0, 0.5, -2.3)
	hitch_front.rotation.y = PI   # front attachments extend forward
	add_child(hitch_front)
	Util.bake(self)   # V29: merge all static parts per material = far fewer draw calls


# tire with tread blocks, yellow rim, hub and spokes. The spokes + tread make the turning visible.
func _wheel(pos: Vector3, r: float, w: float, steers: bool) -> void:
	var tire_m := Util.mat(Color(0.07, 0.07, 0.07), 0.95)
	var tread_m := Util.mat(Color(0.12, 0.12, 0.12), 0.95)
	var rim_m := Util.mat(Color(0.95, 0.76, 0.1), 0.45, 0.2)
	var hub_m := Util.mat(Color(0.5, 0.52, 0.56), 0.35, 0.8)
	var spoke_m := Util.mat(Color(0.2, 0.2, 0.22), 0.5, 0.4)

	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	var spin := Node3D.new()
	holder.add_child(spin)

	var tire := Util.mim(Util.cyl(r, w, 16), tire_m)
	tire.rotation_degrees.z = 90.0
	spin.add_child(tire)
	var rim := Util.mim(Util.cyl(r * 0.6, w + 0.03, 12), rim_m)
	rim.rotation_degrees.z = 90.0
	spin.add_child(rim)
	var hub := Util.mim(Util.cyl(r * 0.2, w + 0.1, 10), hub_m)
	hub.rotation_degrees.z = 90.0
	spin.add_child(hub)
	for k in 3:
		var spoke := Util.mim(Util.box(Vector3(w + 0.06, r * 1.1, r * 0.1)), spoke_m)
		spoke.rotation_degrees.x = 60.0 * k
		spin.add_child(spoke)

	var lugs: Array = []
	var n := 20 if r > 0.6 else 14
	for k in n:
		var a := TAU * float(k) / float(n)
		var b := Basis(Vector3.RIGHT, a)
		lugs.append(Transform3D(b, b * Vector3(0, 0, r + 0.01)))
	Util.multi(spin, Util.box(Vector3(w * 0.96, r * 0.34, 0.12)), tread_m, lugs)

	spinners.append([spin, r])
	if steers:
		steerers.append(holder)


func stop_inputs() -> void:
	gas = false
	brake = false
	steer = 0.0


func kmh() -> float:
	return absf(speed) * 3.6


# the lowest speed limit (km/h) of the tractor and everything hooked on it, right now
func speed_limit_kmh() -> float:
	var l := MAX_KMH
	for k in slots:
		var a = slots[k]
		if a != null and a.has_method("speed_limit_kmh"):
			l = minf(l, a.speed_limit_kmh())
	return l


func _physics_process(delta: float) -> void:
	var limit := speed_limit_kmh() / 3.6
	var empty := fuel <= 0.0   # no fuel: no engine
	if gas and not empty:
		var acc := ACCEL * (1.0 - 0.55 * clampf(speed / MAX_FWD, 0.0, 1.0))   # pulls less at high speed
		speed = move_toward(speed, limit, (acc if speed <= limit else OVER_LIMIT_DECEL) * delta)
	elif brake and not empty:
		if speed > 0.2:
			speed = move_toward(speed, 0.0, BRAKE_FORCE * delta)
		else:
			speed = move_toward(speed, -MAX_REV, REV_ACCEL * delta)   # stopped + brake = reverse
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)
	if speed > limit:
		speed = move_toward(speed, limit, OVER_LIMIT_DECEL * delta)   # a machine asks for less speed

	# turning only while moving (reverse turns the other way, like a real vehicle); gentler when fast
	var f := clampf(speed / 3.0, -1.0, 1.0) * lerpf(1.0, 0.4, clampf(absf(speed) / MAX_FWD, 0.0, 1.0))
	rotation.y -= steer * TURN * f * delta

	var fwd := -global_transform.basis.z
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if absf(speed) > 0.05 and fuel > 0.0:
		var used := absf(speed) * delta / 1000.0 / FuelD.TRACTOR_KM_PER_L * FuelD.FUEL_SCALE
		if is_working():
			used *= FuelD.WORK_FUEL_MULT
		fuel = maxf(0.0, fuel - used)
	if is_on_wall():
		speed = move_toward(speed, 0.0, 25.0 * delta)

	for s in spinners:
		s[0].rotation.x -= speed / float(s[1]) * delta
	for h in steerers:
		h.rotation.y = lerpf(h.rotation.y, -steer * 0.45, 10.0 * delta)

	_update_attachments()


func _hitch_point(side: String) -> Node3D:
	return hitch_rear if side == "rear" else hitch_front


# an attachment close enough to its hitch point and not connected yet (or null)
func candidate() -> Node3D:
	for a in get_tree().get_nodes_in_group("attachment"):
		var side: String = a.get_meta("side", "rear")
		if slots.get(side) != null:
			continue
		var h: Node3D = a.get_node_or_null("Hitch")
		if h == null:
			continue
		if h.global_position.distance_to(_hitch_point(side).global_position) < ATTACH_RANGE:
			return a
	return null


func attach_nearby() -> void:
	var a := candidate()
	if a != null:
		slots[a.get_meta("side", "rear")] = a
		if a.has_method("hooked"):
			a.hooked(true)


func has_attached() -> bool:
	for k in slots:
		if slots[k] != null:
			return true
	return false


func detach_all() -> void:
	for k in slots:
		var a = slots[k]
		if a != null and a.has_method("hooked"):
			a.hooked(false)   # also stops its work
	slots.clear()   # attachments stay where they are


# --- WORK button: starts / stops every hooked machine ---
func is_working() -> bool:
	for k in slots:
		var a = slots[k]
		if a != null and a.get("working") == true:
			return true
	return false


func toggle_work() -> void:
	var on := not is_working()
	for k in slots:
		var a = slots[k]
		if a != null and a.has_method("set_working"):
			a.set_working(on)


# "PLOW" / "PLOW + SEEDER" for the screen
func attached_names() -> String:
	var names: Array = []
	for k in slots:
		var a = slots[k]
		if a != null:
			names.append(str(a.get("label")))
	return " + ".join(names)


func _update_attachments() -> void:
	for side in slots:
		var a: Node3D = slots[side]
		if a == null:
			continue
		var h: Node3D = a.get_node_or_null("Hitch")
		if h == null:
			continue
		a.global_transform = _hitch_point(side).global_transform * h.transform.affine_inverse()


# hook a SPECIFIC machine (used when loading a saved game)
func attach_node(a: Node3D) -> void:
	slots[a.get_meta("side", "rear")] = a
	if a.has_method("hooked"):
		a.hooked(true)


func is_attached(a: Node) -> bool:
	return slots.values().has(a)


# extra lines for the screen (trailer load, sprayer liters ...)
func attached_info() -> String:
	var out: Array = []
	for k in slots:
		var a = slots[k]
		if a != null and a.has_method("hud_text"):
			var t: String = a.hud_text()
			if t != "":
				out.append(t)
	return "   |   ".join(out)
