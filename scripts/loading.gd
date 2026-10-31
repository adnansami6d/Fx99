extends Control
# V29 splash: logo + progress bar while the game builds. All drawn in code (no image files).
var progress := 0.0
var shown := 0.0
var msg := "Loading..."
var t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_progress(p: float, m: String) -> void:
	progress = p
	msg = m


func _process(d: float) -> void:
	t += d
	shown = move_toward(shown, progress, d * 0.8)
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var f := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.1, 0.07))
	draw_rect(Rect2(0, vp.y * 0.62, vp.x, vp.y * 0.38), Color(0.1, 0.17, 0.09))   # field
	var c := Vector2(vp.x / 2.0, vp.y * 0.34)
	var r := minf(vp.x, vp.y) * 0.17
	# logo: tractor wheel + wheat
	draw_circle(c, r, Color(0.95, 0.76, 0.1))
	draw_circle(c, r * 0.82, Color(0.08, 0.1, 0.09))
	draw_circle(c, r * 0.62, Color(0.12, 0.52, 0.17))
	for k in 6:
		var a := t * 1.2 + TAU * float(k) / 6.0
		draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.6, Color(0.95, 0.76, 0.1), 5.0)
	draw_circle(c, r * 0.16, Color(0.95, 0.76, 0.1))
	for k in 5:
		var x := c.x - r * 0.5 + float(k) * r * 0.25
		draw_line(Vector2(x, c.y + r * 1.0), Vector2(x, c.y + r * 1.3), Color(0.95, 0.85, 0.3), 3.0)
		draw_circle(Vector2(x, c.y + r * 0.98), 6.0, Color(0.95, 0.85, 0.3))
	var title := "FX001 FARM"
	var fs := int(minf(vp.x, vp.y) * 0.1)
	var sz := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, Vector2(c.x - sz.x / 2.0, c.y + r + fs * 1.5), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.85, 0.3))
	# progress bar
	var bw := vp.x * 0.5
	var bar := Rect2(vp.x / 2.0 - bw / 2.0, vp.y * 0.86, bw, 18.0)
	draw_rect(bar, Color(0.2, 0.25, 0.2))
	draw_rect(Rect2(bar.position, Vector2(bw * clampf(shown, 0.0, 1.0), bar.size.y)), Color(0.5, 0.85, 0.15))
	var ms := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	draw_string(f, Vector2(vp.x / 2.0 - ms.x / 2.0, bar.position.y - 14.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.85, 0.9, 0.85))
