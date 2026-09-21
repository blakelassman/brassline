extends CharacterBody3D

const Loadouts = preload("res://scripts/loadouts.gd")
var class_id = "vanguard"
func weapon_stats(index: int = -1) -> Dictionary:
	return Loadouts.weapon(class_id,weapon if index<0 else index)
func set_class(id: String) -> void:
	if id==class_id: return
	class_id=id if Loadouts.CLASSES.has(id) else "vanguard"
	if is_instance_valid(viewmodel): viewmodel.apply_cosmetics()

const Rules = preload("res://scripts/rules.gd")
const Viewmodel = preload("res://scripts/viewmodel.gd")
var cosmetics: Dictionary = {}
var rifle_shots = 0
var rifle_idle = 99.0
var look_sway = Vector2.ZERO
var landing_pose = 0.0
var movement_phase = 0.0

const RemoteView = preload("res://scripts/remote_view.gd")
var locally_controlled = true
var peer_id = 0
var net_action_id = 0
var shot_view_time = -1.0
var net_slot = -1
var life_id = 1
var net_controls: Dictionary = {"move":Vector2.ZERO,"aim":false,"crouch":false}
var last_input_sequence = 0
var crouched = false
var body_shape: CollisionShape3D
var hitboxes: Array[Area3D] = []
var movement_jump = false
var game: Node
var camera: Camera3D
var render_camera: Camera3D
var view_previous = Vector3.ZERO
var view_current = Vector3.ZERO
var view_eye = 1.64
var view_ready = false
var fov_start=86.0
var fov_goal=86.0
var fov_elapsed=.12
var viewmodel: Node
var weapon = 0
var ammo = [24, 7, 0, 6]
var blast_count = 1
var smoke_count = 1
var team = 1
var target_name = "YOU"
var health = 100
var hurt_flash = 0.0
var sniper_cycle = 0.0
var bolt_cues = 0
var sensitivity = 0.0023
var pitch = 0.0
var fire_cooldown = 0.0
var equip_cooldown = 0.0
var reload_timer = 0.0
var visual_kick = 0.0
var parry_timer = 0.0
var parry_cooldown = 0.0
var swing_timer = 0.0
var swing_pending = false
var fire_requested = false
var fire_buffer = 0.0
var jump_requested = false
var blast_requested = false
var smoke_requested = false
var short_toss_requested = false
var toss_buffer=0.0
var buffered_short_toss=false
var jump_buffer = 0.0
var scope_age = 0.0
var held_grenade = ""
var throw_pose = 0.0
var fire_blocked_until_release = false
var last_jump_time = -999.0
var launch_origin = Vector3.ZERO
var last_boost_time = -999.0
var max_height = 0.0
var footstep_time = 0.0
var spread_rng = RandomNumberGenerator.new()
var last_shot_direction = Vector3.FORWARD
var correction_offset = Vector3.ZERO
func _process(delta: float) -> void:
	if camera==null: return
	if health<=0:
		if not locally_controlled:
			viewmodel.root.hide(); viewmodel.title.hide()
		return
	if not locally_controlled:
		if game.active and not game.net.dedicated: viewmodel.update_pose(delta)
		return
	correction_offset *= exp(-20*delta)
	if game.active and not game.menu_open and not game.replays.active and not game.replays.transitioning():
		look_sway=look_sway.lerp(Vector2.ZERO,1-exp(-12*delta))
		var target_fov=32.0 if is_aiming() and weapon==3 else (70.0 if is_aiming() else 86.0)
		update_zoom(delta,target_fov)
		viewmodel.update_pose(delta)
	camera.position = Vector3(0,1.00 if crouched else 1.64,0)
	update_presentation(delta,Engine.get_physics_interpolation_fraction())

func update_zoom(delta: float, target: float) -> void:
	if not is_equal_approx(target,fov_goal):
		fov_start=camera.fov; fov_goal=target; fov_elapsed=0
	fov_elapsed=minf(.12,fov_elapsed+delta)
	camera.fov=lerpf(fov_start,fov_goal,smoothstep(0,.12,fov_elapsed))

func presentation_camera() -> Camera3D:
	return render_camera if is_instance_valid(render_camera) else camera

func reset_presentation() -> void:
	view_previous=global_position; view_current=global_position
	view_eye=1.00 if crouched else 1.64
	view_ready=true
	update_presentation(0,1)

func update_presentation(delta: float, fraction: float) -> void:
	if not is_instance_valid(render_camera): return
	# Only translation is interpolated. Aim and all combat queries use the logical camera.
	if not view_ready or global_position.distance_squared_to(view_current)>4:
		view_previous=global_position; view_current=global_position; view_ready=true
	view_eye=lerpf(view_eye,1.00 if crouched else 1.64,1-exp(-18*delta))
	render_camera.global_transform=Transform3D(camera.global_basis,view_previous.lerp(view_current,clampf(fraction,0,1))+Vector3.UP*view_eye+correction_offset)
	render_camera.fov=camera.fov


func _ready() -> void:
	spread_rng.randomize()
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.18
	var collider = CollisionShape3D.new()
	body_shape = collider
	var shape = CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.8
	collider.shape = shape
	collider.position.y = 0.9
	add_child(collider)
	camera = Camera3D.new()
	camera.position.y = 1.64
	camera.near = 0.045
	camera.fov = 86.0
	camera.current = false
	add_child(camera)
	if locally_controlled:
		render_camera=Camera3D.new()
		render_camera.top_level=true
		render_camera.near=camera.near
		add_child(render_camera)
		render_camera.make_current()
		reset_presentation()
	_create_hitboxes()
	viewmodel = Viewmodel.new() if locally_controlled else RemoteView.new()
	viewmodel.player = self
	add_child(viewmodel)

func is_aiming() -> bool:
	return health>0 and held_grenade.is_empty() and weapon != 2 and reload_timer <= 0.0 and equip_cooldown <= 0.0 and held("aim")

func current_spread() -> float:
	return Rules.spread_degrees(weapon, Vector2(velocity.x,velocity.z).length(), not is_on_floor(), scope_age)*(float(weapon_stats().get("spread",1.0)) if weapon==0 else 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if locally_controlled and health>0 and not game.menu_open and game.net.is_destroy() and event.is_action_pressed("drop_bomb"):
		if game.net.server: game.net.destroy.drop(net_slot)
		else: game.net._drop_bomb.rpc_id(1,life_id)
	if not locally_controlled or not game.active or game.menu_open or game.replays.active or health<=0:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_motion = event.screen_relative if not event.screen_relative.is_zero_approx() else event.relative
		look_sway = (look_sway+mouse_motion*.00045).clamp(Vector2(-.04,-.04),Vector2(.04,.04))
		rotate_y(-mouse_motion.x * sensitivity * Rules.fov_sensitivity(camera.fov))
		pitch = clampf(pitch - mouse_motion.y * sensitivity * Rules.fov_sensitivity(camera.fov), -1.50, 1.50)
		camera.rotation.x = pitch
	if event.is_action_pressed("jump"):
		jump_requested = true
	if event.is_action_pressed("fire"):
		fire_requested = true
	if event.is_action_pressed("aim") and not held_grenade.is_empty():
		short_toss_requested = true
	if event.is_action_pressed("aim") and weapon==2 and held_grenade.is_empty():
		start_parry()
	if event.is_action_pressed("blast"):
		blast_requested = true
	if event.is_action_pressed("smoke"):
		smoke_requested = true
	if event.is_action_pressed("reload"):
		start_reload()
	for i in range(4):
		if event.is_action_pressed("weapon_%d" % i):
			equip(i)

func _physics_process(delta: float) -> void:
	if locally_controlled: view_previous=view_current
	else: viewmodel.presentation.begin_tick(global_transform)
	if locally_controlled and game.net.is_client_ready(): game.net.consume_reconciliation()
	if not game.active or (game.net.running and not game.net.combat_allowed()):
		return
	if not locally_controlled: look_sway = look_sway.lerp(Vector2.ZERO,1-exp(-12*delta))
	landing_pose = move_toward(landing_pose,0,delta*3)
	hurt_flash = maxf(0,hurt_flash-delta)
	if health<=0:
		viewmodel.root.hide()
		return
	if locally_controlled or not (game.net.running and game.net.server):
		advance_weapon_state(delta)
	var aiming = is_aiming()
	var move_input = movement_input()
	movement_jump = jump_requested
	if locally_controlled:
		if game.net.is_client_ready(): game.net.send_input(self,move_input,jump_requested,aiming)
		simulate_movement(delta,move_input,jump_requested,held("crouch"),false)
	elif game.net.running and game.net.server:
		game.net.simulate_remote(self,delta)
	else:
		simulate_movement(delta,move_input,jump_requested,held("crouch"),false)
	if locally_controlled: view_current=global_position
	else: viewmodel.presentation.end_tick(global_transform)
	jump_requested = false
	var flat = Vector2(velocity.x,velocity.z)
	if locally_controlled and game.net.is_client_ready(): game.net.remember_input(self,move_input,movement_jump)
	if position.y < -8.0:
		game.net.fell(self) if game.net.running else game.reset_practice(false)
	if game.clock - last_boost_time < 5.0:
		max_height = maxf(max_height, position.y - launch_origin.y)
	if is_on_floor() and flat.length() > 2.0:
		footstep_time += delta
		if footstep_time > 0.32:
			play_sound("step_"+game.surface_at(global_position), -21.0)
			footstep_time = 0.0
	if blast_requested:
		equip_grenade("blast")
	if smoke_requested:
		equip_grenade("smoke")
	blast_requested = false
	smoke_requested = false
	if fire_blocked_until_release and not held("fire"):
		fire_blocked_until_release = false
	fire_buffer=.10 if fire_requested else maxf(0,fire_buffer-delta)
	toss_buffer=maxf(0,toss_buffer-delta)
	if not held_grenade.is_empty():
		if short_toss_requested or fire_requested:
			toss_buffer=.20; buffered_short_toss=short_toss_requested
		if toss_buffer>0 and equip_cooldown<=0:
			throw_grenade(held_grenade,buffered_short_toss)
			toss_buffer=0
	elif not fire_blocked_until_release and (fire_buffer>0 or (weapon == 0 and weapon_stats().get("auto",true) and held("fire"))):
		if fire_cooldown<=0 and equip_cooldown<=0 and reload_timer<=0:
			fire_buffer=0
			shoot()
	fire_requested = false
	short_toss_requested = false
	if swing_timer > 0.0:
		swing_timer = maxf(0.0, swing_timer - delta)
		if swing_pending and swing_timer <= 0.39:
			swing_pending = false
			game.melee_attack(self)
	var target_fov = 86.0
	if aiming:
		target_fov = 32.0 if weapon == 3 else 70.0
	if not locally_controlled:
		camera.fov = move_toward(camera.fov,target_fov,450.0*delta)

func advance_weapon_state(delta: float) -> void:
	rifle_idle += delta
	if rifle_idle>=Rules.RIFLE_RESET: rifle_shots = 0
	parry_timer = maxf(0,parry_timer-delta)
	parry_cooldown = maxf(0,parry_cooldown-delta)
	var old_cycle = sniper_cycle
	sniper_cycle = maxf(0,sniper_cycle-delta)
	if weapon==3 and reload_timer<=0:
		if old_cycle>.88 and sniper_cycle<=.88:
			play_sound("bolt_open",-9)
			bolt_cues += 1
		if old_cycle>.35 and sniper_cycle<=.35:
			play_sound("bolt_close",-9)
			bolt_cues += 1
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	equip_cooldown = maxf(0.0, equip_cooldown - delta)
	throw_pose = maxf(0.0,throw_pose-delta)
	visual_kick = move_toward(visual_kick, 0.0, delta * 4.0)
	if reload_timer > 0.0:
		var old_progress = 1.0 - reload_timer/float(weapon_stats()["reload"])
		reload_timer = maxf(0.0, reload_timer - delta)
		var progress = 1.0 - reload_timer/float(weapon_stats()["reload"])
		for cue in [[.18,"mag_out"],[.70,"mag_in"],[.88,"slide"]]:
			if old_progress < cue[0] and progress >= cue[0]:
				play_sound(cue[1], -12.0)
		if reload_timer == 0.0:
			ammo[weapon] = weapon_stats()["mag"]
	var aiming = is_aiming()
	scope_age = scope_age + delta if aiming and weapon == 3 else 0.0

func start_parry() -> void:
	if objective_busy(): return
	if health<=0 or weapon!=2 or not held_grenade.is_empty() or parry_cooldown>0 or fire_cooldown>0 or equip_cooldown>0: return
	network_action("parry")
	parry_timer = .28
	parry_cooldown = .75
	play_sound("equip",-12)

func equip(index: int) -> void:
	if index == weapon and held_grenade.is_empty():
		return
	network_action("equip",index)
	held_grenade = ""
	parry_timer = 0.0
	toss_buffer=0
	fire_buffer=0
	weapon = index
	rifle_shots = 0
	rifle_idle = 99.0
	equip_cooldown = 0.22
	reload_timer = 0.0
	scope_age = 0.0
	swing_pending = false
	swing_timer = 0.0
	short_toss_requested = false
	play_sound("equip", -19.0)

func equip_grenade(kind: String) -> void:
	if health<=0:
		return
	if (kind == "blast" and blast_count == 0) or (kind == "smoke" and smoke_count == 0):
		game.notify("OUT OF GRENADES", "Press F to refill practice supplies.")
		return
	network_action("grenade",1 if kind=="smoke" else 0)
	parry_timer = 0.0
	toss_buffer=0
	fire_buffer=0
	held_grenade = kind
	rifle_shots = 0
	rifle_idle = 99.0
	reload_timer = 0.0
	scope_age = 0.0
	swing_pending = false
	swing_timer = 0.0
	equip_cooldown = .18
	play_sound("equip", -19.0)

func shoot() -> void:
	if objective_busy(): return
	if parry_timer>0: return
	if health<=0 or not held_grenade.is_empty() or fire_cooldown > 0.0 or equip_cooldown > 0.0 or reload_timer > 0.0:
		return
	if weapon == 2:
		network_action("fire")
		fire_cooldown = Rules.WEAPONS[2]["cooldown"]
		swing_timer = 0.50
		swing_pending = true
		play_sound("sword", -13.0)
		return
	if ammo[weapon] <= 0:
		play_sound("empty",-12)
		start_reload()
		return
	network_action("fire")
	if weapon==3:
		sniper_cycle = 1.1
	ammo[weapon] -= 1
	fire_cooldown = weapon_stats()["cooldown"]
	var direction = -camera.global_basis.z
	var spread = deg_to_rad(current_spread())
	if spread > 0:
		var angle = spread_rng.randf()*TAU
		var radius = sqrt(spread_rng.randf())*tan(spread)
		direction = (direction+camera.global_basis.x*cos(angle)*radius+camera.global_basis.y*sin(angle)*radius).normalized()
	last_shot_direction = direction
	game.shoot_ray(camera.global_position, direction, weapon, not is_on_floor(),self)
	play_sound("sniper" if weapon == 3 else ("rifle" if weapon == 0 else "pistol"), -9.0 if weapon == 3 else -11.0)
	visual_kick = .5 if weapon == 0 else 1.0
	viewmodel.on_shot()
	var recoil = Rules.rifle_recoil(rifle_shots)*float(weapon_stats().get("recoil",1.0)) if weapon==0 else Vector2(0,weapon_stats()["kick"])
	if weapon==0:
		rifle_shots = mini(23,rifle_shots+1)
		rifle_idle = 0
	rotate_y(-deg_to_rad(recoil.x))
	pitch = clampf(pitch + deg_to_rad(recoil.y), -1.50, 1.50)
	camera.rotation.x = pitch

func start_reload() -> void:
	if objective_busy(): return
	if health<=0 or not held_grenade.is_empty() or weapon == 2 or reload_timer > 0.0 or ammo[weapon] == weapon_stats()["mag"]:
		return
	network_action("reload")
	if weapon==3:
		sniper_cycle = 0
	reload_timer = weapon_stats()["reload"]
	rifle_shots = 0
	rifle_idle = 99.0
	scope_age = 0.0
	play_sound("equip", -12.0)

func throw_grenade(kind: String, short_toss: bool = false) -> void:
	if objective_busy(): return
	if health<=0 or equip_cooldown > 0.0:
		return
	if (kind == "blast" and blast_count == 0) or (kind == "smoke" and smoke_count == 0):
		return
	network_action("throw",1 if short_toss else 0)
	if kind == "blast":
		blast_count -= 1
	else:
		smoke_count -= 1
	var forward = -camera.global_basis.z
	var origin = camera.global_position
	if short_toss:
		forward = (-global_basis.z*.35+Vector3.DOWN*.94).normalized()
		origin = global_position+Vector3.UP*.85
	game.spawn_grenade(kind, origin, forward, velocity, short_toss,self)
	held_grenade = ""
	equip_cooldown = .22
	throw_pose = .30
	fire_blocked_until_release = true
	play_sound("equip", -12.0)

func take_damage(amount: int, source_team: int, attacker: String = "ENEMY") -> bool:
	if game.mode not in ["combat","online"] or (game.net.running and not game.net.combat_allowed()) or health<=0 or source_team==team:
		return false
	health = maxi(0,health-amount)
	hurt_flash = .35
	play_sound("hurt",-12)
	if health==0:
		velocity = Vector3.ZERO
		collision_layer = 0
		for area in hitboxes: area.collision_layer = 0
		reload_timer = 0
		sniper_cycle = 0
		scope_age = 0
		held_grenade = ""
		fire_buffer=0
		fire_requested = false
		jump_requested = false
		blast_requested = false
		smoke_requested = false
		short_toss_requested = false
		swing_pending = false
		swing_timer = 0
		camera.fov = 86
		camera.position.y = 1.05
		viewmodel.root.hide()
		game.chain_count = 0
		if game.net.running: game.net.human_died(self)
		else: game.combat.player_died(attacker,source_team)
		return true
	return false

func refill() -> void:
	rifle_shots = 0
	rifle_idle = 99.0
	max_height = 0.0
	blast_count = 1
	smoke_count = 1
	ammo = [weapon_stats(0).mag, 7, 0, 6]
	reload_timer = 0.0
	health = 100

func reset_at(pos: Vector3) -> void:
	if not game.net.running:
		set_class(Loadouts.allowed(game.prefs.data.selected_class,game.progression.xp_for("YOU")))
	elif game.net.server and game.net.peers.has(peer_id):
		var peer=game.net.peers[peer_id]
		set_class(Loadouts.allowed(peer.get("selected_class","vanguard"),peer.progress.xp_for("YOU")))
	rifle_shots = 0
	rifle_idle = 99.0
	parry_timer = 0.0
	parry_cooldown = 0.0
	correction_offset = Vector3.ZERO
	net_controls = {"move":Vector2.ZERO,"aim":false,"crouch":false}
	if not locally_controlled and game.net.peers.has(peer_id): game.net.peers[peer_id].frames.clear()
	collision_layer = 2
	for area in hitboxes: area.collision_layer = 8
	hurt_flash = 0
	sniper_cycle = 0
	set_crouch(false,true)
	camera.position.y = 1.64
	position = pos
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	pitch = 0.0
	camera.rotation = Vector3.ZERO
	camera.fov = 86.0
	fov_start=86.0; fov_goal=86.0; fov_elapsed=.12
	last_jump_time = -999.0
	last_boost_time = -999.0
	fire_requested = false
	jump_requested = false
	fire_buffer=0
	jump_buffer = 0.0
	blast_requested = false
	smoke_requested = false
	short_toss_requested = false
	held_grenade = ""
	scope_age = 0.0
	swing_pending = false
	swing_timer = 0.0
	fire_cooldown = 0.0
	equip_cooldown = 0.0
	throw_pose = 0.0
	toss_buffer=0
	visual_kick = 0.0
	landing_pose = 0
	look_sway = Vector2.ZERO
	refill()
	viewmodel.update_pose(0.0)
	reset_presentation()

func held(action: String) -> bool:
	if locally_controlled and game.replays.active: return false
	if not locally_controlled: return bool(net_controls.get(action,false))
	return not game.menu_open and Input.is_action_pressed(action)
func movement_input() -> Vector2:
	if not locally_controlled: return net_controls.get("move",Vector2.ZERO)
	return Vector2.ZERO if game.menu_open else Input.get_vector("left","right","forward","back")
func network_action(action: String, value: int = 0) -> void:
	if action=="jump": return # Included once in its numbered movement tick.
	if locally_controlled and game.net.is_client_ready(): game.net.send_action(action,value,self)
func play_sound(key: String, volume: float) -> void:
	if game.net.running and game.net.server and key not in ["rifle","pistol","sniper","head","hit","empty"]: game.net.audio_fx(net_slot,key,global_position,volume-7)
	if locally_controlled: game.sound(key,volume)
	elif not game.net.running: game.world_sound(key,global_position,-16 if key in ["rifle","pistol","sniper"] else volume-7)
	elif game.net.server: game.world_sound(key,global_position,-16 if key in ["rifle","pistol","sniper"] else volume-7,false)
func simulate_movement(delta: float, move_input: Vector2, jump_press: bool, crouch_hold: bool, silent: bool = false, grounded_override: int = -1, aiming_override: int = -1) -> void:
	set_crouch(crouch_hold)
	var aiming = is_aiming() if aiming_override<0 else aiming_override==1

	var direction = global_basis * Vector3(move_input.x, 0.0, move_input.y)
	var wish = Vector2(direction.x,direction.z)
	var speed = Rules.WALK_SPEED * (.48 if crouched else (.75 if aiming else 1.0))
	if jump_press:
		jump_buffer = Rules.JUMP_BUFFER
	else:
		jump_buffer = maxf(0,jump_buffer-delta)
	var flat = Vector2(velocity.x,velocity.z)
	if grounded_override==1 or (grounded_override<0 and is_on_floor()):
		if jump_buffer > 0.0:
			# Jump before friction on the landing frame, preserving earned speed.
			velocity.y = Rules.JUMP_SPEED
			jump_buffer = 0.0
			last_jump_time = game.clock
			if not silent and locally_controlled: play_sound("jump", -15.0)
			flat = Rules.air_move(flat,wish,delta)
		else:
			flat = Rules.ground_move(flat,wish,speed,delta)
	else:
		flat = Rules.air_move(flat,wish,delta)
	velocity.x = flat.x
	velocity.z = flat.y
	velocity.y -= Rules.GRAVITY * delta
	var was_grounded = is_on_floor()
	var fall_speed = velocity.y
	move_and_slide()
	if is_on_floor() and not was_grounded and fall_speed < -3:
		landing_pose = clampf(-fall_speed/24,.15,.55)
		if not silent and locally_controlled: play_sound("land",-16)
	movement_phase += delta*flat.length()*1.7

func set_crouch(value: bool, force: bool = false) -> void:
	if crouched==value and not force: return
	if not value and not force:
		var query = PhysicsShapeQueryParameters3D.new()
		var shape = CapsuleShape3D.new()
		shape.radius = .32
		shape.height = 1.8
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY,global_position+Vector3.UP*.91)
		query.collision_mask = 1
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return
	crouched = value
	body_shape.shape.height = 1.1 if crouched else 1.8
	body_shape.position.y = body_shape.shape.height*.5
	camera.position.y = 1.00 if crouched else 1.64
	if hitboxes.size()==2:
		hitboxes[0].position.y = .50 if crouched else .8
		hitboxes[0].get_child(0).shape.size.y = .86 if crouched else 1.36
		hitboxes[1].position.y = 1.03 if crouched else 1.68
func _create_hitboxes() -> void:
	for head in [false,true]:
		var area = Area3D.new()
		area.collision_layer = 8
		area.collision_mask = 0
		area.set_meta("target",self)
		area.set_meta("zone","head" if head else "body")
		var collision = CollisionShape3D.new()
		if head:
			collision.shape = SphereShape3D.new()
			collision.shape.radius = .24
		else:
			collision.shape = BoxShape3D.new()
			collision.shape.size = Vector3(.68,1.36,.4)
		area.add_child(collision)
		add_child(area)
		area.position.y = 1.68 if head else .8
		hitboxes.append(area)

func objective_busy() -> bool:
	if not game.net.is_destroy(): return false
	if not game.net.combat_allowed(): return true
	return held("interact") if locally_controlled else game.net.destroy.holding(net_slot)
