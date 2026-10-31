extends Control
# Phone controls.
# On foot: joystick (left), drag right side = look, JUMP, RUN, GET IN (near tractor).
# Driving: GAS, BRAKE, < and >, ATTACH/DETACH, GET IN/OUT. Drag anywhere else = look around.
# Driving also shows the BOTTOM BAR: HORN (hold) and WORK (press = machine starts, press again = stops).
# WORK only appears while a machine is hooked on.
# SET button (top right, on foot) = edit mode: drag buttons, - / + to resize,
# VIEW switches between FOOT and DRIVE buttons. Positions are saved on the phone.

signal look_dragged(dx: float, dy: float)
signal jump_pressed
signal run_pressed
signal action_pressed
signal hitch_pressed
signal work_pressed
signal menu_pressed
signal map_pressed
signal poi_pressed
signal seed_pressed
signal reload_pressed
signal swap_pressed
signal bag_pressed

const STICK_R := 100.0
const LOOK_HOLD := ["fire", "jump"]   # a finger on these buttons can still drag to look / aim
const CFG := "user://controls.cfg"

# pos = screen position as a fraction (0..1) so it fits any phone; scale = size multiplier
# mode: foot / drive / both      hold: true = active while the finger stays down
var btn := {
	"jump": {"pos": Vector2(0.883, 0.764), "scale": 1.0, "r": 85.0, "text": "JUMP", "mode": "foot", "hold": false},
	"run": {"pos": Vector2(0.742, 0.847), "scale": 1.0, "r": 65.0, "text": "RUN", "mode": "foot", "hold": false},
	"action": {"pos": Vector2(0.88, 0.45), "scale": 1.0, "r": 65.0, "text": "IN/OUT", "mode": "both", "hold": false},
	"gas": {"pos": Vector2(0.90, 0.74), "scale": 1.0, "r": 90.0, "text": "GAS", "mode": "drive", "hold": true},
	"brake": {"pos": Vector2(0.75, 0.85), "scale": 1.0, "r": 70.0, "text": "BRAKE", "mode": "drive", "hold": true},
	"left": {"pos": Vector2(0.10, 0.80), "scale": 1.0, "r": 70.0, "text": "<", "mode": "drive", "hold": true},
	"right": {"pos": Vector2(0.25, 0.80), "scale": 1.0, "r": 70.0, "text": ">", "mode": "drive", "hold": true},
	"hitch": {"pos": Vector2(0.74, 0.62), "scale": 1.0, "r": 60.0, "text": "ATTACH", "mode": "drive", "hold": false},
	"poi": {"pos": Vector2(0.88, 0.27), "scale": 1.0, "r": 62.0, "text": "SHOP", "mode": "both", "hold": false},
	"fire": {"pos": Vector2(0.745, 0.60), "scale": 1.0, "r": 78.0, "text": "FIRE", "mode": "foot", "hold": true},
	"reload": {"pos": Vector2(0.62, 0.78), "scale": 1.0, "r": 52.0, "text": "RELOAD", "mode": "foot", "hold": false},
	"bag": {"pos": Vector2(0.78, 0.12), "scale": 1.0, "r": 46.0, "text": "BAG", "mode": "foot", "hold": false},
	"swap": {"pos": Vector2(0.62, 0.60), "scale": 1.0, "r": 48.0, "text": "SWAP", "mode": "foot", "hold": false},
}
var defaults := {}
var held := {"gas": false, "brake": false, "left": false, "right": false, "horn": false, "fire": false}
var hold_touch := {}      # finger index -> button id
var move_dir := Vector2.ZERO
var run_on := false
var drive_mode := false
var action_visible := false
var action_enabled := false
var action_text := "IN/OUT"
var hitch_text := "ATTACH"
var hitch_enabled := false
var work_available := false   # a machine is hooked on -> the WORK button shows in the bottom bar
var work_on := false          # machine is working right now
var seed_available := false   # seeder hooked on -> SEED button next to the horn
var poi_visible := false      # a shop / warehouse / fertilizer point is near -> button shows
var poi_text := "SHOP"
var swap_text := "SWAP"
var fire_off := Vector2.ZERO      # FIRE button slides with the finger (like a joystick) and springs back
var fire_target := Vector2.ZERO
var blocked := false          # a pop-up screen is open: ignore touches
var map_rect := Rect2(20, 20, 220, 220)   # tap here = big map
var edit := false
var edit_drive := false
var sel := "jump"
var drag_touch := -1
var stick_id := -1
var look_id := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the game is paused (edit mode)
	defaults = btn.duplicate(true)
	_load()


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


func _center(id: String) -> Vector2:
	return Vector2(btn[id]["pos"]) * _vp()


func _rad(id: String) -> float:
	return float(btn[id]["r"]) * float(btn[id]["scale"])


# is this button shown right now?
func _vis(id: String) -> bool:
	var m: String = btn[id]["mode"]
	if edit:
		return m == "both" or ((m == "drive") == edit_drive)
	if id == "action" and not action_visible:
		return false
	if id == "poi" and not poi_visible:
		return false
	return m == "both" or ((m == "drive") == drive_mode)


func release_all() -> void:
	stick_id = -1
	look_id = -1
	move_dir = Vector2.ZERO
	hold_touch.clear()
	fire_target = Vector2.ZERO
	for k in held:
		held[k] = false


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return
	for id in btn:
		var p: Vector2 = btn[id]["pos"]
		btn[id]["pos"] = Vector2(float(cf.get_value(id, "x", p.x)), float(cf.get_value(id, "y", p.y)))
		btn[id]["scale"] = float(cf.get_value(id, "scale", btn[id]["scale"]))


func _save() -> void:
	var cf := ConfigFile.new()
	for id in btn:
		var p: Vector2 = btn[id]["pos"]
		cf.set_value(id, "x", p.x)
		cf.set_value(id, "y", p.y)
		cf.set_value(id, "scale", btn[id]["scale"])
	cf.save(CFG)


# small buttons: id -> [center, radius, text]
func _ui_buttons() -> Dictionary:
	var vp := _vp()
	var d := {}
	if edit:
		var y := vp.y - 70.0
		var cx := vp.x / 2.0
		d["minus"] = [Vector2(cx - 330.0, y), 44.0, "-"]
		d["plus"] = [Vector2(cx - 220.0, y), 44.0, "+"]
		d["view"] = [Vector2(cx - 80.0, y), 60.0, "DRIVE" if edit_drive else "FOOT"]
		d["reset"] = [Vector2(cx + 70.0, y), 50.0, "RESET"]
		d["done"] = [Vector2(cx + 210.0, y), 56.0, "DONE"]
	else:
		d["menu"] = [Vector2(vp.x - 55.0, 55.0), 36.0, ""]
	return d


func _hit_ui(p: Vector2) -> String:
	var d := _ui_buttons()
	for id in d:
		if p.distance_to(d[id][0]) < float(d[id][1]) + 10.0:
			return id
	return ""


func start_edit() -> void:
	_set_edit(true)


func _set_edit(on: bool) -> void:
	edit = on
	get_tree().paused = on
	release_all()
	if on:
		edit_drive = false
		sel = "jump"
	else:
		_save()


func _process(delta: float) -> void:
	var tgt := fire_target if held.get("fire", false) else Vector2.ZERO
	fire_off = fire_off.lerp(tgt, minf(1.0, 22.0 * delta))
	queue_redraw()


func _circle_btn(c: Vector2, r: float, text: String, col: Color, fs: int = 24) -> void:
	draw_circle(c, r, col)
	draw_string(ThemeDB.fallback_font, c + Vector2(-r, fs * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color.WHITE)


# bottom bar: rectangles of the panel and its buttons (screen pixels)
func _bar_rects() -> Dictionary:
	var vp := _vp()
	var u := clampf(vp.y / 720.0, 0.6, 1.6)
	var bs := 100.0 * u
	var gap := 10.0 * u
	var pad := 12.0 * u
	var n := 1 + (1 if work_available else 0) + (1 if seed_available else 0)
	var w := pad * 2.0 + bs * n + gap * (n - 1)
	var h := pad * 2.0 + bs
	var panel := Rect2(vp.x / 2.0 - w / 2.0, vp.y - h - 14.0 * u, w, h)
	var d := {"panel": panel}
	var x := panel.position.x + pad
	if work_available:
		d["work"] = Rect2(x, panel.position.y + pad, bs, bs)
		x += bs + gap
	if seed_available:
		d["seed"] = Rect2(x, panel.position.y + pad, bs, bs)
		x += bs + gap
	d["horn"] = Rect2(x, panel.position.y + pad, bs, bs)
	return d


func _bar_btn(r: Rect2, sb: StyleBoxFlat, active: bool) -> void:
	sb.bg_color = Color(0.1, 0.24, 0.1) if active else Color(0.05, 0.05, 0.05)
	sb.border_color = Color(0.55, 0.9, 0.2) if active else Color(0.3, 0.3, 0.3)
	draw_style_box(sb, r)


func _icon_horn(r: Rect2, col: Color) -> void:
	var k := r.size.x * 0.4
	var c := r.get_center()
	var pts := PackedVector2Array([Vector2(-0.62, -0.12), Vector2(-0.2, -0.12), Vector2(0.4, -0.42), Vector2(0.4, 0.42), Vector2(-0.2, 0.12), Vector2(-0.62, 0.12)])
	for i in pts.size():
		pts[i] = c + pts[i] * k
	draw_colored_polygon(pts, col)
	draw_circle(c + Vector2(-0.72, 0) * k, 0.15 * k, col)
	draw_arc(c + Vector2(0.45, 0) * k, 0.3 * k, deg_to_rad(-45), deg_to_rad(45), 12, col, 0.09 * k)
	draw_arc(c + Vector2(0.45, 0) * k, 0.52 * k, deg_to_rad(-45), deg_to_rad(45), 12, col, 0.09 * k)


func _icon_work(r: Rect2, col: Color) -> void:
	var k := r.size.x * 0.4
	var c := r.get_center()
	var w := 0.13 * k
	draw_polyline(PackedVector2Array([c + Vector2(-0.6, -0.4) * k, c + Vector2(-0.35, -0.15) * k, c + Vector2(0.15, -0.8) * k]), col, w)
	draw_line(c + Vector2(-0.55, 0.8) * k, c + Vector2(0.25, 0.0) * k, col, 0.22 * k)
	draw_arc(c + Vector2(0.4, -0.15) * k, 0.26 * k, deg_to_rad(15), deg_to_rad(305), 18, col, 0.13 * k)


func _icon_seed(r: Rect2, col: Color) -> void:
	var k := r.size.x * 0.4
	var c := r.get_center()
	draw_circle(c + Vector2(-0.45, 0.35) * k, 0.26 * k, col)
	draw_circle(c + Vector2(0.45, 0.35) * k, 0.26 * k, col)
	draw_circle(c + Vector2(0.0, -0.4) * k, 0.26 * k, col)
	draw_line(c + Vector2(0.0, -0.1) * k, c + Vector2(0.0, 0.9) * k, col, 0.08 * k)


func _draw_bar() -> void:
	var b := _bar_rects()
	var sb_panel := StyleBoxFlat.new()
	sb_panel.bg_color = Color(0.12, 0.12, 0.13, 0.92)
	sb_panel.border_color = Color(0.3, 0.3, 0.32)
	sb_panel.set_border_width_all(3)
	sb_panel.set_corner_radius_all(16)
	draw_style_box(sb_panel, b["panel"])
	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	var green := Color(0.5, 0.85, 0.15)
	if b.has("work"):
		_bar_btn(b["work"], sb, work_on)
		_icon_work(b["work"], Color(0.7, 1.0, 0.35) if work_on else green)
		if work_on:
			draw_circle((b["work"] as Rect2).position + Vector2((b["work"] as Rect2).size.x - 14.0, 14.0), 7.0, Color(0.5, 1.0, 0.2))
	if b.has("seed"):
		_bar_btn(b["seed"], sb, false)
		_icon_seed(b["seed"], green)
	_bar_btn(b["horn"], sb, held.get("horn", false))
	_icon_horn(b["horn"], Color(0.7, 1.0, 0.35) if held.get("horn", false) else green)


func _draw() -> void:
	var vp := _vp()
	if edit:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.35))
		draw_string(ThemeDB.fallback_font, Vector2(0, 50), "Drag a button to move it. Tap it, then - / + to resize.", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 26, Color.WHITE)
	elif stick_id != -1:
		var d := stick_pos - stick_origin
		if d.length() > STICK_R:
			d = d.normalized() * STICK_R
		draw_circle(stick_origin, STICK_R, Color(1, 1, 1, 0.2))
		draw_circle(stick_origin + d, 42.0, Color(1, 1, 1, 0.55))

	for id in btn:
		if not _vis(id):
			continue
		var col := Color(1.0, 0.6, 0.1, 0.9)
		var text: String = btn[id]["text"]
		if id == "run":
			col = Color(0.2, 0.8, 0.3, 0.95) if (run_on and not edit) else Color(0.3, 0.45, 0.7, 0.8)
		elif id == "action":
			if not edit:
				text = action_text
				if not action_enabled:
					col = Color(0.4, 0.4, 0.4, 0.6)
		elif id == "hitch":
			if not edit:
				text = hitch_text
				if not hitch_enabled:
					col = Color(0.4, 0.4, 0.4, 0.6)
		elif id == "fire":
			col = Color(1.0, 0.25, 0.15, 0.95) if held.get(id, false) else Color(0.8, 0.2, 0.15, 0.8)
		elif id == "reload" or id == "swap" or id == "bag":
			col = Color(0.25, 0.5, 0.35, 0.85)
			if id == "swap" and not edit:
				text = swap_text
		elif id == "poi":
			col = Color(0.15, 0.6, 0.85, 0.95)
			if not edit:
				text = poi_text
		elif btn[id]["hold"]:
			col = Color(1.0, 0.85, 0.2, 0.95) if held.get(id, false) else Color(0.3, 0.45, 0.7, 0.8)
		if id == "fire" and not edit:
			_circle_btn(_center(id) + fire_off, _rad(id) * (1.12 if held.get("fire", false) else 1.0), text, col)
		else:
			_circle_btn(_center(id), _rad(id), text, col)
		if edit and id == sel:
			draw_arc(_center(id), _rad(id) + 8.0, 0.0, TAU, 48, Color(1, 0.95, 0.2), 4.0)

	var u := _ui_buttons()
	for id in u:
		_circle_btn(u[id][0], u[id][1], u[id][2], Color(0.15, 0.15, 0.2, 0.85), 22)
		if id == "menu":
			var mc: Vector2 = u[id][0]
			for k in 3:
				draw_line(mc + Vector2(-16, -12 + k * 12), mc + Vector2(16, -12 + k * 12), Color.WHITE, 4.0)
	if drive_mode and not edit:
		_draw_bar()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event)
		else:
			_release(event)
	elif event is InputEventScreenDrag:
		_drag(event)


func _press(e: InputEventScreenTouch) -> void:
	var ui := _hit_ui(e.position)
	if edit:
		match ui:
			"minus":
				btn[sel]["scale"] = clampf(float(btn[sel]["scale"]) - 0.1, 0.5, 2.0)
				_save()
			"plus":
				btn[sel]["scale"] = clampf(float(btn[sel]["scale"]) + 0.1, 0.5, 2.0)
				_save()
			"view":
				edit_drive = not edit_drive
				sel = "gas" if edit_drive else "jump"
			"reset":
				for id in btn:
					btn[id]["pos"] = defaults[id]["pos"]
					btn[id]["scale"] = defaults[id]["scale"]
				_save()
			"done":
				_set_edit(false)
			_:
				for id in btn:
					if _vis(id) and e.position.distance_to(_center(id)) < _rad(id) + 10.0:
						sel = id
						drag_touch = e.index
		return

	if blocked:
		return
	if ui == "menu":
		menu_pressed.emit()
		return
	if map_rect.has_point(e.position):
		map_pressed.emit()
		return
	if drive_mode:
		var bar := _bar_rects()
		if bar.has("work") and (bar["work"] as Rect2).grow(10.0).has_point(e.position):
			work_pressed.emit()
			return
		if bar.has("seed") and (bar["seed"] as Rect2).grow(10.0).has_point(e.position):
			seed_pressed.emit()
			return
		if (bar["horn"] as Rect2).grow(10.0).has_point(e.position):
			held["horn"] = true
			hold_touch[e.index] = "horn"
			return
	for id in btn:
		if not _vis(id):
			continue
		if e.position.distance_to(_center(id)) < _rad(id) + 20.0:
			if btn[id]["hold"]:
				held[id] = true
				hold_touch[e.index] = id
			elif id == "jump":
				jump_pressed.emit()
				hold_touch[e.index] = "jump"
			elif id == "run":
				run_pressed.emit()
			elif id == "action":
				action_pressed.emit()
			elif id == "hitch":
				hitch_pressed.emit()
			elif id == "poi":
				poi_pressed.emit()
			elif id == "reload":
				reload_pressed.emit()
			elif id == "swap":
				swap_pressed.emit()
			elif id == "bag":
				bag_pressed.emit()
			return
	# on foot: left side = joystick. driving: no joystick, the whole screen is look (look only, never steers)
	if not drive_mode and e.position.x < _vp().x * 0.4:
		if stick_id == -1:
			stick_id = e.index
			stick_origin = e.position
			stick_pos = e.position
	elif look_id == -1:
		look_id = e.index


func _release(e: InputEventScreenTouch) -> void:
	if e.index == drag_touch:
		drag_touch = -1
		_save()
	if hold_touch.has(e.index):
		var hid: String = hold_touch[e.index]
		if hid == "fire":
			fire_target = Vector2.ZERO
		if held.has(hid):
			held[hid] = false
		hold_touch.erase(e.index)
	if e.index == stick_id:
		stick_id = -1
		move_dir = Vector2.ZERO
	if e.index == look_id:
		look_id = -1


func _drag(e: InputEventScreenDrag) -> void:
	if edit:
		if e.index == drag_touch:
			btn[sel]["pos"] = (e.position / _vp()).clamp(Vector2(0.05, 0.1), Vector2(0.95, 0.9))
		return
	if blocked:
		return
	if hold_touch.has(e.index) and hold_touch[e.index] == "fire":
		fire_target = (e.position - _center("fire")).limit_length(_rad("fire") * 0.7)
	if hold_touch.has(e.index) and LOOK_HOLD.has(hold_touch[e.index]):
		look_dragged.emit(e.relative.x, e.relative.y)
		return
	if e.index == stick_id:
		stick_pos = e.position
		var d := stick_pos - stick_origin
		if d.length() > STICK_R:
			d = d.normalized() * STICK_R
		move_dir = d / STICK_R
	elif e.index == look_id:
		look_dragged.emit(e.relative.x, e.relative.y)
