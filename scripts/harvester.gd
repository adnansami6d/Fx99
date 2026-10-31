extends "res://scripts/implement.gd"
# HARVESTER (tank 300 kg, on the FRONT hitch). Press WORK and drive forward over RIPE wheat / rice:
# it cuts a 4 m strip and collects the grain. Fertilized soil gives double yield.
# Full tank -> drive to a warehouse point (Wheat / Rice) and press UNLOAD.
# cargo: product -> kg

const D = preload("res://scripts/farm_data.gd")
const CUT_R := 2.0
var cargo := {}
var reel: Node3D


func _init() -> void:
	label = "HARVESTER"
	side = "front"
	transport_kmh = 35.0
	work_kmh = 8.0


func _build() -> void:
	var red := Util.mat(Color(0.8, 0.12, 0.1), 0.5, 0.2)
	var yellow := Util.mat(Color(0.95, 0.76, 0.1), 0.5, 0.2)
	var steel := Util.mat(Color(0.32, 0.34, 0.38), 0.45, 0.7)
	Util.part(self, Vector3(1.0, 0.16, 0.14), Vector3(0, 0.5, 0.1), yellow)
	Util.part(self, Vector3(0.16, 0.16, 1.6), Vector3(0, 0.62, 0.9), yellow)
	Util.part(self, Vector3(1.6, 0.9, 1.4), Vector3(0, 1.1, 1.6), red)            # grain tank
	Util.part(self, Vector3(1.7, 0.08, 1.5), Vector3(0, 1.58, 1.6), steel)
	Util.part(self, Vector3(4.0, 0.14, 0.9), Vector3(0, 0.45, 2.7), steel)        # cutter bar
	Util.part(self, Vector3(4.0, 0.5, 0.06), Vector3(0, 0.75, 3.1), yellow)
	for sx in [-2.0, 2.0]:
		Util.part(self, Vector3(0.06, 0.5, 0.9), Vector3(sx, 0.75, 2.7), yellow)
	reel = Node3D.new()
	reel.position = Vector3(0, 1.0, 2.9)
	add_child(reel)
	var drum := Util.mim(Util.cyl(0.3, 3.8, 10), yellow)
	drum.rotation_degrees.z = 90.0
	reel.add_child(drum)
	Util.part(reel, Vector3(3.8, 0.7, 0.05), Vector3.ZERO, steel)


func cut_point() -> Vector3:
	return global_transform * Vector3(0, 0, 2.8)


func bed_center() -> Vector3:
	return global_transform * Vector3(0, 0, 1.6)


func total() -> float:
	var t := 0.0
	for k in cargo:
		t += float(cargo[k])
	return t


func take(prod: String, kg: float) -> float:
	var have := float(cargo.get(prod, 0.0))
	var t := minf(kg, have)
	if t <= 0.0:
		return 0.0
	cargo[prod] = have - t
	if float(cargo[prod]) <= 0.001:
		cargo.erase(prod)
	return t


func _animate(delta: float) -> void:
	if working and ground_speed > 0.3:
		reel.rotation.x += 6.0 * delta


func hud_text() -> String:
	return "HARVESTER: %d / %d kg" % [int(total()), int(D.HARVESTER_CAP)]


func _work(_delta: float, gs: float) -> void:
	var farm = get_tree().get_first_node_in_group("farm")
	if gs < 0.3 or field_map == null:
		return
	var room: float = D.HARVESTER_CAP - total()
	var got: Dictionary = field_map.harvest_at(cut_point(), CUT_R, room)
	for k in got:
		cargo[k] = float(cargo.get(k, 0.0)) + float(got[k])
	if D.HARVESTER_CAP - total() < 3.0:
		set_working(false)
		if farm != null:
			farm.message.emit("Harvester full - go to a warehouse and UNLOAD")


func extra_state() -> Dictionary:
	return {"cargo": cargo}


func load_extra(d: Dictionary) -> void:
	cargo = {}
	var c = d.get("cargo")
	if c is Dictionary:
		for k in c:
			cargo[String(k)] = float(c[k])
