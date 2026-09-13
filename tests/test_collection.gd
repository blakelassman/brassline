extends Node
const Challenges = preload("res://scripts/challenges.gd")
const Collection = preload("res://scripts/cosmetics.gd")
const Rules = preload("res://scripts/rules.gd")
var checks = 0
var failures: Array[String] = []
func check(value: bool, title: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ",title)
	if not value: failures.append(title)
func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame
	await get_tree().process_frame
func run(game: Node) -> void:
	await frames(3)
	var c = Challenges.new()
	check(c.catalog().size()>=75,"Broad catalog contains at least 75 distinct milestones")
	var ids: Dictionary = {}
	for item in c.catalog(): ids[item.id] = true
	check(ids.size()==c.catalog().size(),"Every milestone has a unique persistent ID")
	var event = {"weapon":"LONGSHOT","head":true,"air":true,"boosted":true,"scope":.2,"one_shot":true,"distance":35,"health":20,"group":1,"time":1.0,"victim":"a"}
	c.event("kill",event)
	check(c.stats.kills==1 and c.stats.headshots==1 and c.stats.jump_kills==1,"Airborne headshot counts each relevant track once")
	check(c.stats.air_heads==1 and c.stats.boost_kills==1 and c.stats.quickscopes==1,"Boosted quickscope qualifies only relevant specialty tracks")
	check(c.stats.longshots==1 and c.stats.clutch==1 and c.stats.one_shots==1,"Distance, low-health and full-health one-shot milestones track")
	event.victim = "b"
	c.event("kill",event)
	check(c.stats.collats==1 and c.stats.best_chain==2,"Same-shot second kill earns one collateral and double kill")
	event.victim = "c"
	c.event("kill",event)
	check(c.stats.triple_collats==1 and c.stats.collats==1,"Triple collateral does not double-count the two-target shot")
	event.victim = "d"
	c.event("kill",event)
	check(c.stats.collats==1 and c.stats.triple_collats==1 and c.stats.best_chain==4,"Four-target shot advances chain without repeating collateral awards")
	c.event("death",{"killer":"nemesis"})
	check(c.streak==0 and c.chain==0 and c.head_streak==0,"Death resets all per-life streak counters")
	check(not c.pending.is_empty(),"Death preserves queued notification playback")
	event.group = 2
	event.time = 10
	event.victim = "nemesis"
	c.event("kill",event)
	check(c.stats.revenge==1 and c.streak==1,"Payback awards once against the most recent killer")
	c.event("kill",event)
	check(c.stats.revenge==1,"Repeated victim does not award repeated payback")
	c.reset_match()
	for i in range(30): c.event("kill",{"weapon":"RIFLE","group":100+i,"time":20+i*2,"victim":str(i)})
	check(c.unlocked.has("best_streak_10") and c.unlocked.has("best_streak_30"),"Ten and thirty kills in one life unlock their milestones")
	check(c.stats.best_streak==30 and c.chain==1,"Killstreak persists beyond multi-kill timing window")
	var before = c.unlocked.size()
	c.check_unlocks()
	check(c.unlocked.size()==before,"Checking completed milestones never duplicates them")
	var restored = Challenges.new()
	restored.load_data(JSON.parse_string(JSON.stringify(c.save_data())))
	check(c.catalog().all(func(item): return int(restored.stats.get(item.stat,0))==int(c.stats.get(item.stat,0))) and restored.unlocked==c.unlocked,"JSON round-trip preserves counters and earned milestones")
	check(restored.streak==0,"Restart does not carry an unfinished life streak")
	check(c.update(.1,true) and not c.current.is_empty(),"Notification starts with one presentation cue")
	var elapsed = c.elapsed
	check(not c.update(10,false) and c.elapsed==elapsed,"Hidden menu pauses notification time instead of consuming rewards")
	var pending_count = c.pending.size()
	c.event("death")
	check(not c.current.is_empty() and c.pending.size()==pending_count,"Current and queued notifications survive respawn")
	check(c.update(3,true),"Next queued notification starts after previous presentation")
	var timing = Challenges.new()
	for i in range(4): timing.event("kill",{"weapon":"LONGSHOT","time":i*1.1,"group":i})
	check(timing.stats.best_chain==4,"Sniper cadence can qualify for a four-kill chain")
	timing.event("kill",{"weapon":"LONGSHOT","time":5.0,"group":5})
	check(timing.chain==1,"A kill after the chain window starts a new chain")
	for kind in ["parries","boosts","wins"]:
		timing.event(kind)
		check(timing.stats[kind]==1,"Confirmed specialty event records "+kind)
	var skins = Collection.new()
	skins.load_data({})
	check(Collection.catalog().size()==55 and skins.owned.size()==5,"55 styles include five free starting loadout items")
	check(Collection.catalog().values().filter(func(item): return item.case).size()==50,"Case pool contains 50 collectible finishes")
	var odds = [0,0,0,0,0]
	for roll in range(10000): odds[Collection.rarity_for_roll(roll)] += 1
	check(odds==[7000,2200,600,175,25],"Every possible roll gives the exact displayed rarity odds")
	check(odds[4]==25 and 10000/odds[4]==400,"Special category has exactly one-in-400 odds per opening")
	for rarity in range(5):
		check(Collection.catalog().values().any(func(item): return item.case and item.rarity==rarity),"Every rarity has a nonempty eligible item pool")
	check(not skins.equip_item("rifle_aurora"),"Unowned cosmetics cannot be equipped through the inventory")
	skins.rng.seed = 929
	var first = skins.open_case()
	skins.rng.seed = 929
	var second = skins.open_case()
	check(first.item.id==second.item.id and second.duplicate and second.count==2,"Duplicate drops stack without deleting the first item")
	check(skins.opened==2 and skins.equip_item(first.item.id),"Free openings need no keys or currency; owned item can be equipped")
	var reloaded = Collection.new()
	reloaded.load_data(JSON.parse_string(JSON.stringify(skins.save_data())))
	check(reloaded.save_data()==skins.save_data(),"Inventory, counts, last drop and equipment survive JSON save/load")
	reloaded.load_data({"owned":{"bogus":50,"rifle_aurora":-1},"equipped":{"rifle":"rifle_aurora","armor":"rifle_standard"},"opened":-2})
	check(reloaded.owned.size()==5 and reloaded.equipped==Collection.DEFAULTS and reloaded.opened==0,"Invalid local inventory values recover to valid defaults")
	check(Collection.clean_loadout({"armor":"../../bad","rifle":"armor_aurora"})==Collection.DEFAULTS,"Network cosmetic IDs cannot introduce paths or wrong equipment slots")
	var prefs = game.Preferences.new("user://collection_roundtrip.json")
	prefs.data.challenges = c.save_data()
	prefs.data.cosmetics = skins.save_data()
	prefs.data.xp = 98765
	check(prefs.save(),"Expanded profile saves atomically")
	var loaded = game.Preferences.new(prefs.path)
	loaded.load_profile()
	var saved_skins = Collection.new()
	saved_skins.load_data(loaded.data.cosmetics)
	check(saved_skins.save_data()==skins.save_data() and loaded.data.xp==98765,"Profile reload preserves collection and existing XP together")
	var saved_challenges = Challenges.new()
	saved_challenges.load_data(loaded.data.challenges)
	check(saved_challenges.unlocked==c.unlocked,"Profile reload preserves achievements")
	DirAccess.remove_absolute(prefs.path)
	DirAccess.remove_absolute(prefs.path+".bak")
	# Real player firing: stationary compensated spray keeps every direction on target.
	game.world_root.free()
	game.world_root = Node3D.new()
	game.add_child(game.world_root)
	game.Geo.box(game.world_root,Vector3(0,-.3,0),Vector3(64,.6,62),Color.GRAY,true)
	for target in game.targets: target.set_physics_process(false)
	var p = game.player
	p.set_physics_process(false)
	p.reset_at(Vector3(0,.02,20))
	p.weapon = 0
	await frames(3)
	for i in range(20): p.simulate_movement(1.0/60,Vector2.ZERO,false,false,true)
	check(p.is_on_floor() and p.current_spread()==0,"Stationary rifle has no random accuracy spread")
	var directions: Array = []
	for i in range(24):
		p.advance_weapon_state(.16)
		p.shoot()
		directions.append(p.last_shot_direction)
	check(p.ammo[0]==0 and directions.any(func(direction): return absf(direction.x)>.1) and p.pitch>.6,"Uncompensated full magazine produces substantial horizontal and vertical recoil")
	p.refill()
	p.rotation.y = 0
	p.pitch = 0
	p.camera.rotation.x = 0
	p.rifle_shots = 0
	p.rifle_idle = 99
	var repeats = true
	for i in range(24):
		p.advance_weapon_state(.16)
		p.shoot()
		repeats = repeats and directions[i].distance_to(p.last_shot_direction)<.00001
	check(repeats,"Two untouched full sprays trace identical directions")
	p.refill()
	p.rotation.y = 0
	p.pitch = 0
	p.camera.rotation.x = 0
	p.rifle_shots = 0
	var perfect = true
	for i in range(24):
		p.advance_weapon_state(.16)
		p.shoot()
		perfect = perfect and p.last_shot_direction.distance_to(Vector3.FORWARD)<.00001
		var recoil = Rules.rifle_recoil(i)
		p.rotation.y += deg_to_rad(recoil.x)
		p.pitch -= deg_to_rad(recoil.y)
		p.camera.rotation.x = p.pitch
	check(perfect,"Exact inverse mouse compensation keeps all 24 live shots centered")
	p.advance_weapon_state(.64)
	check(p.rifle_shots>0,"Short pause retains spray phase")
	p.advance_weapon_state(.02)
	check(p.rifle_shots==0,"650 ms pause resets spray phase")
	p.rifle_shots = 10
	p.equip(1)
	check(p.rifle_shots==0,"Weapon swap resets rifle spray phase")
	p.weapon = 0
	p.rifle_shots = 10
	p.start_reload()
	check(p.rifle_shots==0,"Reload resets rifle spray phase")
	p.rifle_shots = 10
	p.reset_at(Vector3(0,.02,20))
	check(p.rifle_shots==0,"Respawn clears old recoil state")
	var kit_before = [p.ammo.duplicate(),p.health,p.collision_layer,p.body_shape.shape.radius]
	game.cosmetics.owned.rifle_aurora = 1
	game.cosmetics.equip_item("rifle_aurora")
	game.apply_cosmetics()
	check(kit_before==[p.ammo,p.health,p.collision_layer,p.body_shape.shape.radius],"Equipping a finish does not change health, ammo or collision")
	check(p.viewmodel.models[0].find_children("*","MeshInstance3D",true,false).any(func(mesh): return mesh.material_override is ShaderMaterial),"Owned finish is applied to actual first-person weapon geometry")
	var avatar = preload("res://scripts/network_avatar.gd").new()
	avatar.game = game
	avatar.team = 2
	game.add_child(avatar)
	avatar.cosmetics = {"armor":"armor_royal","rifle":"rifle_circuit"}
	avatar.viewmodel.apply_cosmetics()
	check(avatar.viewmodel.rig.root.find_children("*","MeshInstance3D",true,false).any(func(mesh): return mesh.material_override is ShaderMaterial),"Operator finish appears on a remote model")
	avatar.cosmetics = {}
	avatar.viewmodel.apply_cosmetics()
	check(is_instance_valid(avatar.viewmodel.root),"Remote finish can be changed back to standard without stale nodes")
	avatar.queue_free()
	for cue in ["achievement","case_tick","case_reveal"]:
		check(game.audio.has(cue) and game.audio[cue].get_length()>0,"Original synthesized cue loads: "+cue)
	var ui = game.hud.menu.collection_menu
	var old_opened = game.cosmetics.opened
	ui.open_case()
	check(game.cosmetics.opened==old_opened+1 and ui.spin_time==0,"Locker starts a real free opening")
	var disk = game.Preferences.new(game.prefs.path)
	disk.load_profile()
	check(disk.data.cosmetics.last_drop==ui.drop.item.id,"Drop is saved before the reveal animation completes")
	ui.open_case()
	check(game.cosmetics.opened==old_opened+1,"Repeated clicks cannot overlap case transactions")
	ui.finish_spin()
	check(ui.selected_id==ui.drop.item.id and ui.reel.cards[24].id==ui.drop.item.id,"Reel, revealed preview and saved drop agree")
	ui.equip_selected()
	check(game.cosmetics.equipped[ui.drop.item.slot]==ui.drop.item.id,"Reveal can equip the actual won item")
	var real_path = game.prefs.path
	game.prefs.path = "user://nonexistent_collection_directory/profile.json"
	old_opened = game.cosmetics.opened
	ui.open_case()
	check(game.cosmetics.opened==old_opened and ui.spin_time<0,"Failed save rolls back the opening and grants no phantom reward")
	game.prefs.path = real_path
	game.prefs.error = ""
	print("COLLECTION_RESULT ",checks-failures.size(),"/",checks)
	get_tree().quit(0 if failures.is_empty() else 1)
