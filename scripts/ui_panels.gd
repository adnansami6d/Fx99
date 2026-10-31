extends Control
# Pop-up screens: MENU, PRICES, FARM VIEW, SHOP, SEED choice + the small message at the bottom.
# ui.open("menu" | "price" | "farm" | "shop" | "seed", {data}).  New screen = new branch in _rebuild().

signal edit_requested
signal map_requested

const D = preload("res://scripts/farm_data.gd")

var farm
var main
var mode := ""
var ctx := {}
var _dim: ColorRect
var _title: Label
var _list: VBoxContainer
var _toast: Label
var _toast_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.add_child(cc)
	var panel := PanelContainer.new()
	cc.add_child(panel)
	var pad := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(s, 18)
	panel.add_child(pad)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(780, 0)
	box.add_theme_constant_override("separation", 10)
	pad.add_child(box)
	_title = _lab("", 38)
	box.add_child(_title)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 400)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	sc.add_child(_list)
	box.add_child(_btn("CLOSE", close))
	_toast = _lab("", 32)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = -450.0
	_toast.offset_right = 450.0
	_toast.offset_top = -200.0
	_toast.offset_bottom = -140.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	add_child(_toast)


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)


func is_open() -> bool:
	return _dim != null and _dim.visible


func open(kind: String, data: Dictionary = {}) -> void:
	mode = kind
	ctx = data
	_dim.visible = true
	_rebuild()


func close() -> void:
	_dim.visible = false
	mode = ""


func refresh() -> void:
	if is_open():
		_rebuild()


func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_t = 2.8


func _lab(text: String, fs: int = 28) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	return l


func _btn(text: String, cb: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 72)
	b.add_theme_font_size_override("font_size", 30)
	b.disabled = not enabled
	b.pressed.connect(cb)
	return b


func _row(text: String, btn_text: String, cb: Callable, enabled: bool = true) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := _lab(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var b := _btn(btn_text, cb, enabled)
	b.custom_minimum_size = Vector2(150, 64)
	h.add_child(b)
	return h


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	match mode:
		"menu":
			_menu()
		"price":
			_prices()
		"farm":
			_farm_view()
		"shop":
			_shop()
		"seed":
			_seed()


func _go_map() -> void:
	close()
	map_requested.emit()


func _go_edit() -> void:
	close()
	edit_requested.emit()


func _menu() -> void:
	_title.text = "MENU"
	_list.add_child(_btn("Prices", open.bind("price")))
	_list.add_child(_btn("Farm view", open.bind("farm")))
	_list.add_child(_btn("Full map", _go_map))
	_list.add_child(_btn("Button layout (SET)", _go_edit))


func _prices() -> void:
	_title.text = "PRICES  (coins per kg)"
	for pid in D.PRODUCTS:
		var best := 0.0
		var best_shop := 0
		for s in range(1, farm.shop_count + 1):
			var pr: float = farm.price(s, pid)
			if pr > best:
				best = pr
				best_shop = s
		_list.add_child(_lab("Best for %s: Shop %d  (%d)" % [D.PRODUCTS[pid]["name"], best_shop, int(best)], 30))
	for cid in D.CROPS:
		var cd: Dictionary = D.CROPS[cid]
		_list.add_child(_lab("%s seed: %d coins / kg  (every shop)" % [cd["name"], int(cd["seed_price"])]))
	_list.add_child(_lab("Fertilizer: %d coins per full tank (%d L)" % [int(D.TANK_PRICE), int(D.TANK_L)]))
	for s in range(1, farm.shop_count + 1):
		var line := "Shop %d" % s
		for pid in D.PRODUCTS:
			line += "     %s %d" % [D.PRODUCTS[pid]["name"], int(farm.price(s, pid))]
		_list.add_child(_lab(line))


func _farm_view() -> void:
	_title.text = "FARM VIEW"
	_list.add_child(_lab("Coins: %d" % int(farm.coins), 36))
	_list.add_child(_lab("WAREHOUSE   (tr = load on trailer)", 30))
	for pid in D.PRODUCTS:
		var kg: float = farm.stock_of(pid)
		_list.add_child(_row("%s   %d kg" % [D.PRODUCTS[pid]["name"], int(kg)], "tr", _load_tr.bind(pid), kg > 0.5))
	_list.add_child(_lab(main.trailer_text()))
	_list.add_child(_lab("SEEDS", 30))
	for cid in D.CROPS:
		var cd: Dictionary = D.CROPS[cid]
		var extra := "" if bool(cd["ready"]) else "   (not ready)"
		_list.add_child(_lab("%s seed   %d kg%s" % [cd["name"], int(float(farm.seeds.get(cid, 0.0))), extra]))
	_list.add_child(_btn("TEST: +200 kg wheat to warehouse", _test_wheat))


func _load_tr(pid: String) -> void:
	main.load_trailer(pid)
	_rebuild()


func _test_wheat() -> void:
	farm.add_stock("wheat", 200.0)


func _shop() -> void:
	var idx := int(ctx.get("shop", 1))
	_title.text = "SHOP %d" % idx
	_list.add_child(_lab("Coins: %d" % int(farm.coins), 34))
	var tr = main.trailer_near_shop(idx)
	if tr != null and tr.total() > 0.5:
		var sum := 0.0
		for pid in tr.cargo:
			var kg: float = tr.cargo[pid]
			var pr: float = farm.price(idx, pid)
			sum += kg * pr
			_list.add_child(_lab("%s   %d kg  x  %d" % [D.PRODUCTS[pid]["name"], int(kg), int(pr)]))
		_list.add_child(_btn("SELL ALL   +%d coins" % int(sum), _sell.bind(idx)))
	else:
		_list.add_child(_lab("To sell: bring the loaded trailer to the yellow SELL point."))
		var line := "Prices here:"
		for pid in D.PRODUCTS:
			line += "   %s %d" % [D.PRODUCTS[pid]["name"], int(farm.price(idx, pid))]
		_list.add_child(_lab(line))
	_list.add_child(_lab("BUY SEEDS", 30))
	for cid in D.CROPS:
		var cd: Dictionary = D.CROPS[cid]
		if not bool(cd["ready"]):
			continue
		for kgx in [10, 50]:
			_list.add_child(_btn("Buy %d kg %s seed   (%d coins)" % [kgx, cd["name"], int(float(kgx) * float(cd["seed_price"]))], _buy.bind(cid, float(kgx))))


func _sell(idx: int) -> void:
	var tr = main.trailer_near_shop(idx)
	if tr != null:
		farm.sell_cargo(idx, tr)
	_rebuild()


func _buy(cid: String, kg: float) -> void:
	farm.buy_seed(cid, kg)
	_rebuild()


func _seed() -> void:
	_title.text = "CHOOSE SEED"
	for cid in D.CROPS:
		var cd: Dictionary = D.CROPS[cid]
		var have := int(float(farm.seeds.get(cid, 0.0)))
		if bool(cd["ready"]):
			var mark := ">> " if farm.selected_crop == cid else ""
			_list.add_child(_btn("%s%s   (seed %d kg)" % [mark, cd["name"], have], _pick.bind(cid)))
		else:
			_list.add_child(_btn("%s   (not ready yet)" % cd["name"], _pick.bind(cid), false))


func _pick(cid: String) -> void:
	farm.selected_crop = cid
	farm.mark_dirty()
	toast("Seed: %s" % String(D.CROPS[cid]["name"]))
	close()
