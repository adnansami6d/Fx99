extends "res://scripts/trailed.gd"
# SEED PLANTER. Hook it on the rear hitch, press WORK and drive forward over PLOWED soil.
# It uses seed from the farm stock (buy seed in a shop) and plants the crop chosen with the SEED button.
# Tilled + empty cells get the crop; it needs 5 minutes to ripen (grow_sec in farm_data.gd).

const D = preload("res://scripts/farm_data.gd")
const PLANT_R := 1.3
var lift: Node3D
var wheels: Array = []


func _init() -> void:
	label = "SEEDER"
	side = "rear"
	transport_kmh = 40.0
	work_kmh = 12.0
	trail_len = 2.8


func _build() -> void:
	var red := Util.mat(Color(0.75, 0.15, 0.1), 0.5, 0.2)
	var yellow := Util.mat(Color(0.95, 0.76, 0.1), 0.5, 0.2)
	var steel := Util.mat(Color(0.32, 0.34, 0.38), 0.45, 0.7)
	var dark := Util.mat(Color(0.1, 0.1, 0.11), 0.7)
	Util.part(self, Vector3(1.0, 0.16, 0.14), Vector3(0, 0.5, 0.1), red)
	Util.part(self, Vector3(0.14, 0.6, 0.14), Vector3(0, 0.8, 0.1), red)
	_beam(self, Vector3(-0.4, 0.55, 0.1), Vector3(-1.2, 0.7, 1.2), 0.12, red)
	_beam(self, Vector3(0.4, 0.55, 0.1), Vector3(1.2, 0.7, 1.2), 0.12, red)
	Util.part(self, Vector3(2.9, 0.16, 0.22), Vector3(0, 0.7, 1.2), red)
	Util.part(self, Vector3(2.5, 0.7, 0.95), Vector3(0, 1.25, 1.3), yellow)      # seed box
	Util.part(self, Vector3(2.55, 0.08, 1.0), Vector3(0, 1.64, 1.3), dark)       # lid
	lift = Node3D.new()
	lift.position = Vector3(0, 0.7, 1.2)
	add_child(lift)
	for i in 6:
		var x := -1.15 + float(i) * 0.46
		Util.part(lift, Vector3(0.05, 0.62, 0.05), Vector3(x, -0.35, 0.25), steel)
		var disc := Util.mim(Util.cyl(0.2, 0.03, 12), steel)
		disc.rotation_degrees.z = 90.0
		disc.position = Vector3(x, -0.55, 0.35)
		lift.add_child(disc)
	wheels.append(_wheel(Vector3(-1.55, 0.4, 1.2), 0.4, 0.2))
	wheels.append(_wheel(Vector3(1.55, 0.4, 1.2), 0.4, 0.2))
	lift.rotation.x = -0.5


func plant_point() -> Vector3:
	return global_transform * Vector3(0, 0, 1.8)


func _anim(delta: float) -> void:
	lift.rotation.x = lerpf(lift.rotation.x, 0.0 if working else -0.5, clampf(4.0 * delta, 0.0, 1.0))
	for w in wheels:
		w.rotation.x -= ground_speed / 0.4 * delta


func hud_text() -> String:
	var farm = get_tree().get_first_node_in_group("farm")
	if farm == null:
		return ""
	var c: String = farm.selected_crop
	var def: Dictionary = D.CROPS.get(c, {})
	return "SEED: %s  %d kg" % [String(def.get("name", c)), int(float(farm.seeds.get(c, 0.0)))]


func _work(_delta: float, gs: float) -> void:
	if gs < 0.3 or field_map == null or lift.rotation.x < -0.05:
		return
	var farm = get_tree().get_first_node_in_group("farm")
	if farm == null:
		return
	var crop: String = farm.selected_crop
	var def: Dictionary = D.CROPS.get(crop, {})
	if def.is_empty() or not bool(def["ready"]):
		set_working(false)
		farm.message.emit("Choose a seed first (SEED button)")
		return
	var p := plant_point()
	var area: float = field_map.cell_area(p)
	if area <= 0.0:
		return
	var per_cell: float = float(def["seed_kg_m2"]) * area
	var have: float = float(farm.seeds.get(crop, 0.0))
	var n: int = field_map.plant_at(p, PLANT_R, D.CROP_IDS.find(crop), int(have / per_cell))
	if n > 0:
		farm.seeds[crop] = have - float(n) * per_cell
		farm.mark_dirty()
	elif have < per_cell:
		set_working(false)
		farm.message.emit("Out of seed - buy more in a shop")


func extra_state() -> Dictionary:
	return {}
