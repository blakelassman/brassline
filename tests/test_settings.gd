extends Node
var checks = 0
var failures: Array = []
func check(ok: bool, title: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",title)
	if not ok: failures.append(title)
func run(game: Node) -> void:
	await get_tree().physics_frame
	var path = "user://settings_fixture_"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var p = game.Preferences.new(path)
	p.load_profile()
	p.data.xp = 12000
	p.data.name = "Tester"
	p.data.volume = .4
	p.data.sensitivity = .004
	p.data.quality = 0
	check(p.save(),"Atomic profile save succeeds")
	var loaded = game.Preferences.new(path)
	loaded.load_profile()
	check(loaded.data.xp==12000 and loaded.data.id==p.data.id,"Reload restores XP and stable local identity")
	check(loaded.data.sensitivity==.004 and loaded.data.volume==.4 and loaded.data.quality==0,"Settings reload with original values")
	loaded.data.xp = 13000
	loaded.save()
	var corrupt = FileAccess.open(path,FileAccess.WRITE)
	corrupt.store_string("broken json")
	corrupt.close()
	var recovered = game.Preferences.new(path)
	recovered.load_profile()
	check(recovered.data.xp==12000,"Corrupt primary profile recovers backup")
	p.bind("jump",0,KEY_J)
	check(InputMap.action_has_event("jump",key(KEY_J)),"Rebinding applies physical key")
	p.bind("fire",1,-MOUSE_BUTTON_WHEEL_UP)
	var wheel = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	check(InputMap.action_has_event("fire",wheel),"Scroll wheel can bind to any action")
	p.bind("jump",0,KEY_ESCAPE)
	check(KEY_ESCAPE in p.data.bindings.jump and KEY_J in p.data.bindings.pause,"Taking menu key swaps displaced key to menu")
	p.save()
	loaded = game.Preferences.new(path)
	loaded.load_profile()
	check(KEY_ESCAPE in loaded.data.bindings.jump,"Custom bindings persist on disk")
	game.prefs.apply_bindings()
	await game.start_mode("training")
	game.player.reset_at(Vector3(-15,.05,12))
	game.player.set_physics_process(false)
	game.player.set_crouch(true)
	check(game.player.crouched and is_equal_approx(game.player.body_shape.shape.height,1.1),"Crouch reduces actual capsule height")
	check(is_equal_approx(game.player.hitboxes[1].position.y,1.03),"Head hitbox follows crouch")
	var cover = game.Geo.box(game,Vector3(-15,1.5,12),Vector3(2,.2,2),Color.WHITE,true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	game.player.set_crouch(false)
	check(game.player.crouched,"Cannot stand through a low ceiling")
	cover.free()
	await get_tree().physics_frame
	game.player.set_crouch(false)
	check(not game.player.crouched and is_equal_approx(game.player.body_shape.shape.height,1.8),"Standing resumes when overhead clearance returns")
	game.prefs.data.quality = 0
	game.apply_settings()
	check(game.get_viewport().msaa_3d==Viewport.MSAA_DISABLED,"Low quality disables multisampling")
	game.prefs.data.quality = 2
	game.apply_settings()
	check(game.get_viewport().msaa_3d==Viewport.MSAA_2X,"High quality enables multisampling")
	game.progression.profiles["YOU"] = 14350
	game.save_profile()
	loaded = game.Preferences.new(game.prefs.path)
	loaded.load_profile()
	check(loaded.data.xp==14350,"Game saves live progression to profile")
	print("SETTINGS_RESULT ",checks-failures.size(),"/",checks)
	await game.quit_game()
func key(code: int) -> InputEventKey:
	var event = InputEventKey.new()
	event.physical_keycode = code
	return event
