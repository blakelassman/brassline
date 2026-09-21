extends Node
var game: Node
var checks=0
var failures: Array[String]=[]
var root=""
var join_port=27917
func check(ok: bool, label: String) -> void:
	checks+=1; print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func wait_for(condition: Callable, seconds: float=12) -> bool:
	var until=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<until: await get_tree().physics_frame
	return condition.call()
func mark(key: String) -> void:
	var file=FileAccess.open(root+key,FileAccess.WRITE); file.store_string("1")
func marked(key: String) -> bool: return FileAccess.file_exists(root+key)
func freeze() -> void:
	for actor in game.combat.actors(): actor.set_physics_process(false)
func run(g: Node) -> void:
	game=g
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--coord="): root=arg.trim_prefix("--coord=")+"/"
		if arg.begins_with("--join-port="): join_port=arg.trim_prefix("--join-port=").to_int()
	var args=OS.get_cmdline_user_args()
	await get_tree().physics_frame
	if "--role=host" in args: await host_test()
	elif "--role=client" in args: await client_test()
	else: await unit_test()
	print("KILLCAM_RESULT ",checks-failures.size(),"/",checks)
	if game.net.running: await game.net.leave()
	get_tree().quit(0 if failures.is_empty() else 1)
func seed_history(killer: Node, victim: Node, seconds: float=3.0) -> void:
	var history=game.replays.history
	history.clear()
	for i in range(int(seconds*20)):
		game.clock+=.05
		killer.position.x+=.004
		history.sample(game,.05,true)
func unit_test() -> void:
	await game.start_mode("combat")
	freeze()
	var replay=game.replays
	replay.set_process(false)
	var killer=game.combat.bots[4]
	var victim=game.player
	killer.position=Vector3(-5,.05,13); killer.rotation.y=0
	victim.position=Vector3(-5,.05,19)
	seed_history(killer,victim,4.5)
	check(replay.history.frames.size()<=replay.History.MAX_FRAMES,"Replay history remains bounded")
	var before=victim.position
	Input.action_press("jump")
	victim.take_damage(100,killer.team,killer.target_name)
	game.replays.history.shot(game,killer,killer.position+Vector3.UP*1.38,victim.position+Vector3.UP*1.1,0)
	await get_tree().process_frame
	replay._process(.01)
	check(replay.active,"Holding jump at death does not accidentally skip the replay")
	Input.action_release("jump"); replay._process(.01)
	check(game.get_viewport().disable_3d and game.player.viewmodel.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Hidden live views stop rendering during replay")
	check(replay.active and not replay.final and victim.health==0,"Offline death starts skippable replay without respawning underneath it")
	check(replay.viewport.world_3d!=game.get_world_3d(),"Replay uses its own 3D world")
	check(replay.camera.position.distance_to(killer.position+Vector3.UP*1.38)<.4,"Replay camera starts at killer's recorded first-person eye")
	check(replay.clip.frames.size()<=82 and replay.clip.events.size()==1,"Clip contains bounded pre-roll and the actual lethal shot")
	check(replay.clip.victim_life==victim.life_id,"Clip is tied to the victim's exact life")
	var recorded=replay.clip.duplicate(true)
	var packed=replay.History.encode(recorded)
	var decoded=replay.History.decode(packed)
	check(not decoded.is_empty() and decoded.frames==recorded.frames,"Compressed clip preserves recorded poses")
	check(replay.History.decode(PackedByteArray([1,2,3])).is_empty(),"Malformed clip is rejected")
	killer.position+=Vector3(10,0,0)
	replay.advance(.5)
	check(victim.position==before and killer.position.distance_to(replay.camera.position)>5,"Playing history never teleports live combat actors")
	var ghost_before=replay.ghosts[recorded.killer].root.position
	killer.position+=Vector3(5,0,0)
	replay.advance(0)
	check(replay.ghosts[recorded.killer].root.position==ghost_before,"Replay ghosts do not follow the current live positions")
	var life=victim.life_id
	Input.action_press("jump"); replay._process(.01); Input.action_release("jump")
	check(not replay.active and victim.health==100 and victim.life_id>life,"Jump binding skips death replay and instantly respawns without a shield")
	victim.take_damage(1,killer.team,killer.target_name)
	check(not game.get_viewport().disable_3d and game.player.viewmodel.viewport.render_target_update_mode!=SubViewport.UPDATE_DISABLED,"Skipping restores live world and first-person rendering")
	check(victim.health==99,"Player is vulnerable immediately after skipping")
	check(not replay.play(recorded,false),"Duplicate or old-life death clip cannot restart playback")
	var snapshot=killer.position
	check(replay.play(recorded,true),"A final killcam always starts even for a living player")
	Input.action_press("jump"); replay._process(.01); Input.action_release("jump")
	check(replay.active and replay.final,"Jump cannot skip mandatory final killcam")
	var previous=Engine.time_scale
	replay.cursor=recorded.time-.5
	replay.advance(.2)
	check(is_equal_approx(replay.cursor,recorded.time-.45) and replay.playback_speed==.25,"Final .65 seconds play at quarter speed")
	check(Engine.time_scale==previous and killer.position==snapshot,"Slow motion never changes global simulation speed or actor state")
	replay.cursor=recorded.time; replay.advance(.1)
	check(replay.hit_played and replay.ghosts[recorded.victim].rig.root.rotation.x>0,"Lethal hit confirmation and recorded victim fall play at the finish")
	replay.advance(.71)
	check(not replay.active,"Final killcam finishes automatically after the finishing hit")
	check(replay.fade_alpha()==0,"Final playback never blacks out the screen")
	check(not replay.play(recorded,true),"Duplicate final packet cannot replay the final kill again")
	# Capture at death, before the bot's deferred instant respawn changes position/life.
	replay.reset(); victim.health=100
	killer.reset(); killer.set_physics_process(false)
	seed_history(victim,killer)
	var dead_pos=killer.position
	var dead_life=killer.life_id
	killer.take_damage(100,victim.team)
	replay.note_kill(killer.target_name,"YOU","LONGSHOT",true)
	await get_tree().process_frame
	var terminal=replay.history.last_clip.frames[-1][1]
	var found=false
	for row in terminal:
		if row[0]==killer.target_name: found=row[4]==0 and row[8]==dead_life and row[1]==dead_pos
	check(killer.health==100 and found,"Instant bot respawn cannot corrupt the death pose in a recorded clip")
	check(replay.history.last_clip.head and replay.history.last_clip.weapon=="LONGSHOT","Final clip preserves sniper/headshot metadata")
	# FOV and camera orientation recorded, rather than using the watching player's aim.
	victim.weapon=3; victim.camera.fov=32; victim.pitch=.15; victim.rotation.y=.8
	replay.reset(); seed_history(victim,killer)
	killer.health=0; replay.note_kill(killer.target_name,"YOU","LONGSHOT",true); replay.flush()
	check(replay.play(replay.history.last_clip,true),"Scoped final replay starts")
	check(replay.scoped and is_equal_approx(replay.camera.fov,32) and absf(replay.camera.rotation.x-.15)<.01,"First-person scope FOV and killer pitch are reconstructed")
	replay.reset()
	var moving=recorded.duplicate(true)
	moving.view_lag=.2
	var collateral=""
	for id in moving.roster:
		if id!=moving.killer and id!=moving.victim: collateral=id; break
	for frame in moving.frames:
		for row in frame[1]:
			if row[0]==moving.victim: row[1].x=frame[0]*10
			if row[0]==collateral:
				row[8]=444; row[4]=0 if frame==moving.frames[-1] else 100
	replay.play(moving,true)
	replay.cursor=moving.time-.5; replay.advance(0)
	check(absf(replay.ghosts[moving.victim].root.position.x-(replay.cursor-.2)*10)<.02,"Remote victim poses use the recorded shooter's lag-compensated view")
	replay.cursor=moving.time; replay.advance(.1)
	check(replay.deaths.has(collateral) and replay.ghosts[collateral].rig.root.rotation.x>0,"Collateral victims also fall in the final replay")
	replay.reset()
	check(not replay.active and replay.history.last_clip.is_empty() and replay.ghosts.is_empty(),"Map/session reset releases ghosts and old final-kill state")
	# Short lives and long lives have identical playback windows; finals run longer.
	for short in [false,true]:
		for mandatory in [false,true]:
			replay.reset(); victim.health=0
			var timed=recorded.duplicate(true)
			if short: timed.frames=[timed.frames[-1]]
			timed.events.push_front([timed.time-3.5,timed.killer,Vector3.ZERO,Vector3.ONE,0])
			replay.play(timed,mandatory)
			if not mandatory: check(replay.event_index==1,"Normal replay skips shot audio preceding its three-second window")
			var expected=6.75 if mandatory else 3.65
			replay.advance(expected-.01)
			check(replay.active,"Replay keeps its full duration (short=%s final=%s)" % [short,mandatory])
			replay.advance(.02)
			check(not replay.active,"Replay ends on time (short=%s final=%s)" % [short,mandatory])
	replay.reset(); victim.health=100
	# Finals delay actual objective round progression, even when death cams are off.
	await game.net.host(27926,"",false,"destroy"); freeze()
	var n=game.net
	n.set_physics_process(false)
	victim=game.player; killer=n.slots[5].actor
	seed_history(killer,victim)
	victim.take_damage(100,2,"S5")
	n.record_kill("S0","RIFLE",false,false,1,"S5",2,false)
	n.destroy.finish(2,"ATTACKERS ELIMINATED")
	await get_tree().process_frame
	check(replay.transitioning() and not replay.active,"Round end presents the result before cutting to the replay")
	replay._process(replay.OUTRO_SECONDS-.15)
	check(replay.transitioning() and replay.fade_alpha()==0,"Round result keeps the arena visible before the camera change")
	replay._process(.16)
	check(replay.active and replay.final and n.final_replay_until>game.clock,"Destroy round end transitions into its mandatory final")
	check(n.destroy.next_round_at>=n.final_replay_until+n.destroy.INTERMISSION-.01,"Next objective round waits until after final replay and result interval")
	n.finish_death_replay()
	check(victim.health==0,"Skipping a replay never revives a Destroy player mid-round")
	var xp=game.progression.xp_for("YOU")
	replay.advance(10)
	check(game.progression.xp_for("YOU")==xp,"Watching replays cannot award duplicate kills or XP")
func host_test() -> void:
	check(await game.net.host(27917,"cams",false),"Real replay host starts")
	freeze(); mark("host")
	check(await wait_for(func(): return game.net.peers.size()==2),"Remote replay client joins")
	var n=game.net
	var id=0
	for peer in n.peers:
		if peer!=1: id=peer
	if id==0: return
	var remote=n.slots[n.peers[id].slot].actor
	game.player.reset_at(Vector3(-5,.05,13))
	remote.life_id+=1; remote.reset_at(Vector3(-5,.05,19)); remote.set_physics_process(false)
	n._spawn.rpc_id(id,remote.position,remote.life_id)
	await get_tree().create_timer(3.1).timeout
	var life=remote.life_id
	remote.take_damage(100,1,"S0")
	n.record_kill(remote.target_name,"LONGSHOT",true,false,1,"S0",1,true)
	n.shot_fx(0,game.player.camera.global_position,remote.position+Vector3.UP*1.68,3)
	check(await wait_for(func(): return marked("watching")),"Victim receives and displays server-recorded killcam")
	check(remote.health==0 and remote.life_id==life,"Server leaves the victim dead while the replay plays")
	mark("skip")
	check(await wait_for(func(): return remote.health==100),"Remote skip RPC immediately respawns the victim")
	check(remote.life_id==life+1,"Skip creates exactly one fresh life")
	check(await wait_for(func(): return marked("respawned")),"Client receives authoritative skip/respawn")
	# Old-life skip packets must not affect a subsequent death.
	remote.take_damage(100,1,"S0")
	n._complete_replay(id,life)
	check(remote.health==0,"Stale skip RPC cannot resurrect a newer life")
	n.record_kill(remote.target_name,"RIFLE",false,false,2,"S0",1,false)
	game.combat.scores=[0,250,0]; n._end_round()
	check(await wait_for(func(): return marked("final")),"All clients receive the mandatory final killcam")
	check(game.replays.active and game.replays.final,"Host watches the same final replay")
	mark("final_skip")
	check(await wait_for(func(): return marked("blocked")),"Remote client cannot skip the final replay")
	n._complete_replay(id,remote.life_id)
	check(remote.health==0 and not n.round_active,"Final replay cannot revive a player or restart combat")
	n.vote(1)
	check(n.votes.is_empty(),"Map voting is blocked until final replay ends")
	check(await wait_for(func(): return marked("finished") and game.clock>=n.final_replay_until),"Final replay completes on the connected client")
	n.vote(1); mark("vote")
	check(await wait_for(func(): return n.vote_counts[1]==2),"Map voting unlocks after the final replay")
	n.vote_end=game.clock+.1
	check(await wait_for(func(): return game.current_map==1 and n.round_active,18),"Match rotates after final and voting")
	freeze()
	check(await wait_for(func(): return marked("map_loaded")),"Client exits replay and loads voted map")
	check(game.replays.history.last_clip.is_empty(),"New map cannot reuse an old final kill")
	mark("done")
func client_test() -> void:
	check(await wait_for(func(): return marked("host")),"Host is available")
	game.net.join("127.0.0.1",join_port,"cams")
	check(await wait_for(func(): return game.net.is_client_ready()),"Client connects")
	check(await wait_for(func(): return game.replays.active),"Death replay crosses the actual ENet connection")
	check(not game.replays.final and game.player.health==0,"Client shows a skippable death replay")
	check(game.replays.clip.weapon=="LONGSHOT" and game.replays.clip.head,"Network clip contains lethal weapon and headshot metadata")
	mark("watching")
	await wait_for(func(): return marked("skip"))
	Input.action_press("jump")
	await get_tree().process_frame
	Input.action_release("jump")
	check(await wait_for(func(): return game.player.health==100 and not game.replays.active),"Jump skips and receives a fresh authoritative spawn")
	mark("respawned")
	check(await wait_for(func(): return game.replays.active and game.replays.final),"Mandatory final replaces the next death killcam")
	mark("final")
	await wait_for(func(): return marked("final_skip"))
	Input.action_press("jump"); await get_tree().process_frame; Input.action_release("jump")
	check(game.replays.active and game.replays.final,"Skip input cannot dismiss the final killcam")
	mark("blocked")
	check(await wait_for(func(): return not game.replays.active,10),"Final replay finishes automatically")
	mark("finished")
	await wait_for(func(): return marked("vote") and game.clock>=game.net.final_replay_until)
	game.net.vote(1)
	check(await wait_for(func(): return game.current_map==1 and game.net.round_active,18),"Client loads next map after final and vote")
	check(not game.replays.active and game.replays.ghosts.is_empty(),"Replay ghosts do not leak into the next map")
	mark("map_loaded")
	await wait_for(func(): return marked("done"))
