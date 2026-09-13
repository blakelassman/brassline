extends Node
## Offline team skirmish coordination, ground routing and four spawn zones.
const Bot = preload("res://scripts/bot.gd")
const Geo = preload("res://scripts/geo.gd")
const SPAWNS = [Vector3(-27,.05,25),Vector3(27,.05,25),Vector3(-27,.05,-25),Vector3(27,.05,-25)]
var game: Node3D
var bots: Array[CharacterBody3D] = []
var spawn_candidates: Array = []
var navigation = AStar3D.new()
var node_ids: Dictionary = {}
var markers: Node3D
var scores = [0,0,0]
var deaths = 0
var last_killer = ""
var rng = RandomNumberGenerator.new()
var bot_shots = 0
var bot_damage = 0
var respawns = 0

func _ready() -> void:
	rng.seed = 3032026

func actors() -> Array:
	if game.net.running and game.net.server: return game.net.actors()
	var result: Array = bots.duplicate()
	result.append(game.player)
	return result

func build_navigation() -> void:
	if navigation.get_point_count()>0:
		return
	for x in range(39):
		for z in range(37):
			var pos = Vector3(-28.5+x*1.5,.05,-27+z*1.5)
			if not free_space(pos):
				continue
			var id = x*100+z
			navigation.add_point(id,pos)
			node_ids[Vector2i(x,z)] = id
	for cell in node_ids:
		for offset in [Vector2i(1,0),Vector2i(0,1)]:
			var other = cell+offset
			if node_ids.has(other):
				var a = navigation.get_point_position(node_ids[cell])
				var b = navigation.get_point_position(node_ids[other])
				# Midpoint clearance catches thin walls between grid cells.
				if free_space((a+b)*.5):
					navigation.connect_points(node_ids[cell],node_ids[other])

	# Explicit elevation routes follow the same ramp surfaces used by player collision.
	for route in game.world_root.get_meta("upper_routes",[]):
		var previous = navigation.get_closest_point(route[0])
		for point in route:
			var id = navigation.get_available_point_id()
			navigation.add_point(id,point)
			navigation.connect_points(previous,id)
			previous = id

func free_space(pos: Vector3) -> bool:
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = .48
	shape.height = 1.8
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,pos+Vector3.UP*.93)
	query.collision_mask = 1
	return game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func path_between(from: Vector3, to: Vector3) -> PackedVector3Array:
	if navigation.get_point_count()==0:
		return PackedVector3Array()
	return navigation.get_point_path(navigation.get_closest_point(from),navigation.get_closest_point(to))

func patrol_goal() -> Vector3:
	# Combat patrols concentrate on the playable yard, rather than staying in corners.
	var ids = navigation.get_point_ids()
	if ids.is_empty(): return Vector3.ZERO
	var point = navigation.get_point_position(ids[rng.randi_range(0,ids.size()-1)])
	for i in range(8):
		if absf(point.x)<14 and absf(point.z)<12:
			break
		point = navigation.get_point_position(ids[rng.randi_range(0,ids.size()-1)])
	return point

func start() -> void:
	build_navigation()
	scores = [0,0,0]
	deaths = 0
	bot_shots = 0
	bot_damage = 0
	respawns = 0
	markers = Node3D.new()
	game.add_child(markers)
	for i in range(SPAWNS.size()):
		Geo.box(markers,SPAWNS[i],Vector3(3,.03,3),Color("5f8990"))
	game.player.health = 0
	game.player.reset_at(choose_spawn(1,game.player))
	game.player.rotation.y = atan2(game.player.position.x,game.player.position.z)
	for i in range(9):
		var bot = Bot.new()
		bot.game = game
		bot.combat = self
		bot.team = 1 if i<4 else 2
		bot.target_name = ("ALLY %d" % (i+1)) if i<4 else ("ENEMY %d" % (i-3))
		bot.bot_index = i
		bot.position = choose_spawn(bot.team,bot)
		game.add_child(bot)
		bots.append(bot)
		game.targets.append(bot)

func stop() -> void:
	for bot in bots:
		bot.set_physics_process(false)
		bot.collision_layer = 0
		for area in bot.hitboxes:
			area.collision_layer = 0
		bot.queue_free()
	bots.clear()
	if is_instance_valid(markers):
		markers.queue_free()

func spawn_score(pos: Vector3, team: int, ignore: Node) -> float:
	var score = 0.0
	var nearest_enemy = 35.0
	for actor in actors():
		if actor == ignore or not is_instance_valid(actor) or actor.health<=0:
			continue
		var distance = pos.distance_to(actor.global_position)
		if actor.team != team:
			nearest_enemy = minf(nearest_enemy,distance)
			if distance < 8:
				score -= 160
			if game.unobstructed(pos+Vector3.UP,actor.global_position+Vector3.UP):
				score -= 28.0*clampf(1.0-distance/40.0,0,1)
		else:
			if distance < 13:
				score += 7
		if distance < 5:
			score -= 14
		if distance < 1.2:
			score -= 1000
	return score+nearest_enemy*2.5

func choose_spawn(team: int, ignore: Node) -> Vector3:
	var best = SPAWNS[0 if team==1 else 3]
	var best_score = -INF
	if spawn_candidates.is_empty():
		for i in range(SPAWNS.size()):
			for offset in [Vector3.ZERO,Vector3(1.3,0,0),Vector3(-1.3,0,0),Vector3(0,0,1.3),Vector3(0,0,-1.3),Vector3(1.3,0,1.3)]:
				var point = SPAWNS[i]+offset
				if free_space(point): spawn_candidates.append([i,point])
	for entry in spawn_candidates:
		var i = entry[0]
		var point = entry[1]
		var score = spawn_score(point,team,ignore)
		if (team==1 and i<2) or (team==2 and i>=2): score += .5
		if score>best_score:
			best_score = score
			best = point
	return best

func player_died(killer: String, killer_team: int) -> void:
	deaths += 1
	last_killer = killer
	game.action_serial += 1
	game.record_kill("YOU","RIFLE",false,false,game.action_serial,killer,killer_team)
	respawn_player.call_deferred()

func respawn_player() -> void:
	if game.mode not in ["combat","online"] or game.player.health>0:
		return
	game.player.reset_at(choose_spawn(1,game.player))
	game.player.rotation.y = atan2(game.player.position.x,game.player.position.z)
	game.player.fire_blocked_until_release = true
	respawns += 1

func sight_clear(origin: Vector3, destination: Vector3) -> bool:
	if not game.unobstructed(origin,destination):
		return false
	var segment = destination-origin
	var length_sq = segment.length_squared()
	for smoke in game.smoke_nodes:
		if not is_instance_valid(smoke) or smoke.is_queued_for_deletion():
			continue
		var center = smoke.global_position+Vector3.UP*.5
		var t = clampf((center-origin).dot(segment)/maxf(length_sq,.001),0,1)
		if (origin+segment*t).distance_to(center)<2.65:
			return false
	return true

func shoot_bot(bot: CharacterBody3D, aim_point: Vector3) -> void:
	if bot.health<=0 or game.mode not in ["combat","online"]:
		return
	game.radar.mark(bot,game.clock)
	bot_shots += 1
	var origin = bot.global_position+Vector3.UP*1.38
	var direction = (aim_point-origin).normalized()
	var right = direction.cross(Vector3.UP).normalized()
	var up = right.cross(direction).normalized()
	var angle = bot.rng.randf()*TAU
	var spread = tan(deg_to_rad(bot.profile.spread))*sqrt(bot.rng.randf())
	direction = (direction+right*cos(angle)*spread+up*sin(angle)*spread).normalized()
	var query = PhysicsRayQueryParameters3D.create(origin,origin+direction*40,1|8)
	query.collide_with_areas = true
	var excluded: Array[RID] = []
	for area in bot.hitboxes:
		excluded.append(area.get_rid())
	query.exclude = excluded
	var hit = game.get_world_3d().direct_space_state.intersect_ray(query)
	var end = origin+direction*40
	if not hit.is_empty():
		end = hit.position
		var victim = game.player if hit.collider == game.player else (hit.collider.get_meta("target") if hit.collider.has_meta("target") else null)
		if victim != null and victim.health>0 and victim.team!=bot.team:
			var before = victim.health
			var killed = game.damage_actor(victim,25,bot.team,bot.target_name)
			bot_damage += before-victim.health
			if killed and (game.net.running or victim != game.player):
				game.action_serial += 1
				game.record_kill(victim.target_name,"RIFLE",false,false,game.action_serial,bot.target_name,bot.team)
	game._tracer(origin+direction*.45,end,Color("73d5df") if bot.team==1 else Color("ff9772"))
	if game.net.running: game.net.shot_fx(bot.net_slot,origin,end,0)
	bot.muzzle_time = .065
	game.world_sound("rifle",origin,-16)
