extends "res://scripts/trailed.gd"
# TRAILER (800 kg). Hook it on the rear hitch. Load a product with the "tr" button in FARM VIEW (menu),
# drive to a shop SELL point and sell, or to a warehouse point (wheat / rice) and UNLOAD slowly.
# cargo: product -> kg

const D = preload("res://scripts/farm_data.gd")
var cargo := {}
var pile: MeshInstance3D
var wheels: Array = []


func _init() -> void:
	label = "TRAILER"
	side = "rear"
	transport_kmh = 45.0
	work_kmh = 45.0
	trail_len = 4.5
	max_swing = 0.8


func _build() -> void:
	var blue := Util.mat(Color(0.15, 0.35, 0.6), 0.5, 0.3)
	var wood := Util.mat(Color(0.55, 0.4, 0.22), 0.9)
	var steel := Util.mat(Color(0.3, 0.32, 0.36), 0.45, 0.7)
	_beam(self, Vector3(0, 0.5, 0.0), Vector3(-0.55, 0.8, 1.6), 0.1, steel)
	_beam(self, Vector3(0, 0.5, 0.0), Vector3(0.55, 0.8, 1.6), 0.1, steel)
	Util.part(self, Vector3(2.3, 0.18, 5.2), Vector3(0, 0.85, 4.0), steel)
	Util.part(self, Vector3(2.3, 0.08, 5.2), Vector3(0, 0.97, 4.0), wood)
	for sx in [-1.15, 1.15]:
		Util.part(self, Vector3(0.08, 0.8, 5.2), Vector3(sx, 1.4, 4.0), blue)
	Util.part(self, Vector3(2.3, 0.8, 0.08), Vector3(0, 1.4, 1.4), blue)
	Util.part(self, Vector3(2.3, 0.8, 0.08), Vector3(0, 1.4, 6.6), blue)
	wheels.append(_wheel(Vector3(-1.25, 0.55, 5.0), 0.55, 0.35))
	wheels.append(_wheel(Vector3(1.25, 0.55, 5.0), 0.55, 0.35))
	pile = Util.mi(Util.box(Vector3.ONE), D.PRODUCTS["wheat"]["col"])
	pile.set_meta("nobake", true)
	add_child(pile)
	_refresh()


func bed_center() -> Vector3:
	return global_transform * Vector3(0, 0, 4.0)


func total() -> float:
	var t := 0.0
	for k in cargo:
		t += float(cargo[k])
	return t


func add(prod: String, kg: float) -> float:
	var ok := minf(kg, D.TRAILER_CAP - total())
	if ok <= 0.0:
		return 0.0
	cargo[prod] = float(cargo.get(prod, 0.0)) + ok
	_refresh()
	return ok


func take(prod: String, kg: float) -> float:
	var have := float(cargo.get(prod, 0.0))
	var t := minf(kg, have)
	if t <= 0.0:
		return 0.0
	cargo[prod] = have - t
	if float(cargo[prod]) <= 0.001:
		cargo.erase(prod)
	_refresh()
	return t


func clear_cargo() -> void:
	cargo.clear()
	_refresh()


func _refresh() -> void:
	if pile == null:
		return
	var t := total()
	pile.visible = t > 1.0
	var h := 0.05 + 0.75 * t / D.TRAILER_CAP
	pile.scale = Vector3(2.1, h, 4.9)
	pile.position = Vector3(0, 1.01 + h * 0.5, 4.0)
	var best := ""
	var best_kg := 0.0
	for k in cargo:
		if float(cargo[k]) > best_kg:
			best_kg = float(cargo[k])
			best = String(k)
	if best != "" and D.PRODUCTS.has(best):
		pile.material_override = Util.mat(D.PRODUCTS[best]["col"])


func _anim(delta: float) -> void:
	for w in wheels:
		w.rotation.x -= ground_speed / 0.55 * delta


func hud_text() -> String:
	return "TRAILER: %d / %d kg" % [int(total()), int(D.TRAILER_CAP)]


func extra_state() -> Dictionary:
	return {"cargo": cargo}


func load_extra(d: Dictionary) -> void:
	cargo = {}
	var c = d.get("cargo")
	if c is Dictionary:
		for k in c:
			cargo[String(k)] = float(c[k])
	_refresh()
