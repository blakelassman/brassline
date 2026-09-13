extends Node3D

var radar = preload("res://scripts/radar.gd").new()
var applied_display = ""

const Progression = preload("res://scripts/progression.gd")
var progression = Progression.new()
const Network = preload("res://scripts/network.gd")
const Preferences = preload("res://scripts/preferences.gd")
const Optimizer = preload("res://scripts/optimizer.gd")
var net: Node
var prefs = Preferences.new()
var menu_open = true
var save_timer = 0.0
var quitting = false

const Effects = preload("res://scripts/effects.gd")
var effects: Node

const Maps = preload("res://scripts/maps.gd")
var selected_map = 0
var current_map = 0
var world_root: Node3D
var changing_map = false

const Rules = preload("res://scripts/rules.gd")
const Geo = preload("res://scripts/geo.gd")
const Player = preload("res://scripts/player.gd")
const Target = preload("res://scripts/target.gd")
const Grenade = preload("res://scripts/grenade.gd")
const Combat = preload("res://scripts/combat.gd")
const Hud = preload("res://scripts/hud.gd")

var ambience: AudioStreamPlayer
var ui_speaker: AudioStreamPlayer
var audio_rng = RandomNumberGenerator.new()

var mode = "training"
var has_started = false
var combat: Node
var world_sounds: Array[AudioStreamPlayer3D] = []
var world_sound_index = 0
var player: CharacterBody3D
var hud: Control
var targets: Array[CharacterBody3D] = []
var grenades: Array[CharacterBody3D] = []
var smoke_nodes: Array[Node3D] = []
var active = false
var clock = 0.0
var kills = 0
var air_heads = 0
var perfect_boosts = 0
var shot_count = 0
var hit_count = 0
var toast_title = ""
var toast_detail = ""
var toast_time = 0.0
var hit_flash = 0.0
var last_head = false
var audio: Dictionary = {}
var sound_pool: Array[AudioStreamPlayer] = []
var sound_index = 0
var kill_feed: Array[Dictionary] = []
var action_serial = 0
var chain_count = 0
var last_kill_time = -999.0
var launch_pad = Vector3(-6, 0.06, 6)

func _ready() -> void:
	get_tree().auto_accept_quit = false
	progression.reset_roster(false)
	var test_run = Array(OS.get_cmdline_user_args()).any(func(arg): return "test" in arg or "capture" in arg)
	if test_run: prefs = Preferences.new("user://test_profile_%s.json" % Crypto.new().generate_random_bytes(8).hex_encode())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): prefs = Preferences.new(arg.trim_prefix("--profile="))
	if "--server" in OS.get_cmdline_user_args(): prefs = Preferences.new("user://server_profile_v1.json")
	prefs.load_profile()
	progression.profiles["YOU"] = prefs.data.xp
	_inputs()
	prefs.apply_bindings()
	net = Network.new()
	net.name = "Network"
	net.game = self
	add_child(net)
	_world()
	_load_audio()
	effects = Effects.new()
	effects.game = self
	add_child(effects)
	player = Player.new()
	player.game = self
	add_child(player)
	player.position = launch_pad
	_training_targets()
	combat = Combat.new()
	combat.game = self
	add_child(combat)
	var canvas = CanvasLayer.new()
	canvas.layer = 1
	add_child(canvas)
	hud = Hud.new()
	hud.game = self
	canvas.add_child(hud)
	apply_settings()
	apply_display_settings()
	get_window().size_changed.connect(_apply_render_resolution)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var args = OS.get_cmdline_user_args()
	if "--profile-write-test" in args:
		progression.profiles["YOU"] = 98765
		prefs.data.sensitivity = .0037
		call_deferred("quit_game")
	elif "--profile-read-test" in args:
		print("RESTART_PROFILE xp=",progression.xp_for("YOU")," sensitivity=",prefs.data.sensitivity)
		call_deferred("quit_game")
	elif "--server" in args:
		call_deferred("_dedicated_server")
	elif "--capacity-test" in args:
		call_deferred("_capacity_test")
	elif "--lagcomp-test" in args:
		call_deferred("_lagcomp_test")
	elif "--prediction-test" in args:
		call_deferred("_prediction_test")
	elif "--network-test" in args:
		call_deferred("_network_test")
	elif "--display-test" in args:
		call_deferred("_display_test")
	elif "--polish-test" in args:
		call_deferred("_polish_test")
	elif "--settings-test" in args:
		call_deferred("_settings_test")
	elif "--expansion-test" in args:
		call_deferred("_expansion_test")
	elif "--progression-test" in args:
		call_deferred("_progression_test")
	elif "--combat-test" in args:
		call_deferred("_combat_test")
	elif "--self-test" in args:
		call_deferred("_self_test")
	elif Array(args).any(func(arg): return arg.begins_with("--capture")):
		call_deferred("_capture")
	print("BRASSLINE ready | multiplayer prototype 0.8.0 | Godot ", Engine.get_version_info()["string"])

func _training_targets() -> void:
	var names = ["WALL PEEK","STRAFE","HIGH GROUND","CLOSE RANGE","TEAMMATE","COLLATERAL A","COLLATERAL B"]
	for i in range(7): _target(Maps.PRACTICE[current_map][i],names[i],i==1,1 if i==4 else 2)

func _inputs() -> void:
	var keys = {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
		"jump": KEY_SPACE, "weapon_0": KEY_1, "weapon_1": KEY_2, "weapon_2": KEY_3, "weapon_3": KEY_4,
		"reload": KEY_R, "blast": KEY_G, "smoke": KEY_Q, "refill": KEY_F,
		"reset": KEY_T, "pause": KEY_ESCAPE, "help": KEY_H, "scoreboard": KEY_TAB}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event = InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)
	var wheel = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	InputMap.action_add_event("jump",wheel)
	for action in ["fire", "aim"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT if action == "fire" else MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action, event)

func _world() -> void:
	radar.clear()
	world_root = Node3D.new()
	world_root.name = "ArenaGeometry"
	add_child(world_root)
	Maps.environment(world_root,current_map)
	Maps.build(world_root,current_map)
	launch_pad = Maps.PADS[current_map]
	Optimizer.batch(world_root)


func _target(pos: Vector3, title: String, moving: bool, team: int = 2) -> void:
	var target = Target.new()
	target.game = self
	target.position = pos
	target.target_name = title
	target.team = team
	target.moving = moving
	add_child(target)
	targets.append(target)

func _load_audio() -> void:
	for key in ["rifle","pistol","blast","tick","jump","hit","head","equip","sword","parry","step","sniper","bolt_open","bolt_close","hurt","mag_out","mag_in","slide","empty","land","step_concrete","step_metal","step_tile","grenade_bounce","smoke_hiss","impact_concrete","impact_metal","ui","kill","ambient_foundry","ambient_dock","ambient_sunspire","ambient_relay"]:
		audio[key] = AudioStreamWAV.load_from_file("res://assets/%s.wav" % key)
	ambience = AudioStreamPlayer.new()
	add_child(ambience)
	ambience.volume_db = -24
	ui_speaker = AudioStreamPlayer.new()
	add_child(ui_speaker)
	ui_speaker.stream = audio["ui"]
	ui_speaker.volume_db = -20
	audio_rng.seed = 602026
	for i in range(12):
		var spatial = AudioStreamPlayer3D.new()
		spatial.unit_size = 4
		spatial.max_distance = 48
		add_child(spatial)
		world_sounds.append(spatial)
	for i in range(12):
		var speaker = AudioStreamPlayer.new()
		add_child(speaker)
		sound_pool.append(speaker)

func sound(key: String, volume: float = -12.0) -> void:
	if DisplayServer.get_name() == "headless" or not audio.has(key):
		return
	var speaker = sound_pool[sound_index % sound_pool.size()]
	sound_index += 1
	speaker.stream = audio[key]
	speaker.volume_db = volume
	speaker.pitch_scale = audio_rng.randf_range(.94,1.06) if key.begins_with("step_") or key.begins_with("impact_") else 1.0
	speaker.play()

func world_sound(key: String, at: Vector3, volume: float, replicate: bool = true) -> void:
	if replicate and net.running and net.server and key not in ["rifle","pistol","sniper","blast"]: net.audio_fx(-1,key,at,volume)
	if DisplayServer.get_name()=="headless" or not audio.has(key):
		return
	var speaker = world_sounds[world_sound_index % world_sounds.size()]
	world_sound_index += 1
	speaker.position = at
	speaker.stream = audio[key]
	speaker.volume_db = volume
	speaker.pitch_scale = audio_rng.randf_range(.94,1.06) if key.begins_with("step_") or key.begins_with("impact_") else 1.0
	speaker.play()

func start_mode(selected: String, map_index: int = -1) -> void:
	if changing_map: return
	radar.clear()
	if net.running and selected!="online": await net.leave()
	if map_index>=0: selected_map = clampi(map_index,0,3)
	set_active(false)
	_clear_effects()
	combat.stop()
	for target in targets:
		if is_instance_valid(target) and not target.is_queued_for_deletion():
			target.set_physics_process(false)
			target.collision_layer = 0
			for area in target.hitboxes:
				area.collision_layer = 0
			target.hide()
			target.queue_free()
	targets.clear()
	if current_map!=selected_map:
		changing_map = true
		world_root.free()
		current_map = selected_map
		_world()
		combat.navigation.clear()
		combat.node_ids.clear()
		combat.spawn_candidates.clear()
		# Let physics register the new collision shapes before clearance queries.
		await get_tree().physics_frame
		await get_tree().physics_frame
		changing_map = false
	mode = selected
	progression.reset_roster(mode=="combat")
	kills = 0
	air_heads = 0
	perfect_boosts = 0
	shot_count = 0
	hit_count = 0
	kill_feed.clear()
	chain_count = 0
	last_kill_time = -999
	toast_time = 0
	if mode=="combat":
		combat.start()
	elif mode=="training":
		_training_targets()
		player.reset_at(launch_pad)
	else:
		player.reset_at(launch_pad)
		if not net.server: player.set_physics_process(false)
	has_started = true
	start_ambience()
	apply_settings()
	set_active(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		set_active(menu_open)
	if active and mode=="training" and event.is_action_pressed("refill"):
		player.refill()
		notify("SUPPLIES REFILLED", "One blast. One smoke. Fresh magazines.")
	if active and mode=="training" and event.is_action_pressed("reset"):
		reset_practice(true)
	if event.is_action_pressed("help"):
		hud.help_visible = not hud.help_visible

func set_active(value: bool) -> void:
	if changing_map and value: return
	menu_open = not value
	active = value or (net.running and mode=="online")
	if value:
		has_started = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE
	hud.menu.visible = not value
	hud.resume_button.visible = has_started
	if net.running:
		player.fire_requested = false
		player.jump_requested = false
		player.blast_requested = false
		player.smoke_requested = false
		player.short_toss_requested = false
		player.fire_blocked_until_release = true
		return
	for tween in get_tree().get_processed_tweens():
		if not tween.is_valid() or tween.get_loops_left()==0: continue
		if value:
			tween.play()
		else:
			tween.pause()
	if is_instance_valid(ambience): ambience.stream_paused = not value
	for sound_player in sound_pool:
		sound_player.stream_paused = not value
	for sound_player in world_sounds:
		sound_player.stream_paused = not value
	# Drop pending actions across pause; opening a menu must not buffer a shot.
	player.fire_requested = false
	player.jump_requested = false
	player.blast_requested = false
	player.smoke_requested = false
	player.short_toss_requested = false
	player.jump_buffer = 0.0
	player.scope_age = 0.0
	player.fire_blocked_until_release = true

func _physics_process(delta: float) -> void:
	save_timer += delta
	if save_timer>=2.5:
		save_timer = 0
		if prefs.data.xp!=progression.xp_for("YOU") or prefs.dirty: save_profile()
	if not active: return
	clock += delta
	if not net.is_client_ready(): progression.update(clock)
	update_feed()
	toast_time = maxf(0.0, toast_time - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	grenades = grenades.filter(func(g): return is_instance_valid(g) and not g.is_queued_for_deletion())
	smoke_nodes = smoke_nodes.filter(func(s): return is_instance_valid(s) and not s.is_queued_for_deletion())

func notify(title: String, detail: String) -> void:
	toast_title = title
	toast_detail = detail
	toast_time = 3.4

func spawn_grenade(kind: String, origin: Vector3, forward: Vector3, momentum: Vector3, short_toss: bool = false, shooter: Node = null) -> void:
	if shooter==null: shooter = player
	var grenade = Grenade.new()
	grenade.game = self
	grenade.kind = kind
	grenade.owner_actor = shooter
	grenade.source_team = shooter.team
	grenade.owner_name = shooter.target_name
	net.serial += 1
	grenade.net_id = net.serial
	grenade.prediction_action = net.action_id if net.is_client_ready() else shooter.net_action_id
	if net.is_client_ready():
		grenade.predicted = true
		grenade.net_id = -net.action_id
		net.predicted_grenades[net.action_id] = grenade
	# Clamp the spawn point against a wall instead of spawning through it.
	var spawn_pos = origin + forward * 0.48
	var query = PhysicsRayQueryParameters3D.create(origin, spawn_pos, 1)
	var obstruction = get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty():
		spawn_pos = obstruction.position + obstruction.normal * 0.18
	add_child(grenade)
	grenade.global_position = spawn_pos
	grenade.velocity = forward * (2.8 if short_toss else 13.0) + momentum * (0.2 if short_toss else 0.45)
	grenades.append(grenade)

func unobstructed(origin: Vector3, destination: Vector3) -> bool:
	var query = PhysicsRayQueryParameters3D.create(origin, destination, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func explode(origin: Vector3, owner_actor: Node = null, source_team: int = 1, owner_name: String = "YOU") -> void:
	if net.is_client_ready(): return
	var shooter = owner_actor if is_instance_valid(owner_actor) else (player if not net.running else null)
	if net.running: net.blast_fx(origin)
	action_serial += 1
	effects.burst(origin)
	sound("blast", -8.0)
	if is_instance_valid(shooter):
		var distance = (shooter.global_position + Vector3.UP * 0.4).distance_to(origin)
		if shooter.health>0 and distance < Rules.BLAST_RADIUS and unobstructed(origin, shooter.global_position + Vector3.UP * 0.7):
			var age = clock - shooter.last_jump_time
			shooter.velocity = Rules.launch_velocity(shooter.velocity, shooter.global_position + Vector3.UP * 0.4, origin, age)
			shooter.launch_origin = shooter.global_position
			shooter.last_boost_time = clock
			shooter.max_height = 0.0
			if Rules.perfect_jump(age):
				perfect_boosts += 1
				if shooter==player: notify("PERFECT BOOST", "Draw the pistol. Find the head. Own the landing.")
			else:
				if shooter==player: notify("SMALL BOOST", "Jump just before the burst. F refills supplies.")
	for target in net.actors() if net.running else targets:
		if target.health<=0 or target==shooter: continue
		var center = target.global_position+Vector3.UP*.8
		var damage = Rules.blast_damage(center.distance_to(origin),source_team,target.team,false)
		if damage>0 and unobstructed(origin,center):
			if damage_actor(target,damage,source_team,owner_name):
				record_kill(target.target_name,"BLAST",false,false,action_serial,owner_name,source_team)
	var flash = Geo.sphere(self, origin, 0.18, Color("ffe3a0"))
	var material = flash.material_override as StandardMaterial3D
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tween = create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 11, 0.20)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.20)
	tween.chain().tween_callback(flash.queue_free)

func make_smoke(origin: Vector3, remaining: float = 6.1) -> void:
	world_sound("smoke_hiss",origin,-15)
	var root = Node3D.new()
	add_child(root)
	root.position = origin + Vector3.UP * 0.8
	smoke_nodes.append(root)
	root.set_meta("expires",clock+remaining)
	for i in range(9):
		var angle = float(i) * TAU / 8.0
		var offset = Vector3(cos(angle)*1.1, 0.25+float(i%3)*0.45, sin(angle)*1.1)
		if i == 8:
			offset = Vector3(0,0.5,0)
		var cloud = Geo.sphere(root, offset, 1.65, Color("b8c5bd"))
		var mat = cloud.material_override as StandardMaterial3D
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.82
		var tween = create_tween()
		tween.tween_interval(maxf(0,remaining-1.1))
		tween.tween_property(mat, "albedo_color:a", 0.0, 1.0)
	var cleanup = create_tween()
	cleanup.tween_interval(remaining)
	cleanup.tween_callback(root.queue_free)
	notify("SMOKE DEPLOYED", "Six seconds of visual cover. Bullets still pass through.")

func record_kill(victim: String, weapon_name: String, head: bool, airborne: bool, group: int, killer: String = "YOU", killer_team: int = 1, one_shot: bool = false) -> void:
	if net.running:
		if net.server and not net.round_active: return
		net.record_kill(victim,weapon_name,head,airborne,group,killer,killer_team,one_shot)
		return
	progression.record(killer,victim,killer_team,head,one_shot,clock,group,weapon_name=="LONGSHOT")
	if killer=="YOU":
		if not head: sound("kill",-19)
		kills += 1
		chain_count = chain_count + 1 if clock-last_kill_time <= 3.0 else 1
		last_kill_time = clock
	if mode=="combat":
		combat.scores[killer_team] += 1
	feed_entry(victim,weapon_name,head,airborne,group,killer,killer_team)

func feed_entry(victim: String, weapon_name: String, head: bool, airborne: bool, group: int, killer: String, killer_team: int) -> void:
	kill_feed.push_front({"killer":killer,"team":killer_team,"victim":victim,"weapon":weapon_name,"head":head,"air":airborne,
		"time":clock,"group":group,"evicted":-1.0,"collateral":false})
	var matching = 0
	for entry in kill_feed:
		if entry.group == group:
			matching += 1
	if matching > 1 and weapon_name == "LONGSHOT":
		for entry in kill_feed:
			if entry.group == group:
				entry.collateral = true
	for i in range(4,kill_feed.size()):
		if kill_feed[i].evicted < 0:
			kill_feed[i].evicted = clock
	while kill_feed.size() > 6:
		kill_feed.pop_back()

func update_feed() -> void:
	kill_feed = kill_feed.filter(func(entry): return clock-entry.time < 7.0 and (entry.evicted < 0 or clock-entry.evicted < .45))

func shoot_ray(origin: Vector3, direction: Vector3, weapon_id: int, airborne: bool, shooter: Node = null) -> Dictionary:
	if net.running and not net.round_active: return {}
	if net.is_client_ready():
		# Cosmetic local ray only. Health, headshots, XP and kills need server confirmation.
		shot_count += 1
		var end = origin+direction.normalized()*150
		var query = PhysicsRayQueryParameters3D.create(origin,end,1|4)
		var hit = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			end = hit.position
			if hit.collider.collision_layer & 1:
				effects.impact(hit.position,hit.normal,hit.collider.get_meta("surface","") in ["metal","panel"])
		_tracer(origin,end)
		return {}
	if shooter==null: shooter = player
	radar.mark(shooter,clock)
	shot_count += 1
	action_serial += 1
	var far_end = origin + direction.normalized() * 150.0
	var end = far_end
	var ray_start = origin
	var excluded: Array[RID] = []
	for area in shooter.hitboxes: excluded.append(area.get_rid())
	var first_hit: Dictionary = {}
	var shot_kills = 0
	var any_head = false
	var any_hit = false
	var rewind = net.running and net.server and shooter.shot_view_time>=0
	for _penetration in range(4 if weapon_id == 3 else 1):
		var query = PhysicsRayQueryParameters3D.create(ray_start, far_end, 1 if rewind else (1 | 8))
		query.collide_with_areas = true
		query.exclude = excluded
		var hit = get_world_3d().direct_space_state.intersect_ray(query)
		if rewind:
			var historical = net.lag_comp.raycast(net.slots,ray_start,direction.normalized(),ray_start.distance_to(far_end),shooter,shooter.shot_view_time,excluded)
			if not historical.is_empty() and (hit.is_empty() or ray_start.distance_squared_to(historical.position)<ray_start.distance_squared_to(hit.position)):
				query.collision_mask = 1|8
				var current_hit = get_world_3d().direct_space_state.intersect_ray(query)
				if current_hit.is_empty() or current_hit.collider!=historical.collider: net.lag_rescued_hits += 1
				hit = historical
		if hit.is_empty():
			end = far_end
			break
		end = hit.position
		if first_hit.is_empty():
			first_hit = hit
		var collider = hit.collider
		if not collider.has_meta("target"):
			effects.impact(hit.position,hit.normal,collider.get_meta("surface","") in ["metal","panel"])
			break
		var target = collider.get_meta("target")
		# Teammates remain safe and stop the ray; world geometry never penetrates.
		if target.team == shooter.team:
			break
		for area in target.hitboxes:
			excluded.append(area.get_rid())
		if target.health > 0:
			var head = collider.get_meta("zone") == "head"
			var damage = Rules.WEAPONS[weapon_id]["head" if head else "body"]
			var full_health = target.health==100
			var killed = damage_actor(target,damage,shooter.team,shooter.target_name)
			hit_count += 1
			any_hit = true
			any_head = any_head or head
			if killed:
				shot_kills += 1
				record_kill(target.target_name,Rules.WEAPONS[weapon_id]["name"],head,airborne,action_serial,shooter.target_name,shooter.team,full_health and damage>=100)
				if head and airborne:
					air_heads += 1
			hit["headshot"] = head
			hit["damage"] = damage
			hit["killed"] = killed
		ray_start = hit.position + direction.normalized() * .01
	if any_hit:
		net.hit_feedback(shooter,any_head)
	first_hit["kill_count"] = shot_kills
	_tracer(origin, end)
	if net.running: net.shot_fx(shooter.net_slot,origin,end,weapon_id)
	return first_hit

func _tracer(start: Vector3, end: Vector3, color: Color = Color("ffe6a8")) -> void:
	var distance = start.distance_to(end)
	if distance < 0.01:
		return
	var beam = Geo.box(self, (start+end)*0.5, Vector3(0.015,0.015,distance), color)
	beam.look_at(end, Vector3.UP)
	var tween = create_tween()
	tween.tween_interval(0.045)
	tween.tween_callback(beam.queue_free)

func melee_attack(shooter: Node = null) -> void:
	if net.is_client_ready() or (net.running and not net.round_active): return
	if shooter==null: shooter = player
	action_serial += 1
	var origin = shooter.camera.global_position
	var forward = -shooter.camera.global_basis.z
	var closest = null
	var closest_distance = 2.3
	for target in net.actors() if net.running else targets:
		if target.team == shooter.team or target.health <= 0:
			continue
		var center = target.global_position + Vector3.UP
		var offset = center - origin
		if offset.length() < closest_distance and forward.dot(offset.normalized()) > 0.78 and unobstructed(origin, center):
			closest = target
			closest_distance = offset.length()
	if closest != null:
		if closest.get("parry_timer") != null and closest.parry_timer>0 and Rules.parry_blocks(-closest.global_basis.z,shooter.global_position-closest.global_position):
			shooter.fire_cooldown = maxf(shooter.fire_cooldown,.85)
			world_sound("parry",closest.global_position,-8)
			return
		var killed = damage_actor(closest,Rules.WEAPONS[2].body,shooter.team,shooter.target_name)
		net.hit_feedback(shooter,false)
		if killed:
			record_kill(closest.target_name,"SWORD",false,false,action_serial,shooter.target_name,shooter.team)


func _clear_effects() -> void:
	if is_instance_valid(effects): effects.clear()
	for grenade in grenades:
		if is_instance_valid(grenade):
			grenade.queue_free()
	grenades.clear()
	for smoke in smoke_nodes:
		if is_instance_valid(smoke):
			smoke.queue_free()
	smoke_nodes.clear()

func reset_practice(reset_score: bool) -> void:
	if mode=="combat":
		if player.health<=0:
			return
		player.take_damage(100,2,"FALL")
		return
	_clear_effects()
	player.reset_at(launch_pad)
	for target in targets:
		target.reset()
	if reset_score:
		progression.reset_roster(false)
		kills = 0
		air_heads = 0
		perfect_boosts = 0
		shot_count = 0
		hit_count = 0
		kill_feed.clear()
		chain_count = 0
		last_kill_time = -999.0
	notify("BACK ON THE PAD", "G to equip. Right-click to drop. Jump just before the burst.")

func _self_test() -> void:
	var suite = load("res://tests/test_game.gd").new()
	add_child(suite)
	await suite.run(self)

func _combat_test() -> void:
	var suite = load("res://tests/test_combat.gd").new()
	add_child(suite)
	await suite.run(self)

func _capture() -> void:
	if not Array(OS.get_cmdline_user_args()).any(func(arg): return arg in ["--capture-menu","--capture-online","--capture-settings","--capture-controls"]):
		set_active(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.set_physics_process(false)
	var modes = OS.get_cmdline_user_args()
	for page in ["ONLINE","SETTINGS","CONTROLS"]:
		if "--capture-"+page.to_lower() in modes: hud.menu.show_page(page)
	if "--capture-client" in modes:
		net.join("127.0.0.1",27020,"")
		var deadline = Time.get_ticks_msec()+10000
		while not net.is_client_ready() and Time.get_ticks_msec()<deadline:
			await get_tree().physics_frame
		await get_tree().create_timer(2).timeout
		player.set_physics_process(false)
	if "--capture-vote" in modes:
		await net.host(27925,"",false)
		combat.scores = [0,250,197]
		net._end_round()
		net.vote(2)
	if "--capture-perf" in modes:
		await start_mode("combat",1)
		for bot in combat.bots: bot.set_physics_process(false)
		player.set_physics_process(false)
		player.position = Vector3(-11,.05,14)
		player.look_at(Vector3(1,.05,-3))
		Engine.max_fps = 0
		var frame_times: Array = []
		var draws: Array = []
		for index in range(40):
			var begin = Time.get_ticks_usec()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			if index>=10:
				frame_times.append((Time.get_ticks_usec()-begin)/1000.0)
				draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		frame_times.sort()
		print("PERFORMANCE median_ms=",frame_times[15]," draw_calls=",draws[15]," batching=", "--no-batching" not in modes)

	for index in range(4):
		if "--capture-"+["foundry","dock","sunspire","relay"][index] in modes:
			await start_mode("combat",index)
			await get_tree().physics_frame
			await get_tree().physics_frame
			for bot in combat.bots: bot.set_physics_process(false)
			player.position = Vector3(-11,.05,14)
			player.look_at(Vector3(1,.05,-3))
			player.equip_cooldown = 0
	if "--capture-xp" in modes or "--capture-bonus" in modes or "--capture-scoreboard" in modes:
		start_mode("combat")
		for bot in combat.bots: bot.set_physics_process(false)
		player.position = Vector3(-6,.05,8)
		player.rotation.y = 0
		for i in range(4):
			clock += 1.1
			record_kill("ENEMY %d" % (i+1),"LONGSHOT",i%2==0,false,900+i,"YOU",1,true)
		record_kill("ENEMY 5","RIFLE",false,false,950,"ALLY 1",1)
		record_kill("ALLY 2","RIFLE",false,false,951,"ENEMY 5",2)
		if "--capture-bonus" in modes:
			player.take_damage(100,2,"ENEMY 3")
			await get_tree().physics_frame
			await get_tree().physics_frame
			clock += 2.01
			progression.update(clock)
		if "--capture-scoreboard" in modes: Input.action_press("scoreboard")
	if "--capture-variants" in modes:
		start_mode("combat")
		for bot in combat.bots:
			bot.set_physics_process(false)
			bot.position = Vector3(17,.05,-16)
		for i in range(3):
			var bot = combat.bots[4+i]
			bot.position = Vector3(-2.4+i*2.4,.05,-3)
			bot.rotation.y = 0
			bot.Rig.animate(bot.rig,3.5,1.6+i*.2,0,0,0,true)
		player.position = Vector3(0,.05,3)
		player.rotation.y = 0
	if "--capture-combat" in modes or "--capture-respawn" in modes:
		start_mode("combat")
		player.position = Vector3(-6,.05,8)
		player.rotation.y = 0
		for i in range(combat.bots.size()):
			combat.bots[i].position = Vector3(-12+i*3,.05,-2-(i%3)*2)
			combat.bots[i].set_physics_process(false)
		if "--capture-respawn" in modes:
			player.take_damage(100,2,"ENEMY 3")
		else:
			player.health = 50
			combat.scores = [0,8,6]
			record_kill("ENEMY 2","LONGSHOT",true,false,999)
	if "--capture-bolt" in modes:
		player.equip(3)
		player.sniper_cycle = .55
	if "--capture-wall" in modes:
		player.position = Vector3(-6,.04,-3.30)
		player.camera.rotation = Vector3.ZERO
	if "--capture-scope" in modes:
		player.position = Vector3(-1,.04,2)
		player.equip(3)
		player.scope_age = Rules.SCOPE_READY
		player.camera.fov = 32
	if "--capture-reload" in modes:
		player.ammo[0] = 5
		player.reload_timer = .9
	if "--capture-grenade" in modes:
		player.equip_grenade("blast")
	if "--capture-feed" in modes:
		for i in range(4):
			record_kill("TARGET %d" % (i+1),"RIFLE",true,false,100+i)
		record_kill("COLLATERAL A","LONGSHOT",true,false,110)
		record_kill("COLLATERAL B","LONGSHOT",true,false,110)
		notify("COLLATERAL x2","One round. Multiple targets.")
	if "--capture-sniper" in modes:
		player.equip(3)
	player.viewmodel.update_pose(0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output = OS.get_environment("BRASSLINE_CAPTURE_PATH")
	if output.is_empty():
		output = "user://brassline_preview.png"
	get_viewport().get_texture().get_image().save_png(output)
	print("CAPTURE ", output)
	await quit_game()

func start_ambience() -> void:
	if DisplayServer.get_name()=="headless": return
	var key = ["ambient_foundry","ambient_dock","ambient_sunspire","ambient_relay"][current_map]
	var stream = audio[key] as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length()*stream.mix_rate)
	ambience.stream = stream
	ambience.play()

func surface_at(at: Vector3) -> String:
	var query = PhysicsRayQueryParameters3D.create(at+Vector3.UP*.2,at+Vector3.DOWN*.5,1)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var kind = hit.collider.get_meta("surface","concrete")
		if kind in ["metal","panel"]: return "metal"
		if kind=="tile": return "tile"
	return "concrete"

func _expansion_test() -> void:
	var suite = load("res://tests/test_expansion.gd").new()
	add_child(suite)
	await suite.run(self)
func _progression_test() -> void:
	var suite = load("res://tests/test_progression.gd").new()
	add_child(suite)
	await suite.run(self)

func quit_game() -> void:
	if quitting: return
	quitting = true
	if net.running: await net.leave()
	progression.finish_chain(clock)
	save_profile()
	set_active(false)
	ambience.stop()
	ui_speaker.stop()
	for speaker in sound_pool: speaker.stop()
	for speaker in world_sounds: speaker.stop()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST: quit_game()

func menu_sound() -> void:
	if DisplayServer.get_name()!="headless": ui_speaker.play()

func damage_actor(victim: Node, amount: int, source_team: int, attacker: String) -> bool:
	if net.running and not net.round_active: return false
	if victim is Player: return victim.take_damage(amount,source_team,attacker)
	return victim.take_damage(amount,source_team)
func save_profile() -> void:
	prefs.data.xp = progression.xp_for("YOU")
	if not prefs.save(): net.status = prefs.error
func apply_settings() -> void:
	player.sensitivity = prefs.data.sensitivity
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.0001,prefs.data.volume)))
	Engine.max_fps = int(prefs.data.fps_limit)
	get_viewport().msaa_3d = Viewport.MSAA_2X if prefs.data.quality==2 else Viewport.MSAA_DISABLED
	for light in world_root.find_children("*","DirectionalLight3D",true,false): light.shadow_enabled = prefs.data.quality==2
func apply_display_settings() -> void:
	# Window mode changes only on startup or Apply Display, never on match load.
	if DisplayServer.get_name()=="headless": return
	var requested = "%s/%d/%d" % [prefs.data.fullscreen,prefs.data.resolution_width,prefs.data.resolution_height]
	if requested==applied_display: return
	var window = get_window()
	var desired = Window.MODE_FULLSCREEN if prefs.data.fullscreen else Window.MODE_WINDOWED
	if window.mode!=desired: window.mode = desired
	if not prefs.data.fullscreen:
		var usable = DisplayServer.screen_get_usable_rect(window.current_screen)
		var resolution = Vector2(prefs.data.resolution_width,prefs.data.resolution_height)
		var limit = Vector2(usable.size-Vector2i(32,64))
		resolution *= minf(1,minf(limit.x/resolution.x,limit.y/resolution.y))
		var pixels = Vector2i(resolution)
		if window.size!=pixels:
			window.size = pixels
			window.position = usable.position+(usable.size-pixels)/2
	applied_display = requested
	_apply_render_resolution()
func _apply_render_resolution() -> void:
	if DisplayServer.get_name()=="headless": return
	var window = get_window()
	var play_height = minf(window.size.y,window.size.x*9.0/16.0)
	window.scaling_3d_scale = clampf(minf(prefs.data.resolution_height,prefs.data.resolution_width*9.0/16.0)/maxf(1,play_height),.25,1.0) if prefs.data.fullscreen else 1.0
func _dedicated_server() -> void:
	var config = ConfigFile.new()
	config.load("res://server.cfg")
	selected_map = clampi(int(config.get_value("server","map",0)),0,3)
	var port = int(config.get_value("server","port",27020))
	var secret = str(config.get_value("server","password",""))
	await net.host(port,secret,true)
func _network_test() -> void:
	var suite = load("res://tests/test_network.gd").new()
	add_child(suite)
	await suite.run(self)
func _settings_test() -> void:
	var suite = load("res://tests/test_settings.gd").new()
	add_child(suite)
	await suite.run(self)

func _capacity_test() -> void:
	var suite = load("res://tests/test_capacity.gd").new()
	add_child(suite)
	await suite.run(self)

func _prediction_test() -> void:
	var suite = load("res://tests/test_prediction.gd").new()
	add_child(suite)
	await suite.run(self)

func _lagcomp_test() -> void:
	var suite = load("res://tests/test_lag_compensation.gd").new()
	add_child(suite)
	await suite.run(self)

func _polish_test() -> void:
	var suite = load("res://tests/test_polish.gd").new()
	add_child(suite)
	await suite.run(self)

func _display_test() -> void:
	var suite = load("res://tests/test_display.gd").new()
	add_child(suite)
	await suite.run(self)
