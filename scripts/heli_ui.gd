extends Control
# V29 helicopter controls: JOYSTICK (left side: up/down = forward/back, left/right = turn), drag right side = look around,
# UP / DOWN height buttons + GET OUT. Keyboard arrows also work (in helicopter.gd).
signal exit_pressed
signal look_dragged(dx: float, dy: float)
const STICK_R := 110.0
var stick_id := -1
var look_id := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var stick := Vector2.ZERO
var heli
var can_exit := false
var held := {}   # id -> bool
var _touch := {}  # touch index -> id
const R := 62.0
var _arrows := {"up": "▲", "down": "▼", "left": "◀", "right": "▶"}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _vp() -> Vector2:
	return get_viewport_rect().size


func _pos(id: String) -> Vector2:
	var v := _vp()
	match id:
		"alt_up": return Vector2(v.x - 130, v.y - 300)
		"alt_dn": return Vector2(v.x - 130, v.y - 150)
		"exit": return Vector2(v.x - 130, 90)
	return Vector2.ZERO


func _ids() -> Array:
	return ["alt_up", "alt_dn", "exit"]


func _hit(p: Vector2) -> String:
	for id in _ids():
		if p.distance_to(_pos(id)) < R * 1.05 and (id != "exit" or can_exit):
			return id
	return ""


func axes() -> Vector3:   # x = turn, y = forward, z = lift
	return Vector3(stick.x, -stick.y, float(held.get("alt_up", false)) - float(held.get("alt_dn", false)))


func release_all() -> void:
	held.clear()
	_touch.clear()
	stick_id = -1
	look_id = -1
	stick = Vector2.ZERO


func _process(_d: float) -> void:
	queue_redraw()


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			var id := _hit(e.position)
			if id != "":
				_touch[e.index] = id
				if id == "exit":
					exit_pressed.emit()
				else:
					held[id] = true
				get_viewport().set_input_as_handled()
			elif e.position.x < _vp().x * 0.45:
				if stick_id == -1:
					stick_id = e.index
					stick_origin = e.position
					stick_pos = e.position
			elif look_id == -1:
				look_id = e.index
		elif e.index == stick_id:
			stick_id = -1
			stick = Vector2.ZERO
		elif e.index == look_id:
			look_id = -1
		elif _touch.has(e.index):
			held[_touch[e.index]] = false
			_touch.erase(e.index)
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		_input_drag(e)


func _input_drag(e: InputEventScreenDrag) -> void:
	if e.index == stick_id:
		stick_pos = e.position
		var d := (stick_pos - stick_origin).limit_length(STICK_R)
		stick = d / STICK_R
		if stick.length() < 0.12:
			stick = Vector2.ZERO
	elif e.index == look_id:
		look_dragged.emit(e.relative.x, e.relative.y)


func _draw() -> void:
	var f := ThemeDB.fallback_font
	if stick_id != -1:
		var dd := (stick_pos - stick_origin).limit_length(STICK_R)
		draw_circle(stick_origin, STICK_R, Color(1, 1, 1, 0.2))
		draw_circle(stick_origin + dd, 44.0, Color(1, 1, 1, 0.55))
	for id in _ids():
		if id == "exit" and not can_exit:
			continue
		var on: bool = held.get(id, false)
		var col := Color(1.0, 0.85, 0.2, 0.95) if on else Color(0.2, 0.4, 0.75, 0.75)
		if id == "exit":
			col = Color(0.85, 0.25, 0.2, 0.9)
		var c := _pos(id)
		draw_circle(c, R, col)
		draw_arc(c, R, 0, TAU, 32, Color(1, 1, 1, 0.8), 3.0)
		var t: String = _arrows.get(id, "")
		if id == "alt_up": t = "UP"
		elif id == "alt_dn": t = "DOWN"
		elif id == "exit": t = "GET OUT"
		var fs := 40 if _arrows.has(id) else 24
		var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, c + Vector2(-sz.x / 2.0, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
