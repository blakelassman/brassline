extends "res://tests/test_prediction.gd"
var moving_target: Node
var motion_start = 0.0
func _physics_process(_delta: float) -> void:
	if is_instance_valid(moving_target) and moving_target.health>0:
		moving_target.position.x = -8+fmod(game.clock-motion_start,4.0)*4
		moving_target.velocity = Vector3(4,0,0)
func run(g: Node) -> void:
	game = g
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--join-port="): join_port = arg.trim_prefix("--join-port=").to_int()
		if arg.begins_with("--coord="): root = arg.trim_prefix("--coord=")+"/"
	if "--role=host" in OS.get_cmdline_user_args(): await host_lag()
	else: await client_lag()
	print("LAG_COMPENSATION_RESULT ",checks-failures.size(),"/",checks)
	if game.net.running: await game.net.leave()
	await game.quit_game()
func host_lag() -> void:
	check(await game.net.host(27917,"test-only",false),"Lag compensation host starts")
	freeze_bots()
	platform()
	game.player.set_physics_process(false)
	mark("host")
	check(await wait_for(func(): return game.net.peers.size()==2),"Delayed shooter connects")
	var remote_id = 0
	for id in game.net.peers:
		if id!=1: remote_id = id
	if remote_id==0: return
	var actor = game.net.slots[game.net.peers[remote_id].slot].actor
	actor.life_id += 1
	actor.reset_at(Vector3(0,30.01,10))
	game.net._spawn.rpc_id(remote_id,actor.position,actor.life_id)
	game.player.life_id += 1
	game.player.reset_at(Vector3(-8,30.01,-8))
	moving_target = game.player
	motion_start = game.clock
	mark("target_ready")
	check(await wait_for(func(): return game.net.slots[actor.net_slot].kills>0,15),"Aiming directly at the displayed moving target earns a server-confirmed kill")
	moving_target = null
	check(game.net.lag_rescued_hits>0,"The same shot would miss the target's current position without rewind")
	check(game.net.slots[0].deaths==1,"Rewound damage is applied once to the correct living target")
	mark("shot_checked")
	await wait_for(func(): return marked("client_done"))
	# Deterministic history edge cases use the actual player hitbox shapes.
	var lag = game.net.LagCompensation.new()
	var target = game.player
	target.reset_at(Vector3(0,30,0))
	var rows = [{"index":0,"actor":target}]
	lag.record(rows,100.0)
	lag.record(rows,100.1)
	target.position.x = 20
	lag.record(rows,100.2)
	var no_exclusions: Array[RID] = []
	var historical = lag.raycast(rows,Vector3(0,31.68,10),Vector3.FORWARD,30,actor,100.05,no_exclusions)
	check(not historical.is_empty() and historical.headshot,"Historical sphere ray recognizes a headshot")
	check(target.position.x==20,"History ray tests never teleport the live target")
	check(lag.raycast(rows,Vector3(0,31.68,10),Vector3.FORWARD,30,actor,100.2,no_exclusions).is_empty(),"Current-time ray misses a target that has moved away")
	var body = lag.raycast(rows,Vector3(0,30.8,10),Vector3.FORWARD,30,actor,100.05,no_exclusions)
	check(not body.is_empty() and not body.headshot,"Historical box ray recognizes a body hit")
	var excluded: Array[RID] = []
	for area in target.hitboxes: excluded.append(area.get_rid())
	check(lag.raycast(rows,Vector3(0,31.68,10),Vector3.FORWARD,30,actor,100.05,excluded).is_empty(),"Penetration exclusions prevent a second hit on the same target")
	target.life_id += 1
	check(lag.raycast(rows,Vector3(0,31.68,10),Vector3.FORWARD,30,actor,100.05,no_exclusions).is_empty(),"Old-life history cannot damage a freshly respawned player")
	check(game.net.bounded_shot_time({},game.clock+20)==game.clock,"Future shot timestamps are clamped to server time")
	check(game.net.bounded_shot_time({},game.clock-20)>=game.clock-.181,"Unverified clients cannot request arbitrary historical times")
	for tick in range(120): lag.record(rows,101+tick/60.0)
	check(lag.history[0].size()<=72,"History memory remains bounded")
	# The regular combat path still lets walls and teammates stop rewound bullets.
	actor.set_physics_process(false)
	actor.reset_at(Vector3(0,30,10))
	target.reset_at(Vector3(0,30,0))
	game.net.lag_comp.clear()
	game.net.lag_comp.record(game.net.slots,game.clock)
	actor.shot_view_time = game.clock
	var wall = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(4,4,1)
	wall.add_child(shape)
	game.add_child(wall)
	wall.position = Vector3(0,31,5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	game.shoot_ray(Vector3(0,31.68,10),Vector3.FORWARD,3,false,actor)
	check(target.health==100,"Solid walls block lag-compensated sniper shots")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	target.team = actor.team
	game.shoot_ray(Vector3(0,31.68,10),Vector3.FORWARD,3,false,actor)
	check(target.health==100,"Friendly fire stays disabled during rewind")
	actor.shot_view_time = -1
	mark("host_done")
func client_lag() -> void:
	await wait_for(func(): return marked("host"))
	game.net.join("127.0.0.1",join_port,"test-only")
	check(await wait_for(func(): return game.net.is_client_ready()),"Lag compensation client joins")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--client-fps="): Engine.max_fps = arg.trim_prefix("--client-fps=").to_int()
	platform()
	await wait_for(func(): return marked("target_ready"))
	await get_tree().create_timer(1.2).timeout
	game.player.equip(3)
	Input.action_press("aim")
	await get_tree().create_timer(.6).timeout
	await get_tree().process_frame
	var target = game.net.proxies[0]
	var direction = (target.position+Vector3.UP*.8-game.player.camera.global_position).normalized()
	game.player.rotation.y = atan2(-direction.x,-direction.z)
	game.player.pitch = asin(direction.y)
	game.player.camera.rotation = Vector3(game.player.pitch,0,0)
	var shots = game.shot_count
	print("AIM_METRICS target=",target.position," origin=",game.player.camera.global_position," scope=",game.player.scope_age," spread=",game.player.current_spread()," view=",game.net.presentation_time," latest=",game.net.latest_server_time)
	game.player.shoot()
	check(game.shot_count==shots+1,"Moving-target shot draws immediately on the client")
	check(await wait_for(func(): return game.kills==1,10),"No manual lead: the target under the crosshair is killed")
	check(game.progression.xp_for("YOU")==100,"Lag-compensated one-shot kill awards confirmed XP")
	Input.action_release("aim")
	mark("client_done")
	await wait_for(func(): return marked("host_done"),20)
