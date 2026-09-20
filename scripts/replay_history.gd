extends RefCounted
## Bounded server/offline presentation history. No playback code mutates combat.
const Player = preload("res://scripts/player.gd")
const Bot = preload("res://scripts/bot.gd")
const PRE_ROLL = 4.0
const MAX_FRAMES = 96
const MAX_EVENTS = 512
const MAX_PACKET = 131072
const MAX_DECODED = 524288
var frames: Array = []
var events: Array = []
var roster: Dictionary = {}
var timer = 0.0
var serial = 0
var last_clip: Dictionary = {}
var pending: Array = []
func clear() -> void:
	frames.clear(); events.clear(); roster.clear(); pending.clear(); last_clip.clear()
	timer = 0
func actor_id(actor: Node) -> String:
	return str(actor.net_slot) if actor.game.net.running else actor.target_name
func actors(game: Node) -> Array:
	return game.net.actors() if game.net.running else game.combat.actors()
func sample(game: Node, delta: float = 0, force: bool = false) -> void:
	if game.net.running and not game.net.server: return
	if game.mode not in ["combat","online"]: return
	timer += delta
	if not force and timer<.05: return
	timer = fmod(timer,.05)
	var rows: Array = []
	for actor in actors(game):
		if not is_instance_valid(actor): continue
		var id = actor_id(actor)
		var human = actor is Player
		var nickname = game.net.slots[actor.net_slot].name if game.net.running else actor.target_name
		roster[id] = [nickname,actor.team,actor.cosmetics.duplicate() if human else {}]
		var yaw = actor.rotation.y if human else actor.rotation.y+PI
		var pitch = actor.pitch if human else float(actor.get_meta("replay_pitch",0.0))
		rows.append([id,actor.position,yaw,pitch,actor.health,actor.weapon if human else 0,actor.is_aiming() if human else false,actor.crouched if human else false,actor.life_id,actor.velocity.length(),actor.reload_timer if human else actor.reload_time,(1.0 if actor.crouched else 1.64) if human else 1.38,actor.camera.fov if human else 86.0])
	var smokes: Array = []
	for smoke in game.smoke_nodes:
		if is_instance_valid(smoke) and not smoke.is_queued_for_deletion(): smokes.append(smoke.position)
	var grenades: Array = []
	for grenade in game.grenades:
		if is_instance_valid(grenade) and not grenade.is_queued_for_deletion(): grenades.append([grenade.position,grenade.kind])
	var frame = [game.clock,rows,smokes.slice(0,10),grenades.slice(0,20)]
	if not frames.is_empty() and is_equal_approx(frames[-1][0],game.clock): frames[-1] = frame
	else: frames.append(frame)
	while frames.size()>MAX_FRAMES or (frames.size()>2 and frames[1][0]<game.clock-PRE_ROLL-.5): frames.pop_front()
	while not events.is_empty() and events[0][0]<game.clock-PRE_ROLL-.5: events.pop_front()
func shot(game: Node, actor: Node, start: Vector3, end: Vector3, weapon: int) -> void:
	if game.net.running and not game.net.server: return
	var direction = (end-start).normalized()
	if actor is Bot: actor.set_meta("replay_pitch",asin(clampf(direction.y,-1,1)))
	events.append([game.clock,actor_id(actor),start,end,weapon])
	while events.size()>MAX_EVENTS: events.pop_front()
func make_clip(game: Node, kill: Dictionary) -> Dictionary:
	var terminal = kill.frame
	var selected: Array = []
	var killer_life = -1
	var victim_life = -1
	for row in terminal[1]:
		if row[0]==kill.killer: killer_life=row[8]
		if row[0]==kill.victim: victim_life=row[8]
	# Never cross a respawn boundary into the killer's previous life.
	for frame in frames:
		if frame[0]<kill.time-PRE_ROLL or frame[0]>=kill.time: continue
		var found = false
		for row in frame[1]:
			if row[0]==kill.killer and row[8]==killer_life: found=true
		if found: selected.append(frame.duplicate(true))
	selected.append(terminal.duplicate(true))
	if not kill.roster.has(kill.killer): return {}
	serial += 1
	var clip = kill.duplicate(true)
	clip.erase("frame")
	clip.merge({"victim_life":victim_life,"id":serial,"map":game.current_map,"frames":selected,"roster":kill.roster.duplicate(true),"events":events.filter(func(event): return event[0]>=selected[0][0] and event[0]<=kill.time).duplicate(true)},true)
	last_clip = clip
	return clip
static func encode(clip: Dictionary) -> PackedByteArray:
	var raw = var_to_bytes(clip)
	if raw.size()>MAX_DECODED: return PackedByteArray()
	var packed = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	return packed if packed.size()<=MAX_PACKET else PackedByteArray()
static func decode(packed: PackedByteArray) -> Dictionary:
	if packed.size()<8 or packed.size()>MAX_PACKET: return {}
	var raw = packed.decompress_dynamic(MAX_DECODED,FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty(): return {}
	var clip = bytes_to_var(raw)
	if not clip is Dictionary or not clip.get("frames") is Array or clip.frames.is_empty() or clip.frames.size()>MAX_FRAMES: return {}
	if not clip.get("roster") is Dictionary or clip.roster.size()>10 or not clip.get("events") is Array or clip.events.size()>MAX_EVENTS: return {}
	if not clip.has_all(["id","map","time","killer","victim","victim_life","weapon","head"]): return {}
	for frame in clip.frames:
		if not frame is Array or frame.size()!=4 or not frame[1] is Array or frame[1].size()>10: return {}
		for row in frame[1]:
			if not row is Array or row.size()!=13 or not row[1] is Vector3 or not row[1].is_finite(): return {}
	return clip
