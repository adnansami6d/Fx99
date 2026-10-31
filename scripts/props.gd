extends RefCounted
# Makes map objects by type name. Order: your scene res://props/<type>.tscn first, then built-in ones.
# New object type = drop a scene in res://props/ . No code change needed.
# Built-in: tree, house, house2, house3, barn, silo, shed, well, greenhouse.
# The front (door side) of a building looks to +Z when "rot" is 0.

const Util = preload("res://scripts/util.gd")

# footprint (x, z in meters) - the minimap and the "keep trees away" logic use this
const FOOT := {
	"house": Vector2(8, 6), "house2": Vector2(8, 6), "house3": Vector2(7, 6),
	"barn": Vector2(10, 8), "silo": Vector2(5, 5), "shed": Vector2(5, 4),
	"well": Vector2(2.5, 2.5), "greenhouse": Vector2(12, 6),
	"palace": Vector2(36, 20), "shop": Vector2(6, 5), "biogas": Vector2(14, 14),
	"ftank": Vector2(10, 10), "storage": Vector2(30, 18),
	"tower": Vector2(8, 8), "airport": Vector2(66, 32),
	"bunker": Vector2(30, 22), "powerstation": Vector2(58, 58), "windmill": Vector2(6, 6), "solar": Vector2(36, 27), "fuelstation": Vector2(44, 34), "seedshop": Vector2(6, 5),
}

static var trunk_mesh: Mesh
static var leaf_mesh: Mesh
static var trunk_mat: Material
static var leaf_mat: Material


static func make(type: String) -> Node3D:
	var path := "res://props/%s.tscn" % type
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is PackedScene:
			var n = res.instantiate()
			if n is Node3D:
				return n
	match type:
		"tree":
			return _tree()
		"house":
			return _building(Vector3(8, 3, 6), Color(0.93, 0.88, 0.72), Color(0.5, 0.22, 0.14), 2.2, "house")
		"house2":
			return _building(Vector3(8, 3, 6), Color(0.72, 0.82, 0.9), Color(0.25, 0.27, 0.32), 2.2, "house")
		"house3":
			return _building(Vector3(7, 3.2, 6), Color(0.9, 0.78, 0.55), Color(0.35, 0.25, 0.2), 2.4, "house")
		"barn":
			return _building(Vector3(10, 5, 8), Color(0.7, 0.15, 0.12), Color(0.3, 0.2, 0.14), 2.8, "barn")
		"shed":
			return _building(Vector3(5, 2.6, 4), Color(0.55, 0.42, 0.28), Color(0.3, 0.32, 0.36), 1.2, "shed")
		"silo":
			return _silo()
		"well":
			return _well()
		"greenhouse":
			return _greenhouse()
		"palace":
			return _palace()
		"shop":
			return _shop()
		"seedshop":
			return _seedshop()
		"biogas":
			return _biogas()
		"ftank":
			return _ftank()
		"storage":
			return _storage()
		"tower":
			return _tower()
		"airport":
			return _airport()
		"bunker":
			return _bunker()
		"powerstation":
			return _powerstation()
		"windmill":
			return _windmill()
		"solar":
			return _solar()
		"fuelstation":
			return _fuelstation()
	push_warning("Unknown object type: " + type)
	return null


static func _tree() -> Node3D:
	if trunk_mesh == null:
		trunk_mesh = Util.cyl(0.4, 5.0, 8)
		leaf_mesh = Util.sphere(3.0, 12, 6)
		trunk_mat = Util.mat(Color(0.4, 0.26, 0.13))
		leaf_mat = Util.mat(Color(0.14, 0.52, 0.2))
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.4
	sh.height = 5.0
	cs.shape = sh
	cs.position = Vector3(0, 2.5, 0)
	body.add_child(cs)
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.material_override = trunk_mat
	trunk.position = Vector3(0, 2.5, 0)
	body.add_child(trunk)
	var leaves := MeshInstance3D.new()
	leaves.mesh = leaf_mesh
	leaves.material_override = leaf_mat
	leaves.position = Vector3(0, 6.5, 0)
	body.add_child(leaves)
	return body


static func _box_collider(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	body.add_child(cs)


# kind: "house" (door + windows), "barn" (big doors), "shed" (door only)
static func _building(size: Vector3, wall: Color, roof_col: Color, roof_h: float, kind: String) -> Node3D:
	var body := StaticBody3D.new()
	var walls := Util.mi(Util.box(size), wall)
	walls.position = Vector3(0, size.y / 2.0, 0)
	body.add_child(walls)
	_box_collider(body, size, Vector3(0, size.y / 2.0, 0))
	var prism := PrismMesh.new()
	prism.size = Vector3(size.x + 0.8, roof_h, size.z + 0.8)
	var roof := Util.mi(prism, roof_col)
	roof.position = Vector3(0, size.y + roof_h / 2.0, 0)
	body.add_child(roof)

	var trim := Util.mat(Color(0.95, 0.95, 0.92))
	var door_m := Util.mat(Color(0.32, 0.2, 0.1))
	var glass := Util.mat(Color(0.55, 0.75, 0.9), 0.2, 0.2)
	var fz := size.z / 2.0 + 0.02
	match kind:
		"house":
			Util.part(body, Vector3(1.2, 2.0, 0.08), Vector3(0, 1.0, fz), door_m)
			for sx in [-2.4, 2.4]:
				Util.part(body, Vector3(1.3, 1.2, 0.06), Vector3(sx, 1.7, fz), trim)
				Util.part(body, Vector3(1.1, 1.0, 0.08), Vector3(sx, 1.7, fz + 0.01), glass)
			Util.part(body, Vector3(0.9, 3.4, 0.9), Vector3(size.x * 0.28, size.y + roof_h * 0.65, -size.z * 0.15), Util.mat(Color(0.5, 0.3, 0.25)))   # chimney
		"barn":
			Util.part(body, Vector3(4.2, 3.6, 0.08), Vector3(0, 1.8, fz), door_m)
			Util.part(body, Vector3(0.18, 3.6, 0.1), Vector3(0, 1.8, fz + 0.02), trim)
			Util.part(body, Vector3(4.4, 0.18, 0.1), Vector3(0, 3.7, fz + 0.02), trim)
			Util.part(body, Vector3(4.2, 0.14, 0.1), Vector3(0, 1.8, fz + 0.03), trim, Vector3(0, 0, 40))
			Util.part(body, Vector3(4.2, 0.14, 0.1), Vector3(0, 1.8, fz + 0.03), trim, Vector3(0, 0, -40))
		"shed":
			Util.part(body, Vector3(1.1, 1.9, 0.08), Vector3(0, 0.95, fz), door_m)
	return body


static func _silo() -> Node3D:
	var body := StaticBody3D.new()
	var metal := Util.mat(Color(0.75, 0.77, 0.8), 0.35, 0.7)
	var tube := Util.mim(Util.cyl(2.2, 9.0, 20), metal)
	tube.position = Vector3(0, 4.5, 0)
	body.add_child(tube)
	for i in 3:
		var ring := Util.mim(Util.cyl(2.25, 0.18, 20), Util.mat(Color(0.5, 0.52, 0.55), 0.4, 0.6))
		ring.position = Vector3(0, 2.0 + i * 3.0, 0)
		body.add_child(ring)
	var dome := Util.mim(Util.sphere(2.2, 20, 8), Util.mat(Color(0.6, 0.15, 0.12), 0.5, 0.3))
	dome.scale = Vector3(1, 0.55, 1)
	dome.position = Vector3(0, 9.0, 0)
	body.add_child(dome)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 2.2
	sh.height = 9.0
	cs.shape = sh
	cs.position = Vector3(0, 4.5, 0)
	body.add_child(cs)
	return body


static func _well() -> Node3D:
	var body := StaticBody3D.new()
	var stone := Util.mim(Util.cyl(0.9, 0.9, 12), Util.mat(Color(0.55, 0.55, 0.55)))
	stone.position = Vector3(0, 0.45, 0)
	body.add_child(stone)
	var water := Util.mim(Util.cyl(0.72, 0.05, 12), Util.mat(Color(0.1, 0.25, 0.4)))
	water.position = Vector3(0, 0.86, 0)
	body.add_child(water)
	var wood := Util.mat(Color(0.4, 0.26, 0.13))
	for sx in [-0.8, 0.8]:
		Util.part(body, Vector3(0.1, 1.8, 0.1), Vector3(sx, 1.8, 0), wood)
	var roof := PrismMesh.new()
	roof.size = Vector3(2.2, 0.8, 1.6)
	var r := Util.mim(roof, Util.mat(Color(0.5, 0.22, 0.14)))
	r.position = Vector3(0, 2.9, 0)
	r.rotation_degrees.y = 90.0
	body.add_child(r)
	_box_collider(body, Vector3(1.8, 1.0, 1.8), Vector3(0, 0.5, 0))
	return body


static func _greenhouse() -> Node3D:
	var body := StaticBody3D.new()
	var size := Vector3(12, 3.0, 6)
	var frame := Util.mat(Color(0.9, 0.9, 0.9), 0.4, 0.4)
	var glass := Util.mat(Color(0.7, 0.9, 0.85, 0.35), 0.1)
	var g := Util.mim(Util.box(size), glass)
	g.position = Vector3(0, size.y / 2.0, 0)
	body.add_child(g)
	var prism := PrismMesh.new()
	prism.size = Vector3(size.x, 1.6, size.z)
	var roof := Util.mim(prism, glass)
	roof.position = Vector3(0, size.y + 0.8, 0)
	body.add_child(roof)
	for i in 5:
		var x := -size.x / 2.0 + i * size.x / 4.0
		for sz in [-size.z / 2.0, size.z / 2.0]:
			Util.part(body, Vector3(0.12, size.y, 0.12), Vector3(x, size.y / 2.0, sz), frame)
	Util.part(body, Vector3(size.x, 0.12, 0.12), Vector3(0, size.y, size.z / 2.0), frame)
	Util.part(body, Vector3(size.x, 0.12, 0.12), Vector3(0, size.y, -size.z / 2.0), frame)
	for i in 4:   # green plants inside
		Util.part(body, Vector3(size.x - 1.5, 0.5, 0.8), Vector3(0, 0.3, -2.0 + i * 1.33), Util.mat(Color(0.2, 0.55, 0.2)))
	_box_collider(body, size, Vector3(0, size.y / 2.0, 0))
	return body


# ---------------------------------------------------------------- big buildings (door / front looks to +Z)

static func _palace() -> Node3D:
	var body := StaticBody3D.new()
	var stone := Util.mat(Color(0.93, 0.89, 0.8), 0.8)
	var gold := Util.mat(Color(0.85, 0.68, 0.2), 0.35, 0.6)
	var blue := Util.mat(Color(0.2, 0.3, 0.6), 0.6)
	var dark := Util.mat(Color(0.25, 0.15, 0.1), 0.8)
	Util.part(body, Vector3(24, 10, 14), Vector3(0, 5, 0), stone)
	_box_collider(body, Vector3(24, 10, 14), Vector3(0, 5, 0))
	for sx in [-1.0, 1.0]:
		Util.part(body, Vector3(9, 7, 12), Vector3(sx * 16.5, 3.5, 0), stone)   # wings
		_box_collider(body, Vector3(9, 7, 12), Vector3(sx * 16.5, 3.5, 0))
		var tw := Util.mim(Util.cyl(2.4, 16.0, 10), stone)                      # corner towers
		tw.position = Vector3(sx * 13.0, 8.0, 7.5)
		body.add_child(tw)
		var cap := Util.mim(Util.cone(3.2, 5.0, 10), blue)
		cap.position = Vector3(sx * 13.0, 18.5, 7.5)
		body.add_child(cap)
		_box_collider(body, Vector3(5, 16, 5), Vector3(sx * 13.0, 8.0, 7.5))
	var dome := Util.mim(Util.sphere(5.5, 12, 6), gold)
	dome.scale = Vector3(1, 0.8, 1)
	dome.position = Vector3(0, 12.5, 0)
	body.add_child(dome)
	var spire := Util.mim(Util.cone(0.5, 4.0, 6), gold)
	spire.position = Vector3(0, 19.0, 0)
	body.add_child(spire)
	Util.part(body, Vector3(5, 6, 0.3), Vector3(0, 3, 7.1), dark)                 # gate
	Util.part(body, Vector3(12, 0.6, 3), Vector3(0, 0.3, 8.5), stone)             # steps
	for i in 4:
		Util.part(body, Vector3(0.9, 8, 0.9), Vector3(-4.5 + i * 3.0, 4, 7.6), stone)   # columns
	Util.part(body, Vector3(14, 0.6, 1.4), Vector3(0, 8.3, 7.6), gold)
	return body


static func _shop() -> Node3D:
	var body := StaticBody3D.new()
	Util.part(body, Vector3(6, 3, 5), Vector3(0, 1.5, 0), Util.mat(Color(0.92, 0.85, 0.65)))
	_box_collider(body, Vector3(6, 3, 5), Vector3(0, 1.5, 0))
	Util.part(body, Vector3(6.6, 0.25, 5.6), Vector3(0, 3.1, 0), Util.mat(Color(0.75, 0.2, 0.18)))
	Util.part(body, Vector3(5.4, 0.15, 1.8), Vector3(0, 2.7, 3.3), Util.mat(Color(0.95, 0.9, 0.3)))   # awning
	Util.part(body, Vector3(1.0, 2.0, 0.1), Vector3(-1.6, 1.0, 2.52), Util.mat(Color(0.32, 0.2, 0.1)))
	Util.part(body, Vector3(2.4, 1.0, 0.1), Vector3(1.1, 1.6, 2.52), Util.mat(Color(0.55, 0.75, 0.9), 0.2, 0.2))
	Util.part(body, Vector3(3.0, 0.7, 0.9), Vector3(1.1, 0.45, 3.2), Util.mat(Color(0.5, 0.34, 0.18)))   # counter
	return body


# V26: seed shop = shop with a green roof, green awning and seed sacks (buy seed here, like every shop)
static func _seedshop() -> Node3D:
	var body := _shop()
	Util.part(body, Vector3(6.6, 0.25, 5.6), Vector3(0, 3.12, 0), Util.mat(Color(0.2, 0.6, 0.25)))
	Util.part(body, Vector3(5.4, 0.15, 1.8), Vector3(0, 2.72, 3.3), Util.mat(Color(0.35, 0.8, 0.3)))
	for i in 3:
		Util.part(body, Vector3(0.8, 0.5, 0.5), Vector3(-1.2 + 0.9 * float(i), 0.25, 4.1), Util.mat(Color(0.8, 0.7, 0.45)))
	Util.part(body, Vector3(4.0, 0.9, 0.1), Vector3(0, 3.9, 2.6), Util.mat(Color(0.15, 0.5, 0.2)))
	return body


static func _biogas() -> Node3D:
	var body := StaticBody3D.new()
	var green := Util.mat(Color(0.3, 0.55, 0.3), 0.6)
	var tank := Util.mim(Util.cyl(5.5, 4.0, 18), Util.mat(Color(0.7, 0.7, 0.66), 0.8))
	tank.position = Vector3(0, 2.0, 0)
	body.add_child(tank)
	var dome := Util.mim(Util.sphere(5.5, 18, 6), green)
	dome.scale = Vector3(1, 0.55, 1)
	dome.position = Vector3(0, 4.0, 0)
	body.add_child(dome)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 5.5
	sh.height = 6.0
	cs.shape = sh
	cs.position = Vector3(0, 3.0, 0)
	body.add_child(cs)
	Util.part(body, Vector3(4, 2.6, 3), Vector3(0, 1.3, 9.5), Util.mat(Color(0.6, 0.6, 0.62)))   # control hut
	_box_collider(body, Vector3(4, 2.6, 3), Vector3(0, 1.3, 9.5))
	Util.part(body, Vector3(0.35, 6, 0.35), Vector3(4.2, 3, -4.2), Util.mat(Color(0.3, 0.3, 0.32)), Vector3.ZERO)   # pipe
	return body


static func _ftank() -> Node3D:
	var body := StaticBody3D.new()
	var steel := Util.mat(Color(0.45, 0.47, 0.5), 0.5, 0.6)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Util.part(body, Vector3(0.45, 9.0, 0.45), Vector3(sx * 3.0, 4.5, sz * 3.0), steel)
	var tank := Util.mim(Util.cyl(4.5, 5.0, 16), Util.mat(Color(0.2, 0.55, 0.3), 0.5, 0.3))
	tank.position = Vector3(0, 11.5, 0)
	body.add_child(tank)
	var cap := Util.mim(Util.sphere(4.5, 16, 6), Util.mat(Color(0.2, 0.55, 0.3), 0.5, 0.3))
	cap.scale = Vector3(1, 0.4, 1)
	cap.position = Vector3(0, 14.0, 0)
	body.add_child(cap)
	Util.part(body, Vector3(0.3, 9.0, 0.3), Vector3(0, 4.5, 4.4), steel)          # fill pipe
	Util.part(body, Vector3(2.0, 2.2, 1.6), Vector3(0, 1.1, 4.8), Util.mat(Color(0.85, 0.7, 0.1)))   # pump booth
	_box_collider(body, Vector3(7, 9, 7), Vector3(0, 4.5, 0))
	_box_collider(body, Vector3(2.0, 2.2, 1.6), Vector3(0, 1.1, 4.8))
	return body


# open front (+Z): trailers drive up to the mouth
static func _storage() -> Node3D:
	var body := StaticBody3D.new()
	var wall := Util.mat(Color(0.62, 0.55, 0.45), 0.9)
	Util.part(body, Vector3(30, 8, 0.6), Vector3(0, 4, -8.7), wall)
	_box_collider(body, Vector3(30, 8, 0.6), Vector3(0, 4, -8.7))
	for sx in [-1.0, 1.0]:
		Util.part(body, Vector3(0.6, 8, 18), Vector3(sx * 14.7, 4, 0), wall)
		_box_collider(body, Vector3(0.6, 8, 18), Vector3(sx * 14.7, 4, 0))
	var prism := PrismMesh.new()
	prism.size = Vector3(31, 4.5, 19)
	var roof := Util.mi(prism, Color(0.35, 0.3, 0.28))
	roof.position = Vector3(0, 10.25, 0)
	body.add_child(roof)
	Util.part(body, Vector3(29, 0.1, 17), Vector3(0, 0.06, 0), Util.mat(Color(0.5, 0.45, 0.4)))   # floor
	Util.part(body, Vector3(8, 3.0, 8), Vector3(-6, 1.5, -4), Util.mat(Color(0.9, 0.8, 0.35)))     # rice heap
	Util.part(body, Vector3(8, 3.0, 8), Vector3(6, 1.5, -4), Util.mat(Color(0.85, 0.62, 0.3)))     # wheat heap
	return body


# ---------------------------------------------------------------- mobile tower (30 m lattice mast)

static func _tower() -> Node3D:
	var body := StaticBody3D.new()
	var steel := Util.mat(Color(0.78, 0.8, 0.82), 0.5, 0.6)
	var red := Util.mat(Color(0.85, 0.15, 0.12), 0.6)
	var H := 30.0
	var lean := rad_to_deg(atan(1.2 / H))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Util.part(body, Vector3(0.18, H + 0.05, 0.18), Vector3(sx * 1.0, H / 2.0, sz * 1.0), steel, Vector3(-sz * lean, 0, sx * lean))
	for i in 6:
		var h := 2.5 + i * 5.0
		var s := 1.6 - 1.2 * h / H
		var m := red if i % 2 == 0 else steel
		for sg in [-1.0, 1.0]:
			Util.part(body, Vector3(s * 2.0, 0.12, 0.12), Vector3(0, h, sg * s), m)
			Util.part(body, Vector3(0.12, 0.12, s * 2.0), Vector3(sg * s, h, 0), m)
	for i in 3:   # panel antennas
		var a := i * TAU / 3.0
		Util.part(body, Vector3(0.5, 1.7, 0.2), Vector3(sin(a) * 0.95, 28.0, cos(a) * 0.95), Util.mat(Color(0.92, 0.92, 0.9)), Vector3(0, rad_to_deg(a), 0))
	Util.part(body, Vector3(0.1, 2.5, 0.1), Vector3(0, 31.0, 0), steel)
	var beacon := Util.mim(Util.sphere(0.4, 8, 4), Util.glow(Color(1.0, 0.1, 0.05), 2.5))
	beacon.position = Vector3(0, 32.4, 0)
	body.add_child(beacon)
	Util.part(body, Vector3(3.0, 2.4, 2.4), Vector3(3.2, 1.2, 0), Util.mat(Color(0.7, 0.72, 0.74)))   # equipment hut
	Util.part(body, Vector3(0.1, 2.0, 0.1), Vector3(2.2, 3.4, 1.0), steel)
	_box_collider(body, Vector3(3.4, H, 3.4), Vector3(0, H / 2.0, 0))
	_box_collider(body, Vector3(3.0, 2.4, 2.4), Vector3(3.2, 1.2, 0))
	return body


# ---------------------------------------------------------------- airport (66 x 32 m, runway along x)

static func _airport() -> Node3D:
	var body := StaticBody3D.new()
	var asphalt := Util.mat(Color(0.17, 0.17, 0.19), 0.95)
	var apron := Util.mat(Color(0.32, 0.32, 0.34), 0.95)
	var white := Util.mat(Color(0.95, 0.95, 0.92), 0.8)
	var yellow := Util.mat(Color(0.95, 0.8, 0.15), 0.8)
	var wall := Util.mat(Color(0.9, 0.9, 0.86), 0.8)
	var glass := Util.mat(Color(0.45, 0.7, 0.85), 0.15, 0.2)
	var roofm := Util.mat(Color(0.2, 0.3, 0.55), 0.7)
	Util.part(body, Vector3(66.0, 0.06, 32.0), Vector3(0, 0.03, 0), Util.mat(Color(0.5, 0.62, 0.38), 1.0))   # airfield grass
	Util.part(body, Vector3(64.0, 0.08, 9.0), Vector3(0, 0.07, -10.0), asphalt)        # runway
	Util.part(body, Vector3(40.0, 0.08, 12.0), Vector3(-3.0, 0.065, 0.0), apron)       # apron
	for i in 10:
		Util.part(body, Vector3(3.0, 0.02, 0.35), Vector3(-27.0 + i * 6.0, 0.115, -10.0), white)   # centre line
	for sg in [-1.0, 1.0]:
		Util.part(body, Vector3(62.0, 0.02, 0.2), Vector3(0, 0.115, -10.0 + sg * 4.1), white)       # edge lines
		for k in 5:
			Util.part(body, Vector3(2.0, 0.02, 0.5), Vector3(sg * 29.0, 0.115, -10.0 + (k - 2) * 1.5), white)   # thresholds
	# helipad
	var ring := Util.mim(Util.cyl(4.6, 0.04, 28), yellow)
	ring.position = Vector3(-14.0, 0.12, 0.0)
	body.add_child(ring)
	var pad := Util.mim(Util.cyl(4.2, 0.05, 28), Util.mat(Color(0.2, 0.2, 0.24), 0.95))
	pad.position = Vector3(-14.0, 0.125, 0.0)
	body.add_child(pad)
	for sx in [-1.0, 1.0]:
		Util.part(body, Vector3(0.6, 0.02, 3.4), Vector3(-14.0 + sx * 1.1, 0.155, 0.0), white)
	Util.part(body, Vector3(2.2, 0.02, 0.6), Vector3(-14.0, 0.155, 0.0), white)
	# terminal (front / entrance looks to +Z)
	Util.part(body, Vector3(20.0, 5.0, 6.0), Vector3(-6.0, 2.5, 12.0), wall)
	Util.part(body, Vector3(21.0, 0.4, 7.0), Vector3(-6.0, 5.2, 12.0), roofm)
	for sz in [-1.0, 1.0]:
		Util.part(body, Vector3(18.0, 2.0, 0.1), Vector3(-6.0, 2.0, 12.0 + sz * 3.03), glass)
	Util.part(body, Vector3(6.0, 0.2, 2.4), Vector3(-6.0, 3.6, 15.9), yellow)   # entrance canopy
	_box_collider(body, Vector3(20.0, 5.0, 6.0), Vector3(-6.0, 2.5, 12.0))
	# control tower
	var shaft := Util.mim(Util.cyl(1.5, 10.0, 12), wall)
	shaft.position = Vector3(10.0, 5.0, 12.5)
	body.add_child(shaft)
	var cab := Util.mim(Util.cyl(2.6, 2.2, 12), glass)
	cab.position = Vector3(10.0, 11.1, 12.5)
	body.add_child(cab)
	var cap := Util.mim(Util.cyl(3.0, 0.4, 12), roofm)
	cap.position = Vector3(10.0, 12.4, 12.5)
	body.add_child(cap)
	Util.part(body, Vector3(0.1, 3.0, 0.1), Vector3(10.0, 14.1, 12.5), Util.mat(Color(0.3, 0.3, 0.32)))
	var lamp := Util.mim(Util.sphere(0.3, 8, 4), Util.glow(Color(1.0, 0.1, 0.05), 2.5))
	lamp.position = Vector3(10.0, 15.7, 12.5)
	body.add_child(lamp)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 1.6
	sh.height = 12.0
	cs.shape = sh
	cs.position = Vector3(10.0, 6.0, 12.5)
	body.add_child(cs)
	# hangar (big door looks to -Z, towards the apron)
	Util.part(body, Vector3(12.0, 5.0, 8.0), Vector3(24.0, 2.5, 11.0), Util.mat(Color(0.7, 0.72, 0.75), 0.6, 0.3))
	var prism := PrismMesh.new()
	prism.size = Vector3(12.6, 2.0, 8.6)
	var hroof := Util.mim(prism, Util.mat(Color(0.45, 0.47, 0.5), 0.6, 0.3))
	hroof.position = Vector3(24.0, 6.0, 11.0)
	body.add_child(hroof)
	Util.part(body, Vector3(8.0, 4.0, 0.1), Vector3(24.0, 2.0, 6.95), Util.mat(Color(0.25, 0.27, 0.3)))
	Util.part(body, Vector3(16.0, 0.08, 6.0), Vector3(14.0, 0.065, 4.0), apron)   # taxi strip to the hangar
	_box_collider(body, Vector3(12.0, 5.0, 8.0), Vector3(24.0, 2.5, 11.0))
	# small parked plane (nose to +X)
	var fus := Util.mim(Util.cyl(0.75, 8.0, 12), Util.mat(Color(0.95, 0.95, 0.95), 0.4, 0.2))
	fus.position = Vector3(5.0, 1.3, 0.5)
	fus.rotation_degrees = Vector3(0, 0, 90)
	body.add_child(fus)
	var nose := Util.mim(Util.cone(0.75, 1.6, 12), Util.mat(Color(0.8, 0.15, 0.12), 0.5))
	nose.position = Vector3(9.8, 1.3, 0.5)
	nose.rotation_degrees = Vector3(0, 0, -90)
	body.add_child(nose)
	Util.part(body, Vector3(1.8, 0.14, 10.5), Vector3(5.6, 1.9, 0.5), Util.mat(Color(0.8, 0.15, 0.12), 0.5))   # wings
	Util.part(body, Vector3(1.2, 2.0, 0.12), Vector3(1.4, 2.4, 0.5), Util.mat(Color(0.8, 0.15, 0.12), 0.5))   # tail fin
	Util.part(body, Vector3(1.0, 0.12, 3.2), Vector3(1.4, 1.7, 0.5), Util.mat(Color(0.95, 0.95, 0.95), 0.5))  # tail wing
	_box_collider(body, Vector3(9.0, 1.8, 1.6), Vector3(5.0, 1.3, 0.5))
	_box_collider(body, Vector3(1.8, 0.4, 10.5), Vector3(5.6, 1.9, 0.5))
	# windsock
	Util.part(body, Vector3(0.12, 5.0, 0.12), Vector3(30.0, 2.5, -2.0), Util.mat(Color(0.8, 0.8, 0.82)))
	var sock := Util.mim(Util.cone(0.45, 2.4, 10), Util.mat(Color(1.0, 0.5, 0.1), 0.8))
	sock.position = Vector3(31.2, 4.8, -2.0)
	sock.rotation_degrees = Vector3(0, 0, 90)
	body.add_child(sock)
	return body


# ---------------------------------------------------------------- V19: bunker, power station, windmill, solar field

const Spinner = preload("res://scripts/spinner.gd")


static func _taper(top: float, bottom: float, h: float, radial: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = radial
	c.rings = 1
	return c


# low sandbag wall (2 layers) with collision
static func _bag_wall(body: StaticBody3D, ma: Material, mb: Material, cx: float, cz: float, sx: float, sz: float) -> void:
	Util.part(body, Vector3(sx, 0.6, sz), Vector3(cx, 0.3, cz), ma)
	var long_x := sx > sz
	Util.part(body, Vector3(sx - 0.5 if long_x else sx, 0.6, sz if long_x else sz - 0.5), Vector3(cx, 0.9, cz), mb)
	_box_collider(body, Vector3(sx, 1.2, sz), Vector3(cx, 0.6, cz))


# sandbag bunker (30 x 22 m). Open entrance on the +Z side.
static func _bunker() -> Node3D:
	var body := StaticBody3D.new()
	var dirt := Util.mat(Color(0.55, 0.47, 0.32), 1.0)
	var bag_a := Util.mat(Color(0.76, 0.68, 0.47), 1.0)
	var bag_b := Util.mat(Color(0.68, 0.6, 0.41), 1.0)
	var concrete := Util.mat(Color(0.58, 0.59, 0.57), 0.95)
	var dark := Util.mat(Color(0.08, 0.08, 0.09), 1.0)
	var crate := Util.mat(Color(0.32, 0.38, 0.22), 0.9)
	Util.part(body, Vector3(30.0, 0.05, 22.0), Vector3(0, 0.025, 0), dirt)
	Util.part(body, Vector3(10.0, 2.8, 6.0), Vector3(0, 1.4, -3.5), concrete)
	Util.part(body, Vector3(11.0, 0.4, 7.0), Vector3(0, 3.0, -3.5), concrete)
	Util.part(body, Vector3(6.0, 0.6, 0.12), Vector3(0, 1.9, -0.47), dark)
	Util.part(body, Vector3(1.6, 2.0, 0.12), Vector3(3.0, 1.0, -0.47), dark)
	_box_collider(body, Vector3(11.0, 3.2, 7.0), Vector3(0, 1.6, -3.5))
	_bag_wall(body, bag_a, bag_b, -14.0, 0.0, 0.9, 20.0)
	_bag_wall(body, bag_a, bag_b, 14.0, 0.0, 0.9, 20.0)
	_bag_wall(body, bag_a, bag_b, 0.0, -10.0, 28.0, 0.9)
	_bag_wall(body, bag_a, bag_b, -8.75, 9.0, 10.5, 0.9)
	_bag_wall(body, bag_a, bag_b, 8.75, 9.0, 10.5, 0.9)
	_bag_wall(body, bag_a, bag_b, -7.0, 4.0, 3.5, 0.9)
	_bag_wall(body, bag_a, bag_b, 7.0, 4.0, 3.5, 0.9)
	_bag_wall(body, bag_a, bag_b, 0.0, 5.5, 2.5, 0.9)
	for p in [Vector3(-10.0, 0.4, -6.0), Vector3(-10.0, 0.4, -7.3), Vector3(-8.7, 0.4, -6.6)]:
		Util.part(body, Vector3(1.1, 0.8, 1.1), p, crate)
	return body


# electric power station (58 x 58 m): turbine hall, 2 cooling towers, chimney, transformers, pylons, fence
static func _powerstation() -> Node3D:
	var body := StaticBody3D.new()
	var pad := Util.mat(Color(0.5, 0.52, 0.5), 1.0)
	var wallm := Util.mat(Color(0.82, 0.83, 0.8), 0.9)
	var roofm := Util.mat(Color(0.3, 0.36, 0.45), 0.7)
	var conc := Util.mat(Color(0.72, 0.72, 0.7), 0.95)
	var steel := Util.mat(Color(0.7, 0.72, 0.75), 0.5, 0.6)
	var yellow := Util.mat(Color(0.95, 0.8, 0.15), 0.8)
	var tfm := Util.mat(Color(0.42, 0.48, 0.55), 0.6, 0.3)
	var redm := Util.mat(Color(0.85, 0.15, 0.12), 0.6)
	var fencem := Util.mat(Color(0.25, 0.3, 0.25), 0.9)
	var glass := Util.mat(Color(0.45, 0.7, 0.85), 0.15, 0.2)
	var dark := Util.mat(Color(0.08, 0.08, 0.09), 1.0)
	Util.part(body, Vector3(58.0, 0.08, 58.0), Vector3(0, 0.04, 0), pad)
	# turbine hall
	Util.part(body, Vector3(30.0, 9.0, 14.0), Vector3(-8.0, 4.5, -18.0), wallm)
	Util.part(body, Vector3(31.0, 0.8, 15.0), Vector3(-8.0, 9.4, -18.0), roofm)
	Util.part(body, Vector3(26.0, 1.4, 0.15), Vector3(-8.0, 6.5, -10.92), glass)
	Util.part(body, Vector3(4.0, 4.0, 0.15), Vector3(-8.0, 2.0, -10.92), yellow)
	_box_collider(body, Vector3(30.0, 9.5, 14.0), Vector3(-8.0, 4.75, -18.0))
	# cooling towers
	for z in [-19.0, -2.0]:
		var ct := Util.mim(_taper(5.0, 7.0, 24.0, 16), conc)
		ct.position = Vector3(19.0, 12.0, z)
		body.add_child(ct)
		_box_collider(body, Vector3(12.0, 24.0, 12.0), Vector3(19.0, 12.0, z))
	# chimney with red beacon
	var ch := Util.mim(_taper(0.9, 1.3, 30.0, 10), conc)
	ch.position = Vector3(-24.0, 15.0, -4.0)
	body.add_child(ch)
	var bc := Util.mim(Util.sphere(0.4, 8, 4), Util.glow(Color(1.0, 0.1, 0.05), 2.5))
	bc.position = Vector3(-24.0, 30.4, -4.0)
	body.add_child(bc)
	_box_collider(body, Vector3(2.6, 30.0, 2.6), Vector3(-24.0, 15.0, -4.0))
	# control cabin
	Util.part(body, Vector3(8.0, 4.0, 6.0), Vector3(-22.0, 2.0, 6.0), wallm)
	Util.part(body, Vector3(8.4, 0.4, 6.4), Vector3(-22.0, 4.2, 6.0), roofm)
	Util.part(body, Vector3(5.0, 1.0, 0.12), Vector3(-22.0, 2.6, 9.04), glass)
	_box_collider(body, Vector3(8.0, 4.4, 6.0), Vector3(-22.0, 2.2, 6.0))
	# transformers
	for x in [-20.0, -12.0, -4.0]:
		Util.part(body, Vector3(4.0, 3.4, 3.0), Vector3(x, 1.7, 15.0), tfm)
		Util.part(body, Vector3(2.4, 0.5, 1.8), Vector3(x, 3.65, 15.0), redm)
		for k in [-0.8, 0.8]:
			Util.part(body, Vector3(0.3, 1.4, 0.3), Vector3(x + k, 4.6, 15.0), yellow)
		_box_collider(body, Vector3(4.0, 3.4, 3.0), Vector3(x, 1.7, 15.0))
	# pylons + wires
	for px in [12.0, 24.0]:
		_pylon(body, px, 15.0, steel)
	for dz in [-3.0, 0.0, 3.0]:
		Util.part(body, Vector3(12.0, 0.06, 0.06), Vector3(18.0, 16.5, 15.0 + dz), dark)
	# fence (gate on the +Z side)
	_bag_fence(body, fencem, -28.5, 0.0, 0.15, 57.0)
	_bag_fence(body, fencem, 28.5, 0.0, 0.15, 57.0)
	_bag_fence(body, fencem, 0.0, -28.5, 57.0, 0.15)
	_bag_fence(body, fencem, -16.0, 28.5, 24.0, 0.15)
	_bag_fence(body, fencem, 16.0, 28.5, 24.0, 0.15)
	return body


static func _bag_fence(body: StaticBody3D, m: Material, x: float, z: float, sx: float, sz: float) -> void:
	Util.part(body, Vector3(sx, 2.2, sz), Vector3(x, 1.1, z), m)
	_box_collider(body, Vector3(sx, 2.2, sz), Vector3(x, 1.1, z))


static func _pylon(body: StaticBody3D, x: float, z: float, m: Material) -> void:
	var H := 18.0
	var lean := rad_to_deg(atan(1.0 / H))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Util.part(body, Vector3(0.22, H, 0.22), Vector3(x + sx * 1.0, H / 2.0, z + sz * 1.0), m, Vector3(-sz * lean, 0, sx * lean))
	Util.part(body, Vector3(0.3, 0.3, 7.0), Vector3(x, H - 1.5, z), m)
	Util.part(body, Vector3(0.3, 0.3, 5.0), Vector3(x, H - 5.0, z), m)
	_box_collider(body, Vector3(2.4, H, 2.4), Vector3(x, H / 2.0, z))


# wind turbine (the rotor turns by itself)
static func _windmill() -> Node3D:
	var body := StaticBody3D.new()
	var white := Util.mat(Color(0.93, 0.94, 0.95), 0.6)
	var grey := Util.mat(Color(0.7, 0.72, 0.75), 0.5, 0.4)
	var tower := Util.mim(_taper(0.6, 1.3, 18.0, 10), white)
	tower.position = Vector3(0, 9.0, 0)
	body.add_child(tower)
	Util.part(body, Vector3(1.6, 1.6, 3.2), Vector3(0, 18.6, 0.2), grey)
	var hub := Util.mim(Util.sphere(0.55, 8, 4), grey)
	hub.position = Vector3(0, 18.6, 2.0)
	body.add_child(hub)
	var rotor := Spinner.new()
	rotor.position = Vector3(0, 18.6, 2.2)
	body.add_child(rotor)
	for i in 3:
		var arm := Node3D.new()
		arm.rotation_degrees.z = i * 120.0
		rotor.add_child(arm)
		Util.part(arm, Vector3(0.5, 8.0, 0.14), Vector3(0, 4.6, 0), white)
	_box_collider(body, Vector3(2.4, 18.0, 2.4), Vector3(0, 9.0, 0))
	return body


# solar field (36 x 27 m): 5 rows x 11 panels, facing south (+Z)
static func _solar() -> Node3D:
	var body := StaticBody3D.new()
	var gravel := Util.mat(Color(0.6, 0.6, 0.57), 1.0)
	var panel_m := Util.mat(Color(0.1, 0.2, 0.45), 0.25, 0.3)
	var post_m := Util.mat(Color(0.72, 0.73, 0.75), 0.5, 0.5)
	var cab := Util.mat(Color(0.82, 0.83, 0.8), 0.9)
	Util.part(body, Vector3(36.0, 0.05, 27.0), Vector3(0, 0.025, 0), gravel)
	var panels: Array = []
	var posts: Array = []
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(25.0))
	for r in 5:
		var z := -10.0 + r * 4.6
		for i in 11:
			var x := -16.5 + i * 3.3
			panels.append(Transform3D(tilt, Vector3(x, 1.25, z)))
			posts.append(Transform3D(Basis(), Vector3(x, 0.6, z)))
		_box_collider(body, Vector3(35.0, 1.8, 2.0), Vector3(0, 0.9, z))
	Util.multi(body, Util.box(Vector3(3.1, 0.07, 2.0)), panel_m, panels)
	Util.multi(body, Util.box(Vector3(0.12, 1.2, 0.12)), post_m, posts)
	Util.part(body, Vector3(3.0, 2.4, 2.0), Vector3(-14.0, 1.2, 11.5), cab)
	Util.part(body, Vector3(1.6, 1.6, 1.0), Vector3(-10.0, 0.8, 11.5), cab)
	_box_collider(body, Vector3(3.0, 2.4, 2.0), Vector3(-14.0, 1.2, 11.5))
	return body


# ---------------------------------------------------------------- V20: fuel station (44 x 34 m). Pump ring is on the +Z side.

static func _fuelstation() -> Node3D:
	var body := StaticBody3D.new()
	var slab := Util.mat(Color(0.55, 0.56, 0.55), 1.0)
	var white := Util.mat(Color(0.93, 0.93, 0.9), 0.7)
	var redm := Util.mat(Color(0.85, 0.15, 0.12), 0.6)
	var grey := Util.mat(Color(0.7, 0.72, 0.75), 0.5, 0.5)
	var wallm := Util.mat(Color(0.88, 0.85, 0.75), 0.9)
	var roofm := Util.mat(Color(0.3, 0.36, 0.45), 0.7)
	var glass := Util.mat(Color(0.45, 0.7, 0.85), 0.15, 0.2)
	var island := Util.mat(Color(0.35, 0.35, 0.37), 0.9)
	Util.part(body, Vector3(44.0, 0.06, 34.0), Vector3(0, 0.03, 0), slab)
	# canopy + 4 pillars + 4 pumps
	Util.part(body, Vector3(18.0, 0.5, 9.0), Vector3(0, 5.2, -2.0), white)
	Util.part(body, Vector3(18.2, 0.3, 9.2), Vector3(0, 4.85, -2.0), redm)
	for sx in [-8.0, 8.0]:
		for sz in [-5.0, 1.0]:
			Util.part(body, Vector3(0.5, 5.0, 0.5), Vector3(sx, 2.5, sz), grey)
			_box_collider(body, Vector3(0.6, 5.0, 0.6), Vector3(sx, 2.5, sz))
	Util.part(body, Vector3(16.0, 0.2, 1.6), Vector3(0, 0.16, -2.0), island)
	for x in [-6.0, -2.0, 2.0, 6.0]:
		Util.part(body, Vector3(0.9, 1.7, 0.7), Vector3(x, 1.05, -2.0), redm)
		Util.part(body, Vector3(0.6, 0.5, 0.05), Vector3(x, 1.5, -1.62), glass)
		_box_collider(body, Vector3(0.9, 1.7, 0.7), Vector3(x, 1.05, -2.0))
	# sign
	var lab := Label3D.new()
	lab.text = "FUEL"
	lab.font_size = 96
	lab.pixel_size = 0.03
	lab.modulate = Color(1.0, 0.85, 0.1)
	lab.outline_modulate = Color(0, 0, 0)
	lab.outline_size = 14
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0, 7.4, -2.0)
	body.add_child(lab)
	# shop booth
	Util.part(body, Vector3(8.0, 3.2, 5.0), Vector3(-16.0, 1.6, -10.0), wallm)
	Util.part(body, Vector3(8.6, 0.4, 5.6), Vector3(-16.0, 3.4, -10.0), roofm)
	Util.part(body, Vector3(5.0, 1.0, 0.1), Vector3(-16.0, 1.8, -7.45), glass)
	_box_collider(body, Vector3(8.0, 3.4, 5.0), Vector3(-16.0, 1.7, -10.0))
	# two storage tanks (lying cylinders) at the back
	for x in [2.0, 12.0]:
		var tk := Util.mim(Util.cyl(1.7, 8.0, 12), grey)
		tk.rotation_degrees.z = 90.0
		tk.position = Vector3(x, 1.8, -13.5)
		body.add_child(tk)
		Util.part(body, Vector3(1.0, 0.5, 1.0), Vector3(x, 3.7, -13.5), redm)
		_box_collider(body, Vector3(8.0, 3.6, 3.6), Vector3(x, 1.8, -13.5))
	return body
