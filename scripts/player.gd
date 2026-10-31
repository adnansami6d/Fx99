extends CharacterBody3D
# The character. Height = 5 ft = 1.524 m.
# Built-in body is a placeholder. use_model(node) swaps in your own character.
# main.gd sets move_dir (joystick) and cam_yaw (camera) every frame.

const Util = preload("res://scripts/util.gd")
const Cartoon = preload("res://scripts/cartoon.gd")
const HEIGHT := 1.524
const WALK_SPEED := 3.0 * Util.CHAR_SCALE
const RUN_SPEED := 6.5 * Util.CHAR_SCALE
const JUMP_SPEED := 6.0
const GRAVITY := 20.0
const CUSTOM_MODEL_TURN_DEG := 180.0   # glb models usually face +Z; change to 0 if yours walks backwards

var move_dir := Vector2.ZERO
var cam_yaw := 0.0
var running := false

var model: Node3D
var pivot: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var anim: AnimationPlayer
var anim_t := 0.0
var was_on_floor := true
var squash := 0.0
var seated := false
var aiming := false   # combat.gd: facing the camera direction with the gun up


func _ready() -> void:
	add_to_group("player")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25 * Util.CHAR_SCALE
	cap.height = HEIGHT * Util.CHAR_SCALE
	cs.shape = cap
	add_child(cs)

	pivot = Node3D.new()
	pivot.scale = Vector3.ONE * Util.CHAR_SCALE
	add_child(pivot)
	model = Node3D.new()
	model.position = Vector3(0, -HEIGHT / 2.0, 0)   # feet at the bottom of the capsule
	pivot.add_child(model)
	_build_placeholder()


func _build_placeholder() -> void:
	var parts: Dictionary = Cartoon.build(model, {"shirt": Color(0.2, 0.55, 0.9), "pants": Color(0.25, 0.28, 0.42), "boots": Color(0.4, 0.26, 0.15), "hair": Color(0.25, 0.15, 0.08), "hat": "cap", "hat_col": Color(0.9, 0.2, 0.2), "pack": true, "outline": true})
	arm_l = parts["arm_l"]
	arm_r = parts["arm_r"]
	leg_l = parts["leg_l"]
	leg_r = parts["leg_r"]
	var gun := Util.mi(Util.box(Vector3(0.07, 0.55, 0.09)), Color(0.12, 0.12, 0.14))
	gun.position = Vector3(0, -0.62, 0)
	arm_r.add_child(gun)


# a limb = a joint node at the top; the box hangs below it, so rotating the joint swings the limb
func _limb(pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	var part := Util.mi(Util.box(size), color)
	part.position = Vector3(0, -size.y / 2.0, 0)
	j.add_child(part)
	model.add_child(j)
	return j


# Swap the placeholder for your own character (call after the player is in the scene).
func use_model(node: Node3D) -> void:
	for c in model.get_children():
		c.queue_free()
	arm_l = null
	arm_r = null
	leg_l = null
	leg_r = null
	model.add_child(node)

	var box := _model_aabb(node)
	if box.size.y > 0.001:
		var s := HEIGHT / box.size.y
		node.scale = Vector3.ONE * s
		node.position.y = -box.position.y * s
	node.rotation_degrees.y = CUSTOM_MODEL_TURN_DEG

	var aps := node.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		anim = aps[0]


func _model_aabb(root: Node3D) -> AABB:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	var box := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for m in meshes:
		var xf: Transform3D = inv * m.global_transform
		var b: AABB = xf * m.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


# Sit on a seat marker (tractor). Character stays visible; physics off while seated.
func sit(seat: Node3D) -> void:
	seated = true
	running = false
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	reparent(seat, false)
	position = Vector3.ZERO
	reset_physics_interpolation()
	rotation = Vector3.ZERO
	pivot.rotation = Vector3.ZERO
	pivot.scale = Vector3.ONE
	model.rotation = Vector3.ZERO
	model.scale = Vector3.ONE
	if arm_l != null:
		arm_l.rotation.x = -1.0
		arm_r.rotation.x = -1.0
		leg_l.rotation.x = -1.3
		leg_r.rotation.x = -1.3
	elif anim != null and anim.has_animation("sit"):
		anim.play("sit")


func stand(world: Node, pos: Vector3) -> void:
	reparent(world, false)
	global_position = pos
	reset_physics_interpolation()
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	collision_layer = 1
	collision_mask = 1
	pivot.scale = Vector3.ONE * Util.CHAR_SCALE
	seated = false
	set_physics_process(true)


func jump() -> void:
	if is_on_floor():
		velocity.y = JUMP_SPEED


# Run: tap once = keeps running in the camera direction. Tap again = stop.
func toggle_run() -> void:
	running = not running


func _physics_process(delta: float) -> void:
	var dir := move_dir
	var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if kb != Vector2.ZERO:
		dir = kb
	if Input.is_action_just_pressed("ui_accept"):
		jump()

	# V29: touching the joystick while auto-running stops the run (walk with the stick)
	if running and move_dir.length() > 0.1:
		running = false
	# auto-run: no joystick -> go straight ahead (the way the camera looks)
	if running and dir.length() < 0.1:
		dir = Vector2(0, -1)

	var moving := dir.length() > 0.1
	var speed := RUN_SPEED if running else WALK_SPEED
	var wd := Vector3(dir.x, 0, dir.y).rotated(Vector3.UP, cam_yaw)
	var v := velocity
	v.x = wd.x * speed
	v.z = wd.z * speed
	if is_on_floor() and v.y <= 0.0:
		v.y = 0.0
	else:
		v.y -= GRAVITY * delta
	velocity = v
	move_and_slide()

	if aiming:
		pivot.rotation.y = lerp_angle(pivot.rotation.y, cam_yaw, 18.0 * delta)
	elif moving:
		var target := atan2(-wd.x, -wd.z)
		pivot.rotation.y = lerp_angle(pivot.rotation.y, target, 12.0 * delta)

	_animate(delta, dir)


func _animate(delta: float, dir: Vector2) -> void:
	var on_floor := is_on_floor()

	if arm_l == null:
		# custom model: play its animations if it has them
		if anim != null:
			var want := "idle"
			if not on_floor:
				want = "jump"
			elif dir.length() > 0.1:
				want = "run" if running else "walk"
			if anim.has_animation(want) and anim.current_animation != want:
				anim.play(want)
	else:
		var al := 0.0
		var ar := 0.0
		var ll := 0.0
		var lr := 0.0
		var lean := 0.0
		if not on_floor:
			# jump pose: arms up, knees tucked
			al = -2.6
			ar = -2.6
			ll = -0.9
			lr = 0.4
		else:
			var sp := minf(dir.length(), 1.0)
			anim_t += delta * (14.0 if running else 9.0) * sp
			var amp := (1.1 if running else 0.7) * sp
			var swing := sin(anim_t) * amp
			al = swing
			ar = -swing
			ll = -swing
			lr = swing
			if running and sp > 0.1:
				lean = -0.18   # lean forward
		if aiming:
			ar = 1.45
			al = 1.1
		var k := 20.0 * delta
		arm_l.rotation.x = lerpf(arm_l.rotation.x, al, k)
		arm_r.rotation.x = lerpf(arm_r.rotation.x, ar, k)
		leg_l.rotation.x = lerpf(leg_l.rotation.x, ll, k)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, lr, k)
		model.rotation.x = lerpf(model.rotation.x, lean, k)

	# landing squash
	if on_floor and not was_on_floor:
		squash = 0.15
	was_on_floor = on_floor
	squash = lerpf(squash, 0.0, 12.0 * delta)
	model.scale.y = 1.0 - squash
