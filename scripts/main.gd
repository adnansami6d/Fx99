extends Node3D
# FX001APK main: start menu -> loads chosen map + character -> game.

const Util = preload("res://scripts/util.gd")
const PlayerScript = preload("res://scripts/player.gd")
const CameraRigScript = preload("res://scripts/camera_rig.gd")
const TouchScript = preload("res://scripts/touch_controls.gd")
const Catalog = preload("res://scripts/catalog.gd")
const LoadingScript = preload("res://scripts/loading.gd")
const DefaultMapScript = preload("res://scripts/default_map.gd")
const TractorScript = preload("res://scripts/tractor.gd")
const HeliScript = preload("res://scripts/helicopter.gd")
const HeliUiScript = preload("res://scripts/heli_ui.gd")
const PlowScript = preload("res://scripts/plow.gd")
const MinimapScript = preload("res://scripts/minimap.gd")
const FarmScript = preload("res://scripts/farm.gd")
const UiScript = preload("res://scripts/ui_panels.gd")
const SeederScript = preload("res://scripts/seeder.gd")
const SprayerScript = preload("res://scripts/sprayer.gd")
const TrailerScript = preload("res://scripts/trailer.gd")
const HarvesterScript = preload("res://scripts/harvester.gd")
const D = preload("res://scripts/farm_data.gd")
const CombatScript = preload("res://scripts/combat.gd")
const MARK_LETTER := {"plow": "P", "seeder": "S", "trailer": "T", "sprayer": "F", "harvester": "H"}
const MARK_COL := {"plow": Color(1.0, 0.6, 0.2), "seeder": Color(0.95, 0.35, 0.3), "trailer": Color(0.45, 0.7, 1.0), "sprayer": Color(0.4, 0.95, 0.5), "harvester": Color(0.95, 0.85, 0.2)}

var layer: CanvasLayer
var loader
var _game_ready := false
var player
var rig
var touch
var tractor
var driving := false
var flying := false
var heli
var heli_ui
var map_node
var minimap
var hud
var speed_label: Label
var horn: AudioStreamPlayer
var impls: Array = []      # every machine you can hook on (plow, seeder, trailer, sprayer)
var trailer
var seeder
var sprayer
var harvester
var farm
var ui
var coin_label: Label
var combat
var poi := {}              # the point you are standing at (shop / warehouse / pump), {} = none
var unload_prod := ""
var _save_ready := false
const SAVE_PATH := "user://save.json"


func _ready() -> void:
	randomize()
	get_viewport().scaling_3d_scale = 0.75   # lighter graphics (1.0 = full)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	layer = CanvasLayer.new()
	add_child(layer)
	loader = LoadingScript.new()
	layer.add_child(loader)
	loader.set_progress(0.05, "Loading...")
	await get_tree().create_timer(0.35).timeout   # logo is on screen before the heavy work starts
	# V29: put your character (.glb/.gltf/.tscn) in res://characters/ -> it is used automatically. No file = default character.
	var custom: Array = Catalog.list("res://characters")
	await _start_game(String(custom[0]) if not custom.is_empty() else "", "")
	loader.set_progress(1.0, "Ready")
	await get_tree().create_timer(0.5).timeout
	_game_ready = true
	loader.queue_free()


func _step(p: float, m: String) -> void:
	loader.set_progress(p, m)
	await get_tree().process_frame
	await get_tree().process_frame


# loads a .tscn/.glb and returns it as a Node3D (or null if it fails)
func _load_scene(path: String) -> Node3D:
	if path == "":
		return null
	var res = load(path)
	if res is PackedScene:
		var n = res.instantiate()
		if n is Node3D:
			return n
		n.queue_free()
	push_warning("Could not load: " + path)
	return null


func _start_game(char_path: String, map_path: String) -> void:
	await _step(0.15, "Building the farm...")

	# --- map ---
	var map_root: Node3D = _load_scene(map_path)
	var custom_map := map_root != null
	if map_root == null:
		map_root = DefaultMapScript.new()
	add_child(map_root)
	if custom_map:
		if map_root.find_children("*", "WorldEnvironment", true, false).is_empty():
			Util.add_env(map_root)
		if map_root.find_children("*", "DirectionalLight3D", true, false).is_empty():
			Util.add_sun(map_root)

	var start := Vector3(0, 3, 0)   # custom map without PlayerStart: drop from above
	var marker := map_root.find_child("PlayerStart", true, false)
	if marker is Node3D:
		start = marker.global_position + Vector3(0, 1.0, 0)

	await _step(0.5, "Spawning machines...")
	# --- character ---
	player = PlayerScript.new()
	player.position = start
	add_child(player)
	var model := _load_scene(char_path)
	if model != null:
		player.use_model(model)

	# --- tractor (+ a test plow lying behind it: reverse into it to attach) ---
	tractor = TractorScript.new()
	tractor.position = start + Vector3(5, -0.95, -3)
	add_child(tractor)
	if not custom_map:
		_spawn_impls()
	heli = HeliScript.new()
	heli.position = start + Vector3(-9, 0, -4)
	heli.rotation.y = 0.6
	add_child(heli)

	await _step(0.75, "Preparing controls...")
	# --- camera and controls ---
	rig = CameraRigScript.new()
	add_child(rig)
	rig.set_target(player)

	# --- minimap + plot info (only for maps that have layout data) ---
	map_node = map_root
	if map_root.get("layout") != null:
		minimap = MinimapScript.new()
		layer.add_child(minimap)
		minimap.set_map(map_root)
		hud = Label.new()
		hud.position = Vector2(24, 250)
		hud.add_theme_font_size_override("font_size", 26)
		hud.add_theme_color_override("font_outline_color", Color.BLACK)
		hud.add_theme_constant_override("outline_size", 8)
		layer.add_child(hud)

	# speed + machine info (top right, while driving)
	speed_label = Label.new()
	speed_label.anchor_left = 1.0
	speed_label.anchor_right = 1.0
	speed_label.offset_left = -640.0
	speed_label.offset_right = -24.0
	speed_label.offset_top = 100.0
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_label.add_theme_font_size_override("font_size", 34)
	speed_label.add_theme_color_override("font_outline_color", Color.BLACK)
	speed_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(speed_label)
	horn = _make_horn()

	farm = FarmScript.new()
	add_child(farm)
	farm.setup(map_root)
	coin_label = Label.new()
	coin_label.position = Vector2(260, 22)
	coin_label.add_theme_font_size_override("font_size", 30)
	coin_label.add_theme_color_override("font_outline_color", Color.BLACK)
	coin_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(coin_label)

	touch = TouchScript.new()
	layer.add_child(touch)
	touch.look_dragged.connect(func(dx: float, dy: float) -> void: rig.look(dx, dy))
	touch.jump_pressed.connect(func() -> void: player.jump())
	touch.run_pressed.connect(func() -> void: player.toggle_run())
	touch.action_pressed.connect(_on_action)
	touch.hitch_pressed.connect(_on_hitch)
	touch.work_pressed.connect(_on_work)

	combat = CombatScript.new()
	add_child(combat)
	combat.setup(self, player, rig, touch, farm, layer)
	combat.minimap = minimap
	touch.reload_pressed.connect(combat.reload)
	touch.swap_pressed.connect(combat.swap_weapon)
	touch.bag_pressed.connect(combat.open_bag)

	heli_ui = HeliUiScript.new()
	layer.add_child(heli_ui)
	heli_ui.exit_pressed.connect(_leave_heli)
	heli_ui.look_dragged.connect(func(dx: float, dy: float) -> void: rig.look(dx, dy))

	ui = UiScript.new()
	ui.farm = farm
	ui.main = self
	layer.add_child(ui)
	farm.message.connect(ui.toast)
	farm.changed.connect(ui.refresh)
	ui.edit_requested.connect(func() -> void: touch.start_edit())
	ui.map_requested.connect(_toggle_map)
	touch.menu_pressed.connect(func() -> void: ui.open("menu"))
	touch.map_pressed.connect(_toggle_map)
	touch.poi_pressed.connect(_on_poi)
	touch.seed_pressed.connect(func() -> void: ui.open("seed"))

	_load_game()
	var tm := Timer.new()   # autosave every 3 s (a closed / killed app still keeps its last place)
	tm.wait_time = 3.0
	tm.autostart = true
	tm.timeout.connect(_save_game)
	add_child(tm)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_save_game()
		if farm != null:
			farm.save_all()


# --- save / load: where the player, tractor and plow stand ---
func _save_game() -> void:
	if player == null or tractor == null or not _save_ready:
		return
	var pp: Vector3 = player.global_position
	var tp: Vector3 = tractor.global_position
	var d := {
		"driving": driving,
		"player": [pp.x, pp.y, pp.z, player.pivot.rotation.y],
		"tractor": [tp.x, tp.y, tp.z, tractor.rotation.y],
		"fuel": [tractor.fuel, heli.fuel],
	}
	var list: Array = []
	for n in impls:
		var q: Vector3 = n.global_position
		list.append({"k": n.get_meta("kind", ""), "p": [q.x, q.y, q.z, n.rotation.y], "a": tractor.is_attached(n), "e": n.extra_state()})
	d["impl"] = list
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


func _load_game() -> void:
	_save_ready = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	var fl = d.get("fuel")
	if fl is Array and fl.size() >= 2:
		tractor.fuel = clampf(float(fl[0]), 0.0, tractor.fuel_cap)
		heli.fuel = clampf(float(fl[1]), 0.0, heli.fuel_cap)
	var t = d.get("tractor")
	if t is Array and t.size() >= 4:
		tractor.global_position = Vector3(t[0], t[1] + 0.2, t[2])
		tractor.reset_physics_interpolation()
		tractor.rotation.y = t[3]
	var il = d.get("impl")
	if il is Array:
		for e in il:
			if not (e is Dictionary):
				continue
			var n = _impl(String(e.get("k", "")))
			var q = e.get("p")
			if n == null or not (q is Array) or q.size() < 4:
				continue
			n.global_position = Vector3(q[0], q[1], q[2])
			n.reset_physics_interpolation()
			n.rotation.y = q[3]
			n.load_extra(e.get("e", {}))
			if e.get("a", false):
				tractor.attach_node(n)
	var p = d.get("player")
	if bool(d.get("driving", false)):
		driving = true
		player.sit(tractor.seat)
		rig.set_target(tractor, 9.0, 1.6, true)
	elif p is Array and p.size() >= 4:
		player.global_position = Vector3(p[0], p[1] + 0.3, p[2])
		player.reset_physics_interpolation()
		player.pivot.rotation.y = p[3]
		rig.set_target(player)


# two-note horn made from math (no sound file needed). Loops while the HORN button is held.
func _make_horn() -> AudioStreamPlayer:
	var rate := 22050
	var n := 4410   # 0.2 s = exactly 60 cycles of 300 Hz and 80 cycles of 400 Hz, so the loop has no click
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var v := 0.0
		for f in [300.0, 400.0]:
			v += sin(TAU * f * t) + 0.5 * sin(TAU * 2.0 * f * t) + 0.25 * sin(TAU * 3.0 * f * t)
		data.encode_s16(i * 2, int(clampf(v * 0.3, -1.0, 1.0) * 22000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	var pl := AudioStreamPlayer.new()
	pl.stream = st
	pl.volume_db = -4.0
	add_child(pl)
	return pl


# WORK button: starts / stops every machine hooked on the tractor
func _on_work() -> void:
	if driving and tractor.has_attached():
		tractor.toggle_work()


# ATTACH / DETACH button (only while driving)
func _on_hitch() -> void:
	if not driving:
		return
	if tractor.candidate() != null:
		tractor.attach_nearby()
	elif tractor.has_attached():
		tractor.detach_all()


# after dying: leave the tractor / helicopter and stand at the start again
func respawn_player() -> void:
	if flying:
		flying = false
		heli.stop_flight()
		heli_ui.release_all()
		heli_ui.visible = false
		touch.visible = true
	if driving:
		driving = false
		if tractor.is_working():
			tractor.toggle_work()
		horn.stop()
		tractor.stop_inputs()
	player.stand(self, Vector3(0, 2.0, 0))
	rig.set_target(player)
	touch.release_all()


func _near_tractor() -> bool:
	return player.global_position.distance_to(tractor.global_position) < 4.5


func _near_heli() -> bool:
	return heli != null and player.global_position.distance_to(heli.global_position) < 6.0


func _leave_heli() -> void:
	if not flying or not heli.on_ground():
		return
	flying = false
	heli.stop_flight()
	heli_ui.release_all()
	heli_ui.visible = false
	touch.visible = true
	var side: Vector3 = heli.global_transform.basis.x * -3.2
	player.stand(self, heli.global_position + side + Vector3(0, 1.0, 0))
	rig.set_target(player)
	touch.release_all()


func _on_action() -> void:
	if flying:
		return
	if not driving and _near_heli():
		flying = true
		player.sit(heli.seat)
		heli.start_flight()
		heli_ui.visible = true
		touch.visible = false
		touch.release_all()
		rig.set_target(heli, 17.0, 3.0, true)
		return
	if driving:
		if absf(tractor.speed) > 1.5:
			return
		driving = false
		if tractor.is_working():
			tractor.toggle_work()   # leaving the seat stops the machine
		horn.stop()
		tractor.stop_inputs()
		var side: Vector3 = tractor.global_transform.basis.x * -2.3
		player.stand(self, tractor.global_position + side + Vector3(0, 1.0, 0))
		rig.set_target(player)
		touch.release_all()
	elif _near_tractor():
		driving = true
		player.sit(tractor.seat)
		rig.set_target(tractor, 9.0, 1.6, true)
		touch.release_all()


func _physics_process(delta: float) -> void:
	if not _game_ready:
		return
	_unload_tick(delta)
	player.cam_yaw = rig.yaw
	combat.firing = bool(touch.held["fire"]) and not touch.blocked
	if flying:
		var a: Vector3 = heli_ui.axes()
		heli.turn = a.x
		heli.fwd = a.y
		heli.lift = a.z
		heli_ui.can_exit = heli.on_ground() and absf(heli.speed) < 1.5
	elif driving:
		tractor.gas = touch.held["gas"]
		tractor.brake = touch.held["brake"]
		tractor.steer = float(touch.held["right"]) - float(touch.held["left"])
	else:
		player.move_dir = Vector2.ZERO if combat.dead else touch.move_dir


func _process(_delta: float) -> void:
	if not _game_ready:
		return
	_fuel_tick(_delta)
	touch.run_on = player.running
	touch.swap_text = combat.weapon_name()
	touch.drive_mode = driving
	if flying:
		speed_label.text = "%d km/h   alt %d m\nFuel %.1f L%s" % [int(round(heli.kmh())), int(round(heli.height())), heli.fuel, _fuel_text(heli)]
		if minimap != null:
			minimap.focus = Vector2(heli.global_position.x, heli.global_position.z)
			minimap.heading = heli.rotation.y
			minimap.tractor_pos = Vector2(tractor.global_position.x, tractor.global_position.z)
			minimap.show_tractor = true
		return
	touch.work_available = driving and tractor.has_attached()
	touch.work_on = tractor.is_working()
	touch.seed_available = driving and seeder != null and seeder.attached
	touch.blocked = (ui != null and ui.is_open()) or combat.bag_open
	coin_label.text = "Coins: %d" % int(farm.coins)
	_update_poi()
	touch.poi_visible = not poi.is_empty()
	touch.poi_text = String(poi.get("text", "SHOP"))
	if driving:
		if touch.held["horn"] and not horn.playing:
			horn.play()
		elif not touch.held["horn"] and horn.playing:
			horn.stop()
		var lim: float = tractor.speed_limit_kmh()
		var txt := "%d km/h   Fuel %.1f L%s" % [int(round(tractor.kmh())), tractor.fuel, _fuel_text(tractor)]
		if tractor.has_attached():
			txt += "\n%s %s | max %d" % [tractor.attached_names(), "WORKING" if tractor.is_working() else "ready", int(lim)]
			var inf: String = tractor.attached_info()
			if inf != "":
				txt += "\n" + inf
		speed_label.text = txt
	else:
		speed_label.text = ""
	if driving:
		touch.action_visible = true
		touch.action_text = "GET OUT"
		touch.action_enabled = absf(tractor.speed) < 1.5
		if tractor.candidate() != null:
			touch.hitch_text = "ATTACH"
			touch.hitch_enabled = true
		elif tractor.has_attached():
			touch.hitch_text = "DETACH"
			touch.hitch_enabled = true
		else:
			touch.hitch_text = "ATTACH"
			touch.hitch_enabled = false
	else:
		var near := _near_tractor() or _near_heli()
		touch.action_visible = near
		touch.action_text = "GET IN"
		touch.action_enabled = near

	if minimap != null:
		var f = tractor if driving else player
		minimap.focus = Vector2(f.global_position.x, f.global_position.z)
		minimap.heading = tractor.rotation.y if driving else player.pivot.rotation.y
		minimap.tractor_pos = Vector2(tractor.global_position.x, tractor.global_position.z)
		minimap.show_tractor = not driving
		var pid: String = map_node.plot_at(f.global_position)
		if pid == "":
			hud.text = ""
		else:
			var cell: Vector2i = map_node.cell_of(pid, f.global_position)
			hud.text = "%s   cell %d, %d   tilled %d%%   %s" % [pid, cell.x, cell.y, int(round(map_node.plot_progress(pid) * 100.0)), map_node.plot_crop_text(pid)]
		var marks: Array = []
		for n in impls:
			if not tractor.is_attached(n):
				var kind: String = n.get_meta("kind", "")
				marks.append({"p": Vector2(n.global_position.x, n.global_position.z), "t": String(MARK_LETTER.get(kind, "?")), "col": MARK_COL.get(kind, Color.WHITE)})
		minimap.marks = marks


# ---------------------------------------------------------------- machines, points, shops

func _spawn_impls() -> void:
	var base: Vector3 = tractor.position + Vector3(0, 0, 5.5)
	var defs := [["plow", PlowScript, Vector3(0, 0, 0)], ["seeder", SeederScript, Vector3(7, 0, 0)], ["trailer", TrailerScript, Vector3(14, 0, 0)], ["sprayer", SprayerScript, Vector3(0, 0, -13.5)], ["harvester", HarvesterScript, Vector3(-8, 0, -13.5)]]
	for d in defs:
		var n: Node3D = d[1].new()
		n.set_meta("kind", d[0])
		n.position = base + d[2]
		add_child(n)
		impls.append(n)
	seeder = _impl("seeder")
	trailer = _impl("trailer")
	sprayer = _impl("sprayer")
	harvester = _impl("harvester")


func _impl(kind: String) -> Node3D:
	for n in impls:
		if n.get_meta("kind", "") == kind:
			return n
	return null


func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() < r


# which shop / warehouse / pump point is next to you (or your trailer)? sets "poi" and the button text
func _update_poi() -> void:
	poi = {}
	var pois = map_node.get("pois")
	if not (pois is Array):
		return
	var actor: Node3D = tractor if driving else player
	var ap: Vector3 = actor.global_position
	var tp := Vector3(1.0e6, 0, 1.0e6)
	var tcargo := 0.0
	if trailer != null:
		tp = trailer.bed_center()
		tcargo = trailer.total()
	for p in pois:
		var pp: Vector3 = p["pos"]
		var r: float = p["r"]
		match String(p["kind"]):
			"shop":
				if _near(tp, pp, r) and tcargo > 0.0:
					poi = {"text": "SELL", "p": p}
				elif _near(ap, pp, r):
					poi = {"text": "SHOP", "p": p}
			"wh":
				if _cargo_near(pp, r, String(p["id"])) > 0.0:
					poi = {"text": "STOP" if unload_prod == String(p["id"]) else "UNLOAD", "p": p}
			"fert":
				if sprayer != null and (_near(sprayer.global_position, pp, r + 2.0) or (sprayer.attached and _near(tractor.global_position, pp, r))):
					poi = {"text": "FILL", "p": p}
		if not poi.is_empty():
			return


func _on_poi() -> void:
	if poi.is_empty():
		return
	var p: Dictionary = poi["p"]
	match String(p["kind"]):
		"shop":
			ui.open("shop", {"shop": int(p["id"])})
		"wh":
			var id := String(p["id"])
			unload_prod = "" if unload_prod == id else id
		"fert":
			farm.fill_sprayer(sprayer)


# machines that carry grain (trailer, harvester) standing at a warehouse mouth
func _cargo_near(pp: Vector3, r: float, prod: String) -> float:
	var sum := 0.0
	for s in [trailer, harvester]:
		if s != null and _near(s.bed_center(), pp, r):
			sum += float(s.cargo.get(prod, 0.0))
	return sum


# warehouse mouth: the trailer / harvester empty slowly into the warehouse
func _unload_tick(delta: float) -> void:
	if unload_prod == "":
		return
	var pois = map_node.get("pois")
	var left: float = D.UNLOAD_KG_S * delta
	var near := false
	var moved := false
	if pois is Array:
		for p in pois:
			if String(p["kind"]) != "wh" or String(p["id"]) != unload_prod:
				continue
			for s in [trailer, harvester]:
				if s != null and _near(s.bed_center(), p["pos"], float(p["r"])):
					near = true
					var got: float = s.take(unload_prod, left)
					if got > 0.0:
						farm.add_stock(unload_prod, got)
						left -= got
						moved = true
	if not near:
		unload_prod = ""
	elif not moved:
		unload_prod = ""
		ui.toast("Unloaded")


func trailer_near_shop(idx: int):
	if trailer == null:
		return null
	var pois = map_node.get("pois")
	if pois is Array:
		for p in pois:
			if String(p["kind"]) == "shop" and int(p["id"]) == idx and _near(trailer.bed_center(), p["pos"], float(p["r"])):
				return trailer
	return null


# FARM VIEW "tr" button: warehouse -> trailer (the trailer must stand near the warehouse)
func load_trailer(product: String) -> void:
	if trailer == null:
		ui.toast("No trailer")
		return
	var near_wh := false
	var pois = map_node.get("pois")
	if pois is Array:
		for p in pois:
			if String(p["kind"]) == "wh" and _near(trailer.bed_center(), p["pos"], 25.0):
				near_wh = true
	if not near_wh:
		ui.toast("Bring the trailer near the warehouse")
		return
	var want := minf(farm.stock_of(product), D.TRAILER_CAP - trailer.total())
	if want <= 0.5:
		ui.toast("Nothing to load (trailer full or no stock)")
		return
	var got: float = trailer.add(product, want)
	farm.take_stock(product, got)
	ui.toast("Loaded %d kg" % int(got))


func trailer_text() -> String:
	if trailer == null:
		return "No trailer"
	var parts: Array = []
	for k in trailer.cargo:
		parts.append("%s %d kg" % [k, int(trailer.cargo[k])])
	return "Trailer  %d / %d kg   %s" % [int(trailer.total()), int(D.TRAILER_CAP), ", ".join(parts)]


# minimap tap: whole map on / off
func _toggle_map() -> void:
	if minimap == null:
		return
	minimap.set_big(not minimap.big)
	touch.map_rect = minimap.hit_rect()
	hud.visible = not minimap.big


# ---------------------------------------------------------------- fuel pump (V20)
var _fuel_acc := 0.0
var _fuel_note := ""
var _fuel_save_t := 0.0


# tractor (or a landed helicopter) inside the FUEL ring: coins go down 1-2 at a time, liters go up until the tank is full
func _fuel_tick(delta: float) -> void:
	_fuel_note = ""
	var pois = map_node.get("pois")
	if not (pois is Array) or tractor == null or heli == null:
		return
	var busy := false
	for p in pois:
		if String(p["kind"]) != "fuel":
			continue
		var pp: Vector3 = p["pos"]
		var r: float = p["r"]
		for v in [tractor, heli]:
			if not _near(v.global_position, pp, r):
				continue
			if v == heli and not heli.on_ground():
				continue
			if v.fuel >= v.fuel_cap - 0.001:
				v.fuel = v.fuel_cap
				_fuel_note = "Tank full"
				continue
			if farm.coins < 1.0:
				_fuel_note = "No coins for fuel"
				continue
			_fuel_acc += D.FUEL_FILL_LPS * D.FUEL_PRICE * delta
			var n := mini(int(_fuel_acc), int(farm.coins))
			n = mini(n, int(ceil((v.fuel_cap - v.fuel) * D.FUEL_PRICE)))
			if n > 0:
				_fuel_acc -= float(n)
				farm.coins -= float(n)
				v.fuel = minf(v.fuel_cap, v.fuel + float(n) / D.FUEL_PRICE)
			busy = true
			_fuel_note = "FUELING   -%d coins/s" % int(D.FUEL_FILL_LPS * D.FUEL_PRICE)
	if busy:
		_fuel_save_t += delta
		if _fuel_save_t > 1.0:
			_fuel_save_t = 0.0
			farm._touch()
	else:
		_fuel_acc = 0.0


func _fuel_text(v) -> String:
	if v.fuel <= 0.0:
		return "   NO FUEL - go to the pump"
	return ("\n" + _fuel_note) if _fuel_note != "" else ""
