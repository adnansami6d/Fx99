extends Control
# Shooting HUD: crosshair, health, ammo, objective, banners, damage flash.

var combat
var hit_t := 0.0
var hit_kill := false
var flash := 0.0
var _say_text := ""
var _say_t := 0.0
var _ban_text := ""
var _ban_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func say(t: String, secs: float = 1.8) -> void:
	_say_text = t
	_say_t = secs


func banner(t: String, secs: float = 4.0) -> void:
	_ban_text = t
	_ban_t = secs


func hit(kill: bool) -> void:
	hit_t = 0.18
	hit_kill = kill


func hurt() -> void:
	flash = 0.45


func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	flash = maxf(0.0, flash - delta)
	_say_t = maxf(0.0, _say_t - delta)
	_ban_t = maxf(0.0, _ban_t - delta)
	queue_redraw()


func _text(s: String, pos: Vector2, size: int, col: Color, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := ThemeDB.fallback_font
	draw_string_outline(f, pos, s, align, width, size, 6, Color(0, 0, 0, 0.9))
	draw_string(f, pos, s, align, width, size, col)


func _draw() -> void:
	if combat == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var c := vp / 2.0
	var u := clampf(vp.y / 720.0, 0.7, 1.5)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.8, 0.0, 0.0, minf(flash, 0.45) * 0.5))

	if combat.on_foot():
		var white := Color(1.0, 0.1, 0.05) if combat.target_on else Color(1, 1, 1, 0.9)   # red when aiming at a bandit
		var gap := 13.0 if combat.target_on else 9.0
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * gap, c + d * (gap + 12.0), white, 4.0 if combat.target_on else 3.0)
		draw_circle(c, 2.5 if combat.target_on else 2.0, Color(1.0, 0.2, 0.2))
		if hit_t > 0.0:
			var hc := Color(1.0, 0.15, 0.1) if hit_kill else Color(1, 1, 1)
			for sgn in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
				draw_line(c + sgn * 8.0, c + sgn * 18.0, hc, 3.0)

	# health bar (top centre)
	var bw := 340.0 * u
	var bh := 22.0 * u
	var bx := (vp.x - bw) / 2.0
	var by := 22.0
	var frac := clampf(combat.hp / combat.MAX_HP, 0.0, 1.0)
	draw_rect(Rect2(bx - 3, by - 3, bw + 6, bh + 6), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(bx, by, bw * frac, bh), Color(0.9, 0.15, 0.1).lerp(Color(0.25, 0.85, 0.25), frac))
	_text("HP %d" % int(ceil(combat.hp)), Vector2(bx, by + bh - 4.0), int(20.0 * u), Color.WHITE, bw, HORIZONTAL_ALIGNMENT_CENTER)

	# objective
	var obj: String = combat.objective_text()
	if obj != "":
		var lines := obj.split("\n")
		var y := 108.0 * u
		for ln in lines:
			_text(ln, Vector2(0, y), int(24.0 * u), Color(1.0, 0.92, 0.5), vp.x, HORIZONTAL_ALIGNMENT_CENTER)
			y += 30.0 * u

	# ammo (bottom centre, on foot)
	if combat.on_foot():
		var ay := vp.y - 40.0 * u
		_text("%s   %s" % [combat.weapon_name(), combat.ammo_text()], Vector2(0, ay), int(32.0 * u), Color.WHITE, vp.x, HORIZONTAL_ALIGNMENT_CENTER)
		if combat.reloading:
			var rw := 220.0 * u
			var rf := 1.0 - clampf(combat.reload_t / combat.reload_total, 0.0, 1.0)
			draw_rect(Rect2(c.x - rw / 2.0, ay - 56.0 * u, rw, 10.0 * u), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(c.x - rw / 2.0, ay - 56.0 * u, rw * rf, 10.0 * u), Color(1.0, 0.85, 0.2))

	if _say_t > 0.0:
		_text(_say_text, Vector2(0, c.y + 130.0 * u), int(28.0 * u), Color.WHITE, vp.x, HORIZONTAL_ALIGNMENT_CENTER)
	if _ban_t > 0.0:
		_text(_ban_text, Vector2(0, c.y - 130.0 * u), int(40.0 * u), Color(1.0, 0.85, 0.2), vp.x, HORIZONTAL_ALIGNMENT_CENTER)

	if combat.dead:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))
		_text("YOU DIED", Vector2(0, c.y), int(70.0 * u), Color(0.95, 0.2, 0.15), vp.x, HORIZONTAL_ALIGNMENT_CENTER)
		_text("Respawning...", Vector2(0, c.y + 50.0 * u), int(28.0 * u), Color.WHITE, vp.x, HORIZONTAL_ALIGNMENT_CENTER)
