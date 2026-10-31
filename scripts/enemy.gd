extends CharacterBody3D
# Bandit soldier. Idles around its camp; when it sees you (or hears shots) it chases, strafes and shoots.

const Util = preload("res://scripts/util.gd")
const Cartoon = preload("res://scripts/cartoon.gd")
const GRAVITY := 20.0

var combat
var player: Node3D
var max_hp := 55.0
var hp := 55.0
var dmg := 5.5
var fire_gap := 1.0
var move_speed := 3.4
var sight := 42.0
var boss := false
var home := Vector3.ZERO
var patrol := 7.0
var alerted := false
var dead := false

var _height := 1.75 * Util.CHAR_SCALE
var _model: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _label: Label3D
var _snd: AudioStreamPlayer3D
var _walk_t := 0.0
var _shoot_t := 1.0
var _los_t := 0.0
var _los := false
var _wander_t := 0.0
var _wander_to := Vector3.ZERO
var _strafe := 1.0
var _strafe_t := 0.0
var _stuck_cd := 0.4
var _last_pos := Vector3.ZERO
var _side_t := 0.0
var _side_dir := 1.0
var _label_t := 0.0


func setup(c, p: Node3D, pos: Vector3, is_boss: bool, hp_mult: float) -> void:
	combat = c
	player = p
	boss = is_boss
	if boss:
		_height = 2.2 * Util.CHAR_SCALE
		max_hp = 320.0 * hp_mult
		dmg = 11.0
		fire_gap = 0.55
		move_speed = 3.0
		sight = 60.0
		patrol = 4.0
	else:
		max_hp = 55.0 * hp_mult
		dmg = 5.5 * (1.0 + (hp_mult - 1.0) * 0.3)
	hp = max_hp
	home = Vector3(pos.x, 0.0, pos.z)
	position = Vector3(pos.x, _height / 2.0 + 0.05, pos.z)


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = (0.38 if boss else 0.32) * Util.CHAR_SCALE
	cap.height = _height
	cs.shape = cap
	add_child(cs)
	_model = Node3D.new()
	_model.position = Vector3(0, -_height / 2.0, 0)
	var sc := _height / 1.524
	_model.scale = Vector3(sc, sc, sc)
	add_child(_model)
	_build()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 40
	_label.pixel_size = 0.012
	_label.outline_size = 8
	_label.position = Vector3(0, _height / 2.0 + 0.55, 0)
	_label.visible = false
	add_child(_label)
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = combat.enemy_sound
	_snd.unit_size = 12.0
	_snd.max_distance = 140.0
	add_child(_snd)
	_wander_to = global_position


func _limb(pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	var part := Util.mi(Util.box(size), color)
	part.position = Vector3(0, -size.y / 2.0, 0)
	j.add_child(part)
	_model.add_child(j)
	return j


func _build() -> void:
	var shirts: Array = [Color(0.4, 0.45, 0.25), Color(0.55, 0.38, 0.22), Color(0.35, 0.35, 0.42)]
	var shirt: Color = shirts[randi() % 3]
	if boss:
		shirt = Color(0.25, 0.22, 0.28)
	var parts: Dictionary = Cartoon.build(_model, {
		"shirt": shirt,
		"pants": Color(0.18, 0.18, 0.2) if boss else Color(0.4, 0.34, 0.24),
		"boots": Color(0.1, 0.1, 0.1),
		"hat": "helmet",
		"hat_col": Color(0.65, 0.1, 0.1) if boss else Color(0.3, 0.36, 0.22),
		"bandana": true, "angry": true, "outline": boss, "pack": not boss})
	_arm_l = parts["arm_l"]
	_arm_r = parts["arm_r"]
	_leg_l = parts["leg_l"]
	_leg_r = parts["leg_r"]
	var gun := Util.mi(Util.box(Vector3(0.07, 0.55, 0.09)), Color(0.1, 0.1, 0.12))
	gun.position = Vector3(0, -0.62, 0)
	_arm_r.add_child(gun)


func play_shot() -> void:
	if _snd != null:
		_snd.play()


func alert() -> void:
	if alerted or dead:
		return
	alerted = true
	_shoot_t = randf_range(0.5, 1.1)


# returns true when this hit killed the bandit
func take_hit(amount: float, head: bool) -> bool:
	if dead:
		return false
	hp -= amount * (2.0 if head else 1.0)
	alert()
	combat.alert_near(global_position, 20.0)
	_label.visible = true
	_label_t = 3.0
	var n := clampi(int(ceil(20.0 * maxf(hp, 0.0) / max_hp)), 0, 20)
	_label.text = "|".repeat(n)
	_label.modulate = Color(0.3, 1.0, 0.3).lerp(Color(1.0, 0.2, 0.15), 1.0 - clampf(hp / max_hp, 0.0, 1.0))
	if hp <= 0.0:
		_die()
		return true
	return false


func _die() -> void:
	dead = true
	collision_layer = 0
	_label.visible = false
	set_physics_process(false)
	var tw := create_tween()
	tw.tween_property(_model, "rotation:x", -PI / 2.0, 0.45)
	tw.tween_interval(6.0)
	tw.tween_callback(queue_free)
	combat.on_enemy_killed(self)


func _face(d: Vector3, delta: float, rate: float) -> void:
	if d.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), rate * delta)


func _check_los() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.6 * Util.CHAR_SCALE, 0)
	var to: Vector3 = player.global_position + Vector3(0, 0.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var r: Dictionary = space.intersect_ray(q)
	if r.is_empty():
		return true
	var col: Object = r["collider"]
	return col == player or (col is Node and (col as Node).is_in_group("tractor"))


func _physics_process(delta: float) -> void:
	if dead or player == null:
		return
	var to_p: Vector3 = player.global_position - global_position
	var flat := Vector3(to_p.x, 0.0, to_p.z)
	var dist := flat.length()
	if dist > 130.0:
		alerted = false
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
			move_and_slide()
		return
	if _label_t > 0.0:
		_label_t -= delta
		if _label_t <= 0.0 and _label != null:
			_label.visible = false

	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.25
		_los = dist < 75.0 and not combat.dead and _check_los()
	if not alerted and dist < sight and _los:
		alert()
		combat.alert_near(global_position, 22.0)

	var want := Vector3.ZERO
	var dir := flat.normalized() if dist > 0.01 else Vector3(0, 0, -1)
	if alerted:
		_face(dir, delta, 10.0)
		var pref := 14.0 if boss else 18.0
		if dist > pref + 6.0 or not _los:
			want = dir * move_speed * Util.CHAR_SCALE * 0.75
		elif dist < 8.0:
			want = -dir * move_speed * 0.8 * Util.CHAR_SCALE * 0.75
		else:
			_strafe_t -= delta
			if _strafe_t <= 0.0:
				_strafe_t = randf_range(1.0, 2.2)
				if randf() < 0.5:
					_strafe = -_strafe
			want = dir.rotated(Vector3.UP, PI / 2.0) * _strafe * move_speed * 0.6 * Util.CHAR_SCALE * 0.75
		_shoot_t -= delta
		if _los and dist < 55.0 and _shoot_t <= 0.0 and not combat.dead:
			_shoot_t = fire_gap * randf_range(0.8, 1.3)
			var hit_chance := clampf(0.7 - dist * 0.011, 0.12, 0.65)
			var muzzle := global_position + (Vector3(0, 0.3, 0) + (-global_transform.basis.z) * 0.8) * Util.CHAR_SCALE
			combat.enemy_shot(self, muzzle, randf() < hit_chance, dmg)
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(3.0, 7.0)
			if randf() < 0.6:
				_wander_to = home + Vector3(randf_range(-patrol, patrol), 0, randf_range(-patrol, patrol))
			else:
				_wander_to = global_position
		var d := _wander_to - global_position
		d.y = 0.0
		if d.length() > 0.7:
			want = d.normalized() * 1.4 * Util.CHAR_SCALE * 0.75
			_face(d, delta, 6.0)

	# stuck behind something? sidestep for a moment
	_stuck_cd -= delta
	if _stuck_cd <= 0.0:
		_stuck_cd = 0.4
		if want.length() > 0.1 and global_position.distance_to(_last_pos) < 0.3:
			_side_t = 0.8
			_side_dir = 1.0 if randf() < 0.5 else -1.0
		_last_pos = global_position
	if _side_t > 0.0:
		_side_t -= delta
		want = dir.rotated(Vector3.UP, PI / 2.0 * _side_dir) * move_speed * Util.CHAR_SCALE * 0.75

	var v := velocity
	v.x = want.x
	v.z = want.z
	if is_on_floor() and v.y <= 0.0:
		v.y = 0.0
	else:
		v.y -= GRAVITY * delta
	velocity = v
	move_and_slide()

	# walking animation
	var sp := Vector2(velocity.x, velocity.z).length()
	_walk_t += delta * sp * 3.0
	var swing := sin(_walk_t) * minf(sp / 3.0, 1.0) * 0.7
	var k := 15.0 * delta
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -swing, k)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, swing, k)
	if alerted:
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 1.45, k)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 1.1, k)
	else:
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -swing, k)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, swing, k)
