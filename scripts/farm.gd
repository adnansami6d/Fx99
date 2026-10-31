extends Node
# Money, warehouse stock and seeds. Found by group "farm". Saves itself to user://farm.json
# (it also saves the soil of the map: plowed / fertilized / planted cells).

const D = preload("res://scripts/farm_data.gd")
const SAVE_PATH := "user://farm.json"

signal message(text: String)
signal changed

var coins := D.START_COINS
var stock := {}          # product -> kg in the warehouse
var seeds := {}          # crop -> kg of seed
var selected_crop := "wheat"
var shop_count := 0
var map = null
var _dirty := false
var _t := 0.0


func _ready() -> void:
	add_to_group("farm")


func setup(m) -> void:
	map = m
	var pois = m.get("pois")
	if pois is Array:
		for p in pois:
			if String(p["kind"]) == "shop":
				shop_count += 1
	if m.has_signal("farm_changed"):
		m.farm_changed.connect(mark_dirty)
	load_all()


func _process(delta: float) -> void:
	_t += delta
	if _dirty and _t > 6.0:
		save_all()


func mark_dirty() -> void:
	_dirty = true


func _touch() -> void:
	_dirty = true
	changed.emit()


# price of a product in a shop (the same every time, different between shops)
func price(shop: int, product: String) -> float:
	var def: Dictionary = D.PRODUCTS.get(product, {})
	if def.is_empty():
		return 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = shop * 7919 + product.hash()
	return float(int(rng.randf_range(float(def["min"]), float(def["max"]))))


func stock_of(product: String) -> float:
	return float(stock.get(product, 0.0))


func add_stock(product: String, kg: float) -> void:
	stock[product] = stock_of(product) + kg
	_touch()


func take_stock(product: String, kg: float) -> void:
	stock[product] = maxf(0.0, stock_of(product) - kg)
	_touch()


func buy_seed(crop: String, kg: float) -> void:
	var def: Dictionary = D.CROPS.get(crop, {})
	if def.is_empty():
		return
	var cost := ceilf(kg * float(def["seed_price"]))
	if coins < cost:
		message.emit("Not enough coins")
		return
	coins -= cost
	seeds[crop] = float(seeds.get(crop, 0.0)) + kg
	message.emit("Bought %d kg %s seed" % [int(kg), String(def["name"])])
	_touch()


# sell everything that is on the trailer in this shop
func sell_cargo(shop: int, trailer) -> void:
	var total := 0.0
	var sold := 0.0
	for prod in trailer.cargo.keys():
		var kg: float = trailer.cargo[prod]
		total += kg * price(shop, String(prod))
		sold += kg
	if sold <= 0.0:
		message.emit("Trailer is empty")
		return
	trailer.clear_cargo()
	coins += total
	message.emit("Sold %d kg   +%d coins" % [int(sold), int(total)])
	_touch()


# fill the sprayer tank at the fertilizer pump (pays only for what is missing)
func fill_sprayer(sp) -> void:
	if sp == null:
		return
	var need: float = D.TANK_L - sp.liters
	if need < 0.5:
		message.emit("Tank is already full")
		return
	var cost := ceilf(need * D.TANK_PRICE / D.TANK_L)
	if coins < cost:
		message.emit("Need %d coins for fertilizer" % int(cost))
		return
	coins -= cost
	sp.liters = D.TANK_L
	message.emit("Tank filled (%d L)   -%d coins" % [int(D.TANK_L), int(cost)])
	_touch()


func save_all() -> void:
	_dirty = false
	_t = 0.0
	var d := {"coins": coins, "stock": stock, "seeds": seeds, "sel": selected_crop}
	if map != null and map.has_method("save_state"):
		d["map"] = map.save_state()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


func load_all() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	coins = float(d.get("coins", coins))
	var s = d.get("stock")
	if s is Dictionary:
		stock = s
	var sd = d.get("seeds")
	if sd is Dictionary:
		seeds = sd
	selected_crop = String(d.get("sel", selected_crop))
	if d.has("map") and map != null and map.has_method("load_state"):
		map.load_state(d["map"])
