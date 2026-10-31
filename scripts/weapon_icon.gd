extends Control
# Draws a picture of a gun (kind 0 = pistol, 1 = rifle) for the bag screen.

var kind := 0


func _init() -> void:
	custom_minimum_size = Vector2(250, 120)


func _draw() -> void:
	var s := size
	var steel := Color(0.78, 0.8, 0.85)
	var dark := Color(0.14, 0.14, 0.17)
	var wood := Color(0.5, 0.32, 0.16)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.12, 0.13, 0.16))
	if kind == 0:
		draw_rect(Rect2(s.x * 0.22, s.y * 0.3, s.x * 0.58, s.y * 0.18), steel)                 # slide
		draw_rect(Rect2(s.x * 0.8, s.y * 0.34, s.x * 0.08, s.y * 0.1), dark)                  # barrel tip
		draw_rect(Rect2(s.x * 0.22, s.y * 0.48, s.x * 0.4, s.y * 0.09), dark)                 # frame
		draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.27, s.y * 0.48), Vector2(s.x * 0.42, s.y * 0.48), Vector2(s.x * 0.37, s.y * 0.88), Vector2(s.x * 0.23, s.y * 0.88)]), wood)
		draw_arc(Vector2(s.x * 0.5, s.y * 0.6), s.y * 0.1, 0.0, PI, 10, dark, 3.0)           # trigger guard
	else:
		draw_rect(Rect2(s.x * 0.1, s.y * 0.38, s.x * 0.2, s.y * 0.2), wood)                   # stock
		draw_rect(Rect2(s.x * 0.3, s.y * 0.36, s.x * 0.34, s.y * 0.16), dark)                 # body
		draw_rect(Rect2(s.x * 0.64, s.y * 0.4, s.x * 0.3, s.y * 0.07), steel)                 # barrel
		draw_rect(Rect2(s.x * 0.4, s.y * 0.28, s.x * 0.16, s.y * 0.08), steel)                # sight
		draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.44, s.y * 0.52), Vector2(s.x * 0.54, s.y * 0.52), Vector2(s.x * 0.58, s.y * 0.82), Vector2(s.x * 0.46, s.y * 0.82)]), steel)   # magazine
		draw_rect(Rect2(s.x * 0.32, s.y * 0.52, s.x * 0.08, s.y * 0.2), wood)                 # grip
