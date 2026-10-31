extends Node
# Shooting layer: weapons, bandits, health, pickups and missions. Created by main.gd, built from code only.

const Util = preload("res://scripts/util.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HudScript = preload("res://scripts/combat_hud.gd")
const SAVE_PATH := "user://combat.json"
const MAX_HP := 100.0

const WEAPONS := [
	{"name": "PISTOL", "dmg": 30.0, "gap": 0.28, "mag": 12, "spread": 0.7, "reload": 1.1},
	{"name": "RIFLE", "dmg": 17.0, "gap": 0.11, "mag": 30, "spread": 2.0, "reload": 1.8},
]
# c = centre (x, z), half = half size of the bandit area. Towers / airport come from data/layout.json.
const MISSIONS := [
	{"name": "Free the south-west tower", "c": Vector2(-125, 125), "half": Vector2(15, 15), "n": 6, "boss": false, "reward": 250},
	{"name": "Free the south-east tower", "c": Vector2(125, 125), "half": Vector2(15, 15), "n": 7, "boss": false, "reward": 350},
	{"name": "Free the central tower", "c": Vector2(0, -42), "half": Vector2(14, 10), "n": 8, "boss": false, "reward": 450},
	{"name": "Capture the airport", "c": Vector2(139.5, 1), "half": Vector2(28, 13), "n": 10, "boss": true, "reward": 1000},
]

var main
var player
var rig
var touch
var farm
var minimap
var hud

var hp := MAX_HP
var dead := false
var firing := false
var cur := 1
var mag: Array = [12, 30]
var reserve: Array = [-1, 120]
var fire_t := 0.0
var reload_t := 0.0
var reload_total := 1.0
var reloading := false
var aim_hold := 0.0
var heal_wait := 0.0
var death_t := 0.0
var kills := 0
var owned: Array = [true, true]
var target_on := false
var bag_open := false
var _bag: Control
var _bag_box: HBoxContainer

var m_idx := 0
var m_alive := 0
var m_active := false
const MISSION_GAP := 1800.0   # 30 minutes between missions
var m_wait := 4.0
var m_next_at := 0.0         # unix time when the next mission starts (kept in the save)
var pickups: Array = []
var enemy_sound: AudioStreamWAV

var _s_pistol: AudioStreamPlayer
var _s_rifle: AudioStreamPlayer
var _s_reload: AudioStreamPlayer
var _s_hit: AudioStreamPlayer
var _s_hurt: AudioStreamPlayer
var _s_pick: AudioStreamPlayer
var _flags := {}
var _mark_t := 0.0


func setup(m, p, r, t, f, layer: CanvasLayer) -> void:
	main = m
	player = p
	rig = r
	touch = t
	farm = f
	hud = HudScript.new()
	hud.combat = self
	layer.add_child(hud)
	_build_bag(layer)
	enemy_sound = _noise_wav(0.3, 28.0, 85.0, 18.0, 0.9)
	_s_pistol = _player_snd(_noise_wav(0.28, 32.0, 120.0, 22.0, 1.0), -2.0)
	_s_rifle = _player_snd(_noise_wav(0.18, 45.0, 160.0, 35.0, 0.9), -4.0)
	_s_reload = _player_snd(_click_wav(), -2.0)
	_s_hit = _player_snd(_noise_wav(0.08, 90.0, 1100.0, 60.0, 0.5), -6.0)
	_s_hurt = _player_snd(_noise_wav(0.22, 18.0, 140.0, 14.0, 0.8), -2.0)
	_s_pick = _player_snd(_noise_wav(0.15, 30.0, 700.0, 18.0, 0.4), -4.0)
	_load_state()
	hud.banner("Bandits took over the towers! Follow the yellow marker.", 5.0)


func on_foot() -> bool:
	return player != null and not dead and not main.driving and not main.flying


func weapon_name() -> String:
	if cur < 0:
		return "NO WEAPON"
	return String(WEAPONS[cur]["name"])


func ammo_text() -> String:
	if cur < 0:
		return ""
	var r: int = reserve[cur]
	return "%d / %s" % [int(mag[cur]), "inf" if r < 0 else str(r)]


# ---------------------------------------------------------------- sounds (made from math, no files)

func _noise_wav(dur: float, decay: float, tone: float, tone_decay: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var v := (randf() * 2.0 - 1.0) * exp(-t * decay)
		if tone > 0.0:
			v += sin(TAU * tone * t) * exp(-t * tone_decay) * 0.9
		data.encode_s16(i * 2, int(clampf(v * vol, -1.0, 1.0) * 30000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st


func _click_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.55 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var a := exp(-t * 160.0)
		var b := 0.0
		if t >= 0.4:
			b = exp(-(t - 0.4) * 160.0)
		var v := (randf() * 2.0 - 1.0) * (a + b) * 0.6
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st


func _player_snd(stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


# ---------------------------------------------------------------- weapons

func reload() -> void:
	if cur < 0 or reloading or dead or not on_foot() or bag_open:
		return
	var w: Dictionary = WEAPONS[cur]
	var size: int = w["mag"]
	if int(mag[cur]) >= size:
		return
	if int(reserve[cur]) == 0:
		hud.say("No ammo! Find an ammo box.")
		return
	reloading = true
	reload_total = float(w["reload"])
	reload_t = reload_total
	_s_reload.play()


func _finish_reload() -> void:
	var size: int = WEAPONS[cur]["mag"]
	var need: int = size - int(mag[cur])
	var r: int = reserve[cur]
	if r < 0:
		mag[cur] = size
	else:
		var take: int = mini(need, r)
		mag[cur] = int(mag[cur]) + take
		reserve[cur] = r - take
	reloading = false


func swap_weapon() -> void:
	if dead or not on_foot() or bag_open:
		return
	if cur < 0:
		cur = 0 if owned[0] else (1 if owned[1] else -1)
	elif owned[1 - cur]:
		cur = 1 - cur
	else:
		hud.say("Only one weapon in the bag")
		return
	reloading = false
	fire_t = 0.2
	hud.say(weapon_name(), 1.0)


func _muzzle() -> Vector3:
	var yaw: float = player.pivot.rotation.y
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var rgt := Vector3(cos(yaw), 0.0, -sin(yaw))
	return player.global_position + (Vector3(0, 0.35, 0) + f * 0.85 + rgt * 0.25) * Util.CHAR_SCALE


func _spread_dir(fwd: Vector3, ang: float) -> Vector3:
	var b := Basis.looking_at(fwd, Vector3.UP)
	var a := randf() * TAU
	var m := randf() * ang
	return (b * Vector3(sin(m) * cos(a), sin(m) * sin(a), -cos(m))).normalized()


func _try_fire() -> void:
	if cur < 0:
		if fire_t <= 0.0:
			fire_t = 1.5
			hud.say("No weapon - open the BAG")
		return
	if reloading or fire_t > 0.0:
		return
	if int(mag[cur]) <= 0:
		reload()
		return
	var w: Dictionary = WEAPONS[cur]
	fire_t = float(w["gap"])
	mag[cur] = int(mag[cur]) - 1
	aim_hold = 1.5
	if cur == 0:
		_s_pistol.play()
	else:
		_s_rifle.play()

	var cam: Camera3D = rig.cam
	var cam_fwd: Vector3 = -cam.global_transform.basis.z
	var origin: Vector3 = cam.global_position + cam_fwd * 1.5
	var fwd := cam_fwd
	var tgt: Node3D = _assist_target(origin, cam_fwd, 7.0)   # light aim assist: pulls the shot toward a bandit near the crosshair
	if tgt != null:
		var td: Vector3 = (tgt.global_position + Vector3(0, 0.25, 0) - origin).normalized()
		fwd = cam_fwd.slerp(td, 0.65)
	var dir := _spread_dir(fwd, deg_to_rad(float(w["spread"])))
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 120.0, 5)
	q.exclude = [player.get_rid()]
	var r: Dictionary = space.intersect_ray(q)
	var aim: Vector3 = origin + dir * 120.0
	if not r.is_empty():
		aim = r["position"]

	var muzzle := _muzzle()
	var to_aim := aim - muzzle
	var end := aim
	if to_aim.length() > 0.5:
		var q2 := PhysicsRayQueryParameters3D.create(muzzle, muzzle + to_aim.normalized() * (to_aim.length() + 0.5), 5)
		q2.exclude = [player.get_rid()]
		var r2: Dictionary = space.intersect_ray(q2)
		if not r2.is_empty():
			end = r2["position"]
			var col: Object = r2["collider"]
			if col is Node and (col as Node).is_in_group("enemy"):
				var en = col
				var head: bool = end.y > en.global_position.y + 0.5 * Util.CHAR_SCALE
				var killed: bool = en.take_hit(float(w["dmg"]), head)
				hud.hit(killed)
				_s_hit.play()
				_puff(end, Color(1.0, 0.1, 0.05), 0.12, 0.12)
			else:
				_puff(end, Color(1.0, 0.85, 0.5), 0.09, 0.1)
	var tr_end := end
	if muzzle.distance_to(end) > 90.0:
		tr_end = muzzle + (end - muzzle).normalized() * 90.0
	_tracer(muzzle, tr_end, Color(1.0, 0.9, 0.4))
	_puff(muzzle, Color(1.0, 0.8, 0.3), 0.13, 0.04)
	alert_near(player.global_position, 22.0 if cur == 0 else 35.0)
	rig.pitch = clampf(rig.pitch - (0.012 if cur == 0 else 0.005), rig.PITCH_MIN, rig.PITCH_MAX)


func _tracer(a: Vector3, b: Vector3, col: Color) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, len)
	var mi := Util.mim(bm, Util.glow(col, 3.0))
	add_child(mi)
	mi.global_position = (a + b) / 2.0
	var up := Vector3.UP
	if absf((b - a).normalized().dot(Vector3.UP)) > 0.98:
		up = Vector3.RIGHT
	mi.look_at(b, up)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)


func _puff(pos: Vector3, col: Color, r: float, life: float) -> void:
	var mi := Util.mim(Util.sphere(r, 6, 3), Util.glow(col, 3.0))
	add_child(mi)
	mi.global_position = pos
	get_tree().create_timer(life).timeout.connect(mi.queue_free)


# ---------------------------------------------------------------- enemies call these

func alert_near(pos: Vector3, radius: float) -> void:
	var list: Array = get_tree().get_nodes_in_group("enemy")
	for e in list:
		if not e.dead and e.global_position.distance_to(pos) < radius:
			e.alert()


func enemy_shot(e, from: Vector3, hit: bool, amount: float) -> void:
	var tgt: Vector3 = player.global_position + Vector3(0, 0.3, 0)
	var end := tgt
	if not hit:
		end = tgt + Vector3(randf_range(-1.6, 1.6), randf_range(-0.8, 0.8), randf_range(-1.6, 1.6))
	var d := end - from
	var tr_end := from + d.normalized() * minf(d.length() + 4.0, 70.0)
	_tracer(from, tr_end, Color(1.0, 0.45, 0.2))
	_puff(from, Color(1.0, 0.6, 0.2), 0.12, 0.04)
	e.play_shot()
	if hit:
		hurt(amount)


func hurt(amount: float) -> void:
	if dead or main.flying:
		return
	hp -= amount
	heal_wait = 6.0
	hud.hurt()
	_s_hurt.play()
	if hp <= 0.0:
		hp = 0.0
		dead = true
		death_t = 3.0
		firing = false
		reloading = false


func on_enemy_killed(e) -> void:
	kills += 1
	m_alive = maxi(0, m_alive - 1)
	farm.coins += 80 if e.boss else 12
	_drop(e.global_position, e.boss)
	alert_near(e.global_position, 18.0)
	if m_active and m_alive == 0:
		_complete_mission()


# ---------------------------------------------------------------- pickups

func _pickup_node(kind: String) -> Node3D:
	var n := Node3D.new()
	if kind == "ammo":
		Util.part(n, Vector3(0.55, 0.32, 0.38), Vector3.ZERO, Util.mat(Color(0.3, 0.38, 0.2)))
		Util.part(n, Vector3(0.58, 0.08, 0.41), Vector3(0, 0.05, 0), Util.glow(Color(1.0, 0.8, 0.1), 1.2))
	elif kind.begins_with("gun"):
		Util.part(n, Vector3(0.9, 0.14, 0.22), Vector3.ZERO, Util.mat(Color(0.12, 0.12, 0.15)))
		Util.part(n, Vector3(0.3, 0.3, 0.2), Vector3(-0.2, -0.18, 0), Util.mat(Color(0.5, 0.32, 0.16)))
		Util.part(n, Vector3(1.2, 0.04, 1.2), Vector3(0, -0.45, 0), Util.glow(Color(0.2, 0.8, 1.0), 1.5))
	else:
		Util.part(n, Vector3(0.5, 0.32, 0.38), Vector3.ZERO, Util.mat(Color(0.95, 0.95, 0.95)))
		Util.part(n, Vector3(0.3, 0.34, 0.08), Vector3(0, 0, 0.2), Util.glow(Color(1.0, 0.1, 0.1), 1.2))
		Util.part(n, Vector3(0.08, 0.34, 0.3), Vector3(0, 0, 0.2), Util.glow(Color(1.0, 0.1, 0.1), 1.2))
	return n


func _drop(pos: Vector3, boss: bool) -> void:
	var kinds: Array = []
	var roll := randf()
	if boss:
		kinds = ["ammo", "health"]
	elif roll < 0.3:
		kinds = ["ammo"]
	elif roll < 0.48:
		kinds = ["health"]
	var i := 0
	for k in kinds:
		var n := _pickup_node(String(k))
		n.position = Vector3(pos.x + float(i) * 0.9, 0.55, pos.z)
		add_child(n)
		pickups.append({"n": n, "k": String(k), "t": 0.0, "cd": 0.0})
		i += 1


func _tick_pickups(delta: float) -> void:
	var pp: Vector3 = player.global_position
	for i in range(pickups.size() - 1, -1, -1):
		var p: Dictionary = pickups[i]
		var n: Node3D = p["n"]
		var t: float = float(p["t"]) + delta
		p["t"] = t
		n.rotation.y += delta * 2.0
		n.position.y = 0.55 + 0.12 * sin(t * 3.0)
		var cd: float = float(p.get("cd", 0.0))
		if cd > 0.0:
			p["cd"] = cd - delta
		var near := cd <= 0.0 and Vector2(n.position.x - pp.x, n.position.z - pp.z).length() < 1.9
		var kind := String(p["k"])
		if near and kind.begins_with("gun"):
			var wi: int = int(p["w"])
			if owned[wi]:
				near = false   # already carrying this weapon: leave it on the ground
			else:
				owned[wi] = true
				mag[wi] = int(p["mag"])
				reserve[wi] = int(p["res"])
				if cur < 0:
					cur = wi
				hud.say("Picked up " + String(WEAPONS[wi]["name"]))
				_s_pick.play()
				n.queue_free()
				pickups.remove_at(i)
				continue
		if near and not dead:
			if String(p["k"]) == "ammo":
				reserve[1] = mini(int(reserve[1]) + 45, 240)
				hud.say("+45 rifle ammo")
			else:
				hp = minf(MAX_HP, hp + 40.0)
				hud.say("+40 health")
			_s_pick.play()
		if (near and not dead) or (t > 90.0 and not kind.begins_with("gun")):
			n.queue_free()
			pickups.remove_at(i)


# ---------------------------------------------------------------- missions

func objective_text() -> String:
	if dead:
		return ""
	var n := MISSIONS.size()
	if not m_active:
		if m_wait > 0.0:
			return "Next mission in %02d:%02d" % [int(ceil(m_wait)) / 60, int(ceil(m_wait)) % 60]
		return ""
	var m: Dictionary = MISSIONS[m_idx % n]
	var c: Vector2 = m["c"]
	var d := int(Vector2(player.global_position.x, player.global_position.z).distance_to(c))
	var rnd := ""
	if m_idx >= n:
		rnd = "  (round %d)" % (floori(float(m_idx) / float(n)) + 1)
	return "MISSION %d: %s%s\nBandits left: %d     Target: %d m" % [(m_idx % n) + 1, String(m["name"]), rnd, m_alive, d]


func _spawn_point(c: Vector2, half: Vector2) -> Vector3:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var pp := Vector2(player.global_position.x, player.global_position.z)
	for t in 14:
		var x := c.x + randf_range(-half.x, half.x)
		var z := c.y + randf_range(-half.y, half.y)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60.0, z), Vector3(x, -2.0, z), 1)
		var r: Dictionary = space.intersect_ray(q)
		if not r.is_empty():
			var hp3: Vector3 = r["position"]
			if hp3.y < 0.4 and Vector2(x, z).distance_to(pp) > 12.0:
				return Vector3(x, 1.0, z)
	return Vector3(c.x + randf_range(-3.0, 3.0), 1.0, c.y + randf_range(-3.0, 3.0))


func _spawn_enemy(pos: Vector3, is_boss: bool, mult: float) -> void:
	var e := EnemyScript.new()
	e.setup(self, player, pos, is_boss, mult)
	add_child(e)


func _start_mission() -> void:
	var n := MISSIONS.size()
	var m: Dictionary = MISSIONS[m_idx % n]
	var rnd := floori(float(m_idx) / float(n))
	var mult := 1.0 + 0.4 * float(rnd)
	var count: int = int(m["n"]) + 2 * rnd
	var c: Vector2 = m["c"]
	var half: Vector2 = m["half"]
	for i in count:
		_spawn_enemy(_spawn_point(c, half), false, mult)
	m_alive = count
	if bool(m["boss"]):
		_spawn_enemy(_spawn_point(c, Vector2(4.0, 4.0)), true, mult)
		m_alive += 1
	m_active = true
	hud.banner("MISSION %d: %s" % [(m_idx % n) + 1, String(m["name"])], 5.0)


func _complete_mission() -> void:
	m_active = false
	var n := MISSIONS.size()
	var m: Dictionary = MISSIONS[m_idx % n]
	var reward: int = int(m["reward"]) * (1 + floori(float(m_idx) / float(n)))
	farm.coins += reward
	hp = MAX_HP
	reserve[1] = mini(int(reserve[1]) + 90, 240)
	var c: Vector2 = m["c"]
	_flag(Vector3(c.x - 3.0, 0.0, c.y))
	hud.banner("MISSION COMPLETE   +%d coins\nNext mission in 30 min" % reward, 5.0)
	m_idx += 1
	m_wait = MISSION_GAP
	m_next_at = Time.get_unix_time_from_system() + MISSION_GAP
	_save_state()


func _flag(pos: Vector3) -> void:
	var key := "%d_%d" % [int(pos.x), int(pos.z)]
	if _flags.has(key):
		return
	_flags[key] = true
	var pole := Util.mim(Util.cyl(0.12, 14.0, 6), Util.mat(Color(0.7, 0.7, 0.72)))
	pole.position = pos + Vector3(0, 7.0, 0)
	add_child(pole)
	var cloth := Util.mim(Util.box(Vector3(2.4, 1.4, 0.06)), Util.glow(Color(0.2, 0.9, 0.3), 1.0))
	cloth.position = pos + Vector3(1.3, 13.0, 0)
	add_child(cloth)


func _save_state() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"m": m_idx, "res": int(reserve[1]), "kills": kills, "next": m_next_at}))


func _load_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		m_idx = int(d.get("m", 0))
		reserve[1] = clampi(int(d.get("res", 120)), 30, 240)
		kills = int(d.get("kills", 0))
		m_next_at = float(d.get("next", 0.0))
		if m_next_at > 0.0:
			m_wait = clampf(m_next_at - Time.get_unix_time_from_system(), 4.0, MISSION_GAP)
		# flags of finished missions come back
		var n := MISSIONS.size()
		for i in mini(m_idx, n):
			var c: Vector2 = MISSIONS[i]["c"]
			_flag(Vector3(c.x - 3.0, 0.0, c.y))


# ---------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if dead:
		death_t -= delta
		if death_t <= 0.0:
			dead = false
			hp = MAX_HP
			main.respawn_player()
		return

	var can := on_foot()
	fire_t -= delta
	aim_hold -= delta
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			_finish_reload()
	player.aiming = can and cur >= 0 and (firing or aim_hold > 0.0)
	if firing and can and not bag_open:
		_try_fire()
	_aim_check(delta, can)

	if hp < MAX_HP:
		heal_wait -= delta
		if heal_wait <= 0.0:
			hp = minf(MAX_HP, hp + 4.0 * delta)

	_tick_pickups(delta)

	if not m_active:
		if m_wait > 0.0:
			m_wait -= delta
			if m_wait <= 0.0:
				_start_mission()

	_mark_t -= delta
	if _mark_t <= 0.0:
		_mark_t = 0.1
		_update_marks()


func _update_marks() -> void:
	if minimap == null:
		return
	var pts: Array = []
	var list: Array = get_tree().get_nodes_in_group("enemy")
	for e in list:
		if not e.dead:
			pts.append(Vector2(e.global_position.x, e.global_position.z))
	minimap.enemy_pts = pts
	if m_active:
		var m: Dictionary = MISSIONS[m_idx % MISSIONS.size()]
		minimap.objective = m["c"]
	else:
		minimap.objective = Vector2(1.0e9, 1.0e9)


# ---------------------------------------------------------------- aim help

func _assist_target(cam_pos: Vector3, cam_fwd: Vector3, max_deg: float) -> Node3D:
	var best: Node3D = null
	var best_a := deg_to_rad(max_deg)
	var list: Array = get_tree().get_nodes_in_group("enemy")
	for e in list:
		if e.dead:
			continue
		var d: Vector3 = e.global_position + Vector3(0, 0.25, 0) - cam_pos
		var dl := d.length()
		if dl > 70.0 or dl < 2.0:
			continue
		var a := cam_fwd.angle_to(d / dl)
		if a < best_a:
			best_a = a
			best = e
	return best


# crosshair turns red over a bandit; while firing the camera is pulled gently toward a bandit near the crosshair
func _aim_check(delta: float, can: bool) -> void:
	target_on = false
	if not can or bag_open:
		return
	var cam: Camera3D = rig.cam
	var cf: Vector3 = -cam.global_transform.basis.z
	var o: Vector3 = cam.global_position + cf * 1.5
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o, o + cf * 110.0, 5)
	q.exclude = [player.get_rid()]
	var r: Dictionary = space.intersect_ray(q)
	if not r.is_empty():
		var col: Object = r["collider"]
		target_on = col is Node and (col as Node).is_in_group("enemy")
	var tg: Node3D = _assist_target(cam.global_position, cf, 9.0 if firing else 2.5)
	if tg != null and not firing:
		target_on = true
	if firing and cur >= 0 and tg != null:
		var d: Vector3 = tg.global_position + Vector3(0, 0.25, 0) - cam.global_position
		var k := 1.0 - exp(-3.0 * delta)
		rig.yaw = lerp_angle(rig.yaw, atan2(-d.x, -d.z), k)
		rig.pitch = clampf(lerpf(rig.pitch, -asin(clampf(d.normalized().y, -1.0, 1.0)), k), rig.PITCH_MIN, rig.PITCH_MAX)


# ---------------------------------------------------------------- bag (weapons list, drop)

func _build_bag(layer: CanvasLayer) -> void:
	_bag = Control.new()
	_bag.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bag.visible = false
	layer.add_child(_bag)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bag.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bag.add_child(cc)
	var panel := PanelContainer.new()
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "BAG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	vb.add_child(title)
	_bag_box = HBoxContainer.new()
	_bag_box.add_theme_constant_override("separation", 20)
	vb.add_child(_bag_box)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0, 70)
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(close_bag)
	vb.add_child(close)


func open_bag() -> void:
	if dead or not on_foot() or _bag == null:
		return
	bag_open = true
	firing = false
	touch.release_all()
	_refresh_bag()
	_bag.visible = true


func close_bag() -> void:
	bag_open = false
	if _bag != null:
		_bag.visible = false


func _refresh_bag() -> void:
	for c in _bag_box.get_children():
		c.queue_free()
	var any := false
	for i in 2:
		if not owned[i]:
			continue
		any = true
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 8)
		var icon = preload("res://scripts/weapon_icon.gd").new()
		icon.kind = i
		card.add_child(icon)
		var name_l := Label.new()
		name_l.text = "%s%s" % [String(WEAPONS[i]["name"]), "   (in hand)" if cur == i else ""]
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 26)
		card.add_child(name_l)
		var res: int = reserve[i]
		var ammo_l := Label.new()
		ammo_l.text = "Ammo %d / %s" % [int(mag[i]), "inf" if res < 0 else str(res)]
		ammo_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ammo_l.add_theme_font_size_override("font_size", 22)
		card.add_child(ammo_l)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var eq := Button.new()
		eq.text = "EQUIP"
		eq.disabled = cur == i
		eq.custom_minimum_size = Vector2(120, 64)
		eq.add_theme_font_size_override("font_size", 24)
		eq.pressed.connect(_equip.bind(i))
		row.add_child(eq)
		var dr := Button.new()
		dr.text = "DROP"
		dr.custom_minimum_size = Vector2(120, 64)
		dr.add_theme_font_size_override("font_size", 24)
		dr.pressed.connect(_drop_weapon.bind(i))
		row.add_child(dr)
		card.add_child(row)
		_bag_box.add_child(card)
	if not any:
		var empty := Label.new()
		empty.text = "Empty. Find weapons on the ground."
		empty.add_theme_font_size_override("font_size", 26)
		_bag_box.add_child(empty)


func _equip(i: int) -> void:
	cur = i
	reloading = false
	fire_t = 0.2
	_refresh_bag()


func _drop_weapon(i: int) -> void:
	if not owned[i]:
		return
	var yaw: float = player.pivot.rotation.y
	var n := _pickup_node("gun%d" % i)
	n.position = player.global_position + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 1.5
	n.position.y = 0.55
	add_child(n)
	pickups.append({"n": n, "k": "gun%d" % i, "t": 0.0, "cd": 1.5, "w": i, "mag": int(mag[i]), "res": int(reserve[i])})
	owned[i] = false
	reloading = false
	if cur == i:
		cur = -1
		if owned[1 - i]:
			cur = 1 - i
	_refresh_bag()
