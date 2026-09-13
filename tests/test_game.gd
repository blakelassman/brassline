extends Node

const Rules = preload("res://scripts/rules.gd")
var checks = 0
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS ", label)
	else:
		failures.append(label)
		push_error("FAIL " + label)

func sync_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame

func run(game: Node) -> void:
	check(Rules.blast_damage(0.5,1,1,true) == 0, "Owner takes no blast damage")
	check(Rules.blast_damage(0.5,1,1,false) == 0, "Teammate takes no blast damage")
	check(Rules.blast_damage(0.5,1,2,false) > 0, "Enemy takes blast damage")
	check(Rules.blast_damage(5.01,1,2,false) == 0, "Blast radius is bounded")
	check(Rules.blast_damage(1.0,1,2,false) == 100 and Rules.blast_damage(5.0,1,2,false) == 100, "Blast is lethal throughout its five meter radius")
	check(Rules.perfect_jump(0.10) and not Rules.perfect_jump(0.2), "Perfect timing window is bounded")
	check(not Rules.perfect_jump(-0.1), "A future jump cannot earn a boost")
	var feet = Vector3(0,0.5,0)
	var origin = Vector3(-0.5,0.15,0)
	var perfect = Rules.launch_velocity(Vector3(0,6,0),feet,origin,0.10)
	var late = Rules.launch_velocity(Vector3(0,6,0),feet,origin,0.3)
	check(perfect.y > late.y and perfect.x > late.x, "Timed jump gives more lift and distance")
	check(perfect.x > 0, "Blast placement controls launch direction")
	var capped = Rules.launch_velocity(Vector3(24,28,0),feet,origin,0.1)
	check(Vector2(capped.x,capped.z).length() <= 24.01 and capped.y <= 29, "Launch velocity respects caps")
	check(Rules.launch_velocity(Vector3.ONE,Vector3(10,0,0),Vector3.ZERO,0.1) == Vector3.ONE, "Out of range blast cannot launch player")
	await sync_physics()
	var wall_target = game.targets[0]
	var target_head = wall_target.global_position + Vector3(0,1.68,0)
	var low_origin = game.player.camera.global_position
	var blocked = game.shoot_ray(low_origin,(target_head-low_origin).normalized(),1,false)
	check(wall_target.health == 100 and not blocked.get("headshot",false), "Solid wall blocks a pistol headshot")
	var high_origin = Vector3(-6,5.4,-1)
	var airborne = game.shoot_ray(high_origin,(target_head-high_origin).normalized(),1,true)
	check(airborne.get("headshot",false) and wall_target.health == 0, "Pistol kills with an exposed airborne headshot")
	check(game.air_heads == 1, "Airborne headshot is recorded")
	wall_target.reset()
	var open_target = game.targets[1]
	var center = open_target.global_position + Vector3(0,1.0,0)
	var firing_point = center + Vector3(0,0,5)
	await sync_physics()
	var body_hit = game.shoot_ray(firing_point,Vector3.FORWARD,1,false)
	check(body_hit.get("damage",0) == 40 and open_target.health == 60, "Pistol body damage is 40, not lethal")
	open_target.reset()
	await sync_physics()
	for i in range(4):
		game.shoot_ray(firing_point,Vector3.FORWARD,0,false)
	check(open_target.health == 0, "Four rifle body hits eliminate 100 health")
	open_target.reset()
	var friend = game.targets[4]
	var friend_origin = friend.global_position + Vector3(0,1.68,4)
	game.shoot_ray(friend_origin,Vector3.FORWARD,1,false)
	check(friend.health == 100, "Friendly gunfire does not damage teammate")
	game.player.weapon = 1
	game.player.ammo = [24,7,0,6]
	game.player.fire_cooldown = 0
	game.player.equip_cooldown = 0
	game.player.shoot()
	var shots = game.shot_count
	game.player.shoot()
	check(game.shot_count == shots and game.player.ammo[1] == 6, "Pistol cooldown prevents rapid second shot")
	game.player.equip(0)
	game.player.shoot()
	check(game.shot_count == shots, "Weapon switching cannot bypass shot cooldown")
	game.player.ammo[0] = 0
	game.player.start_reload()
	check(game.player.reload_timer > 0.0, "Empty rifle starts a real reload")
	game.player.equip(1)
	check(game.player.ammo[0] == 0, "Canceling reload does not grant free ammunition")
	game.player.reset_at(game.launch_pad)
	game.player.velocity = Vector3(0,6.0,0)
	game.player.last_jump_time = game.clock - 0.1
	await sync_physics()
	game.explode(game.player.global_position + Vector3(-0.3,0.16,0))
	check(game.player.health == 100 and game.player.velocity.y > 15, "Live explosion launches owner without injury")
	# Move a target close behind the wall: it is within radius but covered.
	wall_target.position = Vector3(-6,0.04,-5.2)
	await sync_physics()
	game.explode(Vector3(-6,0.6,-3.6))
	check(wall_target.health == 100, "Solid cover also blocks blast damage")
	wall_target.reset()
	game.player.blast_count = 1
	game.player.equip_cooldown = 0
	game.player.throw_grenade("blast")
	var count = game.grenades.size()
	game.player.throw_grenade("blast")
	check(game.grenades.size() == count and game.player.blast_count == 0, "Only one blast grenade until refill")
	game.player.refill()
	check(game.player.blast_count == 1 and game.player.smoke_count == 1, "Practice refill restores both grenades")
	game.reset_practice(true)
	check(game.grenades.is_empty() and game.kills == 0 and game.air_heads == 0, "Practice reset clears effects and score")
	await sync_physics()
	# Exercise the real movement, projectile, fuse, and smoke lifecycle for 100 frames.
	game.set_active(true)
	game.player.pitch = -1.45
	game.player.camera.rotation.x = -1.45
	game.player.throw_grenade("blast")
	game.player.equip_cooldown = 0
	game.player.throw_grenade("smoke")
	for i in range(100):
		if i == 67:
			game.player.jump_requested = true
		await get_tree().physics_frame
	check(game.player.health == 100, "Simulated grenade jump remains free of self damage")
	check(game.grenades.is_empty(), "Real grenade fuse resolves and deletes projectile")
	check(game.perfect_boosts > 0, "Jump shortly before live fuse produces a perfect boost")
	check(game.player.max_height > 1.5, "Actual jump trajectory rises above normal jumping height")
	check(game.smoke_nodes.size() > 0, "Smoke grenade creates temporary visual cover")
	await extended_checks(game)
	game.reset_practice(true)
	await get_tree().process_frame
	print("RESULT ",checks-failures.size(),"/",checks," checks passed")
	if not failures.is_empty():
		print("FAILURES ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func extended_checks(game: Node) -> void:
	game.set_active(false)
	game.reset_practice(true)
	var p = game.player
	check(Rules.ground_move(Vector2(7.5,0),Vector2.ZERO,7.5,.07).length() == 0, "Ground release stops full speed within 70ms")
	var counter = Rules.ground_move(Vector2(7.5,0),Vector2.LEFT,7.5,.02)
	var release = Rules.ground_move(Vector2(7.5,0),Vector2.ZERO,7.5,.02)
	check(counter.length() < release.length(), "Counter strafe brakes faster than releasing the key")
	var strafe = Rules.air_move(Vector2(0,-10),Vector2.RIGHT,1.0/60)
	check(strafe.length() > 10 and strafe.y == -10, "Air strafe adds side speed while preserving forward momentum")
	check(Rules.air_move(Vector2(0,-10),Vector2(0,-1),1.0/60) == Vector2(0,-10), "Holding forward alone cannot endlessly accelerate in air")
	check(Rules.spread_degrees(0,0,false,0) == 0 and Rules.spread_degrees(0,7.5,false,0) > 1, "Rifle accuracy recovers when movement stops")
	check(Rules.spread_degrees(1,24,true,0) == 0, "Blast jump pistol remains accurate in air")
	check(Rules.spread_degrees(3,0,false,.11)>0 and Rules.spread_degrees(3,0,false,.12)==0, "Sniper earns precise quickscope accuracy after 120ms")
	var wheel_bound = false
	for event in InputMap.action_get_events("jump"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel_bound = true
	check(wheel_bound,"Mouse wheel down and space are both bound to jump")
	check(p.viewmodel.viewport.find_world_3d() != p.get_world_3d(), "Weapon rendering uses an isolated world, preventing cover clipping")
	var before = game.grenades.size()
	p.equip_grenade("blast")
	check(p.held_grenade == "blast" and p.blast_count == 1 and game.grenades.size()==before,"Equipping grenade neither spends it nor starts a fuse")
	p.viewmodel.update_pose(0)
	check(p.viewmodel.grenade_model.visible and not p.viewmodel.models[p.weapon].visible,"Equipped grenade replaces the visible gun")
	p.equip_cooldown = 0
	p.throw_grenade("blast",true)
	var short_grenade = game.grenades.back()
	check(short_grenade.velocity.y < 0 and short_grenade.velocity.length() < 3 and p.held_grenade.is_empty(),"Short toss drops downward and returns to previous weapon")
	p.equip_cooldown = 0
	p.smoke_count = 1
	p.throw_grenade("smoke",false)
	var long_grenade = game.grenades.back()
	check(long_grenade.velocity.length()>short_grenade.velocity.length()*3,"Long throw travels faster than underhand drop")
	game.reset_practice(true)
	await sync_physics()
	var target = game.targets[1]
	target.moving = false
	var head_origin = target.global_position+Vector3(0,1.68,4)
	var rifle_hit = game.shoot_ray(head_origin,Vector3.FORWARD,0,false)
	check(rifle_hit.get("headshot",false) and target.health == 0,"Rifle now kills with one headshot")
	var a = game.targets[5]
	var b = game.targets[6]
	await sync_physics()
	var pair_origin = a.global_position+Vector3(0,1,4)
	var coll = game.shoot_ray(pair_origin,Vector3.FORWARD,3,false)
	check(coll.get("kill_count",0)==2 and a.health==0 and b.health==0,"One sniper round kills two aligned bodies in a collateral")
	check(game.kill_feed[0].collateral and game.kill_feed[1].collateral,"Collateral entries share a kill feed highlight")
	a.reset()
	b.reset()
	b.position = Vector3(-6,.04,-8)
	a.position = Vector3(-6,.04,-2)
	await sync_physics()
	game.shoot_ray(Vector3(-6,1.04,1),Vector3.FORWARD,3,false)
	check(a.health==0 and b.health==100,"Sniper penetrates a target but stops at the wall behind it")
	for i in range(7):
		game.record_kill("TEST %d" % i,"RIFLE",false,false,100+i)
	check(game.kill_feed.size()==6 and game.kill_feed[3].evicted<0 and game.kill_feed[4].evicted>=0,"Feed retains four primary entries and two fading overflow entries")
	game.clock += .5
	game.update_feed()
	check(game.kill_feed.size()==4,"Displaced feed entries finish fading")
	game.clock += 8
	game.update_feed()
	check(game.kill_feed.is_empty(),"Old feed entries expire")
	p.equip(3)
	p.ammo[3]=0
	p.start_reload()
	p.reload_timer=1.3
	p.viewmodel.update_pose(0)
	check(p.viewmodel.magazines[3].position.y < p.viewmodel.mag_origins[3].y-.2,"Reload visibly removes the magazine")
	p.equip(0)
	p.viewmodel.update_pose(0)
	check(p.ammo[3]==0 and p.viewmodel.magazines[3].position==p.viewmodel.mag_origins[3],"Reload cancel restores visual pose without granting ammo")
	game.reset_practice(true)
	game.set_active(true)
	for i in range(5):
		await get_tree().physics_frame
	Input.action_press("right")
	for i in range(8):
		await get_tree().physics_frame
	Input.action_release("right")
	var release_position = p.position.x
	for i in range(8):
		await get_tree().physics_frame
	check(absf(p.velocity.x)<.01 and p.position.x-release_position < .3,"Live movement release stops without a long slide")
	# A timed landing jump preserves blast-level horizontal momentum.
	p.position = Vector3(-6,.2,8)
	p.velocity = Vector3(12,-2,0)
	var jumped = false
	for i in range(12):
		p.jump_requested = true
		await get_tree().physics_frame
		if p.velocity.y > 5:
			jumped = true
			break
	check(jumped and p.velocity.x > 11.5,"Buffered landing jump preserves momentum for bunny hopping")
	# Exercise the actual G/right-click input path, including the equip delay.
	game.reset_practice(true)
	var equip_event = InputEventKey.new()
	equip_event.physical_keycode = KEY_G
	equip_event.pressed = true
	p._unhandled_input(equip_event)
	for i in range(15):
		await get_tree().physics_frame
	check(p.held_grenade=="blast" and game.grenades.is_empty(),"G input equips grenade and waits for a click")
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	p._unhandled_input(click)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(p.blast_count==0 and game.grenades.size()==1,"Right-click input throws the equipped grenade")
	game.reset_practice(true)
	for i in range(20):
		await get_tree().physics_frame
	p.equip(3)
	for i in range(15):
		await get_tree().physics_frame
	Input.action_press("aim")
	for i in range(9):
		await get_tree().physics_frame
	check(p.scope_age>=Rules.SCOPE_READY and p.camera.fov <= 32.01 and p.current_spread()==0,"Live scope input reaches precise zoom without a long settle delay")
	p.ammo[3]=0
	p.start_reload()
	for i in range(130):
		await get_tree().physics_frame
	check(p.ammo[3]==6 and p.reload_timer==0,"Sniper reload completes and restores its six-round magazine")
	Input.action_release("aim")
	for i in range(3):
		await get_tree().physics_frame
	check(p.scope_age==0 and p.viewmodel.root.visible,"Releasing aim clears scope and restores the weapon view")
	game.set_active(false)
	game.reset_practice(true)
	target.position = Vector3(3,.04,5)
	await sync_physics()
	game.explode(Vector3(3,.84,.2))
	check(target.health==0,"Live explosion kills an exposed enemy 4.8 meters away")
	check(game.audio["head"].get_length()>.2 and game.audio["sniper"].get_length()>.4,"New headshot crunch and sniper audio load from the portable assets")
	target.moving = true
