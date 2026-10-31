extends RefCounted
# Small helpers shared by all scripts.
# Use:  const Util = preload("res://scripts/util.gd")   then   Util.mi(...)

# Size of every character (player + bandits). 1.0 = old size (player 5 ft). One place to change it.
const CHAR_SCALE := 1.115   # V29: 1.524 m * 1.115 = 1.7 m (Free Fire-like height)

static var _mats := {}


# one shared material per look (cheap on phones). Never change a material you got from here.
static func mat(color: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [color.to_html(true), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


# glowing material (lights, beacon)
static func glow(color: Color, energy: float = 1.5) -> StandardMaterial3D:
	var key := "glow_%s_%s" % [color.to_html(true), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


static func mi(mesh: Mesh, color: Color, rough: float = 0.85, metal: float = 0.0) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat(color, rough, metal)
	return n


# MeshInstance3D with a ready made material
static func mim(mesh: Mesh, material: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = material
	return n


# DRAW-CALL SAVER: merges all plain MeshInstance3D leaves that share a material into ONE mesh (per parent node).
# Works recursively, so wheels / discs that spin still spin (their parent node is untouched).
# A mesh you still need to change later: node.set_meta("nobake", true) before calling this.
static func bake(root: Node) -> void:
	var groups := {}
	var dead: Array = []
	for c in root.get_children():
		if c is MeshInstance3D and c.get_child_count() == 0 and c.mesh != null and c.material_override != null and not c.get_meta("nobake", false) and c.mesh.get_surface_count() > 0:
			var m: Material = c.material_override
			if not groups.has(m):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[m] = st
			(groups[m] as SurfaceTool).append_from(c.mesh, 0, c.transform)
			dead.append(c)
		elif c is Node3D and not c.get_meta("nobake", false):
			bake(c)
	if dead.size() < 2:
		return
	for c in dead:
		root.remove_child(c)
		c.queue_free()
	for m in groups:
		var mi := MeshInstance3D.new()
		mi.mesh = (groups[m] as SurfaceTool).commit()
		mi.material_override = m
		root.add_child(mi)


# box mesh instance placed at pos (shortcut for the many small parts)
static func part(parent: Node, size: Vector3, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var n := mim(box(size), material)
	n.position = pos
	n.rotation_degrees = rot_deg
	parent.add_child(n)
	return n


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func sphere(r: float, radial: int = 16, rings: int = 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = radial
	s.rings = rings
	return s


static func cyl(r: float, h: float, radial: int = 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = radial
	c.rings = 1
	return c


static func cone(r: float, h: float, radial: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = radial
	c.rings = 1
	return c


const CHUNK := 50.0     # big groups are split into 50 m squares
const VIS_END := 175.0  # a square is hidden when its center is farther than this (camera far = 160)


# many copies of one mesh. Big groups (trees, bushes ...) are split into chunks that hide themselves when far away.
static func multi(parent: Node, mesh: Mesh, material: Material, xforms: Array, colors: Array = []) -> MultiMeshInstance3D:
	var use_col := colors.size() == xforms.size() and colors.size() > 0
	if xforms.size() < 60:
		return _multi_one(parent, mesh, material, xforms, colors if use_col else [], Vector3.ZERO, false)
	var groups := {}
	for i in xforms.size():
		var o: Vector3 = xforms[i].origin
		var key := Vector2i(floori(o.x / CHUNK), floori(o.z / CHUNK))
		if not groups.has(key):
			groups[key] = [[], []]
		groups[key][0].append(xforms[i])
		if use_col:
			groups[key][1].append(colors[i])
	var last: MultiMeshInstance3D = null
	for key in groups:
		var center := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
		var xs: Array = []
		for t in groups[key][0]:
			xs.append(Transform3D(t.basis, t.origin - center))
		last = _multi_one(parent, mesh, material, xs, groups[key][1], center, true)
	return last


static func _multi_one(parent: Node, mesh: Mesh, material: Material, xforms: Array, colors: Array, pos: Vector3, far_hide: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() == xforms.size() and colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = material
	inst.position = pos
	if far_hide:
		inst.visibility_range_end = VIS_END
	parent.add_child(inst)
	return inst


# material that reads the per-copy color of a MultiMesh
static func vcol_mat(rough: float = 0.9) -> StandardMaterial3D:
	var key := "vcol_%s" % rough
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	_mats[key] = m
	return m


static func add_env(parent: Node) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.78, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true   # hides the far edge (camera far = 160 m)
	env.fog_light_color = env.background_color
	env.fog_density = 0.006
	we.environment = env
	parent.add_child(we)


static func add_sun(parent: Node) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	parent.add_child(sun)
