extends Node
var checks = 0
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS ",label)
	else:
		failures.append(label)
		push_error("FAIL "+label)

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame

func run(game: Node) -> void:
	game.prefs.data.killcams=false
	await frames(3)
	check(game.mode=="training" and game.targets.size()==7 and game.combat.bots.is_empty(),"Training opens with passive targets and no combat bots")
	game.start_mode("combat")
	await frames(3)
	var c = game.combat
	var p = game.player
	check(c.bots.size()==9 and game.targets.size()==9,"Combat creates exactly nine bots")
	check(c.bots.filter(func(b): return b.team==1).size()==4 and c.bots.filter(func(b): return b.team==2).size()==5,"Roster is player plus four allies versus five enemies")
	check(c.SPAWNS.size()==4,"Combat uses four fixed spawn zones")
	check(c.navigation.get_point_count()>300,"Ground navigation has a usable route graph")
	var route = c.path_between(Vector3(-6,.05,-2),Vector3(-6,.05,-7))
	check(route.size()>3,"Bots route around the wall instead of walking through it")
	var distinct = true
	for a in c.actors():
		for b in c.actors():
			if a!=b and a.position.distance_to(b.position)<1.15:
				distinct = false
	check(distinct,"Initial spawns do not overlap teammates or enemies")
	game.set_active(false)
	for bot in c.bots:
		bot.set_physics_process(false)
	var before = p.health
	p.take_damage(25,1,"ALLY 1")
	check(p.health==before,"Friendly bullets cannot damage the player")
	p.take_damage(25,2,"ENEMY 1")
	check(p.health==75,"Enemy bullets remove real player health")
	p.take_damage(100,2,"ENEMY 1")
	check(p.health==0 and c.deaths==1,"Lethal damage records death and queues an immediate respawn")
	var shots = game.shot_count
	p.shoot()
	p.throw_grenade("blast")
	check(game.shot_count==shots and game.grenades.is_empty(),"Dead player cannot fire or throw grenades")
	check(c.scores[2]==1 and game.kills==0 and game.kill_feed[0].killer=="ENEMY 1","Enemy kill updates its team score and feed without granting a player kill")
	game.set_active(true)
	await frames(2)
	check(p.health==100 and p.ammo[3]==6 and p.collision_layer==2,"Player respawns within two frames with collision and a full six-round sniper")
	p.take_damage(25,2,"ENEMY 1")
	check(p.health==75,"A just-respawned player is immediately vulnerable")
	p.health=100
	var health_before_refill = p.health
	p.health=50
	var refill_event = InputEventKey.new()
	refill_event.physical_keycode=KEY_F
	refill_event.pressed=true
	game._unhandled_input(refill_event)
	check(p.health==50,"Training refill is disabled during combat")
	p.health=health_before_refill
	# Safer spawn selection uses enemy pressure, crowding and friendly support.
	game.set_active(false)
	for bot in c.bots:
		bot.position=Vector3(-17,.05,16)
		bot.health=100
	var spawn = c.choose_spawn(1,p)
	check(spawn.distance_to(Vector3(-17,.05,16))>20,"Spawn selection avoids a crowded enemy-controlled corner")
	var bot = c.bots[4]
	bot.position=Vector3(-18.2,.05,-14)
	p.reset_at(Vector3(-18.2,.05,-10))
	await frames(3)
	check(not c.sight_clear(bot.position+Vector3.UP,p.position+Vector3.UP),"Bots cannot see through solid cover")
	bot.position=Vector3(3,.05,0)
	p.position=Vector3(3,.05,8)
	await frames(3)
	check(c.sight_clear(bot.position+Vector3.UP,p.position+Vector3.UP),"Unobstructed opponents are visible")
	game.make_smoke(Vector3(3,.1,4))
	check(not c.sight_clear(bot.position+Vector3.UP,p.position+Vector3.UP),"Smoke blocks bot target acquisition")
	game._clear_effects()
	# Bot death uses the same damage/hitboxes and comes back without growing roster.
	bot.take_damage(100,1)
	check(bot.health==0 and bot.collision_layer==0,"A killed bot leaves combat collision")
	bot.set_physics_process(true)
	game.set_active(true)
	await frames(2)
	check(bot.health==100 and c.bots.size()==9,"Bot respawns within two frames without adding duplicate actors")
	bot.set_physics_process(false)
	p.equip(3)
	p.equip_cooldown=0
	p.fire_cooldown=0
	p.reload_timer=0
	p.sniper_cycle=0
	p.bolt_cues=0
	p.shoot()
	check(p.ammo[3]==5,"Sniper fires one of its six rounds")
	await frames(50)
	check(p.bolt_cues==2,"Sniper fires one bolt-open and one bolt-close audio cue")
	await frames(20)
	check(p.sniper_cycle==0,"Rechamber cycle completes before the next shot")
	# A real bot must be able to kill the human, not only other bot hitboxes.
	game.start_mode("combat")
	for other in c.bots:
		other.set_physics_process(false)
		other.health=0
		other.collision_layer=0
		for area in other.hitboxes:
			area.collision_layer=0
	var duelist = c.bots[4]
	duelist.reset()
	duelist.position=Vector3(3,.05,0)
	duelist.set_physics_process(true)
	p.reset_at(Vector3(3,.05,6))
	await frames(300)
	check(c.deaths>0,"Actual bot sight, aim and rifle rays can kill the human player")
	# Observe an actual unattended skirmish, including deaths and repeated respawns.
	game.start_mode("combat")
	await frames(2400)
	print("SKIRMISH shots=",c.bot_shots," damage=",c.bot_damage," blue=",c.scores[1]," red=",c.scores[2]," player_deaths=",c.deaths," respawns=",c.respawns)
	check(c.bot_shots>30 and c.bot_damage>=100,"Live bots acquire opponents, fire and deal damage")
	check(c.scores[1]>0 and c.scores[2]>0,"Both teams earn kills in an actual skirmish")
	check(c.respawns>2 and c.bots.size()==9,"Endless play continues through repeated respawns with a stable roster")
	check(game.mode=="combat" and game.active,"No score or timer limit ends the skirmish")
	game.set_active(false)
	var saved_shots=c.bot_shots
	var saved_clock=game.clock
	await frames(30)
	check(c.bot_shots==saved_shots and game.clock==saved_clock,"Pause freezes bot firing and the game clock")
	game.start_mode("training")
	await frames(3)
	check(game.targets.size()==7 and c.bots.is_empty() and p.health==100,"Returning to training removes bots and restores the original arena")
	var training_health=p.health
	await frames(120)
	check(p.health==training_health,"Aim training remains non-hostile")
	game.start_mode("combat")
	await frames(3)
	check(c.bots.size()==9 and c.scores==[0,0,0] and c.deaths==0,"Starting another combat arena resets its roster and stats")
	print("RESULT ",checks-failures.size(),"/",checks," combat checks passed")
	get_tree().quit(0 if failures.is_empty() else 1)
