extends Node
## Internet-capable ENet. Only the host simulates combat and accepts bounded inputs.
const Player = preload("res://scripts/player.gd")
const Bot = preload("res://scripts/bot.gd")
const Avatar = preload("res://scripts/network_avatar.gd")
const Progression = preload("res://scripts/progression.gd")
const Preferences = preload("res://scripts/preferences.gd")
const LagCompensation = preload("res://scripts/lag_compensation.gd")
var lag_comp = LagCompensation.new()
var lag_rescued_hits = 0
const PROTOCOL = 14
var replay_wait: Dictionary = {}
var final_replay_until = 0.0
var mode_id = "tdm"
var destroy = preload("res://scripts/destroy_mode.gd").new()
func is_destroy() -> bool: return running and mode_id=="destroy"
func combat_allowed() -> bool:
	return round_active and (not is_destroy() or (destroy.fighting() if server else destroy.remote.get("phase","") in ["live","planted"]))
var game: Node
var running = false
var server = false
var session_ready = false
var dedicated = false
var status = "Host on your PC or join a friend's public IP. UDP port 27020."
var password = ""
var own_slot = -1
var spawned_life = -1
var slots: Array = []
var peers: Dictionary = {}
var pending: Dictionary = {}
var proxies: Dictionary = {}
var grenade_views: Dictionary = {}
var smoke_seen: Dictionary = {}
var serial = 0
var sequence = 0
var action_id = 0
var inputs: Array = []
var actions: Array = []
var snapshot_timer = 0.0
var connect_started = 0
var last_packet = 0
var snapshots_received = 0
var corrections = 0
var packet_serial = 0
var packet_parts: Dictionary = {}
var applied_packet = 0
var largest_packet = 0
var closing = false
var test_controls: Dictionary = {}
const INPUT_WINDOW = 32
const FIXED_STEP = 1.0/60.0
var pending_reconciliation: Array = []
var latest_server_time = 0.0
var snapshot_arrival = 0
var snapshot_interval = .05
var snapshot_jitter = 0.0
var ping_ms = 0
var server_tick_rate = 60.0
var tick_count = 0
var tick_window = 0
var presentation_time = 0.0
var presentation_ready = false
func _process(delta: float) -> void:
	destroy.view_tick(delta)
	if not is_client_ready() or snapshot_arrival==0: return
	var target = remote_time()-interpolation_delay()
	if not presentation_ready or absf(target-presentation_time)>1:
		presentation_time = target
		presentation_ready = true
	else:
		# Slew the render clock rather than restarting it at every jittery arrival.
		presentation_time += delta*clampf(1+(target-presentation_time)*5,.75,1.25)

var last_correction = 0.0
var predicted_grenades: Dictionary = {}
func remote_time() -> float:
	return latest_server_time + minf(.25,(Time.get_ticks_msec()-snapshot_arrival)/1000.0)
func interpolation_delay() -> float:
	return clampf(.05 + snapshot_jitter*2,.05,.12)
func consume_reconciliation() -> void:
	if pending_reconciliation.is_empty(): return
	var state = pending_reconciliation
	pending_reconciliation = []
	_reconcile(state[0],state[1])

func _ready() -> void:
	destroy.setup(self)
	process_physics_priority = 100
	multiplayer.server_relay = false
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): fail("Connection failed. Check the IP, UDP port, firewall and forwarding."))
	multiplayer.server_disconnected.connect(func(): fail("The host disconnected. Your confirmed XP is saved."))
	multiplayer.peer_connected.connect(func(id):
		if server:
			var peer = multiplayer.multiplayer_peer.get_peer(id)
			pending[id] = {"time":Time.get_ticks_msec(),"authenticated":false,"transport":peer})
	multiplayer.peer_disconnected.connect(_disconnected)
func is_client_ready() -> bool: return running and not server and session_ready
func actors() -> Array:
	var result: Array = []
	for slot in slots:
		if is_instance_valid(slot.get("actor")): result.append(slot.actor)
	return result
func host(port: int, secret: String, headless: bool = false, selected_mode: String = "tdm") -> bool:
	if running or game.changing_map: return false
	var transport = ENetMultiplayerPeer.new()
	var error = transport.create_server(port,16,3)
	if error!=OK:
		status = "Could not host on UDP %d (error %d). Another server may be using that port." % [port,error]
		return false
	multiplayer.multiplayer_peer = transport
	running = true
	server = true
	dedicated = headless
	mode_id = "destroy" if selected_mode=="destroy" else "tdm"
	game.combat.scores = [0,0,0]
	round_number = 1
	round_active = true
	loading_round = false
	winner = ""
	votes.clear()
	vote_counts = [0,0,0,0]
	password = secret.substr(0,64)
	status = "Hosting on UDP %d. Friends join your public IP and this port." % port
	await game.start_mode("online")
	game.combat.build_navigation()
	for index in range(10):
		slots.append({"index":index,"team":1 if index<5 else 2,"peer":0,"name":"BOT %02d" % (index+1),"kills":0,"deaths":0,"xp":0,"actor":null})
	if not dedicated:
		own_slot = 0
		_attach_human(1,0,game.prefs.data.name,game.progression.xp_for("YOU"))
	else:
		game.player.set_physics_process(false)
		game.player.collision_layer = 0
		for area in game.player.hitboxes: area.collision_layer = 0
		game.player.viewmodel.root.hide()
	for index in range(10):
		if slots[index].peer==0: _add_bot(index)
	session_ready = true
	round_active = true
	round_end = game.clock+TIME_LIMIT
	if is_destroy(): destroy.start_match()
	print("SERVER_READY port=",port," actors=",actors().size()," dedicated=",dedicated)
	return true
func join(address: String, port: int, secret: String, selected_mode: String = "tdm") -> void:
	if running or game.changing_map: return
	mode_id = "destroy" if selected_mode=="destroy" else "tdm"
	address = address.strip_edges()
	if address.is_empty() or address.length()>253:
		status = "Enter the host's public IP address or hostname."
		return
	var transport = ENetMultiplayerPeer.new()
	var error = transport.create_client(address,port,3)
	if error!=OK:
		status = "Could not start the connection (error %d)." % error
		return
	multiplayer.multiplayer_peer = transport
	running = true
	server = false
	session_ready = false
	closing = false
	password = secret.substr(0,64)
	connect_started = Time.get_ticks_msec()
	status = "Connecting to %s:%d…" % [address,port]
func _connected() -> void:
	_hello.rpc_id(1,PROTOCOL,password,game.prefs.data.name,int(game.prefs.data.xp),mode_id,game.prefs.data.selected_class)
@rpc("any_peer","call_remote","reliable",0)
func _hello(protocol: int, secret: String, nickname: String, xp: int, requested_mode: String = "tdm", selected_class: String = "vanguard") -> void:
	if not server: return
	var id = multiplayer.get_remote_sender_id()
	if not pending.has(id) or pending[id].authenticated: return
	if not session_ready:
		pending[id].hello = [protocol,secret,nickname,xp,requested_mode,selected_class]
		return
	_authenticate(id,protocol,secret,nickname,xp,requested_mode,selected_class)
func _authenticate(id: int, protocol: int, secret: String, nickname: String, xp: int, requested_mode: String = "tdm", selected_class: String = "vanguard") -> void:
	if not pending.has(id) or pending[id].authenticated: return
	if protocol!=PROTOCOL:
		_reject.rpc_id(id,"Different game version. Update everyone through the launcher.")
		return
	if requested_mode!=mode_id:
		_reject.rpc_id(id,"This server is playing "+("Destroy and Diffuse" if is_destroy() else "Team Deathmatch")+". Select that mode before joining.")
		return
	if secret!=password:
		_reject.rpc_id(id,"Incorrect server password.")
		return
	var counts = [0,0,0]
	var reserved: Array = []
	for peer_id in peers:
		if can_send(peer_id): counts[slots[peers[peer_id].slot].team] += 1
	for entry in pending.values():
		if entry.get("authenticated",false):
			reserved.append(entry.slot)
			counts[slots[entry.slot].team] += 1
	var preferred = 1 if counts[1]<=counts[2] else 2
	var chosen = -1
	for team in [preferred,3-preferred]:
		for slot in slots:
			if slot.team==team and slot.peer==0 and slot.index not in reserved:
				chosen = slot.index
				break
		if chosen>=0: break
	if chosen<0:
		_reject.rpc_id(id,"Server full: ten human players are already connected.")
		return
	pending[id].merge({"selected_class":selected_class,"authenticated":true,"slot":chosen,"name":Preferences.clean_name(nickname),"xp":clampi(xp,0,Progression.threshold(1000))},true)
	_welcome.rpc_id(id,game.current_map,chosen,game.clock,round_number)
@rpc("authority","call_remote","reliable",0)
func _reject(message: String) -> void: fail(message)
@rpc("authority","call_remote","reliable",0)
func _welcome(map_index: int, slot: int, server_clock: float, number: int) -> void:
	if server or not running: return
	own_slot = slot
	game.selected_map = map_index
	await game.start_mode("online",map_index)
	game.player.team = 1 if slot<5 else 2
	game.player.net_slot = slot
	game.clock = server_clock
	status = "Loading the arena…"
	_loaded.rpc_id(1,map_index,number)
@rpc("any_peer","call_remote","reliable",0)
func _loaded(map_index: int, number: int) -> void:
	if not server: return
	_loaded_peer(multiplayer.get_remote_sender_id(),map_index,number)
func _loaded_peer(id: int, map_index: int, number: int) -> void:
	if not pending.has(id) or not pending[id].authenticated: return
	var entry = pending[id]
	if not session_ready:
		entry.loaded = [map_index,number]
		return
	if map_index!=game.current_map or number!=round_number:
		_welcome.rpc_id(id,game.current_map,entry.slot,game.clock,round_number)
		return
	# Loading can finish out of reservation order. Balance the humans who can
	# actually play, swapping pending reservations rather than creating 2v0.
	var counts = [0,0,0]
	for peer_id in peers:
		if can_send(peer_id): counts[slots[peers[peer_id].slot].team] += 1
	var preferred = 1 if counts[1]<=counts[2] else 2
	if slots[entry.slot].team!=preferred:
		for candidate in slots:
			if candidate.team!=preferred or candidate.peer!=0: continue
			var previous = entry.slot
			for waiting_id in pending:
				if waiting_id!=id and pending[waiting_id].get("slot",-1)==candidate.index:
					pending[waiting_id].slot = previous
			entry.slot = candidate.index
			break
	var takeover = capture_life(entry.slot) if is_destroy() else {}
	if is_destroy(): destroy.clear_slot(entry.slot)
	_remove_actor(entry.slot)
	_attach_human(id,entry.slot,entry.name,entry.xp)
	if is_destroy(): restore_life(entry.slot,takeover)
	pending.erase(id)
	_spawn.rpc_id(id,slots[entry.slot].actor.position,slots[entry.slot].actor.life_id,entry.slot,slots[entry.slot].actor.health)
	print("HUMAN_JOIN peer=",id," slot=",entry.slot," actors=",actors().size())
func _attach_human(id: int, slot: int, nickname: String, xp: int) -> void:
	var actor = game.player if id==1 else Player.new()
	if id!=1:
		actor.game = game
		actor.locally_controlled = false
		actor.team = slots[slot].team
		game.add_child(actor)
	actor.net_slot = slot
	actor.peer_id = id
	actor.team = slots[slot].team
	actor.target_name = "S%d" % slot
	actor.life_id += 1
	slots[slot].merge({"peer":id,"name":nickname,"actor":actor,"kills":0,"deaths":0,"xp":xp},true)
	var progress = game.progression if id==1 else Progression.new()
	progress.reset_roster(false)
	progress.profiles["YOU"] = xp
	peers[id] = {"selected_class":preload("res://scripts/loadouts.gd").allowed(game.prefs.data.selected_class if id==1 else pending.get(id,{}).get("selected_class","vanguard"),xp),"killcams":game.prefs.data.killcams if id==1 else true,"slot":slot,"progress":progress,"commands":[],"last_action":0,"received_action":0,"last_input":Time.get_ticks_msec(),"last_sequence":0,"budget":80.0,"loaded":true,"transport":pending[id].transport if pending.has(id) else null,"leaving":false,"frames":[],"move_credit":2.0,"frame_gap":0}
	actor.reset_at(game.combat.choose_spawn(actor.team,actor))
	actor.rotation.y = atan2(actor.position.x,actor.position.z)
func _add_bot(index: int) -> void:
	var row = slots[index]
	var bot = Bot.new()
	bot.game = game
	bot.combat = game.combat
	bot.net_slot = index
	bot.team = row.team
	bot.target_name = "S%d" % index
	bot.bot_index = index if index<5 else index-1
	bot.position = game.combat.choose_spawn(bot.team,bot)
	game.add_child(bot)
	game.combat.bots.append(bot)
	game.targets.append(bot)
	row.merge({"peer":0,"name":"BOT %02d" % (index+1),"actor":bot,"kills":0,"deaths":0,"xp":0},true)
func _remove_actor(index: int) -> void:
	var actor = slots[index].actor
	if not is_instance_valid(actor): return
	game.combat.bots.erase(actor)
	game.targets.erase(actor)
	actor.set_physics_process(false)
	actor.collision_layer = 0
	for area in actor.hitboxes: area.collision_layer = 0
	if actor!=game.player: actor.queue_free()
	slots[index].actor = null
func _disconnected(id: int) -> void:
	replay_wait.erase(id)
	pending.erase(id)
	votes.erase(id)
	vote_counts = [0,0,0,0]
	for index in votes.values(): vote_counts[index] += 1
	if not server or not peers.has(id): return
	var slot = peers[id].slot
	var takeover = capture_life(slot) if is_destroy() else {}
	if is_destroy(): destroy.clear_slot(slot)
	peers.erase(id)
	_remove_actor(slot)
	if running and not closing:
		slots[slot].peer = 0
		if not loading_round:
			_add_bot(slot)
			if is_destroy(): restore_life(slot,takeover)
			else: _balance_humans()
	print("HUMAN_LEFT slot=",slot," actors=",actors().size())
func send_input(actor: Node, move: Vector2, jump: bool, aiming: bool) -> void:
	sequence += 1
	# Every command represents exactly one physics tick. Redundancy recovers
	# lost/reordered UDP packets without waiting for reliable retransmission.
	inputs.append([sequence,move,jump,actor.held("crouch"),actor.rotation.y,actor.held("aim"),actor.pitch,aiming])
	while inputs.size()>180: inputs.pop_front()
	var recent = inputs.slice(maxi(0,inputs.size()-INPUT_WINDOW))
	var packed = var_to_bytes(recent).compress(FileAccess.COMPRESSION_DEFLATE)
	# Keep every datagram below MTU even during rapid aim changes.
	while packed.size()>950 and recent.size()>8:
		recent.pop_front()
		packed = var_to_bytes(recent).compress(FileAccess.COMPRESSION_DEFLATE)
	_input_bundle.rpc_id(1,actor.life_id,packed)
func remember_input(_actor: Node, _move: Vector2, _jump: bool) -> void:
	pass
func send_action(action: String, value: int, actor: Node) -> void:
	action_id += 1
	actions.append([action_id,action,actor.weapon])
	while actions.size()>80: actions.pop_front()
	_command.rpc_id(1,action_id,actor.life_id,action,value,actor.rotation.y,actor.pitch,sequence,presentation_time)
@rpc("any_peer","call_remote","unreliable_ordered",1)
func _input_bundle(life: int, packed: PackedByteArray) -> void:
	if not server or packed.size()>1050: return
	var id = multiplayer.get_remote_sender_id()
	if not peers.has(id): return
	var bytes = packed.decompress_dynamic(8192,FileAccess.COMPRESSION_DEFLATE)
	if bytes.is_empty(): return
	var decoded = bytes_to_var(bytes)
	if decoded is Array: _receive_frames(peers[id],life,decoded)
func _receive_frames(p: Dictionary, life: int, frames: Array) -> void:
	var actor = slots[p.slot].actor
	if life!=actor.life_id or actor.health<=0 or not combat_allowed() or not p.get("loaded",true) or frames.size()>INPUT_WINDOW: return
	for frame in frames:
		if not frame is Array or frame.size()!=8: continue
		if not frame[0] is int or not frame[1] is Vector2: continue
		if not frame[2] is bool or not frame[3] is bool or not frame[5] is bool or not frame[7] is bool: continue
		if not (frame[4] is float or frame[4] is int) or not (frame[6] is float or frame[6] is int): continue
		var seq = int(frame[0])
		if seq<=p.last_sequence or seq>p.last_sequence+600 or not frame[1].is_finite() or not is_finite(frame[4]) or not is_finite(frame[6]): continue
		if p.frames.size()>=120: break
		if p.last_sequence>0: p.frame_gap += maxi(0,seq-p.last_sequence-1)
		p.last_sequence = seq
		p.last_input = Time.get_ticks_msec()
		var clean = frame.duplicate()
		clean[1] = frame[1].limit_length()
		clean[4] = wrapf(frame[4],-PI,PI)
		clean[6] = clampf(frame[6],-1.5,1.5)
		p.frames.append(clean)
func simulate_remote(actor: Node, delta: float) -> void:
	if not peers.has(actor.peer_id): return
	var p = peers[actor.peer_id]
	# Credit is earned using SERVER time, never client-supplied delta. A small
	# burst allowance absorbs jitter without permitting faster-than-real-time play.
	p.move_credit = minf(INPUT_WINDOW,p.move_credit+delta/FIXED_STEP)
	var steps = 0
	while not p.frames.is_empty() and p.move_credit>=1 and steps<8:
		var frame = p.frames.pop_front()
		actor.net_controls = {"move":frame[1],"aim":frame[5],"crouch":frame[3]}
		actor.rotation.y = frame[4]
		actor.pitch = frame[6]
		actor.camera.rotation.x = actor.pitch
		actor.advance_weapon_state(FIXED_STEP)
		actor.simulate_movement(FIXED_STEP,frame[1],frame[2],frame[3],false,-1,1 if frame[7] else 0)
		# Acknowledge only AFTER the matching command has been simulated.
		actor.last_input_sequence = frame[0]
		_commands(p,actor)
		p.move_credit -= 1
		steps += 1
	if steps==0 and Time.get_ticks_msec()-p.last_input>250:
		actor.net_controls = {"move":Vector2.ZERO,"aim":false,"crouch":actor.crouched}
		actor.advance_weapon_state(delta)
		actor.simulate_movement(delta,Vector2.ZERO,false,actor.crouched)
@rpc("any_peer","call_remote","reliable",0)
func _command(number: int, life: int, action: String, value: int, yaw: float, pitch: float, input_seq: int, view_time: float) -> void:
	if not server: return
	var id = multiplayer.get_remote_sender_id()
	if not peers.has(id): return
	var p = peers[id]
	var actor = slots[p.slot].actor
	if number<=p.received_action or number>p.received_action+100 or not is_finite(yaw) or not is_finite(pitch) or not is_finite(view_time): return
	p.received_action = number
	if not combat_allowed() or life!=actor.life_id or actor.health<=0 or p.commands.size()>=32 or p.budget<1: return
	if action not in ["fire","reload","jump","equip","grenade","throw","parry"]: return
	if value<0 or value>3: return
	p.budget -= 1
	p.commands.append({"id":number,"life":life,"action":action,"value":value,"yaw":wrapf(yaw,-PI,PI),"pitch":clampf(pitch,-1.5,1.5),"time":game.clock,"sequence":clampi(input_seq,0,p.last_sequence+600),"view_time":bounded_shot_time(p,view_time)})
func _commands(p: Dictionary, actor: Node) -> void:
	var budget = 8
	while not p.commands.is_empty() and budget>0:
		budget -= 1
		var cmd = p.commands[0]
		if cmd.life==actor.life_id and cmd.sequence>actor.last_input_sequence and game.clock-cmd.time<.5: break
		if cmd.life==actor.life_id and cmd.action in ["fire","throw"] and (actor.equip_cooldown>0 or actor.fire_cooldown>0) and game.clock-cmd.time<.35: break
		p.commands.pop_front()
		p.last_action = cmd.id
		if not combat_allowed() or cmd.life!=actor.life_id or actor.health<=0 or game.clock-cmd.time>.5: continue
		if is_destroy() and destroy.holding(actor.net_slot): continue
		actor.net_action_id = cmd.id
		actor.rotation.y = cmd.yaw
		actor.pitch = cmd.pitch
		actor.camera.rotation.x = actor.pitch
		match cmd.action:
			"jump": pass # Jump is carried in the numbered movement stream.
			"fire":
				actor.shot_view_time = cmd.view_time # Already bounded at receipt; preserve through server queue time.
				actor.shoot()
				actor.shot_view_time = -1.0
			"parry": actor.start_parry()
			"reload": actor.start_reload()
			"equip": actor.equip(cmd.value)
			"grenade": actor.equip_grenade("blast" if cmd.value==0 else "smoke")
			"throw":
				if not actor.held_grenade.is_empty(): actor.throw_grenade(actor.held_grenade,cmd.value==1)
func _physics_process(delta: float) -> void:
	if not running or closing: return
	if server:
		tick_count += 1
		var now = Time.get_ticks_msec()
		if tick_window==0: tick_window = now
		elif now-tick_window>=1000:
			server_tick_rate = tick_count*1000.0/(now-tick_window)
			tick_count = 0
			tick_window = now
	if not server:
		if not session_ready and Time.get_ticks_msec()-connect_started>20000: fail("Connection timed out. Check the host's public IP and UDP forwarding.")
		elif session_ready and Time.get_ticks_msec()-last_packet>10000: fail("Connection lost. Your confirmed XP is saved.")
		return
	if not session_ready: return
	game.replays.history.sample(game,delta)
	for id in replay_wait.keys():
		if not peers.has(id): replay_wait.erase(id); continue
		if game.clock>=replay_wait[id].until:
			var actor = slots[peers[id].slot].actor
			replay_wait.erase(id)
			if combat_allowed() and not is_destroy(): _respawn_human(actor)
	if is_destroy(): destroy.tick(delta)
	_check_round()
	lag_comp.record(slots,game.clock)
	for id in pending.keys():
		if pending[id].has("hello") and not pending[id].authenticated:
			var hello = pending[id].hello
			pending[id].erase("hello")
			_authenticate(id,hello[0],hello[1],hello[2],hello[3],hello[4],hello[5] if hello.size()>5 else "vanguard")
		if pending.has(id) and pending[id].has("loaded"):
			var loaded = pending[id].loaded
			pending[id].erase("loaded")
			_loaded_peer(id,loaded[0],loaded[1])
		if pending.has(id) and Time.get_ticks_msec()-pending[id].time>20000:
			multiplayer.multiplayer_peer.disconnect_peer(id)
	for id in peers:
		var p = peers[id]
		var actor = slots[p.slot].actor
		p.budget = minf(80,p.budget+40*delta)
		if id!=1:
			if Time.get_ticks_msec()-p.last_input>250: actor.net_controls = {"move":Vector2.ZERO,"aim":false,"crouch":actor.crouched}
			if round_active and p.get("loaded",true): _commands(p,actor)
		p.progress.update(game.clock)
		slots[p.slot].xp = p.progress.xp_for("YOU")
	snapshot_timer += delta
	if snapshot_timer>=.05:
		snapshot_timer = fmod(snapshot_timer,.05)
		_send_snapshots()
func _row(slot: Dictionary) -> Array:
	var a = slot.actor
	var human = slot.peer>0
	return [slot.index,a.position,a.velocity,a.rotation.y,a.pitch if human else 0.0,a.health,a.weapon if human else 0,a.crouched if human else false,a.life_id,a.reload_timer if human else a.reload_time,a.parry_timer if human else 0.0,a.cosmetics if human else {},a.class_id if human else "vanguard"]
func board_rows(team: int) -> Array:
	var result: Array = []
	for s in slots:
		if s.team!=team: continue
		result.append({"name":"YOU" if s.index==own_slot else s.name,"team":team,"kills":s.kills,"deaths":s.deaths,"xp":s.xp,"level":Progression.level_for_xp(s.xp)})
	result.sort_custom(func(a,b): return a.kills>b.kills if a.kills!=b.kills else a.deaths<b.deaths)
	return result
func _send_snapshots() -> void:
	if closing: return
	var states: Array = []
	var board: Array = []
	for s in slots:
		states.append(_row(s))
		board.append([s.index,s.team,s.peer,s.name,s.kills,s.deaths,s.xp])
	var projectiles: Array = []
	for g in game.grenades:
		if is_instance_valid(g) and not g.is_queued_for_deletion(): projectiles.append([g.net_id,g.kind,g.position,g.velocity,g.fuse,g.owner_actor.peer_id if is_instance_valid(g.owner_actor) else 0,g.prediction_action])
	var smokes: Array = []
	for smoke in game.smoke_nodes:
		if is_instance_valid(smoke) and not smoke.is_queued_for_deletion(): smokes.append([smoke.get_instance_id(),smoke.position-Vector3.UP*.8,smoke.get_meta("expires",game.clock+6)-game.clock])
	for id in peers:
		var p = peers[id]
		if id==1:
			game.kills = slots[p.slot].kills
			game.combat.deaths = slots[p.slot].deaths
			continue
		if not p.get("loaded",true) or not can_send(id): continue
		var a = slots[p.slot].actor
		var own = {"class_id":a.class_id,"recovery":a.fire_cooldown if a.weapon==2 else 0.0,"radar":game.radar.contacts(actors(),a.team,game.clock),"server_hz":server_tick_rate,"ack":a.last_input_sequence,"action":p.last_action,"ammo":a.ammo,"blast":a.blast_count,"smoke":a.smoke_count,"held":a.held_grenade,"ground":a.is_on_floor(),"jump_buffer":a.jump_buffer,"last_jump":a.last_jump_time,"xp":p.progress.xp_for("YOU"),"awards":p.progress.awards,"level_until":p.progress.level_up_until,"level":p.progress.recent_level,"round":round_info(a.team)}
		var payload = var_to_bytes([game.clock,states,board,own,game.combat.scores,projectiles,smokes]).compress(FileAccess.COMPRESSION_DEFLATE)
		packet_serial += 1
		largest_packet = maxi(largest_packet,payload.size())
		var parts = ceili(payload.size()/1050.0)
		for part in range(parts): _state_chunk.rpc_id(id,packet_serial,part,parts,payload.slice(part*1050,(part+1)*1050))
func _snapshot(time: float, states: Array, board: Array, own: Dictionary, scores: Array, projectiles: Array, smokes: Array) -> void:
	if server or not session_ready: return
	last_packet = Time.get_ticks_msec()
	snapshots_received += 1
	var now = Time.get_ticks_msec()
	if snapshot_arrival>0:
		var interval = (now-snapshot_arrival)/1000.0
		snapshot_jitter = lerpf(snapshot_jitter,absf(interval-.05),.1)
		snapshot_interval = lerpf(snapshot_interval,interval,.1)
	snapshot_arrival = now
	latest_server_time = time
	game.radar.remote = own.get("radar",[])
	game.radar.remote_at = Time.get_ticks_msec()
	server_tick_rate = own.get("server_hz",60)
	var transport = multiplayer.multiplayer_peer.get_peer(1)
	ping_ms = int(transport.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	# Keep the HUD clock monotonic; remote interpolation uses its own arrival clock.
	game.clock = maxf(game.clock,time)
	_round_notice(own.round)
	slots.clear()
	for row in board: slots.append({"index":row[0],"team":row[1],"peer":row[2],"name":row[3],"kills":row[4],"deaths":row[5],"xp":row[6]})
	game.combat.scores = scores
	game.kills = slots[own_slot].kills
	game.combat.deaths = slots[own_slot].deaths
	for row in states:
		var index = row[0]
		if index==own_slot:
			pending_reconciliation = [row,own]
			continue
		if not proxies.has(index):
			var avatar = Avatar.new()
			avatar.game = game
			avatar.team = slots[index].team
			avatar.net_slot = index
			game.add_child(avatar)
			proxies[index] = avatar
		proxies[index].human = slots[index].peer>0
		proxies[index].viewmodel.root.rotation.y = PI if slots[index].peer>0 else 0.0
		proxies[index].target_name = slots[index].name
		proxies[index].receive(row,time)
	game.player.set_class(own.get("class_id","vanguard"))
	game.progression.profiles["YOU"] = own.xp
	game.progression.awards = own.awards
	game.progression.level_up_until = own.level_until
	game.progression.recent_level = own.level
	var visible_ids: Array = []
	for row in projectiles:
		visible_ids.append(row[0])
		if not grenade_views.has(row[0]) and row[5]==multiplayer.get_unique_id() and predicted_grenades.has(row[6]):
			var predicted = predicted_grenades[row[6]]
			predicted_grenades.erase(row[6])
			if is_instance_valid(predicted) and not predicted.is_queued_for_deletion():
				predicted.predicted = false
				predicted.replica = true
				predicted.net_id = row[0]
				grenade_views[row[0]] = predicted
		if not grenade_views.has(row[0]):
			var g = game.Grenade.new()
			g.game = game
			g.kind = row[1]
			g.replica = true
			game.add_child(g)
			game.grenades.append(g)
			grenade_views[row[0]] = g
			g.position = row[2]
		var grenade = grenade_views[row[0]]
		grenade.confirmed_state = [row[2],row[3],row[4]]
		grenade.confirmation_age = minf(.15,ping_ms/2000.0)
	for id in grenade_views.keys():
		if id not in visible_ids:
			if is_instance_valid(grenade_views[id]): grenade_views[id].queue_free()
			grenade_views.erase(id)
	for row in smokes:
		if not smoke_seen.has(row[0]):
			smoke_seen[row[0]] = time+row[2]
			game.make_smoke(row[1],row[2])
	for id in smoke_seen.keys():
		if smoke_seen[id]<time-2: smoke_seen.erase(id)
func _reconcile(row: Array, own: Dictionary) -> void:
	var a = game.player
	if row[8]<a.life_id: return
	if game.replays.active and not game.replays.final and row[8]==game.replays.clip.get("victim_life",-1) and row[5]>0: return
	if row[8]!=a.life_id:
		_spawn(row[1],row[8])
	var previous = a.position
	var phase = a.movement_phase
	var landing = a.landing_pose
	a.position = row[1]
	a.velocity = row[2]
	if row[5]<a.health:
		a.hurt_flash = .35
		game.sound("hurt",-12)
	a.health = row[5]
	a.set_crouch(row[7],true)
	a.jump_buffer = own.jump_buffer
	a.last_jump_time = own.last_jump
	inputs = inputs.filter(func(input): return input[0]>own.ack)
	var yaw = a.rotation.y
	var ground = 1 if own.ground else 0
	if a.health<=0: inputs.clear()
	a.collision_layer = 2 if a.health>0 else 0
	for area in a.hitboxes: area.collision_layer = 8 if a.health>0 else 0
	for input in inputs:
		a.rotation.y = input[4]
		a.simulate_movement(FIXED_STEP,input[1],input[2],input[3],true,ground,1 if input[7] else 0)
		ground = -1
	a.rotation.y = yaw
	a.movement_phase = phase
	a.landing_pose = landing
	last_correction = previous.distance_to(a.position)
	if last_correction>.2: corrections += 1
	if last_correction<2.0:
		a.correction_offset += previous-a.position
		a.correction_offset = a.correction_offset.limit_length(1.0)
	else: a.correction_offset = Vector3.ZERO
	for id in predicted_grenades.keys():
		var grenade = predicted_grenades[id]
		if not is_instance_valid(grenade) or grenade.is_queued_for_deletion(): predicted_grenades.erase(id)
	actions = actions.filter(func(action): return action[0]>own.action)
	var pending_fire = [0,0,0,0]
	for action in actions:
		if action[1]=="fire": pending_fire[action[2]] += 1
	# Advance acknowledged reload state along the pending input timeline before
	# subtracting shots, including shots fired immediately after the local reload.
	var remaining_reload = maxf(0,row[9]-inputs.size()*FIXED_STEP)
	for index in range(4):
		var base_ammo = own.ammo[index]
		if index==row[6] and row[9]>0 and remaining_reload==0: base_ammo = a.weapon_stats(index)["mag"]
		a.ammo[index] = maxi(0,base_ammo-pending_fire[index])
	if actions.is_empty():
		if a.weapon==2: a.fire_cooldown = maxf(a.fire_cooldown,own.get("recovery",0.0)-ping_ms/2000.0)
		a.blast_count = own.blast
		a.smoke_count = own.smoke
		a.held_grenade = own.held
		a.weapon = row[6]
		if absf(a.reload_timer-remaining_reload)>.10: a.reload_timer = remaining_reload
@rpc("authority","call_remote","reliable",0)
func _spawn(at: Vector3, life: int, joined_slot: int = -1, spawn_health: int = 100) -> void:
	if server or life<game.player.life_id or (session_ready and life<=spawned_life): return
	if joined_slot>=0 and joined_slot<10:
		own_slot = joined_slot
		game.player.net_slot = joined_slot
	spawned_life = life
	session_ready = true
	loading_round = false
	if not game.menu_open: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	last_packet = Time.get_ticks_msec()
	status = "Connected • "+("Destroy and Diffuse" if is_destroy() else "5v5 TDM")+" • Your team: "+("BLUE" if own_slot<5 else "RED")
	pending_reconciliation = []
	inputs.clear()
	actions.clear()
	for grenade in predicted_grenades.values():
		if is_instance_valid(grenade): grenade.queue_free()
	predicted_grenades.clear()
	if game.replays.active or game.replays.transitioning(): game.replays.stop(false)
	game.player.life_id = life
	game.player.reset_at(at)
	game.player.health = spawn_health
	if spawn_health<=0:
		game.player.collision_layer = 0
		for area in game.player.hitboxes: area.collision_layer = 0
	game.player.team = 1 if own_slot<5 else 2
	game.player.set_physics_process(true)
	_cosmetic_request.rpc_id(1,game.cosmetics.equipped)
	_replay_settings.rpc_id(1,game.prefs.data.killcams)
func human_died(actor: Node) -> void:
	if not server: return
	if is_destroy():
		destroy.drop(actor.net_slot)
		return
	if peers.has(actor.peer_id) and peers[actor.peer_id].killcams:
		replay_wait[actor.peer_id]={"life":actor.life_id,"until":game.clock+.1}
	_respawn_human.call_deferred(actor)
func _respawn_human(actor: Node) -> void:
	if not running or not is_instance_valid(actor) or actor.health>0 or replay_wait.has(actor.peer_id) or not combat_allowed(): return
	actor.life_id += 1
	actor.reset_at(game.combat.choose_spawn(actor.team,actor))
	if actor.peer_id!=1 and can_send(actor.peer_id): _spawn.rpc_id(actor.peer_id,actor.position,actor.life_id)
func fell(actor: Node) -> void:
	if not server: return
	actor.health = 0
	game.challenge_event(actor,"death")
	if actor.net_slot>=0: slots[actor.net_slot].deaths += 1
	human_died(actor)
func slot_from_name(nickname: String) -> int:
	if nickname=="YOU": return own_slot
	if nickname.begins_with("S") and nickname.substr(1).is_valid_int(): return clampi(nickname.substr(1).to_int(),0,9)
	return -1
func display_name(nickname: String) -> String:
	var slot = slot_from_name(nickname)
	if slot<0 or slot>=slots.size(): return nickname
	return "YOU" if slot==own_slot else slots[slot].name
func record_kill(victim: String, weapon: String, head: bool, air: bool, group: int, killer: String, team: int, one_shot: bool, context: Dictionary = {}) -> void:
	if not server or not round_active: return
	var k = slot_from_name(killer)
	var v = slot_from_name(victim)
	if k<0 or v<0 or k==v or slots[k].team==slots[v].team: return
	game.replays.note_kill(str(v),str(k),weapon,head,float(context.get("view_lag",0.0)))
	context = context.duplicate()
	context.merge({"time":game.clock,"one_shot":one_shot},true)
	slots[k].kills += 1
	slots[v].deaths += 1
	if not is_destroy(): game.combat.scores[team] += 1
	if peers.has(slots[k].peer):
		peers[slots[k].peer].progress.record("YOU",victim,team,head,one_shot,game.clock,group,weapon=="LONGSHOT")
	else: slots[k].xp += 100 if head or one_shot else 50
	if peers.has(slots[v].peer): peers[slots[v].peer].progress.finish_chain(game.clock)
	_kill(k,v,weapon,head,air,group,team,context)
	for id in peers:
		if id!=1 and can_send(id): _kill.rpc_id(id,k,v,weapon,head,air,group,team,context)
	if not is_destroy() and game.combat.scores[team]>=KILL_LIMIT: _end_round()
@rpc("authority","call_remote","reliable",0)
func _kill(k: int, v: int, weapon: String, head: bool, air: bool, group: int, team: int, context: Dictionary = {}) -> void:
	var killer = "YOU" if k==own_slot else (slots[k].name if k<slots.size() else "PLAYER")
	var victim = "YOU" if v==own_slot else (slots[v].name if v<slots.size() else "PLAYER")
	if v==own_slot: game.accept_challenge("death",{"killer":"S%d" % k})
	if k==own_slot:
		var event = context.duplicate()
		event.merge({"weapon":weapon,"head":head,"air":air,"group":group,"victim":"S%d" % v},true)
		game.accept_challenge("kill",event)
	game.feed_entry(victim,weapon,head,air,group,killer,team)
	if k==own_slot and not head: game.sound("kill",-19)
func hit_feedback(actor: Node, head: bool) -> void:
	if actor==game.player: _hit(head)
	elif server and actor.peer_id>1 and can_send(actor.peer_id): _hit.rpc_id(actor.peer_id,head)
@rpc("authority","call_remote","reliable",0)
func _hit(head: bool) -> void:
	game.hit_flash = .22 if head else .16
	game.last_head = head
	game.sound("head" if head else "hit",-5 if head else -10)
func shot_fx(slot: int, start: Vector3, end: Vector3, weapon: int) -> void:
	if not server: return
	game.replays.history.shot(game,slots[slot].actor,start,end,weapon)
	for id in peers:
		if id!=1 and can_send(id): _shot_fx.rpc_id(id,slot,start,end,weapon)
@rpc("authority","call_remote","unreliable",2)
func _shot_fx(slot: int, start: Vector3, end: Vector3, weapon: int) -> void:
	if slot==own_slot: return # Shooter already rendered this instantly.
	game._tracer(start,end)
	if slot!=own_slot:
		game.world_sound("sniper" if weapon==3 else ("pistol" if weapon==1 else "rifle"),start,-16,false)
		if proxies.has(slot): proxies[slot].viewmodel.on_shot()
func blast_fx(at: Vector3) -> void:
	if server:
		for id in peers:
			if id!=1 and can_send(id): _blast_fx.rpc_id(id,at)
@rpc("authority","call_remote","reliable",0)
func _blast_fx(at: Vector3) -> void:
	game.effects.burst(at)
	game.world_sound("blast",at,-8)
func _progress_packet(progress: RefCounted) -> Dictionary:
	progress.finish_chain(game.clock)
	return {"xp":progress.xp_for("YOU"),"awards":progress.awards}
func leave() -> void:
	if not running or closing: return
	closing = true
	status = "Saving progress and disconnecting…"
	if server:
		for id in peers:
			var data = _progress_packet(peers[id].progress)
			if id!=1 and can_send(id): _final_progress.rpc_id(id,data,"The host ended the session.")
		await get_tree().create_timer(.2).timeout
		stop()
	else:
		_leave.rpc_id(1)
		await get_tree().create_timer(1.0).timeout
		if running: fail("Disconnected. Last confirmed XP saved.")
@rpc("any_peer","call_remote","reliable",0)
func _leave() -> void:
	if not server: return
	var id = multiplayer.get_remote_sender_id()
	if peers.has(id) and can_send(id):
		_final_progress.rpc_id(id,_progress_packet(peers[id].progress),"Disconnected. Progress saved.")
		peers[id].leaving = true
@rpc("authority","call_remote","reliable",0)
func _final_progress(data: Dictionary, message: String) -> void:
	game.progression.profiles["YOU"] = data.xp
	game.progression.awards = data.awards
	fail(message)
func fail(message: String) -> void:
	status = message
	stop()
func stop() -> void:
	game.replays.reset()
	replay_wait.clear()
	final_replay_until=0
	destroy.reset_view()
	game.radar.clear()
	lag_comp.clear()
	game.save_profile()
	running = false
	session_ready = false
	closing = false
	if multiplayer.multiplayer_peer: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for slot in slots:
		if slot.has("actor"): _remove_actor(slot.index)
	for actor in proxies.values():
		if is_instance_valid(actor): actor.queue_free()
	slots.clear()
	peers.clear()
	pending.clear()
	proxies.clear()
	grenade_views.clear()
	smoke_seen.clear()
	inputs.clear()
	actions.clear()
	own_slot = -1
	spawned_life = -1
	sequence = 0
	action_id = 0
	pending_reconciliation = []
	snapshot_arrival = 0
	presentation_ready = false
	tick_count = 0
	tick_window = 0
	predicted_grenades.clear()
	packet_parts.clear()
	applied_packet = 0
	packet_serial = 0
	server = false
	round_active = true
	loading_round = false
	game._clear_effects()
	game.combat.stop()
	game.player.life_id = 1
	game.player.net_slot = -1
	game.player.peer_id = 0
	game.player.target_name = "YOU"
	game.player.team = 1
	game.player.set_physics_process(true)
	game.player.reset_at(game.launch_pad)
	game.mode = "training"
	game.has_started = false
	game.set_active(false)

# Match rules are host-owned. One vote per connected human; a new vote replaces it.
const KILL_LIMIT = 250
const TIME_LIMIT = 600.0
const VOTE_TIME = 15.0
var round_active = true
var round_end = 600.0
var vote_end = 0.0
var votes: Dictionary = {}
var vote_counts = [0,0,0,0]
var winner = ""
var round_number = 1
var loading_round = false
func round_info(team: int = 0) -> Dictionary:
	return {"final_until":final_replay_until,"mode":mode_id,"objective":destroy.packet(team if team>0 else game.player.team) if is_destroy() else {},"active":round_active,"end":round_end,"vote_end":vote_end,"counts":vote_counts,"winner":winner,"round":round_number,"loading":loading_round}
func _check_round() -> void:
	if not session_ready or loading_round: return
	if round_active:
		if is_destroy(): return
		if game.combat.scores[1]>=KILL_LIMIT or game.combat.scores[2]>=KILL_LIMIT or game.clock>=round_end: _end_round()
	elif game.clock>=vote_end:
		_next_round.call_deferred()
		loading_round = true
func _end_round() -> void:
	if not round_active: return
	round_active = false
	var replay_delay = schedule_final_replay()
	winner = "DRAW" if game.combat.scores[1]==game.combat.scores[2] else ("BLUE TEAM WINS" if game.combat.scores[1]>game.combat.scores[2] else "RED TEAM WINS")
	votes.clear()
	vote_counts = [0,0,0,0]
	vote_end = game.clock+VOTE_TIME+replay_delay
	for id in peers:
		var p = peers[id]
		p.progress.finish_chain(game.clock)
		var team = slots[p.slot].team
		if game.combat.scores[team]>game.combat.scores[3-team]: game.challenge_event(slots[p.slot].actor,"wins")
	_round_notice(round_info())
	for id in peers:
		if id!=1 and can_send(id): _round_notice.rpc_id(id,round_info(slots[peers[id].slot].team))
	print("ROUND_END ",winner," score=",game.combat.scores," vote_seconds=",VOTE_TIME)
@rpc("authority","call_remote","reliable",0)
func _round_notice(info: Dictionary) -> void:
	final_replay_until = info.get("final_until",0.0)
	if not server and info.has("objective"): destroy.remote = info.objective
	round_active = info.active
	round_end = info.end
	vote_end = info.vote_end
	vote_counts = info.counts
	winner = info.winner
	round_number = info.round
	loading_round = info.loading
	if not round_active and not game.replays.active and game.clock>=final_replay_until: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
func vote(map_index: int) -> void:
	if not running or round_active or loading_round or game.clock<final_replay_until or map_index<0 or map_index>3: return
	if server: _set_vote(1,map_index)
	else: _vote.rpc_id(1,map_index)
@rpc("any_peer","call_remote","reliable",0)
func _vote(map_index: int) -> void:
	if server: _set_vote(multiplayer.get_remote_sender_id(),map_index)
func _set_vote(id: int, map_index: int) -> void:
	if not peers.has(id) or round_active or loading_round or game.clock<final_replay_until or map_index<0 or map_index>3: return
	votes[id] = map_index
	vote_counts = [0,0,0,0]
	for index in votes.values(): vote_counts[index] += 1
func chosen_map() -> int:
	var highest = vote_counts.max()
	for offset in range(1,5):
		var index = (game.current_map+offset)%4
		if vote_counts[index]==highest: return index
	return (game.current_map+1)%4
func _next_round() -> void:
	if not running or not server or closing: return
	lag_comp.clear()
	var map_index = chosen_map()
	session_ready = false
	round_number += 1
	for id in peers:
		peers[id].loaded = id==1
		peers[id].commands.clear()
		if id!=1 and can_send(id): _change_map.rpc_id(id,map_index,round_number)
	for slot in slots:
		if slot.peer==0: slot.actor = null
	await game.start_mode("online",map_index)
	game.combat.build_navigation()
	game.combat.scores = [0,0,0]
	for slot in slots:
		slot.kills = 0
		slot.deaths = 0
		if slot.peer==0: _add_bot(slot.index)
		else:
			slot.actor.life_id += 1
			slot.actor.reset_at(game.combat.choose_spawn(slot.team,slot.actor))
	for id in peers:
		if id!=1 and peers[id].get("loaded",false):
			var actor = slots[peers[id].slot].actor
			_spawn.rpc_id(id,actor.position,actor.life_id,-1,actor.health)
	session_ready = true
	loading_round = false
	round_active = true
	round_end = game.clock+TIME_LIMIT
	winner = ""
	if not game.menu_open: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_destroy(): destroy.start_match()
	print("ROUND_START number=",round_number," map=",map_index," actors=",actors().size())
@rpc("authority","call_remote","reliable",0)
func _change_map(map_index: int, number: int) -> void:
	if server: return
	presentation_ready = false
	pending_reconciliation = []
	session_ready = false
	connect_started = Time.get_ticks_msec()
	loading_round = true
	round_active = false
	round_number = number
	for proxy in proxies.values():
		if is_instance_valid(proxy): proxy.queue_free()
	proxies.clear()
	grenade_views.clear()
	smoke_seen.clear()
	await game.start_mode("online",map_index)
	_map_loaded.rpc_id(1,number)
@rpc("any_peer","call_remote","reliable",0)
func _map_loaded(number: int) -> void:
	if not server or number!=round_number: return
	var id = multiplayer.get_remote_sender_id()
	if not peers.has(id): return
	peers[id].loaded = true
	if session_ready:
		var actor = slots[peers[id].slot].actor
		_spawn.rpc_id(id,actor.position,actor.life_id,-1,actor.health)

@rpc("authority","call_remote","unreliable",1)
func _state_chunk(number: int, index: int, count: int, bytes: PackedByteArray) -> void:
	if server or not session_ready or number<=applied_packet or count<1 or count>16 or index<0 or index>=count or bytes.size()>1050: return
	if not packet_parts.has(number): packet_parts[number] = {}
	packet_parts[number][index] = bytes
	if packet_parts[number].size()==count:
		var payload = PackedByteArray()
		for part in range(count): payload.append_array(packet_parts[number][part])
		var decoded = bytes_to_var(payload.decompress_dynamic(65536,FileAccess.COMPRESSION_DEFLATE))
		if decoded is Array and decoded.size()==7:
			applied_packet = number
			_snapshot.callv(decoded)
	for key in packet_parts.keys():
		if key<=applied_packet or key<number-4: packet_parts.erase(key)

func _balance_humans() -> void:
	if loading_round or not server or (is_destroy() and destroy.phase!="reset"): return
	while true:
		var counts = [0,0,0]
		for peer_id in peers:
			if can_send(peer_id): counts[slots[peers[peer_id].slot].team] += 1
		if absi(counts[1]-counts[2])<=1: return
		var source_team = 1 if counts[1]>counts[2] else 2
		var from = -1
		var to = -1
		var reserved: Array = []
		for entry in pending.values():
			if entry.get("authenticated",false): reserved.append(entry.slot)
		for slot in slots:
			if slot.team==source_team and slot.peer>0 and can_send(slot.peer): from = slot.index
			elif slot.team!=source_team and slot.peer==0 and slot.index not in reserved: to = slot.index
		if from<0 or to<0: return
		var old = slots[from].duplicate()
		var id = old.peer
		var actor = old.actor
		_remove_actor(to)
		slots[to].merge({"peer":id,"actor":actor,"name":old.name,"kills":old.kills,"deaths":old.deaths,"xp":old.xp},true)
		slots[from].actor = null
		_add_bot(from)
		peers[id].slot = to
		peers[id].commands.clear()
		actor.net_slot = to
		actor.team = slots[to].team
		actor.target_name = "S%d" % to
		actor.life_id += 1
		actor.reset_at(game.combat.choose_spawn(actor.team,actor))
		if id!=1:
			actor.viewmodel.root.queue_free()
			actor.viewmodel.title.queue_free()
			actor.viewmodel.queue_free()
			actor.viewmodel = Player.RemoteView.new()
			actor.viewmodel.player = actor
			actor.add_child(actor.viewmodel)
		if id==1:
			own_slot = to
			game.notify("TEAMS BALANCED","You moved to "+("BLUE" if actor.team==1 else "RED")+". XP and K/D are unchanged.")
		elif can_send(id): _assigned.rpc_id(id,to,actor.position,actor.life_id)
		print("TEAM_BALANCE peer=",id," from=",from," to=",to)
@rpc("authority","call_remote","reliable",0)
func _assigned(slot: int, at: Vector3, life: int) -> void:
	own_slot = slot
	game.player.net_slot = slot
	if proxies.has(slot):
		proxies[slot].queue_free()
		proxies.erase(slot)
	_spawn(at,life)
	game.notify("TEAMS BALANCED","You moved to "+("BLUE" if slot<5 else "RED")+". XP and K/D are unchanged.")

func audio_fx(slot: int, key: String, at: Vector3, volume: float) -> void:
	if not server: return
	for id in peers:
		if id!=1 and can_send(id): _audio_fx.rpc_id(id,slot,key,at,volume)
@rpc("authority","call_remote","unreliable",2)
func _audio_fx(slot: int, key: String, at: Vector3, volume: float) -> void:
	if slot!=own_slot: game.world_sound(key,at,volume,false)

func can_send(id: int) -> bool:
	if id==1: return server
	var data = peers.get(id,pending.get(id,{}))
	if data.get("leaving",false): return false
	var transport = data.get("transport")
	return transport!=null and transport.is_active() and transport.get_state()==ENetPacketPeer.STATE_CONNECTED and transport.get_channels()>0

func bounded_shot_time(peer: Dictionary, requested: float) -> float:
	var transport = peer.get("transport")
	var rtt = transport.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)/1000.0 if transport!=null and transport.is_active() else 0.0
	# RTT covers the outbound snapshot and inbound shot. Allow the render buffer
	# and a small jitter margin, with an absolute half-second ceiling.
	var allowance = minf(LagCompensation.MAX_REWIND,rtt+.18)
	return clampf(requested,game.clock-allowance,game.clock)

@rpc("authority","call_remote","reliable",0)
func _challenge(kind: String, data: Dictionary = {}) -> void:
	if kind in ["parries","boosts","wins","death"]: game.accept_challenge(kind,data)

@rpc("any_peer","call_remote","reliable",0)
func _cosmetic_request(loadout: Dictionary) -> void:
	if not server: return
	var id = multiplayer.get_remote_sender_id()
	if not peers.has(id) or loadout.size()>5: return
	var p = peers[id]
	if p.budget<5: return
	p.budget -= 5
	var clean = preload("res://scripts/cosmetics.gd").clean_loadout(loadout)
	var actor = slots[p.slot].actor
	if actor.cosmetics==clean: return
	actor.cosmetics = clean
	actor.viewmodel.apply_cosmetics()

func capture_life(slot: int) -> Dictionary:
	var a = slots[slot].actor
	var human = slots[slot].peer>0
	var inventory = a.get_meta("replacement_inventory",{"ammo":[24,7,0,6],"blast":1,"smoke":1}).duplicate(true)
	if human:
		inventory = {"ammo":a.ammo.duplicate(),"blast":a.blast_count,"smoke":a.smoke_count}
	else: inventory.ammo[0] = a.rounds
	return {"class_id":a.class_id if human else "vanguard","health":a.health,"position":a.position,"rotation":a.rotation,"life":a.life_id,"human":human,"inventory":inventory,"weapon":a.weapon if human else 0,"reload":a.reload_timer if human else a.reload_time,"cooldown":a.fire_cooldown if human else a.shot_timer}
func restore_life(slot: int, data: Dictionary) -> void:
	if data.is_empty(): return
	var a = slots[slot].actor
	a.health = data.health
	a.position = data.position
	a.rotation = data.rotation
	if (slots[slot].peer>0)!=data.human: a.rotation.y += PI
	a.life_id = maxi(a.life_id,data.life+1)
	if slots[slot].peer>0:
		a.set_class(data.get("class_id","vanguard"))
		a.ammo = data.inventory.ammo.duplicate()
		a.blast_count = data.inventory.blast
		a.smoke_count = data.inventory.smoke
		a.weapon = data.weapon
		a.reload_timer = data.reload
		a.fire_cooldown = data.cooldown
	else:
		a.rounds = data.inventory.ammo[0]
		a.reload_time = 1.8 if a.rounds<=0 else (data.reload if data.weapon==0 else 0.0)
		a.set_meta("replacement_inventory",data.inventory.duplicate(true))
	if a.health<=0:
		a.collision_layer = 0
		for area in a.hitboxes: area.collision_layer = 0
		if slots[slot].peer==0: a.hide()
@rpc("any_peer","call_remote","unreliable_ordered",1)
func _objective_hold(life: int, wanted: bool) -> void:
	if not server or not is_destroy(): return
	var id = multiplayer.get_remote_sender_id()
	if peers.has(id) and peers[id].loaded: destroy.receive_hold(peers[id].slot,life,wanted)
@rpc("any_peer","call_remote","reliable",0)
func _drop_bomb(life: int) -> void:
	if not server or not is_destroy(): return
	var id = multiplayer.get_remote_sender_id()
	if peers.has(id):
		var a = slots[peers[id].slot].actor
		if a.life_id==life and a.health>0: destroy.drop(a.net_slot)
@rpc("authority","call_remote","reliable",0)
func _objective_explosion(at: Vector3) -> void:
	game.effects.burst(at)
	for offset in [Vector3(2,1,0),Vector3(-2,2,1),Vector3(0,4,-1)]: game.effects.burst(at+offset)
	game.world_sound("blast",at,0,false)
	game.player.hurt_flash = .9*clampf(1-game.player.position.distance_to(at)/45.0,0,1)

func deliver_death_replay(clip: Dictionary) -> void:
	if not server: return
	var v = int(clip.victim)
	if v<0 or v>=slots.size() or slots[v].peer<=0: return
	var actor=slots[v].actor
	var id=slots[v].peer
	if actor.life_id!=clip.victim_life or actor.health>0 or not peers[id].killcams: return
	var packed=game.replays.History.encode(clip)
	if packed.is_empty(): return
	if not is_destroy(): replay_wait[id]={"life":actor.life_id,"until":game.clock+game.replays.DEATH_TIMEOUT}
	if id==1: game.replays.play(clip,false)
	elif can_send(id): _replay_clip.rpc_id(id,packed,false,round_number,actor.life_id)
func schedule_final_replay() -> float:
	if not server or not game.replays.has_final(): return 0.0
	final_replay_until=game.clock+game.replays.FINAL_LOCK
	_broadcast_final_replay.call_deferred()
	return game.replays.FINAL_LOCK
func _broadcast_final_replay() -> void:
	if not running or not server: return
	game.replays.flush()
	var clip=game.replays.history.last_clip
	if clip.is_empty(): return
	clip["result_title"] = destroy.reason if is_destroy() else winner
	clip["result_team"] = destroy.last_winner if is_destroy() else (0 if game.combat.scores[1]==game.combat.scores[2] else (1 if game.combat.scores[1]>game.combat.scores[2] else 2))
	clip["result_match"] = not round_active
	var packed=game.replays.History.encode(clip)
	if packed.is_empty(): return
	if not dedicated: game.replays.present_final(clip,clip.result_title)
	for id in peers:
		if id!=1 and can_send(id) and peers[id].loaded: _replay_clip.rpc_id(id,packed,true,round_number,slots[peers[id].slot].actor.life_id)
@rpc("authority","call_remote","reliable",2)
func _replay_clip(packed: PackedByteArray, mandatory: bool, generation: int, viewer_life: int) -> void:
	if server or not running or not session_ready or generation!=round_number or viewer_life!=game.player.life_id: return
	var clip=game.replays.History.decode(packed)
	if clip.is_empty() or clip.map!=game.current_map: return
	if not mandatory:
		if clip.victim!=str(own_slot) or clip.victim_life!=game.player.life_id: return
		if not game.prefs.data.killcams: finish_death_replay(); return
		game.player.health=0; game.player.collision_layer=0
		for area in game.player.hitboxes: area.collision_layer=0
		pending_reconciliation.clear(); inputs.clear(); actions.clear()
	if mandatory: game.replays.present_final(clip,clip.get("result_title","ROUND COMPLETE"))
	else: game.replays.play(clip,false)
func finish_death_replay() -> void:
	if not running: return
	if server: _complete_replay(1,game.player.life_id)
	else: _replay_done.rpc_id(1,game.player.life_id)
func _complete_replay(id: int, life: int) -> void:
	if not server or not peers.has(id) or not replay_wait.has(id): return
	var actor=slots[peers[id].slot].actor
	if actor.life_id!=life or replay_wait[id].life!=life or not combat_allowed() or is_destroy(): return
	replay_wait.erase(id)
	_respawn_human(actor)
@rpc("any_peer","call_remote","reliable",0)
func _replay_done(life: int) -> void:
	_complete_replay(multiplayer.get_remote_sender_id(),life)
@rpc("any_peer","call_remote","reliable",0)
func _replay_settings(enabled: bool) -> void:
	if not server: return
	var id=multiplayer.get_remote_sender_id()
	if peers.has(id): peers[id].killcams=enabled

func select_class(id: String) -> void:
	if not running: return
	if server: _queue_class(1,id)
	else: _class_request.rpc_id(1,id)
func _queue_class(peer_id: int, id: String) -> void:
	if not server or not peers.has(peer_id): return
	var peer=peers[peer_id]
	if preload("res://scripts/loadouts.gd").allowed(id,peer.progress.xp_for("YOU"))==id:
		peer.selected_class=id
@rpc("any_peer","call_remote","reliable",0)
func _class_request(id: String) -> void:
	_queue_class(multiplayer.get_remote_sender_id(),id)
