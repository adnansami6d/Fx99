extends RefCounted
# Builds a cartoon person (big round head, capsule body, big eyes, boots) from primitive shapes.
# Feet at y = 0, about 1.52 m tall, the face looks to -Z. Returns the four swinging limb joints.

const Util = preload("res://scripts/util.gd")
static var _mats := {}
static var _meshes := {}


# toon-shaded material; with outline = a black rim is drawn around the shape
static func _m(color: Color, outline: bool) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(false), outline]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if outline:
		var o := StandardMaterial3D.new()
		o.albedo_color = Color(0.05, 0.04, 0.06)
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.grow = true
		o.grow_amount = 0.012
		m.next_pass = o
	_mats[key] = m
	return m


static func _sph(r: float) -> Mesh:
	var key := "s%s" % r
	if not _meshes.has(key):
		_meshes[key] = Util.sphere(r, 14, 7)
	return _meshes[key]


static func _cap(r: float, h: float) -> Mesh:
	var key := "c%s_%s" % [r, h]
	if not _meshes.has(key):
		var c := CapsuleMesh.new()
		c.radius = r
		c.height = h
		c.radial_segments = 12
		c.rings = 4
		_meshes[key] = c
	return _meshes[key]


static func _cyl(r: float, h: float) -> Mesh:
	var key := "y%s_%s" % [r, h]
	if not _meshes.has(key):
		_meshes[key] = Util.cyl(r, h, 14)
	return _meshes[key]


static func _box(x: float, y: float, z: float) -> Mesh:
	var key := "b%s_%s_%s" % [x, y, z]
	if not _meshes.has(key):
		_meshes[key] = Util.box(Vector3(x, y, z))
	return _meshes[key]


static func _add(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, outline: bool, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = _m(color, outline)
	n.position = pos
	n.scale = scl
	n.rotation_degrees = rot
	parent.add_child(n)
	return n


static func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


# o: skin, shirt, pants, boots, hair, hat ("cap" / "helmet" / "none"), hat_col, bandana, angry, pack, outline
static func build(model: Node3D, o: Dictionary) -> Dictionary:
	var skin: Color = o.get("skin", Color(0.96, 0.8, 0.66))
	var shirt: Color = o.get("shirt", Color(0.2, 0.55, 0.9))
	var pants: Color = o.get("pants", Color(0.25, 0.28, 0.4))
	var boots: Color = o.get("boots", Color(0.4, 0.26, 0.15))
	var hair: Color = o.get("hair", Color(0.25, 0.15, 0.08))
	var hat: String = o.get("hat", "cap")
	var hat_col: Color = o.get("hat_col", Color(0.9, 0.2, 0.2))
	var bandana: bool = o.get("bandana", false)
	var angry: bool = o.get("angry", false)
	var ol: bool = o.get("outline", false)
	var dark := Color(0.08, 0.06, 0.07)

	# body
	_add(model, _cap(0.17, 0.54), shirt, Vector3(0, 0.88, 0), ol)
	_add(model, _cyl(0.178, 0.05), Color(0.18, 0.13, 0.09), Vector3(0, 0.67, 0), ol)
	_add(model, _box(0.06, 0.05, 0.02), Color(0.95, 0.8, 0.25), Vector3(0, 0.67, -0.18), false)
	if o.get("pack", false):
		_add(model, _sph(0.16), Color(0.35, 0.4, 0.22), Vector3(0, 0.94, 0.19), ol, Vector3(0.9, 1.1, 0.55))

	# head
	_add(model, _sph(0.2), skin, Vector3(0, 1.31, 0), ol, Vector3(1, 0.96, 1))
	for sx in [-1.0, 1.0]:
		_add(model, _sph(0.045), skin, Vector3(sx * 0.2, 1.3, 0.01), false, Vector3(0.6, 1, 1))       # ears
		_add(model, _sph(0.05), Color(1, 1, 1), Vector3(sx * 0.075, 1.335, -0.172), false, Vector3(1, 1.2, 0.6))   # eye white
		_add(model, _sph(0.028), dark, Vector3(sx * 0.075, 1.335, -0.19), false, Vector3(1, 1.2, 0.6))             # pupil
		if angry:
			_add(model, _box(0.085, 0.018, 0.015), dark, Vector3(sx * 0.075, 1.41, -0.18), false, Vector3.ONE, Vector3(0, 0, -sx * 22.0))
		else:
			_add(model, _sph(0.035), Color(1.0, 0.6, 0.6), Vector3(sx * 0.125, 1.26, -0.15), false, Vector3(1, 0.7, 0.4))   # cheeks
	_add(model, _sph(0.03), skin.darkened(0.08), Vector3(0, 1.29, -0.2), false)                                   # nose
	if bandana:
		_add(model, _cyl(0.19, 0.08), Color(0.8, 0.12, 0.1), Vector3(0, 1.2, 0), ol)
		_add(model, _sph(0.05), Color(0.8, 0.12, 0.1), Vector3(0.1, 1.17, 0.17), false)                           # knot
	else:
		_add(model, _box(0.075, 0.014, 0.01), Color(0.6, 0.15, 0.15), Vector3(0, 1.225, -0.198), false)          # smile

	# hair / hat
	if hat == "helmet":
		_add(model, _sph(0.225), hat_col, Vector3(0, 1.385, 0), ol, Vector3(1, 0.72, 1.02))
	else:
		_add(model, _sph(0.21), hair, Vector3(0, 1.37, 0.035), ol, Vector3(1, 0.7, 1))
		if hat == "cap":
			_add(model, _sph(0.215), hat_col, Vector3(0, 1.41, 0.0), ol, Vector3(1, 0.55, 1.02))
			_add(model, _box(0.24, 0.025, 0.15), hat_col, Vector3(0, 1.39, -0.23), ol)

	# arms (joint at the shoulder, the arm hangs below it so rotating the joint swings it)
	var arm_l := _joint(model, Vector3(-0.25, 1.1, 0))
	var arm_r := _joint(model, Vector3(0.25, 1.1, 0))
	for a in [arm_l, arm_r]:
		_add(a, _cap(0.06, 0.46), shirt, Vector3(0, -0.2, 0), ol)
		_add(a, _sph(0.07), skin, Vector3(0, -0.44, 0), false)

	# legs + boots
	var leg_l := _joint(model, Vector3(-0.085, 0.63, 0))
	var leg_r := _joint(model, Vector3(0.085, 0.63, 0))
	for l in [leg_l, leg_r]:
		_add(l, _cap(0.08, 0.56), pants, Vector3(0, -0.27, 0), ol)
		_add(l, _sph(0.095), boots, Vector3(0, -0.57, -0.03), ol, Vector3(1, 0.7, 1.5))

	return {"arm_l": arm_l, "arm_r": arm_r, "leg_l": leg_l, "leg_r": leg_r}
