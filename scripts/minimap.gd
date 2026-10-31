extends Control
# Minimap (top-left). North is up. Shows 300 m around you. Reads the map's layout data.
# Yellow arrow = you (or the tractor while driving), green square = parked tractor.

var sz := 220.0
var view := 300.0   # meters shown across the minimap
var big := false      # tap = whole map
var marks: Array = []   # machines lying around: [{p, t, col}]
const Props = preload("res://scripts/props.gd")
const Biome = preload("res://scripts/biome.gd")

var map
var focus := Vector2.ZERO
var heading := 0.0
var tractor_pos := Vector2.ZERO
var show_tractor := true
var enemy_pts: Array = []                 # red dots (combat.gd)
var objective := Vector2(1.0e9, 1.0e9)    # mission target (yellow ring)


func _ready() -> void:
	position = Vector2(20, 20)
	size = Vector2(sz, sz)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_map(m) -> void:
	map = m


var _redraw_t := 0.0


func _process(delta: float) -> void:
	_redraw_t += delta
	if _redraw_t >= 0.08:   # V28: 12 redraws per second (less CPU / fewer draw calls)
		_redraw_t = 0.0
		queue_redraw()


func _fc() -> Vector2:
	return Vector2.ZERO if big else focus


func set_big(b: bool) -> void:
	big = b
	var vp := get_viewport().get_visible_rect().size
	if b:
		sz = vp.y - 30.0
		view = 1040.0   # V26: whole 1000 m map
		position = (vp - Vector2(sz, sz)) / 2.0
	else:
		sz = 220.0
		view = 300.0
		position = Vector2(20, 20)
	size = Vector2(sz, sz)


# screen area that a tap must hit to open / close the big map
func hit_rect() -> Rect2:
	if big:
		return Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return Rect2(position, size)


func _w2s(p: Vector2) -> Vector2:
	return Vector2(sz, sz) / 2.0 + (p - _fc()) * (sz / view)


func _rect(r: Rect2) -> Rect2:
	return Rect2(_w2s(r.position), r.size * (sz / view))


func _seen(r: Rect2) -> bool:   # V28: only draw what is inside the minimap (much fewer draw calls)
	return _rect(r).intersects(Rect2(-4, -4, sz + 8, sz + 8))


func _draw() -> void:
	draw_rect(Rect2(0, 0, sz, sz), Color(0.14, 0.4, 0.65, 0.95))   # sea
	if map == null:
		return
	var lay: Dictionary = map.layout
	var g: Dictionary = lay.get("ground", {})
	var half := float(g.get("size", 1000.0)) / 2.0
	_draw_biomes(half)

	for r in lay.get("roads", []):
		var w := float(r["w"])
		var d := float(r["d"])
		draw_rect(_rect(Rect2(float(r["x"]) - w / 2.0, float(r["z"]) - d / 2.0, w, d)), Color(0.3, 0.3, 0.32))

	for id in map.plots:
		var rr: Rect2 = map.plots[id]
		if not _seen(rr):
			continue
		var prog: float = map.plot_progress(id)
		draw_rect(_rect(rr), Color(0.85, 0.7, 0.35, 0.9).lerp(Color(0.38, 0.22, 0.1, 0.95), prog))
		draw_rect(_rect(rr), Color(0.5, 0.35, 0.1), false, 1.0)
		if rr.size.x * (sz / view) > 20.0:   # plot number only, and only when the plot is big enough on the minimap
			draw_string(ThemeDB.fallback_font, _w2s(rr.get_center()) + Vector2(-20, 4), str(int(id.trim_prefix("plot_"))), HORIZONTAL_ALIGNMENT_CENTER, 40, 13, Color(0.2, 0.12, 0.02))

	for o in lay.get("objects", []):
		var f: Vector2 = Props.FOOT.get(String(o["type"]), Vector2(3, 3))
		if int(o.get("rot", 0)) % 180 != 0:
			f = Vector2(f.y, f.x)
		var orr := Rect2(float(o["x"]) - f.x / 2.0, float(o["z"]) - f.y / 2.0, f.x, f.y)
		if _seen(orr):
			draw_rect(_rect(orr), Color(0.9, 0.9, 0.85))

	if big and map.rail_pts.size() > 2:
		var rp := PackedVector2Array()
		for q in map.rail_pts:
			rp.append(_w2s(q))
		rp.append(rp[0])
		draw_polyline(rp, Color(0.15, 0.1, 0.1), 2.0)

	for pd in map.ponds:
		if not _seen(Rect2(float(pd["x"]) - float(pd["r"]), float(pd["z"]) - float(pd["r"]), float(pd["r"]) * 2.0, float(pd["r"]) * 2.0)):
			continue
		draw_circle(_w2s(Vector2(float(pd["x"]), float(pd["z"]))), float(pd["r"]) * (sz / view), Color(0.2, 0.5, 0.75))

	for ep in enemy_pts:
		var es := _w2s(ep)
		if es.x > 0.0 and es.y > 0.0 and es.x < sz and es.y < sz:
			draw_circle(es, 4.5 if big else 3.5, Color(0.95, 0.15, 0.1))
	if objective.x < 1.0e8:
		var cen := Vector2(sz, sz) / 2.0
		var oc := _w2s(objective)
		var lim := sz / 2.0 - 12.0
		var mx := maxf(absf(oc.x - cen.x), absf(oc.y - cen.y))
		if mx > lim:
			oc = cen + (oc - cen) * (lim / mx)
		draw_circle(oc, 9.0, Color(1.0, 0.85, 0.1, 0.35))
		draw_arc(oc, 9.0, 0.0, TAU, 20, Color(1.0, 0.85, 0.1), 3.0)

	var fc := _fc()
	var reach := view * 0.5 + 6.0
	for t in map.trees:
		if absf(t.x - fc.x) < reach and absf(t.y - fc.y) < reach:   # only trees that can be seen
			draw_circle(_w2s(t), 2.0, Color(0.08, 0.35, 0.12))

	var pois = map.get("pois")
	if pois is Array:
		for p in pois:
			var pp: Vector3 = p["pos"]
			var sp := _w2s(Vector2(pp.x, pp.z))
			if sp.x < -10.0 or sp.y < -10.0 or sp.x > sz + 10.0 or sp.y > sz + 10.0:
				continue
			var pc: Color = p["col"]
			var prad := 6.0 if big else 4.0
			draw_circle(sp, prad, pc)
			draw_arc(sp, prad, 0.0, TAU, 12, Color.BLACK, 1.0)
			if big:
				draw_string(ThemeDB.fallback_font, sp + Vector2(-30, -9), String(p["label"]), HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color.BLACK)
	for m in marks:
		var mp := _w2s(m["p"])
		var mcol: Color = m["col"]
		draw_rect(Rect2(mp - Vector2(7, 7), Vector2(14, 14)), mcol)
		draw_rect(Rect2(mp - Vector2(7, 7), Vector2(14, 14)), Color.BLACK, false, 1.5)
		draw_string(ThemeDB.fallback_font, mp + Vector2(-7, 5), String(m["t"]), HORIZONTAL_ALIGNMENT_CENTER, 14, 13, Color.BLACK)

	if show_tractor:
		var tp := _w2s(tractor_pos)
		draw_rect(Rect2(tp - Vector2(6, 6), Vector2(12, 12)), Color(0.15, 0.85, 0.25))
		draw_rect(Rect2(tp - Vector2(6, 6), Vector2(12, 12)), Color.WHITE, false, 1.5)

	# arrow = who you are controlling, pointing the way it faces
	var c := _w2s(focus)
	var fw := Vector2(-sin(heading), -cos(heading))
	var sd := Vector2(-fw.y, fw.x)
	var pts := PackedVector2Array([c + fw * 11.0, c - fw * 7.0 + sd * 7.0, c - fw * 7.0 - sd * 7.0])
	draw_colored_polygon(pts, Color(1.0, 0.9, 0.1))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color.BLACK, 1.5)

	draw_rect(Rect2(0, 0, sz, sz), Color(1, 1, 1, 0.8), false, 3.0)


# ground colors of the biomes around you (recomputed only when you moved ~1 square)
const BG_N := 18
var _bg_key := Vector2i(1 << 30, 0)
var _bg_step := 0.0
var _bg: Array = []
var _bg_tex: ImageTexture


func _draw_biomes(half: float) -> void:
	var step := view / 14.0
	var fc := _fc()
	var key := Vector2i(floori(fc.x / step), floori(fc.y / step))
	if key != _bg_key or absf(step - _bg_step) > 0.01 or _bg_tex == null:
		_bg_key = key
		_bg_step = step
		var img := Image.create(BG_N, BG_N, false, Image.FORMAT_RGBA8)
		for i in BG_N:
			for j in BG_N:
				var wx := float(key.x + i - BG_N / 2) * step
				var wz := float(key.y + j - BG_N / 2) * step
				if absf(wx + step * 0.5) > half or absf(wz + step * 0.5) > half:
					img.set_pixel(i, j, Color(0, 0, 0, 0))
				else:
					img.set_pixel(i, j, Biome.mini_color(wx + step * 0.5, wz + step * 0.5))
		_bg_tex = ImageTexture.create_from_image(img)   # V28: ONE draw call instead of 324 rectangles
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var x0 := float(key.x - BG_N / 2) * step
	var z0 := float(key.y - BG_N / 2) * step
	draw_texture_rect(_bg_tex, _rect(Rect2(x0, z0, step * BG_N, step * BG_N)), false)
