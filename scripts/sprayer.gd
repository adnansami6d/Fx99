extends "res://scripts/implement.gd"
# FERTILIZER SPRAYER (tank on the FRONT hitch, so it works together with a plow / seeder on the rear).
# Fill it at the green FILL point of the big fertilizer tank (500 coins per full 30 L tank).
# WORK ON + drive forward: sprays a 6 m strip over PLOWED soil. 3 L per 10 shotok. Fertilized soil turns darker.

const D = preload("res://scripts/farm_data.gd")
const SPRAY_R := 3.0
var liters := 0.0
var cones: Array = []


func _init() -> void:
	label = "SPRAYER"
	side = "front"
	transport_kmh = 40.0
	work_kmh = 10.0


func _build() -> void:
	var green := Util.mat(Color(0.2, 0.55, 0.3), 0.5, 0.3)
	var steel := Util.mat(Color(0.32, 0.34, 0.38), 0.45, 0.7)
	var yellow := Util.mat(Color(0.95, 0.76, 0.1), 0.5, 0.2)
	var spray_m := Util.mat(Color(0.55, 0.85, 1.0, 0.4), 0.2)
	Util.part(self, Vector3(1.0, 0.16, 0.14), Vector3(0, 0.5, 0.1), yellow)
	Util.part(self, Vector3(0.16, 0.16, 1.6), Vector3(0, 0.62, 0.9), yellow)
	Util.part(self, Vector3(1.5, 0.12, 0.8), Vector3(0, 0.72, 1.6), steel)
	for sx in [-0.6, 0.6]:
		Util.part(self, Vector3(0.1, 0.5, 0.1), Vector3(sx, 0.95, 1.6), steel)
	var tank := Util.mim(Util.cyl(0.55, 1.8, 16), green)
	tank.rotation_degrees.z = 90.0
	tank.position = Vector3(0, 1.3, 1.6)
	add_child(tank)
	Util.part(self, Vector3(0.3, 0.12, 0.3), Vector3(0, 1.88, 1.6), steel)       # filler cap
	Util.part(self, Vector3(0.12, 0.12, 1.2), Vector3(0, 0.95, 2.3), steel)
	Util.part(self, Vector3(6.0, 0.08, 0.08), Vector3(0, 0.9, 2.8), steel)        # boom
	var i := 0
	while i < 7:
		var x := -2.7 + float(i) * 0.9
		Util.part(self, Vector3(0.08, 0.14, 0.08), Vector3(x, 0.8, 2.8), yellow)
		var c := Util.mim(Util.cone(0.3, 0.8, 6), spray_m)
		c.rotation_degrees.x = 180.0
		c.position = Vector3(x, 0.4, 2.8)
		c.visible = false
		c.set_meta("nobake", true)
		add_child(c)
		cones.append(c)
		i += 1


func spray_point() -> Vector3:
	return global_transform * Vector3(0, 0, 2.8)


func _animate(_delta: float) -> void:
	var on := working and liters > 0.05 and ground_speed > 0.3
	for c in cones:
		c.visible = on


func hud_text() -> String:
	return "FERT: %.1f / %d L" % [liters, int(D.TANK_L)]


func _work(_delta: float, gs: float) -> void:
	var farm = get_tree().get_first_node_in_group("farm")
	if liters <= 0.05:
		liters = 0.0
		set_working(false)
		if farm != null:
			farm.message.emit("Tank empty - go to the green FILL point")
		return
	if gs < 0.3 or field_map == null:
		return
	var p := spray_point()
	var n: int = field_map.fertilize_at(p, SPRAY_R)
	if n > 0:
		liters = maxf(0.0, liters - float(n) * field_map.cell_area(p) * D.FERT_L_M2)


func extra_state() -> Dictionary:
	return {"liters": liters}


func load_extra(d: Dictionary) -> void:
	liters = clampf(float(d.get("liters", 0.0)), 0.0, D.TANK_L)
