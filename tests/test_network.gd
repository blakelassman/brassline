extends Node
var game: Node
var checks = 0
var failures: Array[String] = []
var join_port = 27917
var root = "/tmp/brassline_nettest/"
func check(value: bool, title: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ",title)
	if not value: failures.append(title)
func wait_for(condition: Callable, seconds: float = 10.0) -> bool:
	var deadline = Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline: await get_tree().physics_frame
	return condition.call()
func mark(name: String, value: String = "1") -> void:
	var file = FileAccess.open(root+name,FileAccess.WRITE)
	file.store_string(value)
func marked(name: String) -> bool: return FileAccess.file_exists(root+name)
func freeze_bots() -> void:
	for bot in game.combat.bots: bot.set_physics_process(false)
func run(g: Node) -> void:
	game = g
	game.prefs.data.killcams=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--join-port="): join_port = arg.trim_prefix("--join-port=").to_int()
		if arg.begins_with("--coord="): root = arg.trim_prefix("--coord=")+"/"
	await get_tree().physics_frame
	var args = OS.get_cmdline_user_args()
	if "--role=host" in args: await host_test()
	elif "--role=reject" in args: await reject_test()
	else: await client_test()
	print("NET_METRICS snapshots=",game.net.snapshots_received," corrections=",game.net.corrections," largest_snapshot=",game.net.largest_packet)
	print("NETWORK_RESULT ",checks-failures.size(),"/",checks)
	if game.net.running: await game.net.leave()
	await game.quit_game()
func host_test() -> void:
	game.cosmetics.owned.armor_royal = 1
	game.cosmetics.equip_item("armor_royal")
	game.apply_cosmetics()
	check(await game.net.host(27917,"test-only",false),"Host creates real UDP server")
	check(game.net.actors().size()==10 and game.combat.bots.size()==9,"Host fills 1 human / 9 bots")
	mark("host")
	check(await wait_for(func(): return game.net.peers.size()==2),"External process authenticates and replaces a bot")
	freeze_bots()
	var remote_id = 0
	for id in game.net.peers:
		if id!=1: remote_id = id
	if remote_id==0: return
	var p = game.net.peers[remote_id]
	var remote = game.net.slots[p.slot].actor
	check(await wait_for(func(): return remote.cosmetics.get("rifle","")=="rifle_circuit"),"Client equipped finish reaches the actual server actor")
	check(p.slot==5 and remote.team==2 and game.combat.bots.size()==8,"First friend joins opposing team: 1v1 humans, 4v4 bots")
	game.player.set_physics_process(false)
	remote.life_id += 1
	remote.reset_at(Vector3(-5,.05,19))
	game.player.reset_at(Vector3(-5,.05,13))
	game.net._spawn.rpc_id(remote_id,remote.position,remote.life_id)
	mark("move")
	check(await wait_for(func(): return marked("moved")),"Client submits movement input")
	check(remote.position.x>-4.4 and remote.position.x<1,"Host simulates remote movement within speed bounds")
	check(remote.crouched,"Crouch reaches server collider")
	mark("movement_checked")
	check(await wait_for(func(): return marked("release")),"Client releases movement")
	remote.reset_at(Vector3(-5,.05,19))
	game.player.reset_at(Vector3(-5,.05,13))
	remote.life_id += 1
	game.net._spawn.rpc_id(remote_id,remote.position,remote.life_id)
	await get_tree().create_timer(.3).timeout
	mark("shoot")
	check(await wait_for(func(): return game.net.slots[p.slot].kills==1),"Server ray validates remote headshot and records kill")
	check(game.net.slots[0].deaths==1 and game.player.health==100,"Host dies and instantly respawns without shield")
	check(p.progress.xp_for("YOU")==100,"Server awards exactly 100 headshot XP")
	check(remote.ammo[0]==23,"Authoritative rifle magazine consumes one round")
	var pings = game.radar.contacts(game.net.actors(),game.player.team,game.clock)
	check(pings.any(func(dot): return not dot[1]),"A real remote shot reveals the shooter to the opposing minimap")
	mark("shot_checked")
	check(await wait_for(func(): return remote.parry_timer>0),"Client right-click activates an authoritative sword parry")
	check(game.net._row(game.net.slots[p.slot])[10]>0,"Parry pose is included in remote snapshots")
	mark("parry_checked")
	check(await wait_for(func(): return marked("grenade")),"Client performs equip and short toss")
	check(await wait_for(func(): return not game.grenades.is_empty()),"Server owns a thrown grenade")
	check(remote.blast_count==0,"Grenade inventory enforced on server")
	check(await wait_for(func(): return marked("grenade_seen")),"Client receives replicated grenade")
	await get_tree().create_timer(2.0).timeout
	check(game.grenades.is_empty(),"Server grenade fuse resolves")
	# Only the final valid kill is needed to exercise the real 250-kill transition.
	game.combat.scores = [0,0,249]
	remote.reset_at(Vector3(-5,.05,19))
	game.player.reset_at(Vector3(-5,.05,13))
	remote.life_id += 1
	game.net._spawn.rpc_id(remote_id,remote.position,remote.life_id)
	await get_tree().create_timer(.3).timeout
	mark("win_shot")
	check(await wait_for(func(): return not game.net.round_active),"250th kill ends the round immediately")
	check(game.combat.scores[2]==250 and game.net.winner=="RED TEAM WINS","First to 250 wins with no extra score after end")
	await wait_for(func(): return game.clock>=game.net.final_replay_until)
	game.net.vote(1)
	check(await wait_for(func(): return game.net.votes.size()==2),"Map vote crosses real RPC connection")
	check(await wait_for(func(): return game.net.vote_counts[1]==2),"One final vote per player; changed vote replaces previous")
	game.net.vote_end = game.clock+.2
	check(await wait_for(func(): return game.current_map==1 and game.net.round_active,15),"Winning map loads and next round starts")
	freeze_bots()
	check(await wait_for(func(): return marked("map_loaded")),"Client loads the same voted map")
	check(game.net.actors().size()==10 and game.combat.bots.size()==8,"Map change preserves both humans and ten total actors")
	check(game.combat.scores==[0,0,0],"Next round resets team scores")
	check(is_equal_approx(game.net.round_end-game.clock,600.0) or game.net.round_end-game.clock>590,"Each round has a ten-minute maximum")
	game.net.round_end = game.clock+.1
	check(await wait_for(func(): return not game.net.round_active),"Time limit ends round without a kill")
	check(game.net.winner=="DRAW","Equal scores at time limit produce a draw")
	mark("leave")
	check(await wait_for(func(): return game.net.peers.size()==1),"Disconnect removes remote human")
	check(game.net.actors().size()==10 and game.combat.bots.size()==9,"Leaving player is replaced by a bot")
	mark("done")
	check(await wait_for(func(): return marked("rejected")),"Incorrect password rejected without consuming a slot")
	check(game.net.peers.size()<=2,"Rejected connection cannot enter roster")
	check(await wait_for(func(): return marked("rejoined")),"Previously disconnected client rejoins successfully")
	check(await wait_for(func(): return game.net.peers.size()==1),"Rejoined client can leave again")
	await game.net.leave()
	check(await game.net.host(27917,"test-only",false),"Host can start another server without restarting game")
	check(game.combat.scores==[0,0,0] and game.net.round_number==1 and game.net.round_active,"New server starts with fresh scores and match state")
func client_test() -> void:
	check(await wait_for(func(): return marked("host")),"Host available")
	game.prefs.data.name = "Net Tester"
	game.cosmetics.owned.rifle_circuit = 1
	game.cosmetics.equip_item("rifle_circuit")
	game.apply_cosmetics()
	game.net.join("127.0.0.1",join_port,"test-only")
	check(await wait_for(func(): return game.net.is_client_ready()),"Client completes real ENet handshake")
	check(await wait_for(func(): return game.net.snapshots_received>3),"Client receives repeated authoritative snapshots")
	check(await wait_for(func(): return game.net.proxies.has(0) and game.net.proxies[0].cosmetics.get("armor","")=="armor_royal"),"Host outfit appears on the connecting client replica")
	check(game.net.proxies.size()==9,"Nine remote actors are rendered as replicas")
	await wait_for(func(): return marked("move"))
	Input.action_press("right")
	Input.action_press("crouch")
	await get_tree().create_timer(.75).timeout
	mark("moved")
	await wait_for(func(): return marked("movement_checked"))
	Input.action_release("right")
	Input.action_release("crouch")
	mark("release")
	await wait_for(func(): return marked("shoot"))
	game.player.rotation.y = 0
	game.player.pitch = 0
	game.player.camera.rotation.x = 0
	game.player.shoot()
	check(await wait_for(func(): return game.kills==1),"Confirmed kill updates client scoreboard")
	check(game.progression.xp_for("YOU")==100,"Confirmed XP reaches client")
	check(await wait_for(func(): return game.challenges.stats.get("headshots",0)==1),"Only server-confirmed headshot updates client achievements")
	check(game.challenges.unlocked.has("headshots_1"),"Online headshot unlocks the persistent challenge")
	check(await wait_for(func(): return not game.kill_feed.is_empty() and game.kill_feed[0].killer=="YOU" and game.kill_feed[0].head),"Headshot feed identifies local killer")
	await wait_for(func(): return marked("shot_checked"))
	game.player.equip(2)
	await get_tree().create_timer(.35).timeout
	game.player.start_parry()
	check(game.player.parry_timer>0,"Parry pose starts locally before the network reply")
	await wait_for(func(): return marked("parry_checked"))
	game.player.equip(0)
	await get_tree().create_timer(.3).timeout
	game.player.equip_grenade("blast")
	await get_tree().create_timer(.3).timeout
	game.player.throw_grenade("blast",true)
	mark("grenade")
	check(await wait_for(func(): return not game.grenades.is_empty()),"Server projectile appears on client")
	mark("grenade_seen")
	await wait_for(func(): return marked("win_shot"))
	game.player.rotation.y = 0
	game.player.pitch = 0
	game.player.camera.rotation.x = 0
	game.player.shoot()
	check(await wait_for(func(): return not game.net.round_active),"Client receives end-of-round and vote state")
	check(await wait_for(func(): return game.challenges.stats.get("wins",0)==1),"Winning client receives its authoritative victory challenge")
	await wait_for(func(): return game.clock>=game.net.final_replay_until)
	game.net.vote(2)
	game.net.vote(1)
	check(await wait_for(func(): return game.current_map==1 and game.net.is_client_ready(),15),"Client reloads voted arena without reconnecting")
	check(game.progression.xp_for("YOU")>=200,"XP survives map rotation")
	check(game.challenges.streak==0 and game.challenges.stats.get("wins",0)==1,"Map rotation resets life streak while preserving lifetime achievements")
	check(game.player.cosmetics.get("rifle","")=="rifle_circuit","Equipped finish survives map rotation")
	mark("map_loaded")
	await wait_for(func(): return marked("leave"))
	await game.net.leave()
	check(not game.net.running,"Client gracefully disconnects")
	var saved = game.Preferences.new(game.prefs.path)
	saved.load_profile()
	check(saved.data.challenges.stats.get("headshots",0)>=2 and saved.data.cosmetics.equipped.rifle=="rifle_circuit","Confirmed achievements and equipment save on disconnect")
	check(saved.data.xp>=200,"Confirmed multiplayer XP is saved to disk")
	await wait_for(func(): return marked("rejected"))
	game.net.join("127.0.0.1",join_port,"test-only")
	check(await wait_for(func(): return game.net.is_client_ready()),"Reconnect accepts a fresh life ID")
	check(await wait_for(func(): return game.progression.xp_for("YOU")>=200),"Saved XP remains after rejoining")
	mark("rejoined")
func reject_test() -> void:
	await wait_for(func(): return marked("done"),50)
	game.net.join("127.0.0.1",27917,"wrong")
	check(await wait_for(func(): return not game.net.running),"Wrong password is rejected")
	check("Incorrect" in game.net.status,"Useful password error is shown")
	mark("rejected")
