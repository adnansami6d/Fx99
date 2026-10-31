extends Node3D
# TRAIN: 1 engine + 3 open flatbed carriages. Runs round the railway loop (railway.gd) forever.
# It stops 60 seconds at every station, then goes on to the next one.
#  - Flat open deck (top = DECK_H) with a small step on the side AWAY from the platform.
#  - The player hops on by himself: walk against the carriage while it is stopped (no button).
#    While riding he is carried along (the cars are AnimatableBody3D).
#  - A MOVING train pushes the player (not riding) and the tractor away from its path.
# Numbers to change: CRUISE (m/s), STOP_SEC, LENS (length of each car), DECK_H.

const Util = preload("res://scripts/util.gd")

const CRUISE := 14.0          # m/s (50 km/h)
const ACCEL := 2.0
const DECEL := 2.2
const STOP_SEC := 60.0        # wait at each station
const START_WAIT := 15.0      # wait at the first station when the game starts
const DECK_H := 0.75          # deck surface height (character jumps 0.9 m)
const HALF_W := 1.6
const GAP := 0.8
const LENS := [7.0, 8.0, 8.0, 8.0]   # first = engine (front), the others = carriages
const PUSH_SPEED := 9.0       # m/s
const PUSH_MARGIN := 1.0
const HOP_REACH := 0.9
const MOVING_SPEED := 1.0     # above this the train pushes people / cars away

var rail: Node
var cars: Array = []          # {node, off, len, deck}
var s := 0.0                  # distance of the TRAIN CENTER along the track
var speed := 0.0
var dwell := 0.0
var next_i := 0
var train_len := 0.0
var player: Node3D
var tractor: Node3D
var _stations: Array = []
var _clock_t := 0.0


func setup(r: Node) -> void:
	rail = r
	_stations = r.stations.duplicate()
	_stations.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	if _stations.is_empty():
		return
	train_len = GAP * float(LENS.size() - 1)
	for l in LENS:
		train_len += float(l)
	var used := 0.0
	for i in LENS.size():
		var l: float = LENS[i]
		var body := AnimatableBody3D.new()
		body.sync_to_physics = true
		add_child(body)
		if i == 0:
			_build_engine(body, l)
		else:
			_build_carriage(body, l, i)
		cars.append({"node": body, "off": train_len * 0.5 - used - l * 0.5, "len": l, "deck": i > 0})
		used += l + GAP
	s = float(_stations[0]["dist"])
	next_i = 1 % _stations.size()
	dwell = START_WAIT
	_place()


# ---------------------------------------------------------------- look

func _col(body: AnimatableBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	body.add_child(cs)


func _wheels(body: Node3D, len: float) -> void:
	var dark := Util.mat(Color(0.08, 0.08, 0.09), 0.9)
	for z in [-len * 0.3, len * 0.3]:
		for x in [-1.0, 1.0]:
			var w := Util.mim(Util.cyl(0.4, 0.16, 12), dark)
			w.rotation_degrees.z = 90.0
			w.position = Vector3(x, 0.4, z)
			body.add_child(w)


func _build_engine(body: AnimatableBody3D, l: float) -> void:
	var frame := Util.mat(Color(0.18, 0.18, 0.2), 0.7, 0.3)
	var red := Util.mat(Color(0.75, 0.12, 0.1), 0.5, 0.2)
	var blue := Util.mat(Color(0.12, 0.3, 0.6), 0.5, 0.2)
	var glass := Util.mat(Color(0.35, 0.55, 0.7), 0.2)
	var lamp := Util.mat(Color(1.0, 0.95, 0.6), 0.3)
	Util.part(body, Vector3(3.0, 0.5, l), Vector3(0, 0.6, 0), frame)
	Util.part(body, Vector3(3.0, 2.0, 2.6), Vector3(0, 1.85, -2.1), red)       # cab (back)
	Util.part(body, Vector3(2.6, 1.3, 4.0), Vector3(0, 1.5, 1.3), blue)        # hood (front)
	Util.part(body, Vector3(3.04, 0.7, 1.2), Vector3(0, 2.1, -2.1), glass)     # cab windows
	Util.part(body, Vector3(3.1, 0.12, 2.8), Vector3(0, 2.9, -2.1), frame)     # roof
	Util.part(body, Vector3(0.6, 0.6, 0.6), Vector3(0, 2.4, 2.2), frame)       # chimney
	Util.part(body, Vector3(1.2, 0.3, 0.1), Vector3(0, 1.4, l * 0.5 + 0.02), lamp)   # headlight
	_wheels(body, l)
	_col(body, Vector3(3.0, 2.6, l), Vector3(0, 1.6, 0))


func _build_carriage(body: AnimatableBody3D, l: float, idx: int) -> void:
	var frame := Util.mat(Color(0.18, 0.18, 0.2), 0.7, 0.3)
	var decks := [Color(0.55, 0.38, 0.2), Color(0.5, 0.42, 0.25), Color(0.6, 0.35, 0.18)]
	var wood := Util.mat(decks[(idx - 1) % 3], 0.9)
	var trim := Util.mat(Color(0.8, 0.7, 0.15), 0.6)
	var steel := Util.mat(Color(0.7, 0.7, 0.72), 0.4, 0.6)
	Util.part(body, Vector3(2.6, 0.3, l), Vector3(0, 0.5, 0), frame)                       # chassis
	Util.part(body, Vector3(HALF_W * 2.0, 0.14, l), Vector3(0, DECK_H - 0.07, 0), wood)    # open flat deck
	for sx in [-1.0, 1.0]:
		Util.part(body, Vector3(0.1, 0.1, l), Vector3(sx * (HALF_W - 0.05), DECK_H + 0.03, 0), trim)   # low edge strip
	# steps + hand rail on the +X side (the platform is on the -X side)
	Util.part(body, Vector3(0.6, 0.35, 1.2), Vector3(HALF_W + 0.3, 0.175, 0), frame)
	for z in [-0.6, 0.6]:
		Util.part(body, Vector3(0.06, 0.95, 0.06), Vector3(HALF_W - 0.1, DECK_H + 0.47, z), steel)
	Util.part(body, Vector3(0.06, 0.06, 1.26), Vector3(HALF_W - 0.1, DECK_H + 0.92, 0), steel)
	_wheels(body, l)
	_col(body, Vector3(HALF_W * 2.0, 0.5, l), Vector3(0, DECK_H - 0.25, 0))     # deck (top = DECK_H)
	_col(body, Vector3(0.6, 0.35, 1.2), Vector3(HALF_W + 0.3, 0.175, 0))        # step


# ---------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if rail == null or _stations.is_empty():
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if tractor == null:
		tractor = get_tree().get_first_node_in_group("tractor")
	_drive(delta)
	_place()
	_clock_t += delta
	if _clock_t >= 0.25:
		_clock_t = 0.0
		_update_clocks()
	if speed > MOVING_SPEED:
		_push(delta)
	elif speed < 2.0:
		_hop()


func _drive(delta: float) -> void:
	if dwell > 0.0:
		dwell -= delta
		speed = 0.0
		return
	var len: float = rail.length
	var tgt := float(_stations[next_i]["dist"])
	var rem := fposmod(tgt - s, len)
	var step := speed * delta
	if step >= rem - 0.1 or rem < 0.4:   # V26: always stop (the old 'speed < 4' check let it drive past)
		s = tgt
		speed = 0.0
		dwell = STOP_SEC
		next_i = (next_i + 1) % _stations.size()
		return
	var want := minf(CRUISE, sqrt(2.0 * DECEL * maxf(rem - 0.2, 0.0)) + 0.6)
	speed = move_toward(speed, want, (ACCEL if speed < want else DECEL) * delta)
	s = fposmod(s + speed * delta, len)


func _place() -> void:
	for c in cars:
		var d: float = s + float(c["off"])
		var h: float = float(c["len"]) * 0.35
		var f: Vector3 = rail.point_at(d + h)
		var r: Vector3 = rail.point_at(d - h)
		var yaw := atan2(f.x - r.x, f.z - r.z)
		(c["node"] as Node3D).transform = Transform3D(Basis(Vector3.UP, yaw), (f + r) * 0.5)


func _fmt(sec: float) -> String:
	var t := maxi(0, int(ceil(sec)))
	return "%d:%02d" % [t / 60, t % 60]


# RED CLOCKS: station where the train waits = "LEAVES IN m:ss"; the others = about when the train arrives
func _update_clocks() -> void:
	var n := _stations.size()
	var cur := (next_i + n - 1) % n          # station the train waits at (when dwell > 0)
	var len: float = rail.length
	var t := dwell if dwell > 0.0 else 0.0
	var pos_s := s
	var arr := {}
	var i := next_i
	for k in n:
		var dd := float(_stations[i]["dist"])
		t += fposmod(dd - pos_s, len) / CRUISE + 10.0
		arr[i] = t
		pos_s = dd
		t += STOP_SEC
		i = (i + 1) % n
	for j in n:
		var txt := ""
		if dwell > 0.0 and j == cur:
			txt = "LEAVES\n" + _fmt(dwell)
		elif speed > 0.0 and j == next_i and float(arr[j]) < 12.0:
			txt = "ARRIVING"
		else:
			txt = "TRAIN IN\n" + _fmt(float(arr[j]))
		for lab in _stations[j].get("clock", []):
			(lab as Label3D).text = txt


# name of the station the train is at (or going to) - for HUD use
func status_text() -> String:
	var st: Dictionary = _stations[next_i] if dwell <= 0.0 else _stations[(next_i + _stations.size() - 1) % _stations.size()]
	if dwell > 0.0:
		return "TRAIN at %s  (leaves in %d s)" % [String(st["name"]), int(ceil(dwell))]
	return "TRAIN to %s" % String(st["name"])


# ---------------------------------------------------------------- people and cars near the train

func _targets() -> Array:
	var out: Array = []
	if player != null and not bool(player.get("seated")):
		out.append(player)
	if tractor != null:
		out.append(tractor)
	return out


# a MOVING train pushes everything that stands on / near its path to the side (front: forwards)
func _push(delta: float) -> void:
	for t in _targets():
		for i in cars.size():
			var c: Dictionary = cars[i]
			var node: Node3D = c["node"]
			var inv := node.global_transform.affine_inverse()
			var l: Vector3 = inv * t.global_position
			var hl: float = float(c["len"]) * 0.5
			if absf(l.x) > HALF_W + PUSH_MARGIN or absf(l.z) > hl + PUSH_MARGIN or l.y > 4.0:
				continue
			if t == player and bool(c["deck"]) and absf(l.x) < HALF_W and l.y > DECK_H - 0.3:
				continue   # riding on the deck
			var local_dir := Vector3(signf(l.x) if l.x != 0.0 else 1.0, 0, 0)
			var ex: float = HALF_W + PUSH_MARGIN - absf(l.x)
			var ez: float = hl + PUSH_MARGIN - absf(l.z)
			if i == 0 and l.z > 0.0 and ez < ex:
				local_dir = Vector3(0, 0, 1)             # in front of the engine: pushed ahead
			elif i == cars.size() - 1 and l.z < 0.0 and ez < ex:
				local_dir = Vector3(0, 0, -1)            # behind the last car
			var wd: Vector3 = node.global_transform.basis * local_dir
			wd.y = 0.0
			t.global_position += wd.normalized() * PUSH_SPEED * delta
			if t == tractor and "speed" in t:
				t.speed = move_toward(float(t.speed), 0.0, 30.0 * delta)
			break


# a stopped / slow train: the walking player hops onto the deck alone (no button)
func _hop() -> void:
	if player == null or bool(player.get("seated")) or not player.is_on_floor():
		return
	var hv := Vector3(player.velocity.x, 0, player.velocity.z)
	if hv.length() < 0.5:
		return
	for c in cars:
		if not bool(c["deck"]):
			continue
		var node: Node3D = c["node"]
		var l: Vector3 = node.global_transform.affine_inverse() * player.global_position
		if l.y > DECK_H - 0.25 or absf(l.z) > float(c["len"]) * 0.5 - 0.2:
			continue
		var ax := absf(l.x)
		if ax < HALF_W + 0.2 or ax > HALF_W + HOP_REACH + 0.6:
			continue
		var toward: Vector3 = node.global_transform.basis * Vector3(-signf(l.x), 0, 0)
		if hv.normalized().dot(toward) > 0.3:
			player.velocity.y = float(player.JUMP_SPEED)
			return
