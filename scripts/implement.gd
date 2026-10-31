extends Node3D
# BASE for every machine you hook to the tractor (plow, harvester, seeder, sprayer ...).
#
# To make a NEW machine (example: harvester):
#   1. new file  scripts/harvester.gd   with   extends "res://scripts/implement.gd"
#   2. in _init() set the numbers below (label, transport_kmh, work_kmh)
#   3. build its look in _build()      (needs a Marker3D called "Hitch" - the base makes it for you)
#   4. write what it does in _work(delta, ground_speed)   <- called every frame while WORK is ON
#   5. optional: _on_work_changed(on) for animation (lift / lower / start spinning)
# Then put it in the world like  scripts/plow.gd  is placed in main.gd. Nothing else changes:
# the WORK button, the speed limits and the field data all work for any machine.
#
# SPEED LIMITS (written here, in the machine itself - km/h):
#   transport_kmh = max speed while the machine is only hooked on (not working)
#   work_kmh      = max speed while WORK is ON
# The tractor itself never goes faster than its own limit (60 km/h).

const Util = preload("res://scripts/util.gd")

var label := "MACHINE"          # shown on the screen
var side := "rear"               # "rear" or "front" hitch of the tractor
var transport_kmh := 55.0
var work_kmh := 20.0

var working := false
var attached := false
var ground_speed := 0.0          # m/s, measured from the real movement (negative = reverse)
var field_map: Node = null       # the map (has till_at() etc.), found automatically

var _last_pos := Vector3.ZERO
var _have_last := false


func _ready() -> void:
	add_to_group("attachment")
	set_meta("side", side)
	var hitch := Marker3D.new()
	hitch.name = "Hitch"
	hitch.position = Vector3(0, 0.5, 0)
	add_child(hitch)
	_build()
	Util.bake(self)   # V29: merge static parts (draw calls)
	field_map = get_tree().get_first_node_in_group("field_map")


# --- things the tractor / main.gd call -------------------------------------------------------

# max speed (km/h) this machine allows right now
func speed_limit_kmh() -> float:
	return work_kmh if working else transport_kmh


func set_working(on: bool) -> void:
	if on == working:
		return
	working = on
	_on_work_changed(on)


func toggle_working() -> void:
	set_working(not working)


# called by the tractor when it connects / disconnects
func hooked(on: bool) -> void:
	attached = on
	_have_last = false
	if not on:
		set_working(false)


func _physics_process(delta: float) -> void:
	# ground speed from the real movement. The machine points backwards (+Z), so driving forward moves it along -Z
	if _have_last and delta > 0.0:
		var v := (global_position - _last_pos) / delta
		ground_speed = (-1.0 if side == "rear" else 1.0) * v.dot(global_transform.basis.z)   # rear machines point backwards, front ones forwards
	_last_pos = global_position
	_have_last = true
	_animate(delta)
	if working:
		_work(delta, ground_speed)


# --- override these in your machine ------------------------------------------------------------

func _build() -> void:
	pass


func _work(_delta: float, _ground_speed: float) -> void:
	pass


func _on_work_changed(_on: bool) -> void:
	pass


func _animate(_delta: float) -> void:
	pass


# --- optional: machines override these (screen text, saving) ---
func hud_text() -> String:
	return ""


func extra_state() -> Dictionary:
	return {}


func load_extra(_d: Dictionary) -> void:
	pass
