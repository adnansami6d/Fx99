extends Node3D
# V25: trees, rocks, cacti, reeds ... of the big map are made in 200 m squares around the camera.
# Only the nearby squares exist; far squares are deleted. A square is built over a few frames (no big hitch).
# Same square = same things every time (the random seed comes from the square number).

const Util = preload("res://scripts/util.gd")
const Biome = preload("res://scripts/biome.gd")
const CHUNK := 200.0
const LOAD_R := 300.0   # build a square when its centre is closer than this
const KEEP_R := 400.0   # delete a square when its centre is farther than this
const GRID := 25        # 25 x 25 sample cells per square (8 m each)

var half := 500.0
var rail: Node   # V26: has near_track(x, z)
var blocks: Array = []   # Rect2 list: nothing is placed inside (old map, future buildings)
var _chunks := {}
var _t := 1.0
var _building := false
var _tree_shape: CylinderShape3D
var _m := {}


func start() -> void:
	_tree_shape = CylinderShape3D.new()
	_tree_shape.radius = 0.5
	_tree_shape.height = 5.0
	_m["trunk"] = Util.cyl(0.35, 4.6, 6)
	_m["crown"] = Util.sphere(2.6, 6, 4)
	_m["ptrunk"] = Util.cyl(0.3, 2.4, 6)
	_m["cone1"] = Util.cone(2.4, 4.2, 6)
	_m["cone2"] = Util.cone(1.7, 3.6, 6)
	_m["bush"] = Util.sphere(0.7, 6, 3)
	_m["rock"] = Util.sphere(1.0, 6, 3)
	_m["cbody"] = Util.cyl(0.32, 3.0, 6)
	_m["carm_l"] = Util.cyl(0.2, 1.2, 5)
	_m["carm_r"] = Util.cyl(0.2, 0.7, 5)
	_m["reed"] = Util.cone(0.15, 1.2, 4)
	_m["puddle"] = Util.cyl(1.0, 0.04, 10)
	_m["trunk_m"] = Util.mat(Color(0.38, 0.25, 0.13))
	_m["cactus_m"] = Util.mat(Color(0.2, 0.45, 0.22))
	_m["puddle_m"] = Util.mat(Color(0.16, 0.27, 0.26), 0.1, 0.2)


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.3 and not _building:
		_t = 0.0
		_update()


func _centre(k: Vector2i) -> Vector2:
	return Vector2((float(k.x) + 0.5) * CHUNK, (float(k.y) + 0.5) * CHUNK)


func _update() -> void:
	var cam := get_viewport().get_camera_3d()
	var cp := Vector2.ZERO
	if cam != null:
		cp = Vector2(cam.global_position.x, cam.global_position.z)
	for k in _chunks.keys():
		if _centre(k).distance_to(cp) > KEEP_R:
			(_chunks[k] as Node).queue_free()
			_chunks.erase(k)
	var ck := Vector2i(floori(cp.x / CHUNK), floori(cp.y / CHUNK))
	var best := Vector2i.ZERO
	var bd := LOAD_R
	var found := false
	var mapr := Rect2(-half, -half, half * 2.0, half * 2.0)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var k := Vector2i(ck.x + dx, ck.y + dz)
			if _chunks.has(k) or not mapr.intersects(Rect2(float(k.x) * CHUNK, float(k.y) * CHUNK, CHUNK, CHUNK)):
				continue
			var d := _centre(k).distance_to(cp)
			if d < bd:
				bd = d
				best = k
				found = true
	if found:
		_build(best)


func _build(k: Vector2i) -> void:
	_building = true
	var node := Node3D.new()
	var cx := (float(k.x) + 0.5) * CHUNK
	var cz := (float(k.y) + 0.5) * CHUNK
	node.position = Vector3(cx, 0.0, cz)
	add_child(node)
	_chunks[k] = node
	var x0 := float(k.x) * CHUNK
	var z0 := float(k.y) * CHUNK
	var all_farm := true
	for c in [Vector2(x0, z0), Vector2(x0 + CHUNK, z0), Vector2(x0, z0 + CHUNK), Vector2(x0 + CHUNK, z0 + CHUNK), Vector2(cx, cz)]:
		if float(Biome.weights(c.x, c.y)[0]) < 0.999:
			all_farm = false
			break
	if all_farm:
		_building = false
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (k.x * 73856093) ^ (k.y * 19349663) ^ 7919
	var cell := CHUNK / float(GRID)
	var ak := cell * cell / 1000.0
	var lim := half - 28.0
	var rt: Array = []
	var rc: Array = []
	var rcol: Array = []
	var pt: Array = []
	var p1: Array = []
	var p2: Array = []
	var pcol: Array = []
	var bx: Array = []
	var bcol: Array = []
	var rk: Array = []
	var rkcol: Array = []
	var cb: Array = []
	var cl: Array = []
	var cr: Array = []
	var rd: Array = []
	var rdcol: Array = []
	var pd: Array = []
	var shapes: Array = []   # [shape, local position]
	for gx in GRID:
		if gx % 5 == 4:
			await get_tree().process_frame
			if not _chunks.has(k):
				_building = false
				return
		for gz in GRID:
			var x := x0 + (float(gx) + rng.randf()) * cell
			var z := z0 + (float(gz) + rng.randf()) * cell
			if absf(x) > lim or absf(z) > lim:
				continue
			var p2d := Vector2(x, z)
			var blocked := false
			for b in blocks:
				if (b as Rect2).has_point(p2d):
					blocked = true
					break
			if rail != null and rail.near_track(x, z):
				continue
			if blocked:
				continue
			var w: Array = Biome.weights(x, z)
			var lx := x - cx
			var lz := z - cz
			var yaw := Basis(Vector3.UP, rng.randf() * TAU)
			var f: float = w[1]
			var r: float = w[2]
			var d: float = w[3]
			var s: float = w[4]
			if f > 0.03:
				if rng.randf() < 8.0 * ak * f:
					_add_tree(rng, lx, lz, rt, rc, rcol, pt, p1, p2, pcol, shapes, 0.08, 0.34, 0.03, 0.22)
				if rng.randf() < 5.0 * ak * f:
					var sc := rng.randf_range(0.7, 1.6)
					bx.append(Transform3D(yaw * Basis.from_scale(Vector3(sc * 1.3, sc * 0.85, sc * 1.3)), Vector3(lx, 0.35 * sc, lz)))
					bcol.append(Color(rng.randf_range(0.08, 0.2), rng.randf_range(0.32, 0.5), rng.randf_range(0.08, 0.16)))
			if r > 0.03:
				if rng.randf() < 3.5 * ak * r:
					var sc := 0.8 + rng.randf() * rng.randf() * 2.6
					rk.append(Transform3D(yaw * Basis.from_scale(Vector3(sc * 1.1, sc * 0.8, sc)), Vector3(lx, 0.45 * sc, lz)))
					var g := rng.randf_range(0.4, 0.58)
					rkcol.append(Color(g, g * 0.97, g * 0.92))
					if sc > 1.5:
						var cs := CylinderShape3D.new()
						cs.radius = 0.95 * sc
						cs.height = 1.6 * sc
						shapes.append([cs, Vector3(lx, 0.8 * sc, lz)])
				if rng.randf() < 6.0 * ak * r:
					var sc2 := rng.randf_range(0.25, 0.6)
					rk.append(Transform3D(yaw * Basis.from_scale(Vector3(sc2 * 1.2, sc2 * 0.8, sc2)), Vector3(lx, 0.2 * sc2, lz)))
					var g2 := rng.randf_range(0.4, 0.6)
					rkcol.append(Color(g2, g2, g2 * 0.95))
				if rng.randf() < 1.0 * ak * r:
					_add_tree(rng, lx, lz, rt, rc, rcol, pt, p1, p2, pcol, shapes, 0.1, 0.3, 0.1, 0.3)
			if d > 0.03:
				if rng.randf() < 1.0 * ak * d:
					var sc3 := rng.randf_range(0.8, 1.5)
					var t := Transform3D(yaw * Basis.from_scale(Vector3.ONE * sc3), Vector3(lx, 0.0, lz))
					cb.append(t * Transform3D(Basis(), Vector3(0, 1.5, 0)))
					cl.append(t * Transform3D(Basis(), Vector3(-0.5, 1.9, 0)))
					cr.append(t * Transform3D(Basis(), Vector3(0.5, 1.3, 0)))
					shapes.append([_tree_shape, Vector3(lx, 2.5, lz)])
				if rng.randf() < 3.0 * ak * d:
					var sc4 := rng.randf_range(0.6, 1.3)
					bx.append(Transform3D(yaw * Basis.from_scale(Vector3(sc4 * 1.2, sc4 * 0.6, sc4 * 1.2)), Vector3(lx, 0.3 * sc4, lz)))
					bcol.append(Color(rng.randf_range(0.45, 0.55), rng.randf_range(0.38, 0.45), rng.randf_range(0.2, 0.26)))
				if rng.randf() < 0.5 * ak * d:
					var sc5 := rng.randf_range(0.5, 1.4)
					rk.append(Transform3D(yaw * Basis.from_scale(Vector3(sc5 * 1.1, sc5 * 0.8, sc5)), Vector3(lx, 0.4 * sc5, lz)))
					rkcol.append(Color(0.7, 0.62, 0.48))
			if s > 0.03:
				if rng.randf() < 2.5 * ak * s:
					_add_tree(rng, lx, lz, rt, rc, rcol, pt, p1, p2, pcol, shapes, 0.2, 0.32, 0.0, 0.0, true)
				if rng.randf() < 5.0 * ak * s:
					for i in 4:
						var sc6 := rng.randf_range(0.8, 1.6)
						rd.append(Transform3D(Basis.from_scale(Vector3.ONE * sc6), Vector3(lx + rng.randf_range(-0.8, 0.8), 0.6 * sc6, lz + rng.randf_range(-0.8, 0.8))))
						rdcol.append(Color(rng.randf_range(0.25, 0.35), rng.randf_range(0.4, 0.5), rng.randf_range(0.15, 0.2)))
				if rng.randf() < 0.9 * ak * s:
					var pr := rng.randf_range(1.5, 4.5)
					pd.append(Transform3D(Basis.from_scale(Vector3(pr, 1.0, pr)), Vector3(lx, 0.03, lz)))
				if rng.randf() < 2.0 * ak * s:
					var sc7 := rng.randf_range(0.7, 1.4)
					bx.append(Transform3D(yaw * Basis.from_scale(Vector3(sc7 * 1.3, sc7 * 0.85, sc7 * 1.3)), Vector3(lx, 0.35 * sc7, lz)))
					bcol.append(Color(rng.randf_range(0.2, 0.3), rng.randf_range(0.3, 0.4), rng.randf_range(0.12, 0.18)))
	await get_tree().process_frame
	if not _chunks.has(k):
		_building = false
		return
	var leaf_m := Util.vcol_mat()
	var trunk_m: Material = _m["trunk_m"]
	_multi(node, "trunk", trunk_m, rt, [])
	_multi(node, "crown", leaf_m, rc, rcol)
	_multi(node, "ptrunk", trunk_m, pt, [])
	_multi(node, "cone1", leaf_m, p1, pcol)
	_multi(node, "cone2", leaf_m, p2, pcol)
	_multi(node, "bush", leaf_m, bx, bcol)
	_multi(node, "rock", leaf_m, rk, rkcol)
	_multi(node, "cbody", _m["cactus_m"], cb, [])
	_multi(node, "carm_l", _m["cactus_m"], cl, [])
	_multi(node, "carm_r", _m["cactus_m"], cr, [])
	_multi(node, "reed", leaf_m, rd, rdcol)
	_multi(node, "puddle", _m["puddle_m"], pd, [])
	await get_tree().process_frame
	if not _chunks.has(k):
		_building = false
		return
	if not shapes.is_empty():
		var body := StaticBody3D.new()
		for sh in shapes:
			var cs := CollisionShape3D.new()
			cs.shape = sh[0]
			cs.position = sh[1]
			body.add_child(cs)
		node.add_child(body)
	_building = false


func _multi(parent: Node, mesh_key: String, mat: Material, xf: Array, col: Array) -> void:
	if xf.is_empty():
		return
	Util.multi(parent, _m[mesh_key], mat, xf, col)


# round tree or pine. swamp = true: always a round, olive tree
func _add_tree(rng: RandomNumberGenerator, lx: float, lz: float, rt: Array, rc: Array, rcol: Array, pt: Array, p1: Array, p2: Array, pcol: Array, shapes: Array, rg0: float, rg1: float, pg0: float, pg1: float, swamp: bool = false) -> void:
	var sc := rng.randf_range(0.8, 1.5)
	var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * sc)
	if swamp or rng.randf() < 0.55:
		if swamp:
			sc *= 0.8
			b = Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * sc)
			rcol.append(Color(rng.randf_range(0.2, 0.3), rng.randf_range(0.3, 0.4), rng.randf_range(0.12, 0.18)))
		else:
			rcol.append(Color(rng.randf_range(0.08, 0.2), rng.randf_range(rg0 + 0.08, rg1 + 0.16), rng.randf_range(0.08, 0.18)))
		rt.append(Transform3D(b, Vector3(lx, 2.3 * sc, lz)))
		rc.append(Transform3D(b, Vector3(lx, 5.6 * sc, lz)))
	else:
		pt.append(Transform3D(b, Vector3(lx, 1.2 * sc, lz)))
		p1.append(Transform3D(b, Vector3(lx, 4.1 * sc, lz)))
		p2.append(Transform3D(b, Vector3(lx, 6.6 * sc, lz)))
		pcol.append(Color(rng.randf_range(0.03, 0.1), rng.randf_range(pg0 + 0.06, pg1 + 0.12), rng.randf_range(0.1, 0.18)))
	shapes.append([_tree_shape, Vector3(lx, 2.5, lz)])
