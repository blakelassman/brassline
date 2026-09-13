extends "res://tests/test_network.gd"
func run(g: Node) -> void:
	game = g
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--join-port="): join_port = arg.trim_prefix("--join-port=").to_int()
		if arg.begins_with("--coord="): root = arg.trim_prefix("--coord=")+"/"
	if "--role=host" in OS.get_cmdline_user_args(): await host_prediction()
	else: await client_prediction()
	print("PREDICTION_RESULT ",checks-failures.size(),"/",checks)
	if game.net.running: await game.net.leave()
	await game.quit_game()
func platform() -> void:
	var floor_body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(100,1,100)
	floor_body.add_child(shape)
	game.add_child(floor_body)
	floor_body.position = Vector3(0,29.5,0)
func host_prediction() -> void:
	check(await game.net.host(27917,"test-only",false),"Prediction host starts")
	freeze_bots()
	platform()
	game.player.set_physics_process(false)
	mark("host")
	check(await wait_for(func(): return game.net.peers.size()==2),"Prediction client joins")
	var remote_id = 0
	for id in game.net.peers:
		if id!=1: remote_id = id
	if remote_id==0: return
	var actor = game.net.slots[game.net.peers[remote_id].slot].actor
	actor.life_id += 1
	actor.reset_at(Vector3(0,30.01,0))
	game.net._spawn.rpc_id(remote_id,actor.position,actor.life_id)
	mark("ready")
	await wait_for(func(): return marked("stopped"),20)
	await get_tree().create_timer(1).timeout
	mark("server_position",var_to_str(actor.position))
	print("SERVER_MOVE_METRICS pos=",actor.position," ack=",actor.last_input_sequence," received=",game.net.peers[remote_id].last_sequence," gaps=",game.net.peers[remote_id].frame_gap," Hz=",game.net.server_tick_rate)
	check(actor.position.x>10 and actor.position.x<16,"Server movement stays within expected two-second run distance")
	await wait_for(func(): return marked("jump"))
	var apex = actor.position.y
	var deadline = Time.get_ticks_msec()+2500
	while Time.get_ticks_msec()<deadline:
		apex = maxf(apex,actor.position.y)
		await get_tree().physics_frame
	mark("server_apex",str(apex))
	check(apex>31,"Server receives jump under loss")
	await wait_for(func(): return marked("done"),30)
	await get_tree().create_timer(.6).timeout
	# Exercise the same validated receiver with invalid/stale and over-speed input.
	actor.set_physics_process(false)
	var peer = game.net.peers[remote_id]
	peer.frames.clear()
	var seq = peer.last_sequence
	game.net._receive_frames(peer,actor.life_id-1,[[seq+1,Vector2.RIGHT,false,false,0.0,false,0.0,false]])
	game.net._receive_frames(peer,actor.life_id,[[seq+1,Vector2(NAN,0),false,false,0.0,false,0.0,false]])
	game.net._receive_frames(peer,actor.life_id,[[seq+1,"bad",false,false,0.0,false,0.0,false]])
	check(peer.frames.is_empty() and peer.last_sequence==seq,"Stale-life and malformed inputs cannot move the server player")
	var ack = actor.last_input_sequence
	var frames: Array = []
	for n in range(1,13): frames.append([seq+n,Vector2(99,0),false,false,0.0,false,0.0,false])
	game.net._receive_frames(peer,actor.life_id,frames)
	check(actor.last_input_sequence==ack,"Receiving input does not prematurely acknowledge simulation")
	check(peer.frames.size()==12 and peer.frames[0][1].length()<=1,"Movement input is normalized and bounded")
	peer.move_credit = 0
	await get_tree().physics_frame
	game.net.simulate_remote(actor,1.0/60)
	check(actor.last_input_sequence==seq+1 and peer.frames.size()==11,"Flooding twelve inputs earns only one tick of movement")
	mark("host_done")
func client_prediction() -> void:
	await wait_for(func(): return marked("host"))
	game.net.join("127.0.0.1",join_port,"test-only")
	check(await wait_for(func(): return game.net.is_client_ready()),"Prediction client connects")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--client-fps="): Engine.max_fps = arg.trim_prefix("--client-fps=").to_int()
	platform()
	await wait_for(func(): return marked("ready"))
	await get_tree().create_timer(1).timeout
	var start_time = Time.get_ticks_msec()
	var start = game.player.position
	var last = start
	var rollback = 0.0
	var old_corrections = game.net.corrections
	Input.action_press("right")
	for frame in range(120):
		await get_tree().physics_frame
		if frame==2: check(game.player.position.x>start.x+.02,"Local movement begins within two physics ticks")
		rollback = maxf(rollback,last.x-game.player.position.x)
		last = game.player.position
	Input.action_release("right")
	print("CLIENT_TIMING ms=",Time.get_ticks_msec()-start_time," fps=",Engine.get_frames_per_second()," throttle=",game.multiplayer.multiplayer_peer.get_peer(1).get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE))
	print("PREDICTION_METRICS distance=",last.x-start.x," max_rollback=",rollback," corrections=",game.net.corrections-old_corrections)
	check(rollback<.05,"Straight movement has no visible backward corrections")
	mark("stopped")
	await wait_for(func(): return marked("server_position"))
	var server_at = str_to_var(FileAccess.get_file_as_string(root+"server_position"))
	check(game.player.position.distance_to(server_at)<.12,"Client settles within 12 cm of server")
	mark("jump")
	game.player.jump_requested = true
	game.player.network_action("jump")
	var apex = game.player.position.y
	for frame in range(150):
		await get_tree().physics_frame
		apex = maxf(apex,game.player.position.y)
		if frame==2: check(game.player.position.y>30.1,"Jump begins locally without waiting for server")
	await wait_for(func(): return marked("server_apex"))
	var server_apex = FileAccess.get_file_as_string(root+"server_apex").to_float()
	print("JUMP_METRICS client_apex=",apex," server_apex=",server_apex)
	check(absf(apex-server_apex)<.15,"Jump prediction matches server within 15 cm")
	# Aim, crouch, counter-strafe and a jump use the same frame history during replay.
	var old_count = game.net.corrections
	Input.action_press("aim")
	Input.action_press("left")
	for frame in range(60):
		if frame==12: Input.action_press("crouch")
		if frame==24:
			Input.action_release("left")
			Input.action_press("right")
		if frame==36:
			Input.action_release("crouch")
			Input.action_release("aim")
			game.player.jump_requested = true
		await get_tree().physics_frame
	Input.action_release("right")
	await get_tree().create_timer(.6).timeout
	check(game.net.corrections-old_count<=1,"Aim/crouch/counter-strafe/air movement survive delayed reconciliation")
	game.player.equip(3)
	await get_tree().create_timer(.35).timeout
	Input.action_press("aim")
	await get_tree().create_timer(.2).timeout
	var shots = game.shot_count
	var ammo = game.player.ammo[3]
	game.player.shoot()
	check(game.shot_count==shots+1 and game.player.ammo[3]==ammo-1 and game.player.visual_kick>0,"Shot tracer, recoil and ammo respond before a server reply")
	check(game.player.is_aiming() and game.player.scope_age>=game.Rules.SCOPE_READY,"Sniper stays scoped after its predicted shot")
	await get_tree().create_timer(.6).timeout
	check(game.player.ammo[3]==ammo-1,"Shot acknowledgement neither refunds nor double-spends ammo")
	game.player.start_reload()
	check(game.player.reload_timer>0,"Reload begins locally without a round trip")
	await get_tree().create_timer(2.5).timeout
	check(game.player.reload_timer==0 and game.player.ammo[3]==6,"Predicted reload settles to server's six-round magazine")
	Input.action_release("aim")
	game.player.equip_grenade("smoke")
	await get_tree().create_timer(.25).timeout
	var hp = game.player.health
	game.player.throw_grenade("smoke",true)
	var predicted_id = game.net.action_id
	check(game.net.predicted_grenades.has(predicted_id),"Grenade appears on the throwing frame")
	var visual = game.net.predicted_grenades.get(predicted_id)
	check(await wait_for(func(): return not game.net.predicted_grenades.has(predicted_id),1),"Server confirms predicted grenade")
	check(is_instance_valid(visual) and visual in game.net.grenade_views.values(),"Confirmation reuses the visual instead of duplicating the grenade")
	check(game.player.health==hp,"Cosmetic grenade prediction never changes health")
	# A duplicate spawn packet must not reset locally predicted movement/look.
	var old_position = game.player.position
	var old_sequence = game.net.sequence
	game.net._spawn(Vector3(999,999,999),game.player.life_id)
	check(game.player.position==old_position and game.net.sequence==old_sequence,"Duplicate respawn messages do not reset the current life")
	var proxy = game.net.proxies.values()[0]
	proxy.set_process(false)
	proxy.samples = [{"time":10.0,"position":Vector3.ZERO,"velocity":Vector3.RIGHT,"yaw":0.0},{"time":10.05,"position":Vector3(.05,0,0),"velocity":Vector3.RIGHT,"yaw":0.0}]
	game.net.presentation_time = 10.09
	proxy._process(0)
	check(absf(proxy.position.x-.09)<.001,"Remote movement extrapolates beyond the newest sample without freezing")
	game.net.presentation_time = 11.0
	proxy._process(0)
	check(proxy.position.x<=.131,"Remote extrapolation stops after 80 ms rather than running through the map")
	game.net.presentation_ready = false
	proxy.set_process(true)
	game.player.set_physics_process(false)
	mark("done")
	await wait_for(func(): return marked("host_done"))
