extends Node3D
# Fast helicopter. Arrows (keyboard or on-screen): UP=forward DOWN=back LEFT/RIGHT=turn. Q/E or UP/DOWN buttons = height.
# Front = -Z (same as the tractor). Sound is made from math (muffled cabin rotor + engine).
const Util = preload("res://scripts/util.gd")
const FuelD = preload("res://scripts/farm_data.gd")
const MAX_SPEED := 45.0   # m/s (~160 km/h)
const ACCEL := 14.0
const TURN := 1.5
const CLIMB := 9.0
const CRUISE_MIN := 4.0
const MAX_ALT := 120.0

var fuel := FuelD.FUEL_TANK_HELI   # liters
var fuel_cap := FuelD.FUEL_TANK_HELI
var fwd := 0.0       # -1..1 input
var turn := 0.0
var lift := 0.0
var speed := 0.0
var flying := false
var ground_y := 0.0
var seat: Marker3D
var main_rotor: Node3D
var tail_rotor: Node3D
var rotor_speed := 0.0
var snd: AudioStreamPlayer
var vy := 0.0


func _ready() -> void:
	add_to_group("helicopter")
	_build()
	snd = _make_sound()
	await get_tree().physics_frame
	await get_tree().physics_frame
	ground_y = _ground_below(global_position.y + 60.0)
	global_position.y = ground_y + 0.05


func _ground_below(from_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(global_position.x, from_y, global_position.z), Vector3(global_position.x, from_y - 400.0, global_position.z))
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return r.position.y if not r.is_empty() else ground_y


func _build() -> void:
	var red := Util.mat(Color(0.78, 0.07, 0.1), 0.25, 0.45)
	var white := Util.mat(Color(0.95, 0.96, 0.97), 0.3, 0.3)
	var dark := Util.mat(Color(0.08, 0.09, 0.1), 0.5, 0.3)
	var steel := Util.mat(Color(0.55, 0.57, 0.62), 0.3, 0.8)
	var gold := Util.mat(Color(0.95, 0.76, 0.1), 0.35, 0.4)
	var glass := Util.mat(Color(0.45, 0.75, 0.95, 0.35), 0.05, 0.1)
	var lamp := Util.glow(Color(1.0, 0.95, 0.7), 1.8)
	var redl := Util.glow(Color(1.0, 0.1, 0.05), 1.8)

	# fuselage (ellipsoids look smooth) + red belly + white stripe
	var body := Util.mim(Util.sphere(1.0, 16, 8), red)
	body.scale = Vector3(1.25, 1.2, 2.5)
	body.position = Vector3(0, 1.6, 0)
	add_child(body)
	var belly := Util.mim(Util.sphere(1.0, 14, 7), white)
	belly.scale = Vector3(1.0, 0.5, 2.2)
	belly.position = Vector3(0, 0.95, 0.1)
	add_child(belly)
	Util.part(self, Vector3(2.52, 0.14, 4.2), Vector3(0, 1.55, 0.3), gold)       # gold stripe around the body
	# glass canopy
	var can := Util.mim(Util.sphere(1.0, 16, 8), glass)
	can.scale = Vector3(1.12, 1.0, 1.55)
	can.position = Vector3(0, 1.95, -1.35)
	add_child(can)
	Util.part(self, Vector3(0.06, 1.0, 0.06), Vector3(0, 2.0, -2.3), dark)
	# tail boom, fin, stabilizer
	Util.part(self, Vector3(0.5, 0.55, 4.4), Vector3(0, 1.95, 4.2), red, Vector3(-4, 0, 0))
	Util.part(self, Vector3(0.12, 1.5, 0.9), Vector3(0, 2.7, 6.2), red, Vector3(-18, 0, 0))
	Util.part(self, Vector3(1.8, 0.08, 0.6), Vector3(0, 2.1, 5.9), white)
	Util.part(self, Vector3(0.14, 0.14, 0.14), Vector3(0, 3.4, 6.45), redl)
	# engine hump + exhausts
	var hump := Util.mim(Util.sphere(1.0, 16, 8), white)
	hump.scale = Vector3(0.8, 0.5, 1.2)
	hump.position = Vector3(0, 2.75, 0.5)
	add_child(hump)
	for sx in [-0.35, 0.35]:
		var ex := Util.mim(Util.cyl(0.1, 0.5, 10), dark)
		ex.rotation_degrees.x = 90.0
		ex.position = Vector3(sx, 2.8, 1.7)
		add_child(ex)
	# nose lights
	for sx in [-0.55, 0.55]:
		Util.part(self, Vector3(0.22, 0.16, 0.1), Vector3(sx, 1.35, -3.0), lamp)
	# skids
	for sx in [-1.0, 1.0]:
		Util.part(self, Vector3(0.1, 0.1, 4.4), Vector3(1.15 * sx, 0.1, -0.2), steel)
		Util.part(self, Vector3(0.1, 1.0, 0.1), Vector3(1.0 * sx, 0.6, -1.2), steel, Vector3(0, 0, -12 * sx))
		Util.part(self, Vector3(0.1, 1.0, 0.1), Vector3(1.0 * sx, 0.6, 1.2), steel, Vector3(0, 0, -12 * sx))
		Util.part(self, Vector3(0.12, 0.12, 0.5), Vector3(1.15 * sx, 0.1, -2.5), steel, Vector3(-30, 0, 0))
	# main rotor
	Util.part(self, Vector3(0.18, 0.5, 0.18), Vector3(0, 3.15, 0.4), dark)
	main_rotor = Node3D.new()
	main_rotor.position = Vector3(0, 3.45, 0.4)
	add_child(main_rotor)
	var hub := Util.mim(Util.cyl(0.22, 0.2, 12), gold)
	main_rotor.add_child(hub)
	for k in 4:
		var arm := Node3D.new()
		arm.rotation_degrees.y = 90.0 * k
		main_rotor.add_child(arm)
		Util.part(arm, Vector3(5.6, 0.05, 0.38), Vector3(3.0, 0, 0), dark)
		Util.part(arm, Vector3(0.7, 0.055, 0.39), Vector3(5.75, 0, 0), red)
	# tail rotor
	tail_rotor = Node3D.new()
	tail_rotor.position = Vector3(0.2, 2.9, 6.45)
	add_child(tail_rotor)
	for k in 2:
		var b := Node3D.new()
		b.rotation_degrees.x = 90.0 * k
		tail_rotor.add_child(b)
		Util.part(b, Vector3(0.05, 1.5, 0.15), Vector3(0, 0, 0), dark)
	# pilot seat (character sits here)
	Util.part(self, Vector3(0.7, 0.15, 0.6), Vector3(0, 1.2, -1.0), dark)
	Util.part(self, Vector3(0.7, 0.7, 0.12), Vector3(0, 1.6, -0.62), dark)
	seat = Marker3D.new()
	seat.position = Vector3(0, 1.15, -1.0)
	add_child(seat)
	Util.bake(self)   # V29: merge static parts (draw calls)


# engine + rotor "thump", loops cleanly (cabin = muffled, low)
func _make_sound() -> AudioStreamPlayer:
	var rate := 22050
	var n := 11025   # 0.5 s loop: 8 rotor beats = 16 Hz, engine 110 Hz fits exactly
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / float(rate)
		var beat := pow(maxf(0.0, sin(TAU * 16.0 * t)), 3.0)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.12)
		var v := beat * (0.7 * sin(TAU * 48.0 * t) + 0.9 * lp) + 0.22 * sin(TAU * 110.0 * t) + 0.1 * sin(TAU * 220.0 * t) + 0.12 * lp
		data.encode_s16(i * 2, int(clampf(v * 0.55, -1.0, 1.0) * 24000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	var pl := AudioStreamPlayer.new()
	pl.stream = st
	pl.volume_db = -80.0
	add_child(pl)
	return pl


func start_flight() -> void:
	flying = true
	if not snd.playing:
		snd.play()


func stop_flight() -> void:
	flying = false
	fwd = 0.0
	turn = 0.0
	lift = 0.0


func height() -> float:
	return global_position.y - ground_y


func on_ground() -> bool:
	return height() < 0.4


func kmh() -> float:
	return absf(speed) * 3.6


func _physics_process(delta: float) -> void:
	if flying:
		var kf := Input.get_axis("ui_down", "ui_up")
		var kt := Input.get_axis("ui_left", "ui_right")
		var kl := float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))
		var f := fwd if absf(fwd) > 0.01 else kf
		var tn := turn if absf(turn) > 0.01 else kt
		var l := lift if absf(lift) > 0.01 else kl
		# lift off by itself when you push forward from the ground
		if on_ground() and f > 0.0 and l <= 0.0:
			l = 0.6
		if fuel <= 0.0:   # engine dead: no thrust, slow descent
			f = 0.0
			l = -0.7
		var target := f * MAX_SPEED if f > 0.0 else f * MAX_SPEED * 0.3
		speed = move_toward(speed, target, ACCEL * delta)
		if height() > 0.5:
			rotation.y -= tn * TURN * delta
		vy = move_toward(vy, l * CLIMB, 18.0 * delta)
		# tilt: nose down when going forward, bank in turns
		rotation.x = lerpf(rotation.x, -f * 0.18 * (1.0 if height() > 0.5 else 0.0), 3.0 * delta)
		rotation.z = lerpf(rotation.z, -tn * 0.25 * clampf(absf(speed) / 15.0, 0.0, 1.0), 3.0 * delta)
		var d := -global_transform.basis.z
		d.y = 0.0
		d = d.normalized()
		global_position += d * speed * delta
		fuel = maxf(0.0, fuel - absf(speed) * delta / 1000.0 / FuelD.HELI_KM_PER_L * FuelD.FUEL_SCALE)
		ground_y = _ground_below(global_position.y + 80.0)
		var ny := global_position.y + vy * delta
		var lo := ground_y + (0.02 if (speed < 2.0 and l <= 0.0) else CRUISE_MIN * clampf(absf(speed) / 12.0, 0.0, 1.0))
		global_position.y = clampf(ny, lo, ground_y + MAX_ALT)
		if on_ground():
			speed = move_toward(speed, 0.0, 12.0 * delta)
	else:
		speed = move_toward(speed, 0.0, 20.0 * delta)
		rotation.x = lerpf(rotation.x, 0.0, 4.0 * delta)
		rotation.z = lerpf(rotation.z, 0.0, 4.0 * delta)
		if not on_ground():
			ground_y = _ground_below(global_position.y + 80.0)
			global_position.y = maxf(global_position.y - 10.0 * delta, ground_y + 0.02)
	# rotors + sound
	var want := 1.0 if flying else 0.0
	rotor_speed = move_toward(rotor_speed, want, 0.35 * delta)
	main_rotor.rotation.y -= rotor_speed * 38.0 * delta
	tail_rotor.rotation.z += rotor_speed * 50.0 * delta
	if snd.playing:
		snd.pitch_scale = 0.55 + 0.45 * rotor_speed + 0.15 * clampf(absf(speed) / MAX_SPEED, 0.0, 1.0) + (0.05 if vy > 1.0 else 0.0)
		snd.volume_db = lerpf(-60.0, -3.0, rotor_speed)
		if rotor_speed <= 0.0 and not flying:
			snd.stop()
