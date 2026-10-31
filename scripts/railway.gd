extends Node3D
# Closed-loop railway for the FX001 map (V26: big, sharp-cornered, 3 stations with red clocks).
# Builds track + three platforms only. The path API is ready for a future train controller.
# Rails intentionally have no collision so tractors/players can cross them.

const Util = preload("res://scripts/util.gd")

# V26: BIG closed railway (about 3.5 km) with sharp-ish corners (not a circle). It runs round the old 400 m map
# and out into the new land past plots, airports, power stations, fuel stations and warehouses.
# 3 stations. Every station has a RED CLOCK (countdown until the train leaves / arrives).
const VERTS := [Vector2(-212, -215), Vector2(-20, -222), Vector2(130, -300), Vector2(320, -330), Vector2(410, -190), Vector2(225, -120),
	Vector2(214, 130), Vector2(330, 230), Vector2(400, 390), Vector2(180, 420), Vector2(60, 225), Vector2(-150, 218), Vector2(-280, 400),
	Vector2(-430, 300), Vector2(-300, 120), Vector2(-215, 20), Vector2(-220, -120), Vector2(-390, -200), Vector2(-340, -380), Vector2(-200, -330)]
const CORNER_R := 30.0
const STEP := 6.0
const GAUGE := 1.5
const BALLAST_W := 4.4
const SLEEPER_GAP := 3.0
const PLATFORM_LEN := 30.0
const PLATFORM_W := 3.4
const PLATFORM_H := 0.45
const PLATFORM_OFF := 3.7

const STATIONS := [
	{"name": "UTTARPARA STATION", "area": "Uttarpara", "id": "north", "at": Vector2(225, -315), "col": Color(0.85, 0.2, 0.18)},
	{"name": "PURBAPARA STATION", "area": "Purbapara", "id": "east", "at": Vector2(290, 405), "col": Color(0.2, 0.45, 0.85)},
	{"name": "PASCHIMPARA STATION", "area": "Paschimpara", "id": "west", "at": Vector2(-365, 210), "col": Color(0.95, 0.75, 0.15)}
]

var path := PackedVector3Array()
var length := 0.0
var stations: Array = []
var _cum := PackedFloat32Array()
var _grid := {}   # 8 m squares near the track (trees / rocks stay out)

func build() -> void:
	add_to_group("railway")
	_make_path()
	_make_track()
	_make_stations()

func _make_path() -> void:
	var pts: Array = []
	var n := VERTS.size()
	for i in n:
		var p: Vector2 = VERTS[(i + n - 1) % n]
		var c: Vector2 = VERTS[i]
		var q: Vector2 = VERTS[(i + 1) % n]
		var a: Vector2 = p - c
		var b: Vector2 = q - c
		var la := a.length()
		var lb := b.length()
		var th := acos(clampf(a.dot(b) / (la * lb), -1.0, 1.0))
		var t := minf(CORNER_R / tan(th * 0.5), 0.45 * minf(la, lb))
		var e: Vector2 = c + a / la * t
		var x: Vector2 = c + b / lb * t
		pts.append(e)
		for k in range(1, 8):
			var u := float(k) / 8.0
			pts.append(e * ((1.0 - u) * (1.0 - u)) + c * (2.0 * u * (1.0 - u)) + x * (u * u))
		pts.append(x)
	var dense: Array = []
	for i in pts.size():
		var a2: Vector2 = pts[i]
		var b2: Vector2 = pts[(i + 1) % pts.size()]
		var cnt := maxi(1, int(ceil(a2.distance_to(b2) / STEP)))
		for k in cnt:
			dense.append(a2.lerp(b2, float(k) / float(cnt)))
	path = PackedVector3Array()
	_cum = PackedFloat32Array()
	length = 0.0
	for p3 in dense:
		var v := Vector3(p3.x, 0.0, p3.y)
		if path.is_empty() or path[path.size() - 1].distance_to(v) > 0.01:
			path.append(v)
			_cum.append(length)
			if path.size() > 1:
				length += path[path.size() - 2].distance_to(v)
	if path.size() > 2:
		length += path[path.size() - 1].distance_to(path[0])
	_grid.clear()
	for p4 in path:
		for ox in [-11.0, 0.0, 11.0]:
			for oz in [-11.0, 0.0, 11.0]:
				_grid[Vector2i(floori((p4.x + ox) / 8.0), floori((p4.z + oz) / 8.0))] = true


func near_track(x: float, z: float) -> bool:
	return _grid.has(Vector2i(floori(x / 8.0), floori(z / 8.0)))


# binary search: index of the segment that holds distance d (fast, the train asks every frame)
func _seg(d: float) -> int:
	var lo := 0
	var hi := path.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if _cum[mid] <= d:
			lo = mid
		else:
			hi = mid - 1
	return lo


func point_at(dist: float) -> Vector3:
	if path.size() < 2 or length <= 0.0:
		return Vector3.ZERO
	var d := fposmod(dist, length)
	var i := _seg(d)
	var j := (i + 1) % path.size()
	var seg := path[i].distance_to(path[j])
	return path[i].lerp(path[j], clampf((d - _cum[i]) / maxf(seg, 0.001), 0.0, 1.0))


func dir_at(dist: float) -> Vector3:
	if path.size() < 2:
		return Vector3.FORWARD
	var i := _seg(fposmod(dist, length))
	var j := (i + 1) % path.size()
	return (path[j] - path[i]).normalized()


func _make_track() -> void:
	var ballast_mat := Util.mat(Color(0.24, 0.23, 0.21), 1.0)
	var rail_mat := Util.mat(Color(0.38, 0.40, 0.42), 0.55, 0.55)
	var sleeper_mat := Util.mat(Color(0.25, 0.16, 0.10), 1.0)
	var ballast_mesh := Util.box(Vector3(BALLAST_W, 0.12, STEP + 0.08))
	var rail_mesh := Util.box(Vector3(0.12, 0.16, STEP + 0.08))
	var sleeper_mesh := Util.box(Vector3(GAUGE + 1.0, 0.12, 0.24))
	# V26: the track is cut into 150 m pieces; far pieces are not drawn (big speed-up)
	var bx := {}
	var rx := {}
	var sx := {}
	for i in path.size():
		var j := (i + 1) % path.size()
		var a := path[i]
		var b := path[j]
		var delta := b - a
		var seg_len := delta.length()
		if seg_len < 0.01:
			continue
		var ck := int(_cum[i] / 150.0)
		if not bx.has(ck):
			var a1: Array[Transform3D] = []
			var a2: Array[Transform3D] = []
			var a3: Array[Transform3D] = []
			bx[ck] = a1
			rx[ck] = a2
			sx[ck] = a3
		var mid := (a + b) * 0.5
		var yaw := atan2(delta.x, delta.z)
		var basis := Basis(Vector3.UP, yaw)
		bx[ck].append(Transform3D(basis.scaled(Vector3(1.0, 1.0, seg_len / (STEP + 0.08))), mid + Vector3(0, 0.08, 0)))
		for side in [-1.0, 1.0]:
			var offset := basis * Vector3(side * GAUGE * 0.5, 0.22, 0)
			rx[ck].append(Transform3D(basis.scaled(Vector3(1.0, 1.0, seg_len / (STEP + 0.08))), mid + offset))
		var count := maxi(1, int(floor(seg_len / SLEEPER_GAP)))
		for k in count:
			var p := a.lerp(b, float(k) / float(count))
			sx[ck].append(Transform3D(basis, p + Vector3(0, 0.16, 0)))
	for ck in bx:
		_add_multimesh(ballast_mesh, ballast_mat, bx[ck])
		_add_multimesh(sleeper_mesh, sleeper_mat, sx[ck])
		_add_multimesh(rail_mesh, rail_mat, rx[ck])

func _add_multimesh(mesh: Mesh, material: Material, transforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.visibility_range_end = 380.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _make_stations() -> void:
	for data in STATIONS:
		var at: Vector2 = data["at"]
		var best_dist := 0.0
		var best_pos := Vector3.ZERO
		var best_dir := Vector3.FORWARD
		var best := INF
		for i in path.size():
			var d := Vector2(path[i].x, path[i].z).distance_to(at)
			if d < best:
				best = d
				best_dist = _cum[i]
				best_pos = path[i]
				best_dir = dir_at(best_dist)
		var side := Vector3(-best_dir.z, 0, best_dir.x)
		var platform_pos := best_pos + side * PLATFORM_OFF
		var platform := Util.mim(Util.box(Vector3(PLATFORM_W, PLATFORM_H, PLATFORM_LEN)), Util.mat(Color(0.48, 0.48, 0.45), 1.0))
		platform.position = platform_pos + Vector3(0, PLATFORM_H * 0.5, 0)
		platform.rotation.y = atan2(best_dir.x, best_dir.z)
		add_child(platform)
		var roof_mat := Util.mat(Color(0.22, 0.27, 0.31), 0.9)
		var roof := Util.mim(Util.box(Vector3(PLATFORM_W + 1.2, 0.16, 8.0)), roof_mat)
		roof.position = platform_pos + Vector3(0, 3.0, 0)
		roof.rotation.y = platform.rotation.y
		add_child(roof)
		for side_x in [-1.0, 1.0]:
			var post := Util.mim(Util.box(Vector3(0.18, 3.0, 0.18)), Util.mat(Color(0.32, 0.32, 0.3)))
			post.position = platform_pos + Vector3(0, 1.5, 0) + Vector3(side_x * (PLATFORM_W * 0.5 - 0.25), 0, 0)
			post.rotation.y = platform.rotation.y
			add_child(post)
		var sign := Util.mim(Util.box(Vector3(5.6, 1.0, 0.12)), Util.mat(data["col"]))
		sign.position = platform_pos + Vector3(0, 2.0, 0)
		sign.rotation.y = platform.rotation.y + PI * 0.5   # the board faces the track (and the road side)
		add_child(sign)
		for fb in [1.0, -1.0]:
			var lab := Label3D.new()
			lab.text = String(data["name"])
			lab.font_size = 64
			lab.pixel_size = 0.0075
			lab.outline_size = 8
			lab.modulate = Color.WHITE
			lab.outline_modulate = Color(0, 0, 0)
			lab.position = Vector3(0, 0, 0.07 * fb)
			if fb < 0.0:
				lab.rotation.y = PI
			sign.add_child(lab)
		# RED CLOCK: pole + red face + big countdown text (the train writes the text)
		var cpos := platform_pos + Vector3(0, 0, 0) + best_dir * (PLATFORM_LEN * 0.5 - 2.0)
		var pole := Util.mim(Util.box(Vector3(0.25, 6.0, 0.25)), Util.mat(Color(0.2, 0.2, 0.22)))
		pole.position = cpos + Vector3(0, 3.0, 0)
		add_child(pole)
		var face := Util.mim(Util.box(Vector3(4.6, 2.4, 0.3)), Util.mat(Color(0.75, 0.05, 0.05), 0.5))
		face.position = cpos + Vector3(0, 7.2, 0)
		face.rotation.y = platform.rotation.y + PI * 0.5
		add_child(face)
		var clock := Label3D.new()
		clock.text = "--:--"
		clock.font_size = 72
		clock.pixel_size = 0.0075
		clock.outline_size = 10
		clock.modulate = Color(1.0, 0.25, 0.2)
		clock.outline_modulate = Color(0, 0, 0)
		clock.no_depth_test = false
		clock.position = Vector3(0, 0, 0.17)
		face.add_child(clock)
		var clock2 := clock.duplicate() as Label3D
		clock2.position = Vector3(0, 0, -0.17)
		clock2.rotation.y = PI
		face.add_child(clock2)
		stations.append({"name": data["name"], "id": data["id"], "area": data.get("area", ""), "pos": best_pos, "dir": best_dir, "dist": best_dist, "clock": [clock, clock2]})
