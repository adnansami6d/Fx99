extends Node3D
# Turns itself slowly around its local Z axis (windmill rotor). Very cheap.

var speed := 1.4


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	rotation.z += speed * delta
