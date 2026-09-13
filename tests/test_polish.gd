extends Node
const Rules = preload("res://scripts/rules.gd")
var checks = 0
var failures: Array[String] = []
class Guard:
	extends CharacterBody3D
	var health = 100
	var team = 2
	var target_name = "GUARD"
	var life_id = 1
	var parry_timer = .28
	func take_damage(amount: int, source_team: int) -> bool:
		if source_team==team: return false
		health = maxi(0,health-amount)
		return health==0
func check(value: bool, title: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ",title)
	if not value: failures.append(title)
func frames(n: int) -> void:
	for i in range(n): await get_tree().physics_frame
	await get_tree().process_frame
func run(game: Node) -> void:
	await frames(3)
	game.set_active(true)
	var p = game.player
	p.set_physics_process(false)
	var mouse = InputEventMouseMotion.new()
	mouse.relative = Vector2(15,8)
	var screen_motion: Array = []
	for fov in [86.0,70.0,59.0,32.0]:
		p.rotation.y = 0
		p.pitch = 0
		p.camera.fov = fov
		p._unhandled_input(mouse)
		screen_motion.append(absf(p.rotation.y)/tan(deg_to_rad(fov*.5)))
	check(absf(screen_motion.max()-screen_motion.min())<.000001,"Mouse input maintains projected sensitivity throughout scope transition")
	var first = Rules.ground_move(Vector2(7.5,0),Vector2.LEFT,7.5,1.0/60)
	check(first.x>5 and first.x<7.5,"Counter-strafe retains a small amount of first-frame momentum")
	var motion = Vector2(7.5,0)
	for i in range(6): motion = Rules.ground_move(motion,Vector2.LEFT,7.5,1.0/60)
	check(motion.x<0,"Counter-strafe still reverses direction within 100 ms")
	var old_targets = game.targets.duplicate()
	game.targets.clear()
	var guard = Guard.new()
	game.add_child(guard)
	guard.position = Vector3(0,30,-1.5)
	guard.rotation.y = PI
	game.targets.append(guard)
	p.reset_at(Vector3(0,30,0))
	p.weapon = 2
	p.rotation = Vector3.ZERO
	p.camera.rotation = Vector3.ZERO
	game.melee_attack(p)
	check(guard.health==100 and p.fire_cooldown>=.8,"Frontal timed parry blocks a live sword hit and adds recovery")
	guard.rotation.y = 0
	game.melee_attack(p)
	check(guard.health==0,"Sword kills a full-health opponent through a rear-facing parry")
	guard.health = 100
	guard.parry_timer = 0
	guard.rotation.y = PI
	game.melee_attack(p)
	check(guard.health==0,"Unparried sword attack is one shot, one kill")
	guard.health = 100
	guard.team = 1
	game.melee_attack(p)
	check(guard.health==100,"Sword preserves friendly-fire protection")
	p.fire_cooldown = 0
	p.equip_cooldown = 0
	p.start_parry()
	check(p.parry_timer==.28 and p.parry_cooldown==.75,"Right-click guard has a bounded active window and recovery")
	p.parry_timer = 0
	p.start_parry()
	check(p.parry_timer==0,"Repeated parry input cannot bypass cooldown")
	p.reset_at(Vector3(0,30,0))
	check(p.parry_timer==0 and p.parry_cooldown==0,"Respawn clears the previous life's guard state")
	var radar = game.radar
	guard.team = 2
	guard.health = 100
	check(radar.contacts([p,guard],1,100).size()==1,"Silent enemy is absent from radar; teammate remains visible")
	radar.mark(guard,100)
	var shot_position = guard.position
	guard.position.x += 5
	var contacts = radar.contacts([p,guard],1,100.5)
	check(contacts.size()==2 and contacts[1][0]==shot_position,"Enemy ping records last shot location instead of tracking movement")
	check(radar.contacts([p,guard],1,102.1).size()==1,"Enemy firing ping expires after two seconds")
	radar.mark(guard,103)
	guard.life_id += 1
	check(radar.contacts([p,guard],1,103.1).size()==1,"A respawn cannot reuse an old-life enemy ping")
	guard.queue_free()
	game.targets.assign(old_targets)
	var prefs = game.Preferences.new("user://polish_settings.json")
	prefs.data.fullscreen = true
	prefs.data.resolution_width = 2560
	prefs.data.resolution_height = 1440
	check(prefs.save(),"Display preferences can be saved")
	var loaded = game.Preferences.new(prefs.path)
	loaded.load_profile()
	check(loaded.data.fullscreen and loaded.data.resolution_width==2560 and loaded.data.resolution_height==1440,"Fullscreen and 1440p resolution survive profile reload")
	DirAccess.remove_absolute(prefs.path)
	DirAccess.remove_absolute(prefs.path+".bak")
	for index in range(4):
		await game.start_mode("training",index)
		await frames(3)
		p.set_physics_process(false)
		check(game.world_root.get_meta("upper_routes",[]).size()==2,game.Maps.NAMES[index]+": two accessible upper-floor routes")
		var routes = game.world_root.get_meta("upper_routes",[])
		for route in routes:
			p.set_physics_process(true)
			p.reset_at(route[0])
			var direction = route[1]-route[0]
			p.rotation.y = atan2(-direction.x,-direction.z)
			Input.action_press("forward")
			for tick in range(120):
				await frames(1)
				if p.position.y>=3.15: break
			Input.action_release("forward")
			check(p.position.y>=3.15,"Actual player movement climbs the smooth stair collider")
			print("STAIR ",route[0]," -> ",p.position)
			p.set_physics_process(false)
			var top = route[-1]
			var roof = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(top+Vector3.UP*6,top,1))
			check(not roof.is_empty() and absf(roof.position.y-6.4)<.05,"Building roof is solid and within grenade-jump height")
			check(game.combat.free_space(top),"Upper floor has full standing capsule clearance")
		check(game.radar.shots.is_empty() and game.radar.remote.is_empty(),"Changing map clears radar contacts")
	check(game.audio.has("parry") and game.audio.parry.get_length()>.3,"Original steel parry sound loads")
	print("POLISH_RESULT ",checks-failures.size(),"/",checks)
	get_tree().quit(0 if failures.is_empty() else 1)
