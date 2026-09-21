extends Node
var checks=0
var failures=[]
func check(ok: bool, title: String) -> void:
	checks+=1
	print("PASS " if ok else "FAIL ",title)
	if not ok: failures.append(title)
func run(game: Node) -> void:
	await game.start_mode("training")
	var cached=game.replays.scenery
	game.replays.reset(); game.replays._build_world()
	check(game.replays.scenery==cached,"Round reset reuses prepared scenery instead of rebuilding it at the final kill")
	game.prefs.data.quality=1; game.apply_settings()
	check(game.world_root.find_children("*","DirectionalLight3D",true,false).all(func(light): return light.shadow_enabled),"Medium preset provides world shadows")
	game.prefs.data.quality=0; game.apply_settings()
	check(game.world_root.find_children("*","DirectionalLight3D",true,false).all(func(light): return not light.shadow_enabled),"Low preset remains a shadow-free performance option")
	var p=game.player
	p.set_physics_process(false); p.set_process(false)
	p.reset_at(Vector3(0,10,0))
	check(p.presentation_camera()==game.get_viewport().get_camera_3d(),"Local viewport uses the presentation camera")
	p.view_previous=Vector3(0,10,0); p.view_current=Vector3(.12,10,0); p.position=p.view_current
	var samples=[]
	for fraction in [0.0,.25,.5,.75,1.0]:
		p.update_presentation(1.0/240,fraction)
		samples.append(p.render_camera.global_position.x)
		check(is_equal_approx(p.camera.global_position.x,.12),"Render interpolation leaves authoritative ray origin unchanged")
	check(range(5).all(func(i): return is_equal_approx(samples[i],i*.03)),"A 60 Hz movement step has evenly spaced 240 Hz presentation samples")
	p.rotation.y=.8; p.camera.rotation.x=-.3
	p.update_presentation(.001,.25)
	check(p.render_camera.global_basis.is_equal_approx(p.camera.global_basis),"Mouse rotation is copied immediately without aim smoothing")
	p.set_crouch(true,true); p.update_presentation(1.0/120,.5)
	check(p.view_eye>1 and p.view_eye<1.64,"Crouch view moves gradually on its first rendered frame")
	for i in range(120): p.update_presentation(1.0/120,.5)
	check(absf(p.view_eye-1)<.001,"Crouch settles to the intended eye height")
	p.correction_offset=Vector3(.2,0,0); p.update_presentation(.016,1)
	check(is_equal_approx(p.render_camera.global_position.x,.32) and is_equal_approx(p.camera.global_position.x,.12),"Network correction is cosmetic, never part of the firing camera")
	p.reset_at(Vector3(22,2,-17))
	check(p.render_camera.global_position.is_equal_approx(p.camera.global_position) and p.view_previous==p.view_current,"Respawn resets interpolation without sweeping across the map")
	p.global_position=Vector3(-22,4,17); p.update_presentation(.016,.1)
	check(p.render_camera.global_position.distance_to(p.camera.global_position)<.001,"Large teleports reset presentation history")
	p.set_process(true)
	if "--motion-audit" in OS.get_cmdline_user_args():
		p.reset_at(Vector3(0,10,0)); p.set_physics_process(true)
		Engine.max_fps=240
		Input.action_press("right")
		var body_samples={}; var camera_samples={}; var fractions={}
		for frame in range(160):
			await get_tree().process_frame
			body_samples[snappedf(p.position.x,.0001)]=true
			camera_samples[snappedf(p.render_camera.global_position.x,.0001)]=true
			fractions[snappedf(Engine.get_physics_interpolation_fraction(),.01)]=true
		Input.action_release("right"); p.set_physics_process(false)
		print("MOTION_SAMPLES body=",body_samples.size()," camera=",camera_samples.size()," fractions=",fractions.size())
		check(camera_samples.size()>body_samples.size()*1.3,"Live render loop advances the camera between actual physics steps")
	await game.net.host(27926,"",false,"destroy")
	for actor in game.net.actors(): actor.set_physics_process(false)
	game.net.set_physics_process(false)
	game.replays.reset()
	game.net.destroy.finish(2,"TIME EXPIRED")
	await get_tree().process_frame
	check(game.replays.transitioning() and game.replays.pending_final.is_empty(),"A real no-kill objective round still shows its result")
	check(game.replays.outro_title=="ROUND LOST" and game.replays.outro_scores[2]==1,"No-kill result includes viewer-relative outcome and final scores")
	check(game.net.final_replay_until>game.clock and not game.net.combat_allowed(),"No-kill result reserves a server-controlled combat-free window")
	game.replays._process(game.replays.OUTRO_SECONDS+.01)
	check(not game.replays.transitioning() and not game.replays.active,"No-kill result exits without inventing a replay")
	game.replays.present_result("DRAW",0,true,[0,4,4])
	check(game.replays.outro_title=="GAME DRAW" and game.replays.fade_alpha()==0,"Draw presentation keeps the world visible")
	game.replays.reset()
	check(not game.replays.transitioning(),"Session reset clears the result presentation")
	print("PRESENTATION_RESULT ",checks-failures.size(),"/",checks)
	await game.net.leave()
	get_tree().quit(0 if failures.is_empty() else 1)
