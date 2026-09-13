extends Node
var checks = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else:
		failures.append(label)
		push_error("FAIL "+label)
func frames(n: int) -> void:
	for i in range(n): await get_tree().physics_frame
	await get_tree().process_frame
func run(game: Node) -> void:
	await frames(3)
	check(game.Maps.NAMES.size()==4,"Original Foundry plus three selectable maps")
	var surfaces: Dictionary = {}
	for index in range(4):
		await game.start_mode("combat",index)
		await frames(4)
		var c = game.combat
		var name = game.Maps.NAMES[index]
		check(game.current_map==index and game.active and not game.changing_map,name+": transition completes")
		check(c.bots.size()==9 and game.targets.size()==9,name+": correct 5v5 roster")
		var free = true
		for pos in c.SPAWNS: free = free and c.free_space(pos)
		check(free,name+": all four spawn zones have capsule clearance")
		var linked = true
		for pos in c.SPAWNS:
			linked = linked and c.path_between(c.SPAWNS[0],pos).size()>0
		check(linked,name+": all spawn corners are connected by ground routes")
		var ids = c.navigation.get_point_ids()
		var connected = 0
		for id in ids:
			if c.navigation.get_point_path(ids[0],id).size()>0: connected+=1
		check(float(connected)/maxi(1,ids.size())>.97,name+": patrol graph has no isolated pockets")
		var roles: Dictionary = {}
		for bot in c.bots: roles[bot.profile.name]=true
		check(roles.size()==3,name+": assault, flanker and marksman profiles present")
		var inside = true
		for bot in c.bots:
			inside = inside and bot.health==100 and bot.rig.legs.size()==2 and bot.rig.arms.size()==2
		check(inside,name+": variants retain 100 health and articulated limbs")
		await frames(1200)
		print(name," shots=",c.bot_shots," damage=",c.bot_damage," score=",c.scores)
		check(c.bot_shots>15 and c.bot_damage>=100,name+": bots navigate, acquire and fight")
		check(c.scores[1]+c.scores[2]>0 and c.bots.size()==9,name+": kills and instant respawns sustain combat")
		check(game.effects.particles.size()<=100 and game.effects.marks.size()<=48 and game.effects.bodies.size()<=12,name+": cosmetic effects stay bounded")
		game.player.take_damage(100,2,"ENEMY 1")
		await frames(2)
		check(game.player.health==100 and game.player.collision_layer==2,name+": instant unshielded player respawn")
		for bot in c.bots: bot.set_physics_process(false)
		game.player.take_damage(25,2,"ENEMY 1")
		check(game.player.health==75,name+": damage works immediately after respawn")
		await game.start_mode("training",index)
		await frames(4)
		check(game.targets.size()==7 and c.bots.is_empty(),name+": passive training mode works")
		var clear_targets = true
		for target in game.targets:
			clear_targets = clear_targets and game.unobstructed(target.position+Vector3.UP*.25,target.position+Vector3.UP*1.7)
		check(clear_targets,name+": practice targets stand outside solid geometry")
		surfaces[game.surface_at(Vector3(17,.05,16))] = true
	check(surfaces.has("metal") and surfaces.has("tile") and surfaces.has("concrete"),"Surface footsteps distinguish deck, tile and concrete")
	check(game.audio.has("mag_out") and game.audio.has("mag_in") and game.audio.has("smoke_hiss") and game.audio.has("ambient_relay"),"Expanded foley and ambience load")
	# Actual movement must climb each new route and join its platform.
	for data in [[1,Vector3(13,.1,4.9),Vector3(13,2.4,-4),0.0],[2,Vector3(0,.1,9.2),Vector3(0,2,-.6),0.0],[3,Vector3(-14,.1,-8),Vector3(-4,3,-8),-PI/2]]:
		await game.start_mode("training",data[0])
		game.player.reset_at(data[1])
		game.player.rotation.y=data[3]
		Input.action_press("forward")
		await frames(85)
		Input.action_release("forward")
		check(game.player.position.y>data[2].y-.25,game.Maps.NAMES[data[0]]+": player can walk up the ramp onto high ground")
	print("RESULT ",checks-failures.size(),"/",checks," expansion checks passed")
	get_tree().quit(0 if failures.is_empty() else 1)
