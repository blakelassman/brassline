extends Node
var checks = 0
var failures: Array[String] = []
func check(ok: bool, title: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",title)
	if not ok: failures.append(title)
func run(game: Node) -> void:
	await get_tree().physics_frame
	var mixer = game.audio_mix
	check(game.audio.size()==37,"All 37 gameplay, UI and ambience cues load")
	for key in game.audio:
		check(game.audio[key]!=null and game.audio[key].get_length()>0,"Decoded audio exists: "+key)
	check(mixer.variants.rifle.size()==4 and mixer.variants.step_concrete.size()==4,"Gunfire and footsteps use multiple recorded takes")
	var previous: AudioStream = null
	var repeats = false
	for i in range(30):
		var next = mixer.stream_for(game,"rifle")
		if next==previous: repeats = true
		previous = next
	check(not repeats,"Variant picker avoids consecutive repeated takes")
	var gun = mixer.spatial_profile("rifle")
	var foot = mixer.spatial_profile("step_concrete")
	check(gun.range==180 and gun.unit==18 and foot.range==34,"Gunfire travels across the arena while footsteps remain local")
	check(gun.gain==7,"Remote gunfire gains 7 dB before the new distance curve")
	check(game.sound_pool.size()==28 and game.world_sounds.size()==52,"Audio voice budgets are bounded")
	check(game.drone.stream.loop and game.drone.bus=="Ambience","Continuous drone loops on its own adjustable bus")
	check(AudioServer.get_bus_effect(0,0) is AudioEffectHardLimiter,"Master mix has a peak limiter")
	mixer.test_playback = true
	game.sound("head",-5)
	var head_voice: Node
	for speaker in game.sound_pool:
		if speaker.get_meta("group")=="feedback" and speaker.get_meta("serial")>0: head_voice = speaker
	var head_serial = head_voice.get_meta("serial")
	for i in range(60): game.sound("step_concrete",-21)
	check(head_voice.get_meta("serial")==head_serial,"Local footsteps cannot steal a headshot confirmation")
	game.world_sound("rifle",Vector3(60,1,0),-16,false)
	var shot_voice: Node
	for speaker in game.world_sounds:
		if speaker.get_meta("group")=="weapons" and speaker.get_meta("serial")>0: shot_voice = speaker
	var shot_serial = shot_voice.get_meta("serial")
	for i in range(60): game.world_sound("step_metal",Vector3.ZERO,-27,false)
	check(shot_voice.get_meta("serial")==shot_serial,"World footsteps cannot truncate a gunshot")
	check(shot_voice.global_position==Vector3(60,1,0) and shot_voice.bus=="Weapons" and shot_voice.volume_db==-9,"World shot retains direction and uses the calibrated mix")
	var reserved: Array = []
	for i in range(6):
		var chosen = mixer.voice(game.world_sounds,"weapons")
		reserved.append(chosen.get_instance_id())
	var unique: Dictionary = {}
	for id in reserved: unique[id] = true
	check(unique.size()==6,"Multiple gunshots in one physics tick reserve different voices")
	# Exercise the real remote RPC entry, including the local-prediction exclusion.
	game.net.own_slot = 0
	var before = mixer.serial
	game.net._shot_fx(0,Vector3(1,1,1),Vector3(2,1,1),0)
	check(mixer.serial==before,"Client does not double-play its own predicted gunshot")
	game.net._shot_fx(1,Vector3(3,1,2),Vector3(4,1,2),3)
	check(mixer.serial==before+1,"Remote player's shot creates exactly one spatial voice")
	game.net.own_slot = -1
	var path = "user://audio_settings_test.json"
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"xp":3500,"volume":.42}))
	file.close()
	var prefs = game.Preferences.new(path)
	prefs.load_profile()
	check(prefs.data.xp==3500 and is_equal_approx(prefs.data.volume,.42) and prefs.data.ambience_volume==.35,"Old profiles retain XP/master volume and receive quiet ambience defaults")
	prefs.data.ambience_volume = 0
	prefs.data.weapons_volume = .7
	check(prefs.save(),"New audio settings save")
	var reloaded = game.Preferences.new(path)
	reloaded.load_profile()
	mixer.apply(reloaded.data)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambience")),"Zero ambience fully mutes the drone and map ambience")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Weapons")),"Muting ambience does not mute gameplay sounds")
	check(is_equal_approx(reloaded.data.weapons_volume,.7),"Individual audio levels survive profile reload")
	reloaded.data.volume = 0
	mixer.apply(reloaded.data)
	check(AudioServer.is_bus_mute(0),"Master zero produces a true mute")
	mixer.apply(game.prefs.data)
	for suffix in ["",".bak"]: DirAccess.remove_absolute(path+suffix)
	game.world_sound("sniper",Vector3.ZERO,-16,false)
	var pause_voice: Node
	for speaker in game.world_sounds:
		if speaker.get_meta("serial")==mixer.serial: pause_voice = speaker
	await get_tree().physics_frame
	await get_tree().physics_frame
	game.set_active(false)
	check(pause_voice.stream_paused,"Offline pause suspends a currently playing positional sound")
	game.set_active(true)
	check(not pause_voice.stream_paused,"Resuming restores positional sounds")
	print("AUDIO_RESULT ",checks-failures.size(),"/",checks)
	if failures.is_empty(): await game.quit_game()
	else: fail_quit()
func fail_quit() -> void:
	get_tree().quit(1)
