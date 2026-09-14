extends RefCounted
## Bounded voice pools and one consistent host/client mix. No gameplay RNG is used.
const WEAPONS = ["rifle","pistol","sniper","blast"]
const FEEDBACK = ["head","hit","hurt","kill","achievement","case_tick","case_reveal","ui"]
const BUS_SETTINGS = {"Weapons":"weapons_volume","Effects":"effects_volume","Feedback":"feedback_volume","Ambience":"ambience_volume"}
var variants: Dictionary = {}
var last_variant: Dictionary = {}
var serial = 0
var enabled = true
var test_playback = false

func setup(game: Node) -> void:
	enabled = DisplayServer.get_name()!="headless"
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/catalog.json"))
	for key in catalog:
		variants[key] = []
		for file in catalog[key]:
			var stream = AudioStreamOggVorbis.load_from_file("res://assets/audio/"+file)
			assert(stream!=null,"Missing audio: "+file)
			variants[key].append(stream)
		game.audio[key] = variants[key][0]
	for bus in BUS_SETTINGS:
		if AudioServer.get_bus_index(bus)<0:
			AudioServer.add_bus()
			var index = AudioServer.bus_count-1
			AudioServer.set_bus_name(index,bus)
			AudioServer.set_bus_send(index,"Master")
	# A restrained compressor keeps firefights readable without boosting quiet ambience.
	var weapons_bus = AudioServer.get_bus_index("Weapons")
	if AudioServer.get_bus_effect_count(weapons_bus)==0:
		var compressor = AudioEffectCompressor.new()
		compressor.threshold = -10
		compressor.ratio = 2.0
		compressor.attack_us = 1800
		compressor.release_ms = 90
		AudioServer.add_bus_effect(weapons_bus,compressor)
	if AudioServer.get_bus_effect_count(0)==0:
		var limiter = AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(0,limiter)
	game.ambience = AudioStreamPlayer.new()
	game.ambience.bus = "Ambience"
	game.ambience.volume_db = -19
	game.add_child(game.ambience)
	game.drone = AudioStreamPlayer.new()
	game.drone.bus = "Ambience"
	game.drone.volume_db = -14
	game.add_child(game.drone)
	var drone_stream = game.audio.drone as AudioStreamOggVorbis
	drone_stream.loop = true
	game.drone.stream = drone_stream
	if enabled: game.drone.play()
	game.ui_speaker = AudioStreamPlayer.new()
	game.ui_speaker.bus = "Feedback"
	game.ui_speaker.stream = game.audio.ui
	game.ui_speaker.volume_db = -16
	game.add_child(game.ui_speaker)
	game.audio_rng.seed = 602026
	for group in ["weapons","feedback","foley"]:
		for i in range(12 if group=="weapons" else 8):
			var speaker = AudioStreamPlayer.new()
			speaker.set_meta("group",group)
			speaker.set_meta("serial",0)
			game.add_child(speaker)
			game.sound_pool.append(speaker)
	for group in ["weapons","foley"]:
		for i in range(36 if group=="weapons" else 16):
			var spatial = AudioStreamPlayer3D.new()
			spatial.set_meta("group",group)
			spatial.set_meta("serial",0)
			game.add_child(spatial)
			game.world_sounds.append(spatial)

func apply(data: Dictionary) -> void:
	for bus in BUS_SETTINGS:
		var index = AudioServer.get_bus_index(bus)
		var volume = float(data[BUS_SETTINGS[bus]])
		AudioServer.set_bus_volume_db(index,linear_to_db(maxf(.0001,volume)))
		AudioServer.set_bus_mute(index,volume<=0)
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.0001,float(data.volume))))
	AudioServer.set_bus_mute(0,float(data.volume)<=0)

func stream_for(game: Node, key: String) -> AudioStream:
	var choices: Array = variants[key]
	var index = game.audio_rng.randi_range(0,choices.size()-1)
	if choices.size()>1 and index==last_variant.get(key,-1):
		index = (index+game.audio_rng.randi_range(1,choices.size()-1))%choices.size()
	last_variant[key] = index
	return choices[index]

static func group_for(key: String, spatial: bool) -> String:
	if key in WEAPONS: return "weapons"
	if not spatial and key in FEEDBACK: return "feedback"
	return "foley"

static func bus_for(key: String) -> String:
	if key in WEAPONS: return "Weapons"
	if key in FEEDBACK: return "Feedback"
	return "Effects"

func voice(pool: Array, group: String) -> Node:
	var oldest: Node = null
	for speaker in pool:
		if speaker.get_meta("group")!=group: continue
		if not speaker.playing and Time.get_ticks_usec()>=int(speaker.get_meta("pending_until",0)):
			oldest = speaker
			break
		if oldest==null or speaker.get_meta("serial")<oldest.get_meta("serial"): oldest = speaker
	serial += 1
	oldest.set_meta("serial",serial)
	# 3D playback begins on the next physics frame; reserve voices immediately.
	oldest.set_meta("pending_until",Time.get_ticks_usec()+50000)
	return oldest

static func spatial_profile(key: String) -> Dictionary:
	# max_distance also contributes a linear fade, so leave room beyond the arena.
	if key=="blast": return {"unit":22.0,"range":200.0,"gain":1.0,"cutoff":8000.0,"filter":-8.0}
	if key in WEAPONS: return {"unit":18.0,"range":180.0,"gain":7.0,"cutoff":11000.0,"filter":-7.0}
	if key.begins_with("step"):
		return {"unit":6.0,"range":34.0,"gain":4.0,"cutoff":6500.0,"filter":-12.0}
	return {"unit":6.0,"range":48.0,"gain":2.0,"cutoff":8000.0,"filter":-10.0}

func local(game: Node, key: String, volume: float) -> void:
	if (not enabled and not test_playback) or not variants.has(key): return
	var speaker = voice(game.sound_pool,group_for(key,false)) as AudioStreamPlayer
	speaker.stream = stream_for(game,key)
	speaker.bus = bus_for(key)
	speaker.volume_db = volume+(1.5 if key in WEAPONS else 0.0)
	speaker.pitch_scale = 1.0
	speaker.play()

func spatial(game: Node, key: String, at: Vector3, volume: float) -> void:
	if (not enabled and not test_playback) or not variants.has(key): return
	var speaker = voice(game.world_sounds,group_for(key,true)) as AudioStreamPlayer3D
	var profile = spatial_profile(key)
	speaker.stream = stream_for(game,key)
	speaker.global_position = at
	speaker.bus = bus_for(key)
	speaker.volume_db = volume+profile.gain
	speaker.unit_size = profile.unit
	speaker.max_distance = profile.range
	speaker.max_db = 0.0
	speaker.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	speaker.attenuation_filter_cutoff_hz = profile.cutoff
	speaker.attenuation_filter_db = profile.filter
	speaker.panning_strength = .85
	speaker.pitch_scale = 1.0
	speaker.play()
