extends Node3D
# Third-person camera that orbits the target. Drag = look left/right and up/down.
# set_target(node, distance, height, follow_heading)
#   follow_heading = true: camera slowly swings behind the target (used for the tractor)

const PITCH_MIN := -0.1   # camera low, looking up
const PITCH_MAX := 1.2    # camera high, looking down

var target: Node3D
var yaw := 0.0
var pitch := 0.04   # V29.1: almost level like Free Fire (was 0.2 = looking down, too much ground)
var dist := 3.0
var height := 0.7
var follow_heading := false
var idle := 0.0
var cam: Camera3D
var shoulder := 0.55   # on foot the character stands a bit left of the crosshair


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 60.0   # V29: closer, Free Fire-like view
	cam.far = 160.0   # nothing beyond 160 m is drawn
	cam.near = 0.2
	add_child(cam)
	cam.current = true


func look(dx: float, dy: float) -> void:
	yaw -= dx * 0.006
	pitch = clampf(pitch + dy * 0.006, PITCH_MIN, PITCH_MAX)
	idle = 0.0


func _center() -> Vector3:
	var c := target.global_position + Vector3(0, height, 0)
	if target.is_in_group("player"):
		c += Basis(Vector3.UP, yaw) * Vector3(shoulder, 0, 0)
	return c


func _wanted_pos() -> Vector3:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	return _center() + b * Vector3(0, 0, dist)


func set_target(t: Node3D, d: float = 3.0, h: float = 0.7, follow: bool = false) -> void:
	target = t
	dist = d
	height = h
	follow_heading = follow
	idle = 0.0
	if follow:
		yaw = t.rotation.y
	cam.global_position = _wanted_pos()
	cam.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	idle += delta
	if follow_heading and idle > 3.0:
		yaw = lerp_angle(yaw, target.rotation.y, 1.5 * delta)
	cam.global_position = cam.global_position.lerp(_wanted_pos(), 14.0 * delta)
	cam.look_at(_center())
