extends RefCounted
## All objective decisions run on the host. Clients receive presentation state only.
const ROUND_SECONDS = 120.0
const BOMB_SECONDS = 60.0
const PLANT_SECONDS = 4.0
const DEFUSE_SECONDS = 8.0
const INTERMISSION = 6.0
const WINS = 6
const SITES = [Vector3(-21,.05,-9),Vector3(21,.05,-9)]
var net: Node
var phase = "live"
var round_index = 1
var attackers = 1
var carrier = -1
var dropped = Vector3.ZERO
var planted = Vector3.ZERO
var site = -1
var deadline = 0.0
var next_round_at = 0.0
var reason = ""
var last_winner = 0
var holds: Dictionary = {}
var worker = -1
var work = 0.0
var work_origin = Vector3.ZERO
var plan_site = 0
var assigned_defuser = -1
var retriever_slot = -1
var pickup_lock_slot = -1
var pickup_lock_until = 0.0
var alive = [0,5,5]
var remote: Dictionary = {}
var pulse = 0.0
var send_timer = 0.0
var bomb_visual: Node3D
var spectator: Camera3D
var watching = -1
var spectating_name = ""
var last_beep = -999.0
var last_phase = ""

func setup(network: Node) -> void:
	net = network
func start_match() -> void:
	round_index = 1
	attackers = 1
	net.game.combat.scores = [0,0,0]
	start_round()
func start_round() -> void:
	if not net.running or not net.server: return
	net.game.replays.reset()
	net.replay_wait.clear()
	net.final_replay_until=0
	phase = "reset"
	net._balance_humans()
	attackers = 1 if round_index<=5 else 2
	net.game._clear_effects()
	net.game.radar.clear()
	net.lag_comp.clear()
	holds.clear()
	pickup_lock_slot = -1
	worker = -1
	work = 0
	site = -1
	reason = ""
	assigned_defuser = -1
	retriever_slot = -1
	plan_site = (round_index+net.game.current_map)%2
	for row in net.slots:
		var actor = row.actor
		if row.peer==0:
			actor.reset()
		else:
			actor.life_id += 1
			actor.reset_at(spawn_for(actor.team,actor.net_slot))
			actor.rotation.y = 0 if actor.team==attackers else PI
			var peer = net.peers[row.peer]
			peer.frames.clear()
			peer.commands.clear()
			peer.move_credit = 0
			if row.peer!=1 and net.can_send(row.peer) and peer.loaded:
				net._spawn.rpc_id(row.peer,actor.position,actor.life_id)
		actor.velocity = Vector3.ZERO
	carrier = -1
	# Rotate responsibility through the attacking squad, including human players.
	var candidates: Array = []
	for row in net.slots:
		if row.team==attackers: candidates.append(row.index)
	if not candidates.is_empty(): carrier = candidates[(round_index-1)%candidates.size()]
	dropped = spawn_for(attackers,carrier)
	phase = "live"
	deadline = net.game.clock+ROUND_SECONDS
	net.round_end = deadline
	alive = [0,5,5]
	last_phase = ""
	print("DESTROY_ROUND index=",round_index," attackers=",attackers," carrier=",carrier)
func spawn_for(team: int, slot: int) -> Vector3:
	return Vector3((posmod(slot,5)-2)*2.4,.08,25 if team==attackers else -25)
func fighting() -> bool:
	return phase in ["live","planted"] and net.round_active
func holding(slot: int) -> bool:
	return worker==slot and work>0
func receive_hold(slot: int, life: int, wanted: bool) -> void:
	if not net.server or not fighting() or slot<0 or slot>=net.slots.size(): return
	var actor = net.slots[slot].actor
	if actor.life_id!=life or actor.health<=0: return
	if wanted: holds[slot] = net.game.clock+.35
	else:
		holds.erase(slot)
		if worker==slot: cancel_work()
func cancel_work() -> void:
	worker = -1
	work = 0
func clear_slot(slot: int) -> void:
	holds.erase(slot)
	if worker==slot: cancel_work()
func drop(slot: int) -> void:
	if phase!="live" or carrier!=slot: return
	var actor = net.slots[slot].actor
	dropped = safe_drop(actor.global_position)
	carrier = -1
	retriever_slot = -1
	pickup_lock_slot = slot
	pickup_lock_until = net.game.clock+1.25
	clear_slot(slot)
func safe_drop(at: Vector3) -> Vector3:
	# Project onto navigable ground: roofs, out-of-bounds deaths and stair drops
	# must never strand the only bomb somewhere that bots cannot recover it.
	var nav = net.game.combat.navigation
	if nav.get_point_count()==0: return spawn_for(attackers,0)
	var id = nav.get_closest_point(Vector3(clampf(at.x,-28,28),.05,clampf(at.z,-27,27)))
	return nav.get_point_position(id)
func actor_for(slot: int) -> Node:
	return net.slots[slot].actor if slot>=0 and slot<net.slots.size() else null
func reachable(actor: Node, at: Vector3, radius: float) -> bool:
	if actor.global_position.distance_to(at)>radius or absf(actor.global_position.y-at.y)>.65: return false
	var query = PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.8,at+Vector3.UP*.3,1)
	return net.game.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
func valid_work(actor: Node) -> bool:
	if actor.health<=0 or not actor.is_on_floor() or actor.velocity.length()>1.0: return false
	if actor.peer_id>0 and (actor.reload_timer>0 or actor.fire_cooldown>.01 or not actor.held_grenade.is_empty()): return false
	if phase=="live":
		return actor.net_slot==carrier and actor.team==attackers and site_at(actor)>=0
	return phase=="planted" and actor.team!=attackers and reachable(actor,planted,1.9)
func site_at(actor: Node) -> int:
	for i in range(2):
		if reachable(actor,SITES[i],2.8): return i
	return -1
func tick(delta: float) -> void:
	if not net.server or not net.session_ready: return
	if phase=="intermission":
		if net.game.clock>=next_round_at:
			round_index += 1
			start_round()
		return
	if not fighting(): return
	alive = [0,0,0]
	for row in net.slots:
		if row.actor.health>0: alive[row.team] += 1
	if carrier>=0 and actor_for(carrier).health<=0: drop(carrier)
	# Deadline wins ties. Defuse completion at/after detonation is too late.
	if net.game.clock>=deadline:
		if phase=="planted": detonate()
		else: finish(3-attackers,"TIME EXPIRED")
		return
	if alive[3-attackers]==0:
		finish(attackers,"DEFENDERS ELIMINATED")
		return
	if phase=="live" and alive[attackers]==0:
		finish(3-attackers,"ATTACKERS ELIMINATED")
		return
	if phase=="live" and carrier<0:
		for row in net.slots:
			if row.index==pickup_lock_slot and net.game.clock<pickup_lock_until: continue
			if row.team==attackers and row.actor.health>0 and reachable(row.actor,dropped,1.5):
				carrier = row.index
				break
	# Only one action can own the bomb at a time. Work never transfers players.
	var requested: Array = []
	for row in net.slots:
		var actor = row.actor
		var wants = holds.get(row.index,-1.0)>net.game.clock
		if row.peer==0: wants = bot_wants(actor)
		elif row.peer==1: wants = actor.held("interact")
		if wants and valid_work(actor): requested.append(row.index)
	if worker>=0 and (worker not in requested or actor_for(worker).position.distance_to(work_origin)>.2): cancel_work()
	if worker<0 and not requested.is_empty():
		worker = requested[0]
		work_origin = actor_for(worker).position
	if worker>=0:
		work += delta
		if phase=="live" and work>=PLANT_SECONDS:
			site = site_at(actor_for(worker))
			planted = actor_for(worker).position
			carrier = -1
			phase = "planted"
			deadline = net.game.clock+BOMB_SECONDS
			net.round_end = deadline
			cancel_work()
		elif phase=="planted" and work>=DEFUSE_SECONDS:
			finish(3-attackers,"BOMB DEFUSED")
func finish(team: int, message: String) -> void:
	if not fighting(): return
	last_winner = team
	reason = message
	alive = [0,0,0]
	for row in net.slots:
		if row.actor.health>0: alive[row.team] += 1
	phase = "intermission"
	cancel_work()
	holds.clear()
	net.game.combat.scores[team] += 1
	for peer in net.peers.values(): peer.progress.finish_chain(net.game.clock)
	if net.game.combat.scores[team]>=WINS:
		phase = "match_over"
		net._end_round()
	else:
		next_round_at = net.game.clock+INTERMISSION+net.schedule_final_replay()
	print("DESTROY_RESULT round=",round_index," team=",team," reason=",reason)
func detonate() -> void:
	net._objective_explosion(planted)
	for id in net.peers:
		if id!=1 and net.can_send(id): net._objective_explosion.rpc_id(id,planted)
	# Blast kills nearby survivors, independently of friendly-fire rules.
	for row in net.slots:
		var actor = row.actor
		if actor.health>0 and actor.position.distance_to(planted)<24:
			actor.take_damage(1000,3-actor.team)
			row.deaths += 1
	finish(attackers,"BOMB DETONATED")
func bot_wants(bot: Node) -> bool:
	if not valid_work(bot): return false
	if phase=="live": return bot.net_slot==carrier
	return bot.net_slot==defuser()
func defuser() -> int:
	if phase!="planted": return -1
	if worker>=0 and actor_for(worker).team!=attackers: return worker
	var assigned = actor_for(assigned_defuser)
	if is_instance_valid(assigned) and assigned.health>0 and assigned.peer_id==0 and assigned.team!=attackers: return assigned_defuser
	var best = -1
	var distance = INF
	for row in net.slots:
		if row.peer!=0 or row.team==attackers or row.actor.health<=0: continue
		var d = row.actor.position.distance_to(planted)
		if d<distance: best = row.index; distance = d
	assigned_defuser = best
	return best
func bot_goal(bot: Node) -> Vector3:
	if phase=="planted":
		if bot.team!=attackers and bot.net_slot==defuser(): return planted
		return planted+Vector3(4 if posmod(bot.net_slot,2)==0 else -4,0,4 if bot.team==attackers else -4)
	if bot.team==attackers:
		if carrier<0: return dropped if nearest_retriever()==bot.net_slot else dropped+Vector3(3,0,3)
		if bot.net_slot==carrier: return SITES[plan_site]
		var carrier_actor = actor_for(carrier)
		var target_site = plan_site if carrier_actor.peer_id==0 else (0 if carrier_actor.position.distance_to(SITES[0])<carrier_actor.position.distance_to(SITES[1]) else 1)
		return SITES[target_site]+Vector3((posmod(bot.net_slot,3)-1)*4,0,4)
	return SITES[posmod(bot.net_slot,2)]+Vector3((posmod(bot.net_slot,3)-1)*3.5,0,-4)
func nearest_retriever() -> int:
	var assigned = actor_for(retriever_slot)
	if is_instance_valid(assigned) and assigned.health>0 and assigned.peer_id==0 and assigned.team==attackers: return retriever_slot
	var best = -1
	var distance = INF
	for row in net.slots:
		if row.peer!=0 or row.team!=attackers or row.actor.health<=0: continue
		var d = row.actor.position.distance_to(dropped)
		if d<distance: distance = d; best = row.index
	return best
func bot_priority(bot: Node) -> bool:
	return (phase=="planted" and bot.net_slot==defuser()) or (phase=="live" and bot.net_slot==carrier)
func packet(team: int) -> Dictionary:
	var own_worker = worker if worker>=0 and actor_for(worker).team==team else -1
	return {"phase":phase,"round":round_index,"attackers":attackers,"carrier":carrier if team==attackers else -1,"dropped":dropped if team==attackers else Vector3.ZERO,"planted":planted if site>=0 else Vector3.ZERO,"site":site,"deadline":deadline,"next":next_round_at,"reason":reason,"worker":own_worker,"work":work if own_worker>=0 else 0.0,"alive":alive}
func state() -> Dictionary:
	return packet(net.game.player.team) if net.server else remote
func view_tick(delta: float) -> void:
	var game = net.game
	if not net.running or net.mode_id!="destroy" or not net.session_ready:
		if is_instance_valid(spectator) or is_instance_valid(bomb_visual) or not remote.is_empty(): reset_view()
		return
	var info = state()
	if info.is_empty(): return
	if not net.server:
		send_timer -= delta
		if send_timer<=0:
			send_timer = .1
			net._objective_hold.rpc_id(1,game.player.life_id,game.player.held("interact"))
	if info.phase!=last_phase:
		last_phase = info.phase
		if info.phase=="planted": game.sound("achievement",-16)
	if info.phase=="planted" and game.clock-last_beep>clampf((info.deadline-game.clock)/60.0,.16,1):
		last_beep = game.clock
		game.world_sound("tick",info.planted,-12,false)
	if not is_instance_valid(bomb_visual):
		bomb_visual = Node3D.new()
		game.world_root.add_child(bomb_visual)
		game.Geo.box(bomb_visual,Vector3(0,.12,0),Vector3(.5,.24,.32),Color("2b353b"),false,"metal")
		game.Geo.box(bomb_visual,Vector3(0,.245,0),Vector3(.2,.02,.12),Color("ef7757"))
		for x in [-.17,.17]: game.Geo.box(bomb_visual,Vector3(x,.25,0),Vector3(.06,.04,.34),Color("deb25d"))
	bomb_visual.visible = info.phase=="planted" or (info.phase=="live" and info.attackers==game.player.team and info.carrier<0)
	bomb_visual.position = info.planted if info.phase=="planted" else info.dropped
	_update_spectator()
func _update_spectator() -> void:
	var game = net.game
	if game.player.health>0 or net.dedicated:
		if is_instance_valid(spectator): spectator.queue_free(); spectator = null; game.player.presentation_camera().make_current()
		return
	game.player.viewmodel.root.hide()
	if not is_instance_valid(spectator):
		spectator = Camera3D.new()
		game.add_child(spectator)
		spectator.fov = 86
		spectator.make_current()
	var friends: Array = []
	var actors = net.actors() if net.server else net.proxies.values()
	for actor in actors:
		if actor.team==game.player.team and actor.health>0 and actor.net_slot!=net.own_slot: friends.append(actor)
	friends.sort_custom(func(a,b): return a.net_slot<b.net_slot)
	if friends.is_empty():
		# Fixed team-spawn camera, never an enemy-following spectator.
		spectator.position = Vector3(0,2.2,25 if state().attackers==game.player.team else -25)
		spectator.look_at(Vector3(0,2,0))
		spectating_name = "WAITING FOR NEXT ROUND"
		return
	var index = 0
	for i in range(friends.size()):
		if friends[i].net_slot==watching: index = i
	if not game.menu_open and Input.is_action_just_pressed("spectate_next"): index = (index+1)%friends.size()
	var actor = friends[index]
	watching = actor.net_slot
	var eye = actor.global_position+Vector3.UP*1.6
	var forward = -actor.global_basis.z if net.slots[watching].peer>0 else actor.global_basis.z
	var desired = eye-forward*2.2+Vector3.UP*.5
	var query = PhysicsRayQueryParameters3D.create(eye,desired,1)
	var hit = game.get_world_3d().direct_space_state.intersect_ray(query)
	spectator.position = hit.position+hit.normal*.15 if not hit.is_empty() else desired
	spectator.look_at(eye+forward*8)
	spectating_name = net.slots[watching].name
func reset_view() -> void:
	if is_instance_valid(spectator): spectator.queue_free(); spectator = null
	if is_instance_valid(bomb_visual): bomb_visual.queue_free(); bomb_visual = null
	if is_instance_valid(net.game.player): net.game.player.presentation_camera().make_current()
	remote.clear()
	last_phase = ""
