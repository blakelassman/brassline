extends Node
var game: Node
var checks = 0
var failures: Array[String] = []
var root = ""
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func wait_for(condition: Callable, seconds: float = 12) -> bool:
	var until = Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<until: await get_tree().physics_frame
	return condition.call()
func mark(key: String) -> void:
	var f = FileAccess.open(root+key,FileAccess.WRITE)
	f.store_string("1")
func marked(key: String) -> bool: return FileAccess.file_exists(root+key)
func freeze() -> void:
	for actor in game.net.actors(): actor.set_physics_process(false)
func ground(actor: Node, at: Vector3) -> void:
	actor.position = at
	for i in range(10):
		actor.velocity = Vector3.DOWN*6
		actor.move_and_slide()
		if actor.is_on_floor(): break
	actor.velocity = Vector3.ZERO
func advance(seconds: float) -> void:
	var d = game.net.destroy
	for i in range(ceili(seconds*60)):
		game.clock += 1.0/60
		d.tick(1.0/60)
func run(g: Node) -> void:
	game = g
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--coord="): root = arg.trim_prefix("--coord=")+"/"
	var args = OS.get_cmdline_user_args()
	await get_tree().physics_frame
	if "--role=host" in args: await host_test()
	elif "--role=client" in args: await client_test()
	elif "--role=reject" in args: await reject_test()
	else:
		await rules_test()
		if "--autonomous" in args: await autonomous_test()
	print("DESTROY_RESULT_TEST ",checks-failures.size(),"/",checks)
	if game.net.running: await game.net.leave()
	get_tree().quit(0 if failures.is_empty() else 1)
func rules_test() -> void:
	check(await game.net.host(27926,"",false,"destroy"),"Destroy host starts with real objective layout")
	var net = game.net
	var d = net.destroy
	net.set_physics_process(false)
	freeze()
	check(net.actors().size()==10 and game.combat.bots.size()==9,"Ten participants: human plus nine filling bots")
	check(game.world_root.get_meta("destroy") and game.combat.navigation.get_point_count()>300,"Objective geometry has a usable navigation graph")
	check(d.deadline-game.clock>119 and d.carrier==0 and d.attackers==1,"120 second round starts with exactly one bomb on attacking team")
	check(d.packet(2).carrier==-1 and d.packet(2).dropped==Vector3.ZERO,"Defender packets do not reveal the unplanted bomb")
	var bot = net.slots[1].actor
	bot.take_damage(100,2)
	game.player.take_damage(100,2)
	await get_tree().physics_frame
	check(bot.health==0 and game.player.health==0,"Neither humans nor bots respawn mid-round")
	check(d.carrier==-1,"Carrier death drops the only bomb")
	d.start_round(); freeze()
	ground(game.player,d.SITES[0])
	Input.action_press("interact")
	advance(3.9)
	check(d.phase=="live" and d.work>3.8,"Plant requires the full four seconds")
	Input.action_release("interact"); d.tick(.016)
	check(d.work==0 and d.worker==-1,"Releasing interact completely resets plant progress")
	Input.action_press("interact"); advance(4.1)
	Input.action_release("interact")
	check(d.phase=="planted" and d.site==0 and d.carrier==-1,"Human can plant the single bomb at A")
	check(d.deadline-game.clock>59 and d.deadline-game.clock<=60,"Plant starts a separate 60 second bomb timer")
	for row in net.slots:
		if row.team==d.attackers: row.actor.health=0
	d.tick(.016)
	check(d.phase=="planted","Eliminating all attackers after plant does not stop the bomb")
	var defender = net.slots[5].actor
	ground(defender,d.planted)
	advance(7.8)
	check(d.phase=="planted" and d.work>7.7,"Bot defuse requires the full eight seconds")
	defender.position.x += .4; d.tick(.016)
	check(d.work<.1,"Moving during defuse resets progress")
	ground(defender,d.planted); advance(8.1)
	check(d.phase=="intermission" and game.combat.scores[2]==1 and d.reason=="BOMB DEFUSED","Defending bot completes defuse and wins one round")
	advance(6.1); freeze()
	check(d.round_index==2 and d.attackers==1 and net.actors().all(func(a): return a.health==100),"Next round restores all lives and equipment")
	d.deadline=game.clock; d.tick(.016)
	check(game.combat.scores[2]==2 and d.reason=="TIME EXPIRED","Unplanted timeout gives defenders the round")
	advance(6.1); freeze()
	check(d.round_index==3 and d.attackers==2,"Halftime switches roles after round two")
	check(net.slots[0].team==1 and game.combat.scores==[0,0,2],"Halftime preserves team identity and scores")
	# Bot planting on B, then deadline precedence over a nearly completed defuse.
	d.carrier=5; d.plan_site=1
	ground(net.slots[5].actor,d.SITES[1]); advance(4.1)
	check(d.phase=="planted" and d.site==1,"Attacking bot can plant at B")
	ground(game.player,d.planted); Input.action_press("interact")
	d.work=7.99; d.worker=0; d.work_origin=game.player.position
	d.deadline=game.clock; d.tick(.02); Input.action_release("interact")
	check(d.reason=="BOMB DETONATED" and game.player.health==0,"Bomb explodes with lethal radius; deadline wins defuse tie")
	check(not net.round_active and game.combat.scores[2]==3,"First to three immediately ends best-of-five match")
	check(net.vote_end>game.clock,"Match end opens existing map voting")
	var score = game.combat.scores.duplicate(); d.tick(1)
	check(game.combat.scores==score,"Round resolution cannot score twice")
	# Both elimination outcomes and no mid-round refills through actor replacement.
	net.round_active=true; d.start_match(); freeze()
	for row in net.slots:
		if row.team==2: row.actor.health=0
	d.tick(.016)
	check(d.reason=="DEFENDERS ELIMINATED" and game.combat.scores[1]==1,"Defender elimination gives attackers the round")
	d.start_round(); freeze()
	for row in net.slots:
		if row.team==1: row.actor.health=0
	d.tick(.016)
	check(d.reason=="ATTACKERS ELIMINATED" and game.combat.scores[2]==1,"Attacker elimination before planting gives defenders the round")
	d.start_round(); freeze()
	ground(game.player,d.SITES[0]); game.player.position.y=3
	check(not d.valid_work(game.player),"Bomb cannot be planted from a roof above a site")
	d.carrier=0; d.drop(0)
	check(d.dropped.y<1 and game.combat.free_space(d.dropped),"Bomb dropped from height is recoverable by ground bots")

	d.receive_hold(0,game.player.life_id-1,true)
	check(not d.holds.has(0),"Interaction from an obsolete life is rejected")
	game.player.health=38; game.player.ammo[0]=7; game.player.blast_count=0; game.player.smoke_count=0
	var inventory = net.capture_life(0)
	net.restore_life(1,inventory)
	var handback = net.capture_life(1)
	net.restore_life(0,handback)
	check(game.player.health==38 and game.player.ammo[0]==7 and game.player.blast_count==0 and game.player.smoke_count==0,"Human/bot takeover preserves damage, ammunition and spent grenades")
	d.start_round(); freeze()
	check(game.player.health==100 and game.player.blast_count==1 and not net.slots[1].actor.has_meta("replacement_inventory"),"Fresh round clears takeover inventory and restores supplies")
	ground(game.player,d.SITES[0]); d.carrier=0; d.drop(0); d.tick(.016)
	check(d.carrier==-1,"Dropping the bomb does not immediately pick it back up")
	for index in range(4):
		await game.start_mode("online",index)
		# start_mode destroys old bots; reconstruct network roster for each layout.
		for row in net.slots:
			if row.peer==0: net._add_bot(row.index)
		game.combat.build_navigation(); d.start_match(); freeze()
		var paths_ok = true
		for team in [1,2]:
			for slot in range(5):
				var spawn = d.spawn_for(team,slot)
				paths_ok = paths_ok and game.combat.free_space(spawn)
				for site_pos in d.SITES:
					var path = game.combat.path_between(spawn,site_pos)
					paths_ok = paths_ok and path.size()>3 and path[-1].distance_to(site_pos)<1.9
		check(paths_ok,"Map %d: every spawn has navigable paths to both sites" % index)
		check(not game.combat.sight_clear(d.spawn_for(1,2)+Vector3.UP*1.5,d.spawn_for(2,2)+Vector3.UP*1.5),"Map %d: spawns have no direct central shooting lane" % index)
		check(game.world_root.get_meta("upper_routes",[]).size()>=2,"Map %d: two ramp-connected upper floors" % index)
func host_test() -> void:
	check(await game.net.host(27917,"test-only",false,"destroy"),"Online Destroy host starts")
	var n = game.net
	var d = n.destroy
	freeze()
	n.slots[5].actor.take_damage(100,1)
	mark("host")
	check(await wait_for(func(): return n.peers.size()==2),"Real client replaces a bot")
	var id = 0
	for peer in n.peers:
		if peer!=1: id=peer
	if id==0: return
	check(n.peers[id].slot==5 and n.slots[5].actor.health==0,"First friend joins opposite team and inherits dead bot life")
	check(await wait_for(func(): return marked("spectating")),"Remote client enters teammate spectator camera")
	d.start_round(); freeze()
	# Plant on the host, let the remote defender perform actual hold/release RPCs.
	ground(game.player,d.SITES[0]); Input.action_press("interact")
	check(await wait_for(func(): return d.phase=="planted",6),"Host plants using four seconds of held input")
	Input.action_release("interact")
	var actor = n.slots[5].actor
	actor.life_id+=1; actor.reset_at(d.planted+Vector3(1,0,0)); actor.set_physics_process(true)
	n._spawn.rpc_id(id,actor.position,actor.life_id)
	mark("defuse")
	check(await wait_for(func(): return d.worker==5 and d.work>1),"Remote defuse RPC is validated on server")
	mark("release")
	check(await wait_for(func(): return marked("released") and d.worker==-1),"Release packet cancels remote defuse")
	mark("resume")
	check(await wait_for(func(): return d.phase=="intermission",11),"Remote human completes eight-second defuse")
	check(game.combat.scores[2]==1 and d.reason=="BOMB DEFUSED","Both sides use host-owned round scoring")
	mark("defused")
	check(await wait_for(func(): return marked("saw_score")),"Client receives objective result and round score")
	# Finish series and exercise shared map vote/load path.
	d.start_round(); freeze(); game.combat.scores=[0,0,2]; d.finish(2,"BOMB DEFUSED")
	mark("vote")
	n.vote(1)
	check(await wait_for(func(): return n.vote_counts[1]==2),"Destroy mode accepts both map votes")
	n.vote_end=game.clock+.1
	check(await wait_for(func(): return n.round_active and game.current_map==1,18),"Vote starts a new Destroy match on selected map")
	freeze()
	check(await wait_for(func(): return marked("map_loaded")),"Client loads objective version of voted map")
	check(d.round_index==1 and game.combat.scores==[0,0,0] and n.actors().size()==10,"New match resets rounds with 5v5 roster intact")
	mark("leave")
	check(await wait_for(func(): return n.peers.size()==1),"Disconnect restores a filling bot")
	check(await wait_for(func(): return marked("rejected")),"TDM mode selection rejects a Destroy server with clear message")
	mark("done")
func client_test() -> void:
	check(await wait_for(func(): return marked("host")),"Host available")
	game.net.join("127.0.0.1",27917,"test-only","destroy")
	check(await wait_for(func(): return game.net.is_client_ready() and game.net.snapshots_received>3),"Destroy handshake and snapshots succeed")
	check(game.player.team==2 and game.player.health==0,"Late join cannot resurrect an eliminated bot")
	check(await wait_for(func(): return is_instance_valid(game.net.destroy.spectator)),"Dead player gets a spectator camera")
	mark("spectating")
	await wait_for(func(): return marked("defuse"))
	check(await wait_for(func(): return game.player.health>0 and game.player.position.distance_to(game.net.destroy.remote.get("planted",Vector3.ZERO))<1.9),"New round restores remote player and bomb position")
	Input.action_press("interact")
	check(await wait_for(func(): return marked("release")),"Server sees remote interaction")
	Input.action_release("interact"); mark("released")
	await wait_for(func(): return marked("resume")); Input.action_press("interact")
	check(await wait_for(func(): return marked("defused"),12),"Server accepts completed defuse")
	Input.action_release("interact")
	check(await wait_for(func(): return game.combat.scores[2]==1 and game.net.destroy.remote.get("reason","")=="BOMB DEFUSED"),"Client displays defuse result and round score")
	mark("saw_score")
	await wait_for(func(): return marked("vote"))
	await wait_for(func(): return not game.net.round_active)
	game.net.vote(1)
	check(await wait_for(func(): return game.current_map==1 and game.net.round_active and game.net.is_client_ready(),18),"Voted map loads on client")
	check(game.world_root.get_meta("destroy") and game.net.destroy.remote.get("round",0)==1,"Client remains in objective mode across matches")
	mark("map_loaded")
	await wait_for(func(): return marked("leave")); await game.net.leave()
	await wait_for(func(): return marked("done"))
func reject_test() -> void:
	await wait_for(func(): return marked("leave"),55)
	game.net.join("127.0.0.1",27917,"test-only","tdm")
	check(await wait_for(func(): return not game.net.running),"Incorrect game mode is rejected")
	check("Destroy and Diffuse" in game.net.status,"Rejection names the actual server mode")
	mark("rejected")

func autonomous_test() -> void:
	var d = game.net.destroy
	d.start_match(); freeze()
	game.net.set_physics_process(true)
	d.carrier=1; d.plan_site=0
	var carrier_bot = game.net.slots[1].actor
	carrier_bot.set_physics_process(true)
	check(await wait_for(func(): return d.phase=="planted",40),"Autonomous carrier navigates from spawn to A and plants")
	carrier_bot.set_physics_process(false)
	if d.phase!="planted": return
	var defender = game.net.slots[d.defuser()].actor
	defender.set_physics_process(true)
	check(await wait_for(func(): return d.phase=="intermission",40),"Autonomous defender navigates from spawn and resolves bomb")
	print("BOT_RETAKE position=",defender.position," goal=",defender.goal," path=",defender.path_cursor,"/",defender.path.size()," worker=",d.worker," work=",d.work," assigned=",d.assigned_defuser)
	check(d.reason=="BOMB DEFUSED","Autonomous retake ends with a successful bot defuse")
