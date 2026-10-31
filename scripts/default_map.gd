extends Node3D
# Built-in map. Everything comes from res://data/layout.json (see data/README.txt).
# Other scripts (minimap, machines, farming later) read:
#   layout, plots, plot_cell, trees, ponds, plot_at(), cell_of(), till_at(), plot_progress()
#
# Plot ground = a small "mask" picture (2 pixels per meter). A machine paints it with till_at():
# painted soil looks dark with furrows, the rest stays dry. The same data is kept per CELL
# (tilled flag) so crops can use it later: is_tilled(id, cell).

const Util = preload("res://scripts/util.gd")
const Props = preload("res://scripts/props.gd")
const Coast = preload("res://scripts/coast.gd")
const Biome = preload("res://scripts/biome.gd")
const StreamScript = preload("res://scripts/stream.gd")
const RailwayScript = preload("res://scripts/railway.gd")
const TrainScript = preload("res://scripts/train.gd")
const LAYOUT_PATH := "res://data/layout.json"
const RES := 1.0   # mask pixels per meter (V26: lower = lighter, less lag)
const FarmData = preload("res://scripts/farm_data.gd")

signal farm_changed   # soil / crops changed (the farm saves itself)

const SOIL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec3 dry_col = vec3(0.64, 0.5, 0.3);
uniform vec3 till_col = vec3(0.3, 0.18, 0.09);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 mk = texture(mask, UV).rg;
	float m = mk.r;
	float n = fract(sin(dot(floor(wpos.xz * 2.5), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 dry = dry_col * (0.93 + 0.14 * n);
	float st = 0.5 + 0.5 * sin(wpos.x * 7.0 + n * 0.8);
	vec3 till = till_col * (0.7 + 0.55 * st) * (0.92 + 0.16 * n);
	till = mix(till, till * 0.5, smoothstep(0.35, 0.65, mk.g) * 0.75);   // fertilized = darker
	ALBEDO = mix(dry, till, smoothstep(0.35, 0.65, m));
	ROUGHNESS = 1.0;
}
"""

var layout := {}
var plots := {}        # id -> Rect2 on the ground (x, z)
var plot_cell := {}    # id -> grid cell size (m)
var trees: Array = []  # tree positions (Vector2 x, z)
var ponds: Array = []  # [{x, z, r}]
var rail_pts := PackedVector2Array()   # V26: track points for the big map

var _soil_shader: Shader
var _masks := {}       # id -> Image (R8)
var _tex := {}         # id -> ImageTexture
var _cells := {}       # id -> Vector2i (columns, rows)
var _tilled := {}      # id -> PackedByteArray (1 = tilled), one byte per cell
var _tilled_count := {}
var _dirty := {}
var _timer := 0.0

var _rng := RandomNumberGenerator.new()

var pois: Array = []          # points: shops (SELL), warehouse (wheat / rice), fertilizer pump. {kind, id, label, r, col, pos}
var _shop_count := 0
var _crop := {}               # id -> PackedByteArray (crop index per cell, 0 = empty)
var _t0 := {}                 # id -> PackedInt32Array (unix second when planted)
var _fert := {}               # id -> PackedByteArray (1 = fertilized)
var _crop_mm := {}            # id -> MultiMeshInstance3D
var _crop_dirty := {}
var _crop_stats := {}         # id -> [planted cells, ripe cells]
var _crop_timer := 0.0
var _crop_mat: StandardMaterial3D
var _tuft: ArrayMesh


func _ready() -> void:
	add_to_group("field_map")
	layout = _read_layout()
	Util.add_env(self)
	Util.add_sun(self)

	var start := Marker3D.new()
	start.name = "PlayerStart"
	add_child(start)

	var g: Dictionary = layout.get("ground", {})
	var half := float(g.get("size", 600.0)) / 2.0
	_solid_box(Vector3(0, -0.5, 0), Vector3(half * 2.0, 1, half * 2.0), _ground_material())
	var coast := Coast.new()   # hill (north) + sea (west, east, south) + beaches
	add_child(coast)
	coast.build(half)

	var blocked: Array = [Rect2(-12, -12, 24, 24)]   # trees stay away from the start area
	var small: Array = [Rect2(-8, -8, 16, 16)]       # bushes / flowers / rocks keep a smaller distance
	for edge in [Rect2(-half, -half, half * 2.0, 24.0), Rect2(-half, -half, 22.0, half * 2.0), Rect2(half - 22.0, -half, 22.0, half * 2.0), Rect2(-half, half - 22.0, half * 2.0, 22.0)]:
		blocked.append(edge)   # hill foot + beaches stay free of trees and bushes
		small.append(edge)

	_build_roads(blocked, small)
	# V12: low-poly railway loop in the central block, clear of roads and field plots.
	var railway := RailwayScript.new()
	add_child(railway)
	railway.build()
	var train := TrainScript.new()   # train (1 engine + 3 flat carriages), stops 60 s at every station
	add_child(train)
	train.setup(railway)
	for k in range(0, railway.path.size(), 5):
		rail_pts.append(Vector2(railway.path[k].x, railway.path[k].z))
	_soil_shader = Shader.new()
	_soil_shader.code = SOIL_SHADER

	# plots: soil
	for p in layout.get("plots", []):
		var id: String = p["id"]
		var rect := Rect2(float(p["x"]) - float(p["w"]) / 2.0, float(p["z"]) - float(p["d"]) / 2.0, float(p["w"]), float(p["d"]))
		plots[id] = rect
		plot_cell[id] = float(p.get("cell", 1.0))
		_make_soil(id, rect)
		blocked.append(rect.grow(4.0))
		small.append(rect.grow(2.0))

	for o in layout.get("objects", []):
		var node := Props.make(String(o["type"]))
		if node == null:
			continue
		node.position = Vector3(float(o["x"]), 0, float(o["z"]))
		node.rotation_degrees.y = float(o.get("rot", 0))
		add_child(node)
		_far_cull(node, 320.0)
		_make_pois(String(o["type"]), node.position, float(o.get("rot", 0)))
		var f: Vector2 = Props.FOOT.get(String(o["type"]), Vector2(4, 4))
		if int(o.get("rot", 0)) % 180 != 0:
			f = Vector2(f.y, f.x)
		var fr := Rect2(float(o["x"]) - f.x / 2.0, float(o["z"]) - f.y / 2.0, f.x, f.y)
		blocked.append(fr.grow(4.0))
		small.append(fr.grow(1.5))

	for pd in layout.get("ponds", []):
		ponds.append(pd)
		_make_pond(pd)
		var pr := Rect2(float(pd["x"]) - float(pd["r"]), float(pd["z"]) - float(pd["r"]), float(pd["r"]) * 2.0, float(pd["r"]) * 2.0)
		blocked.append(pr.grow(4.0))
		small.append(pr.grow(2.0))

	_rng.seed = int(layout.get("trees", {}).get("seed", 1))
	_build_trees(blocked, half)
	_build_scatter(small, half)
	if half > 250.0:
		var stream := StreamScript.new()   # trees / rocks / cacti of the big map, made around the camera
		stream.half = half
		var sb: Array = [Rect2(-200.0, -200.0, 400.0, 400.0)]
		for pid in plots:
			sb.append((plots[pid] as Rect2).grow(5.0))
		for o in layout.get("objects", []):
			var ff: Vector2 = Props.FOOT.get(String(o["type"]), Vector2(4, 4))
			var m := maxf(ff.x, ff.y) + 10.0
			sb.append(Rect2(float(o["x"]) - m * 0.5, float(o["z"]) - m * 0.5, m, m))
		stream.blocks = sb
		stream.rail = railway
		add_child(stream)
		stream.start()


func _process(delta: float) -> void:
	_crop_timer += delta
	if _crop_timer >= 1.0 and not _crop_dirty.is_empty():
		_crop_timer = 0.0
		for cid in _crop_dirty.keys():
			if not _rebuild_crops(cid):
				_crop_dirty.erase(cid)
	_timer += delta
	if _timer < 0.12 or _dirty.is_empty():
		return
	_timer = 0.0
	for id in _dirty:
		(_tex[id] as ImageTexture).update(_masks[id])
	_dirty.clear()


# ---------------------------------------------------------------- ground, roads, walls

func _ground_material() -> ShaderMaterial:
	# V25: one shader paints all biomes (farm green, forest, rock, desert, swamp). No texture to build at start.
	var sh := Shader.new()
	sh.code = Biome.GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _build_roads(blocked: Array, small: Array) -> void:
	var asphalt := Util.mat(Color(0.27, 0.27, 0.29), 0.9)
	var roads: Array = layout.get("roads", [])
	var dashes_ns: Array = []
	var dashes_ew: Array = []
	var idx := 0
	for r in roads:
		var w := float(r["w"])
		var d := float(r["d"])
		var road := Util.mim(Util.box(Vector3(w, 0.06, d)), asphalt)
		road.position = Vector3(float(r["x"]), 0.03 + 0.003 * idx, float(r["z"]))   # tiny height steps: no flicker at crossings
		add_child(road)
		var rr := Rect2(float(r["x"]) - w / 2.0, float(r["z"]) - d / 2.0, w, d)
		blocked.append(rr.grow(3.0))
		small.append(rr.grow(1.5))
		idx += 1
		# dashed center line (not across crossings)
		var ns := d > w
		var len := d if ns else w
		var t := -len / 2.0 + 6.0
		while t < len / 2.0 - 4.0:
			var x := float(r["x"]) + (0.0 if ns else t)
			var z := float(r["z"]) + (t if ns else 0.0)
			var skip := false
			for o in roads:
				if o == r:
					continue
				var ons := float(o["d"]) > float(o["w"])
				if ns and not ons and absf(z - float(o["z"])) < 7.0:
					skip = true
				elif (not ns) and ons and absf(x - float(o["x"])) < 7.0:
					skip = true
			if not skip:
				var b := Basis() if ns else Basis(Vector3.UP, PI / 2.0)
				(dashes_ns if ns else dashes_ew).append(Transform3D(b, Vector3(x, 0.1, z)))
			t += 10.0
	var dash_m := Util.mat(Color(0.95, 0.85, 0.35), 0.8)
	var dash := Util.box(Vector3(0.22, 0.01, 3.5))
	Util.multi(self, dash, dash_m, dashes_ns + dashes_ew)


# ---------------------------------------------------------------- plots (soil)

func _make_soil(id: String, rect: Rect2) -> void:
	var cw := int(ceil(rect.size.x * RES))
	var ch := int(ceil(rect.size.y * RES))
	var img := Image.create(cw, ch, false, Image.FORMAT_RG8)
	var tex := ImageTexture.create_from_image(img)
	_masks[id] = img
	_tex[id] = tex
	var cell: float = plot_cell[id]
	var cols := int(ceil(rect.size.x / cell))
	var rows := int(ceil(rect.size.y / cell))
	_cells[id] = Vector2i(cols, rows)
	var arr := PackedByteArray()
	arr.resize(cols * rows)
	_tilled[id] = arr
	_tilled_count[id] = 0
	var crop_arr := PackedByteArray()
	crop_arr.resize(cols * rows)
	_crop[id] = crop_arr
	var fert_arr := PackedByteArray()
	fert_arr.resize(cols * rows)
	_fert[id] = fert_arr
	var t0_arr := PackedInt32Array()
	t0_arr.resize(cols * rows)
	_t0[id] = t0_arr

	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := rect.end.x
	var z1 := rect.end.y
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)])
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mat := ShaderMaterial.new()
	mat.shader = _soil_shader
	mat.set_shader_parameter("mask", tex)
	var mi := Util.mim(mesh, mat)
	mi.position = Vector3(0, 0.045, 0)
	add_child(mi)


# ---------------------------------------------------------------- ponds

func _make_pond(pd: Dictionary) -> void:
	var r := float(pd["r"])
	var pos := Vector3(float(pd["x"]), 0, float(pd["z"]))
	var sand := Util.mim(Util.cyl(r + 1.6, 0.04, 28), Util.mat(Color(0.75, 0.68, 0.45), 1.0))
	sand.position = pos + Vector3(0, 0.02, 0)
	add_child(sand)
	var water := Util.mim(Util.cyl(r, 0.05, 28), Util.mat(Color(0.14, 0.42, 0.62), 0.1, 0.2))
	water.position = pos + Vector3(0, 0.05, 0)
	add_child(water)
	var reeds: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 31.0 + pos.z * 17.0)
	for i in int(r * 1.5):
		var a := rng.randf() * TAU
		var d := r + rng.randf_range(0.2, 1.4)
		var s := rng.randf_range(0.8, 1.5)
		reeds.append(Transform3D(Basis.from_scale(Vector3(s, s, s)), pos + Vector3(cos(a) * d, 0.5 * s, sin(a) * d)))
	Util.multi(self, Util.cone(0.18, 1.0, 5), Util.mat(Color(0.25, 0.5, 0.15)), reeds)
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r * 0.97
	sh.height = 2.0
	cs.shape = sh
	cs.position = Vector3(0, 1.0, 0)
	body.add_child(cs)
	add_child(body)


# ---------------------------------------------------------------- trees, bushes, flowers ...

func _free_spot(rect: Rect2, near: Array) -> Variant:
	for t in 8:
		var q := Vector2(_rng.randf_range(rect.position.x, rect.end.x), _rng.randf_range(rect.position.y, rect.end.y))
		var bad := false
		for b in near:
			if b.has_point(q):
				bad = true
				break
		if not bad:
			return q
	return null


func _near(blocked: Array, rect: Rect2) -> Array:
	var out: Array = []
	for b in blocked:
		if rect.intersects(b):
			out.append(b)
	return out


func _build_trees(blocked: Array, half: float) -> void:
	var data: Array = []   # [x, z, scale, kind]
	var ch := minf(half, 200.0)   # V25: the hand-made trees stay inside the old 400 m map; the rest is streamed (stream.gd)
	var whole := Rect2(-ch + 6.0, -ch + 6.0, ch * 2.0 - 12.0, ch * 2.0 - 12.0)

	for f in layout.get("forests", []):
		var rect := Rect2(float(f["x"]) - float(f["w"]) / 2.0, float(f["z"]) - float(f["d"]) / 2.0, float(f["w"]), float(f["d"]))
		var count := int(rect.size.x * rect.size.y / 1000.0 * float(f.get("density", 8)))
		var near := _near(blocked, rect)
		for i in count:
			var q = _free_spot(rect, near)
			if q != null:
				data.append([q.x, q.y, _rng.randf_range(0.8, 1.5), _rng.randi() % 100])

	var tcfg: Dictionary = layout.get("trees", {})
	for i in int(tcfg.get("count", 0)):
		var q = _free_spot(whole, blocked)
		if q != null:
			data.append([q.x, q.y, _rng.randf_range(0.8, 1.4), _rng.randi() % 100])

	var rt: Array = []   # round trees: trunk, crown (+ colors)
	var rc: Array = []
	var rcol: Array = []
	var pt: Array = []   # pines: trunk, two cones
	var p1: Array = []
	var p2: Array = []
	var pcol: Array = []
	var body := StaticBody3D.new()
	body.name = "TreeBody"
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = 5.0
	for d in data:
		var x: float = d[0]
		var z: float = d[1]
		var s: float = d[2]
		var kind: int = d[3]
		trees.append(Vector2(x, z))
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * s)
		if kind < 55:
			rt.append(Transform3D(b, Vector3(x, 2.3 * s, z)))
			rc.append(Transform3D(b, Vector3(x, 5.6 * s, z)))
			rcol.append(Color(_rng.randf_range(0.1, 0.22), _rng.randf_range(0.42, 0.62), _rng.randf_range(0.1, 0.22)))
		else:
			pt.append(Transform3D(b, Vector3(x, 1.2 * s, z)))
			p1.append(Transform3D(b, Vector3(x, 4.1 * s, z)))
			p2.append(Transform3D(b, Vector3(x, 6.6 * s, z)))
			pcol.append(Color(_rng.randf_range(0.04, 0.12), _rng.randf_range(0.28, 0.42), _rng.randf_range(0.12, 0.2)))
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(x, 2.5, z)
		body.add_child(cs)
	add_child(body)

	var trunk_m := Util.mat(Color(0.38, 0.25, 0.13))
	var leaf_m := Util.vcol_mat()
	Util.multi(self, Util.cyl(0.35, 4.6, 6), trunk_m, rt)
	Util.multi(self, Util.sphere(2.6, 6, 4), leaf_m, rc, rcol)
	Util.multi(self, Util.cyl(0.3, 2.4, 6), trunk_m, pt)
	Util.multi(self, Util.cone(2.4, 4.2, 6), leaf_m, p1, pcol)
	Util.multi(self, Util.cone(1.7, 3.6, 6), leaf_m, p2, pcol)


func _build_scatter(small: Array, half: float) -> void:
	var sc: Dictionary = layout.get("scatter", {})
	if sc.is_empty():
		return
	_rng.seed = int(sc.get("seed", 3))
	var ch := minf(half, 200.0)
	var whole := Rect2(-ch + 3.0, -ch + 3.0, ch * 2.0 - 6.0, ch * 2.0 - 6.0)
	var leaf_m := Util.vcol_mat()

	var bushes: Array = []
	var bcol: Array = []
	for i in int(sc.get("bush", 0)):
		var q = _free_spot(whole, small)
		if q == null:
			continue
		var s := _rng.randf_range(0.7, 1.6)
		bushes.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3(s * 1.3, s * 0.85, s * 1.3)), Vector3(q.x, 0.35 * s, q.y)))
		bcol.append(Color(_rng.randf_range(0.12, 0.3), _rng.randf_range(0.4, 0.6), _rng.randf_range(0.1, 0.22)))
	Util.multi(self, Util.sphere(0.7, 8, 4), leaf_m, bushes, bcol)

	var rocks: Array = []
	var rcol: Array = []
	for i in int(sc.get("rock", 0)):
		var q = _free_spot(whole, small)
		if q == null:
			continue
		var s := _rng.randf_range(0.5, 1.4)
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3(s * _rng.randf_range(0.8, 1.4), s * 0.6, s))
		rocks.append(Transform3D(b, Vector3(q.x, 0.15 * s, q.y)))
		var g := _rng.randf_range(0.4, 0.62)
		rcol.append(Color(g, g, g * 0.95))
	Util.multi(self, Util.sphere(0.6, 6, 3), leaf_m, rocks, rcol)

	var flowers: Array = []
	var fcol: Array = []
	var palette := [Color(0.9, 0.15, 0.15), Color(0.98, 0.85, 0.15), Color(0.97, 0.97, 0.95), Color(0.65, 0.3, 0.85), Color(1.0, 0.5, 0.15)]
	for i in int(sc.get("flower", 0)):
		var q = _free_spot(whole, small)
		if q == null:
			continue
		var col: Color = palette[_rng.randi() % palette.size()]
		for k in 7:
			var a := _rng.randf() * TAU
			var d := _rng.randf() * 1.3
			flowers.append(Transform3D(Basis(), Vector3(q.x + cos(a) * d, 0.12, q.y + sin(a) * d)))
			fcol.append(col)
	Util.multi(self, Util.sphere(0.085, 5, 3), leaf_m, flowers, fcol)

	# hay bales just outside the fields
	var bales: Array = []
	var ids: Array = plots.keys()
	if not ids.is_empty():
		for i in int(sc.get("bale", 0)):
			var r: Rect2 = plots[ids[_rng.randi() % ids.size()]]
			var g := r.grow(3.2)
			var q := Vector2(g.position.x, g.position.y)
			match _rng.randi() % 4:
				0:
					q = Vector2(_rng.randf_range(g.position.x, g.end.x), g.position.y)
				1:
					q = Vector2(_rng.randf_range(g.position.x, g.end.x), g.end.y)
				2:
					q = Vector2(g.position.x, _rng.randf_range(g.position.y, g.end.y))
				3:
					q = Vector2(g.end.x, _rng.randf_range(g.position.y, g.end.y))
			var bad := false
			for b in small:
				if (b as Rect2).has_point(q):
					bad = true
					break
			if bad or absf(q.x) > half - 4.0 or absf(q.y) > half - 4.0:
				continue
			bales.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, PI / 2.0), Vector3(q.x, 0.6, q.y)))
	Util.multi(self, Util.cyl(0.65, 1.1, 10), Util.mat(Color(0.86, 0.72, 0.27), 1.0), bales)


# ---------------------------------------------------------------- map data for other scripts

func _read_layout() -> Dictionary:
	if ResourceLoader.exists(LAYOUT_PATH):
		var res = load(LAYOUT_PATH)   # .json is imported as a JSON resource (also works inside the APK)
		if res is JSON and res.data is Dictionary:
			return res.data
	if FileAccess.file_exists(LAYOUT_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
		if d is Dictionary:
			return d
	push_warning("layout.json not found or broken - using an empty map")
	return {"ground": {"size": 600}}


# which plot is this position in? ("" = none)
func plot_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	for id in plots:
		var r: Rect2 = plots[id]
		if r.has_point(q):
			return id
	return ""


# grid cell (column, row) of a position inside a plot
func cell_of(id: String, p: Vector3) -> Vector2i:
	var r: Rect2 = plots[id]
	var c: float = plot_cell[id]
	return Vector2i(int(floor((p.x - r.position.x) / c)), int(floor((p.z - r.position.y) / c)))


# A MACHINE CALLS THIS to work the soil at a world position (plow = till). radius in meters.
func till_at(pos: Vector3, radius: float) -> void:
	var id := plot_at(pos)
	if id == "":
		return
	var r: Rect2 = plots[id]
	var img: Image = _masks[id]
	var cx := (pos.x - r.position.x) * RES
	var cy := (pos.z - r.position.y) * RES
	var pr := radius * RES
	var changed := false
	for py in range(maxi(0, int(floor(cy - pr))), mini(img.get_height(), int(ceil(cy + pr)) + 1)):
		for px in range(maxi(0, int(floor(cx - pr))), mini(img.get_width(), int(ceil(cx + pr)) + 1)):
			var dx := float(px) + 0.5 - cx
			var dy := float(py) + 0.5 - cy
			if dx * dx + dy * dy <= pr * pr:
				var oc := img.get_pixel(px, py)
				if oc.r < 0.5:
					img.set_pixel(px, py, Color(1.0, oc.g, 0.0))
					changed = true
	if changed:
		_dirty[id] = true
		farm_changed.emit()

	# the same thing as data: which cells are tilled
	var cell: float = plot_cell[id]
	var size: Vector2i = _cells[id]
	var arr: PackedByteArray = _tilled[id]
	var c0 := int(floor((pos.x - radius - r.position.x) / cell))
	var c1 := int(floor((pos.x + radius - r.position.x) / cell))
	var r0 := int(floor((pos.z - radius - r.position.y) / cell))
	var r1 := int(floor((pos.z + radius - r.position.y) / cell))
	for row in range(maxi(0, r0), mini(size.y - 1, r1) + 1):
		for col in range(maxi(0, c0), mini(size.x - 1, c1) + 1):
			var cc := Vector2(r.position.x + (col + 0.5) * cell, r.position.y + (row + 0.5) * cell)
			if cc.distance_to(Vector2(pos.x, pos.z)) <= radius + cell * 0.3 and arr[row * size.x + col] == 0:
				arr[row * size.x + col] = 1
				_tilled_count[id] = int(_tilled_count[id]) + 1
	_tilled[id] = arr


func is_tilled(id: String, cell: Vector2i) -> bool:
	if not _tilled.has(id):
		return false
	var size: Vector2i = _cells[id]
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return false
	return (_tilled[id] as PackedByteArray)[cell.y * size.x + cell.x] == 1


# 0.0 .. 1.0  how much of the plot is tilled
func plot_progress(id: String) -> float:
	if not _cells.has(id):
		return 0.0
	var size: Vector2i = _cells[id]
	return float(_tilled_count[id]) / float(maxi(1, size.x * size.y))


func _solid_box(pos: Vector3, size: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.add_child(Util.mim(Util.box(size), material))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	add_child(body)


func _wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	add_child(body)


# ---------------------------------------------------------------- farming: fertilizer, crops, points

# cell indexes (row * columns + col) of a plot whose centers are inside the circle
func _cell_indices(id: String, pos: Vector3, radius: float) -> PackedInt32Array:
	var r: Rect2 = plots[id]
	var cell: float = plot_cell[id]
	var size: Vector2i = _cells[id]
	var out := PackedInt32Array()
	var c0 := int(floor((pos.x - radius - r.position.x) / cell))
	var c1 := int(floor((pos.x + radius - r.position.x) / cell))
	var r0 := int(floor((pos.z - radius - r.position.y) / cell))
	var r1 := int(floor((pos.z + radius - r.position.y) / cell))
	for row in range(maxi(0, r0), mini(size.y - 1, r1) + 1):
		for col in range(maxi(0, c0), mini(size.x - 1, c1) + 1):
			var cc := Vector2(r.position.x + (col + 0.5) * cell, r.position.y + (row + 0.5) * cell)
			if cc.distance_to(Vector2(pos.x, pos.z)) <= radius + cell * 0.3:
				out.append(row * size.x + col)
	return out


# area (m2) of one grid cell of the plot at this position (0 = not on a plot)
func cell_area(p: Vector3) -> float:
	var id := plot_at(p)
	if id == "":
		return 0.0
	var c: float = plot_cell[id]
	return c * c


# A SPRAYER CALLS THIS: fertilize plowed soil. Returns how many NEW cells got fertilizer.
func fertilize_at(pos: Vector3, radius: float) -> int:
	var id := plot_at(pos)
	if id == "":
		return 0
	var r: Rect2 = plots[id]
	var img: Image = _masks[id]
	var cx := (pos.x - r.position.x) * RES
	var cy := (pos.z - r.position.y) * RES
	var pr := radius * RES
	var painted := false
	for py in range(maxi(0, int(floor(cy - pr))), mini(img.get_height(), int(ceil(cy + pr)) + 1)):
		for px in range(maxi(0, int(floor(cx - pr))), mini(img.get_width(), int(ceil(cx + pr)) + 1)):
			var dx := float(px) + 0.5 - cx
			var dy := float(py) + 0.5 - cy
			if dx * dx + dy * dy <= pr * pr:
				var oc := img.get_pixel(px, py)
				if oc.r > 0.5 and oc.g < 0.5:
					img.set_pixel(px, py, Color(1.0, 1.0, 0.0))
					painted = true
	if painted:
		_dirty[id] = true
	var til: PackedByteArray = _tilled[id]
	var fert: PackedByteArray = _fert[id]
	var n := 0
	for i in _cell_indices(id, pos, radius):
		if til[i] == 1 and fert[i] == 0:
			fert[i] = 1
			n += 1
	if n > 0:
		_fert[id] = fert
		farm_changed.emit()
	return n


# A SEEDER CALLS THIS: plant crop (index in FarmData.CROP_IDS) on plowed, empty cells. Returns cells planted.
func plant_at(pos: Vector3, radius: float, crop: int, max_cells: int) -> int:
	var id := plot_at(pos)
	if id == "" or max_cells <= 0 or crop <= 0:
		return 0
	var til: PackedByteArray = _tilled[id]
	var arr: PackedByteArray = _crop[id]
	var t0: PackedInt32Array = _t0[id]
	var now := int(Time.get_unix_time_from_system())
	var n := 0
	for i in _cell_indices(id, pos, radius):
		if n >= max_cells:
			break
		if arr[i] == 0 and til[i] == 1:
			arr[i] = crop
			t0[i] = now
			n += 1
	if n > 0:
		_crop[id] = arr
		_t0[id] = t0
		_crop_dirty[id] = true
		farm_changed.emit()
	return n


# A HARVESTER CALLS THIS: cut RIPE crops in the circle, up to max_kg. Returns {product: kg}.
# Harvested cells become empty plowed soil again (fertilizer is used up, repaint it as plain plowed).
func harvest_at(pos: Vector3, radius: float, max_kg: float) -> Dictionary:
	var out := {}
	var id := plot_at(pos)
	if id == "" or max_kg <= 0.0:
		return out
	var arr: PackedByteArray = _crop[id]
	var t0: PackedInt32Array = _t0[id]
	var fert: PackedByteArray = _fert[id]
	var img: Image = _masks[id]
	var cell: float = plot_cell[id]
	var size: Vector2i = _cells[id]
	var now := int(Time.get_unix_time_from_system())
	var left := max_kg
	var n := 0
	var repaint := false
	for i in _cell_indices(id, pos, radius):
		var c: int = arr[i]
		if c == 0:
			continue
		var def: Dictionary = FarmData.CROPS[FarmData.CROP_IDS[c]]
		if float(now - t0[i]) < float(def["grow_sec"]):
			continue
		var kg: float = cell * cell * float(def["yield_fert"] if fert[i] == 1 else def["yield_plain"])
		if kg > left:
			break
		left -= kg
		var prod := String(def["product"])
		out[prod] = float(out.get(prod, 0.0)) + kg
		if fert[i] == 1:
			var col := i % size.x
			var row := i / size.x
			for py in range(int(floor(row * cell * RES)), mini(img.get_height(), int(ceil((row + 1) * cell * RES)))):
				for px in range(int(floor(col * cell * RES)), mini(img.get_width(), int(ceil((col + 1) * cell * RES)))):
					if img.get_pixel(px, py).g > 0.5:
						img.set_pixel(px, py, Color(1.0, 0.0, 0.0))
						repaint = true
		arr[i] = 0
		t0[i] = 0
		fert[i] = 0
		n += 1
	if n > 0:
		_crop[id] = arr
		_t0[id] = t0
		_fert[id] = fert
		_crop_dirty[id] = true
		if repaint:
			_dirty[id] = true
		farm_changed.emit()
	return out


# 0.0 .. 1.0 growth of the crop in a cell (-1 = nothing planted). 1.0 = ripe (the harvester will use this).
func crop_growth(id: String, cell: Vector2i) -> float:
	if not _crop.has(id):
		return -1.0
	var size: Vector2i = _cells[id]
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return -1.0
	var i := cell.y * size.x + cell.x
	var c: int = (_crop[id] as PackedByteArray)[i]
	if c == 0:
		return -1.0
	var def: Dictionary = FarmData.CROPS[FarmData.CROP_IDS[c]]
	var age := Time.get_unix_time_from_system() - float((_t0[id] as PackedInt32Array)[i])
	return clampf(age / float(def["grow_sec"]), 0.0, 1.0)


func is_fertilized(id: String, cell: Vector2i) -> bool:
	if not _fert.has(id):
		return false
	var size: Vector2i = _cells[id]
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return false
	return (_fert[id] as PackedByteArray)[cell.y * size.x + cell.x] == 1


func plot_crop_text(id: String) -> String:
	var s = _crop_stats.get(id)
	if s == null or int(s[0]) == 0:
		return ""
	var size: Vector2i = _cells[id]
	var total := maxi(1, size.x * size.y)
	return "crop %d%%   ripe %d%%" % [int(100.0 * float(s[0]) / float(total)), int(100.0 * float(s[1]) / float(maxi(1, int(s[0]))))]


func _tuft_mesh() -> ArrayMesh:
	if _tuft != null:
		return _tuft
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for k in 2:   # V26: only 2 crossed quads (4 triangles) per crop cell
		var d := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		var a := -d * 0.4
		var b := d * 0.4
		var tb := d * 0.12 + Vector3(0, 1.0, 0)
		var ta := -d * 0.12 + Vector3(0, 1.0, 0)
		for v in [a, b, tb, a, tb, ta]:
			st.add_vertex(v)
	_tuft = st.commit()
	return _tuft


# redraw the crops of one plot (every second while something still grows). Returns true while crops are growing.
func _rebuild_crops(id: String) -> bool:
	var arr: PackedByteArray = _crop[id]
	var t0: PackedInt32Array = _t0[id]
	var r: Rect2 = plots[id]
	var cell: float = plot_cell[id]
	var size: Vector2i = _cells[id]
	var now := Time.get_unix_time_from_system()
	var xf: Array = []
	var cols: Array = []
	var growing := false
	var ripe := 0
	for i in arr.size():
		var c: int = arr[i]
		if c == 0:
			continue
		var def: Dictionary = FarmData.CROPS[FarmData.CROP_IDS[c]]
		var g := clampf((now - float(t0[i])) / float(def["grow_sec"]), 0.0, 1.0)
		if g < 1.0:
			growing = true
		else:
			ripe += 1
		var gx := i % size.x
		var gy := i / size.x
		xf.append(Transform3D(Basis.from_scale(Vector3(cell, 0.15 + 0.85 * g, cell)), Vector3(r.position.x + (gx + 0.5) * cell, 0.04, r.position.y + (gy + 0.5) * cell)))
		cols.append((def["col_young"] as Color).lerp(def["col_ripe"] as Color, g))
	_crop_stats[id] = [xf.size(), ripe]
	var inst: MultiMeshInstance3D = _crop_mm.get(id)
	if inst == null:
		if _crop_mat == null:
			_crop_mat = StandardMaterial3D.new()
			_crop_mat.vertex_color_use_as_albedo = true
			_crop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_crop_mat.roughness = 1.0
		var mm0 := MultiMesh.new()
		mm0.transform_format = MultiMesh.TRANSFORM_3D
		mm0.use_colors = true
		mm0.mesh = _tuft_mesh()
		mm0.instance_count = 0
		inst = MultiMeshInstance3D.new()
		inst.multimesh = mm0
		inst.material_override = _crop_mat
		inst.visibility_range_end = 70.0
		add_child(inst)
		_crop_mm[id] = inst
	var mm := inst.multimesh
	mm.instance_count = xf.size()
	for k in xf.size():
		mm.set_instance_transform(k, xf[k])
		mm.set_instance_color(k, cols[k])
	return growing


# ---- save / load of the soil (the farm calls these)
func _pack(b: PackedByteArray) -> Dictionary:
	return {"n": b.size(), "d": Marshalls.raw_to_base64(b.compress(FileAccess.COMPRESSION_DEFLATE))}


func _unpack(d) -> PackedByteArray:
	if not (d is Dictionary):
		return PackedByteArray()
	var raw := Marshalls.base64_to_raw(String(d.get("d", "")))
	if raw.is_empty():
		return PackedByteArray()
	return raw.decompress(int(d.get("n", 0)), FileAccess.COMPRESSION_DEFLATE)


func save_state() -> Dictionary:
	var out := {}
	for id in plots:
		if int(_tilled_count[id]) == 0:
			continue
		out[id] = {"t": _pack(_tilled[id]), "c": _pack(_crop[id]), "f": _pack(_fert[id]), "s": _pack((_t0[id] as PackedInt32Array).to_byte_array())}
	return out


func load_state(d) -> void:
	if not (d is Dictionary):
		return
	for id in d:
		if not plots.has(id):
			continue
		var size: Vector2i = _cells[id]
		var n := size.x * size.y
		var til := _unpack(d[id].get("t"))
		var crop := _unpack(d[id].get("c"))
		var fert := _unpack(d[id].get("f"))
		var t0 := _unpack(d[id].get("s")).to_int32_array()
		if til.size() != n:
			continue
		_tilled[id] = til
		if crop.size() == n:
			_crop[id] = crop
		if fert.size() == n:
			_fert[id] = fert
		if t0.size() == n:
			_t0[id] = t0
		var cell: float = plot_cell[id]
		var img: Image = _masks[id]
		var cnt := 0
		var fa: PackedByteArray = _fert[id]
		for i in n:
			if til[i] == 1:
				cnt += 1
				var x0 := int(round(float(i % size.x) * cell * RES))
				var y0 := int(round(float(i / size.x) * cell * RES))
				var w := int(ceil(cell * RES))
				img.fill_rect(Rect2i(x0, y0, w, w), Color(1.0, float(fa[i]), 0.0))
		_tilled_count[id] = cnt
		_dirty[id] = true
		_crop_dirty[id] = true


# ---- points on the ground (shop SELL points, warehouse mouths, fertilizer pump)
# V26: parts of buildings farther than this from the camera are not drawn (less lag on the 1000 m map)
func _far_cull(n: Node, dist: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = dist
	for c in n.get_children():
		_far_cull(c, dist)


func _make_pois(type: String, pos: Vector3, rot_deg: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(rot_deg))
	match type:
		"shop":
			_shop_count += 1
			_add_poi({"kind": "shop", "id": _shop_count, "label": "Shop %d" % _shop_count, "r": 5.0, "col": Color(1.0, 0.85, 0.1)}, pos + b * Vector3(1.1, 0, 7.0))
		"seedshop":
			_shop_count += 1
			_add_poi({"kind": "shop", "id": _shop_count, "label": "Seed Shop %d" % _shop_count, "r": 5.0, "col": Color(0.3, 0.9, 0.35)}, pos + b * Vector3(1.1, 0, 7.0))
		"storage":
			_add_poi({"kind": "wh", "id": "wheat", "label": "Wheat", "r": 4.5, "col": Color(0.95, 0.75, 0.2)}, pos + b * Vector3(6, 0, 11))
			_add_poi({"kind": "wh", "id": "rice", "label": "Rice", "r": 4.5, "col": Color(0.97, 0.97, 0.9)}, pos + b * Vector3(-6, 0, 11))
		"fuelstation":
			_add_poi({"kind": "fuel", "id": "fuel", "label": "Fuel", "r": 6.0, "col": Color(1.0, 0.45, 0.1)}, pos + b * Vector3(0, 0, 11.0))
		"ftank":
			_add_poi({"kind": "fert", "id": "fert", "label": "Fertilizer", "r": 6.0, "col": Color(0.2, 0.9, 0.35)}, pos + b * Vector3(0, 0, 9.5))


func _add_poi(d: Dictionary, p: Vector3) -> void:
	d["pos"] = p
	pois.append(d)
	var col: Color = d["col"]
	var tm := TorusMesh.new()
	tm.rings = 20   # V28: default is 64 x 32 = 4096 triangles per ring; this is about 160
	tm.ring_segments = 4
	var ring := Util.mim(tm, Util.glow(col, 1.2))
	(ring.mesh as TorusMesh).inner_radius = float(d["r"]) - 0.7
	(ring.mesh as TorusMesh).outer_radius = float(d["r"])
	ring.scale = Vector3(1, 0.15, 1)
	ring.position = p + Vector3(0, 0.12, 0)
	add_child(ring)
	var pole := Util.mim(Util.cyl(0.1, 3.5, 6), Util.mat(Color(0.25, 0.25, 0.28)))
	pole.position = p + Vector3(0, 1.75, 0)
	add_child(pole)
	var top := Util.mim(Util.sphere(0.45, 10, 5), Util.glow(col, 1.6))
	top.position = p + Vector3(0, 3.8, 0)
	add_child(top)
