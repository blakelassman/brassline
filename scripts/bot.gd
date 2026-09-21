extends "res://scripts/target.gd"
## Moderate rifle bot: visible targets, reaction delay, bursts and ground navigation.
const PROFILES = [
	{"name":"ASSAULT","speed":4.2,"strafe":2.0,"near":5.0,"range":16.0,"spread":2.2,"reaction":.6,"burst":3,"cadence":.30},
	{"name":"FLANKER","speed":5.2,"strafe":2.8,"near":4.0,"range":11.0,"spread":2.8,"reaction":.72,"burst":2,"cadence":.27},
	{"name":"MARKSMAN","speed":3.4,"strafe":1.1,"near":10.0,"range":24.0,"spread":1.4,"reaction":.82,"burst":2,"cadence":.46}]
var net_slot = -1
var peer_id = 0
var life_id = 1
var profile: Dictionary = PROFILES[0]
var role_id = 0
var step_clock = 0.0
var combat: Node
var bot_index = 0
var rng = RandomNumberGenerator.new()
var opponent: Node3D
var reaction = 0.0
var scan_timer = 0.0
var shot_timer = 0.0
var burst = 0
var rounds = 24
var reload_time = 0.0
var path = PackedVector3Array()
var path_cursor = 0
var route_timer = 0.0
var wall_stall=0.0
var goal = Vector3.ZERO
var seen_position = Vector3.ZERO
var memory_time = 0.0
var strafe_sign = 1.0
var strafe_timer = 0.0
var muzzle: MeshInstance3D
var muzzle_time = 0.0
var weapon_node: Node3D

func _ready() -> void:
	role_id = (bot_index if team==1 else bot_index-4)%3
	profile = PROFILES[role_id]
	visual_variant = role_id
	super._ready()
	rng.seed = 8200+bot_index*379
	collision_mask = 1|2|4
	reaction = rng.randf_range(profile.reaction,profile.reaction+.35)
	scan_timer = bot_index*.025
	goal = combat.patrol_goal()
	weapon_node = Node3D.new()
	rig.root.add_child(weapon_node)
	var gun = preload("res://scripts/weapon_art.gd").world(weapon_node,0)
	gun.position = Vector3(.28,1.1,.32)
	gun.rotation.y = PI
	muzzle = Geo.sphere(weapon_node,Vector3(.28,1.1,.87),.10,Color("ffeac0"))
	muzzle.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle.visible = false

func take_damage(amount: int, source_team: int) -> bool:
	var killed = super.take_damage(amount,source_team)
	if killed:
		dead_time = 0.0
		opponent = null
		if not game.net.is_destroy(): reset.call_deferred()
	return killed

func reset() -> void:
	if game.mode not in ["combat","online"] or is_queued_for_deletion():
		return
	life_id += 1
	if has_meta("replacement_inventory"): remove_meta("replacement_inventory")
	anchor = combat.choose_spawn(team,self)
	super.reset()
	reaction = rng.randf_range(profile.reaction,profile.reaction+.35)
	shot_timer = .5
	burst = 0
	rounds = 24
	reload_time = 0
	muzzle_time=0
	if is_instance_valid(muzzle): muzzle.hide()
	if is_instance_valid(weapon_node): weapon_node.rotation=Vector3.ZERO
	opponent = null
	memory_time = 0
	path.clear()
	route_timer = 0
	wall_stall=0
	goal = combat.patrol_goal()
	combat.respawns += 1

func _physics_process(delta: float) -> void:
	presentation.begin_tick(global_transform)
	if not game.active or (game.net.running and not game.net.combat_allowed()) or game.mode not in ["combat","online"]:
		return
	if health<=0:
		return
	time += delta
	muzzle_time = maxf(0,muzzle_time-delta)
	muzzle.visible = muzzle_time>0
	title.text = game.net.display_name(target_name) if game.net.running else target_name
	title.visible = team==game.player.team and global_position.distance_to(game.player.global_position)<18 and combat.sight_clear(game.player.camera.global_position,global_position+Vector3.UP*1.7)
	shot_timer = maxf(0,shot_timer-delta)
	memory_time = maxf(0,memory_time-delta)
	if reload_time>0:
		reload_time = maxf(0,reload_time-delta)
		if reload_time==0:
			rounds = 24
	scan_timer -= delta
	if scan_timer<=0:
		scan_timer = .20
		acquire_target()
	var visible_enemy = is_instance_valid(opponent) and opponent.health>0 and combat.sight_clear(global_position+Vector3.UP*1.38,opponent.global_position+Vector3.UP*1.05)
	var movement = Vector3.ZERO
	var objective = game.net.destroy if game.net.is_destroy() else null
	var interacting = objective!=null and (objective.holding(net_slot) or objective.bot_wants(self))
	var urgent = objective!=null and objective.bot_priority(self)
	if visible_enemy and not interacting:
		seen_position = opponent.global_position
		memory_time = 2.0
		reaction = maxf(0,reaction-delta)
		var offset = opponent.global_position-global_position
		offset.y = 0
		var distance = offset.length()
		if distance>.05:
			rotation.y=lerp_angle(rotation.y,atan2(offset.x,offset.z),1-exp(-12*delta))
		strafe_timer -= delta
		if strafe_timer<=0:
			strafe_timer = rng.randf_range(.8,1.6)
			strafe_sign = -1.0 if rng.randf()<.5 else 1.0
		if distance>profile.range:
			var destination = seen_position
			if role_id==1: destination += Vector3(offset.z,0,-offset.x).normalized()*strafe_sign*5
			movement = route_toward(destination,delta)
		else:
			movement = Vector3(offset.z,0,-offset.x).normalized()*strafe_sign*profile.strafe
			if distance<profile.near or reload_time>0:
				movement -= offset.normalized()*1.4
		if urgent: movement = route_toward(objective.bot_goal(self),delta)
		if reaction<=0 and shot_timer<=0 and reload_time<=0 and global_basis.z.dot(offset.normalized())>.90:
			combat.shoot_bot(self,opponent.global_position+Vector3.UP*1.02)
			rounds -= 1
			burst += 1
			shot_timer = profile.cadence if burst<profile.burst else rng.randf_range(.65,1.0)
			if burst>=profile.burst:
				burst = 0
			if rounds<=0:
				reload_time = 1.8
				game.world_sound("mag_out",global_position,-25)
	else:
		reaction = rng.randf_range(profile.reaction,profile.reaction+.35)
		if objective!=null:
			goal = objective.bot_goal(self)
		elif memory_time>0:
			goal = seen_position
		elif global_position.distance_to(goal)<2 or path.is_empty():
			goal = combat.patrol_goal()
		movement = route_toward(goal,delta)
		if movement.length()>.1:
			rotation.y=lerp_angle(rotation.y,atan2(movement.x,movement.z),1-exp(-10*delta))
	if interacting: movement = Vector3.ZERO
	# Local separation prevents a group from choosing the same walking line.
	for actor in combat.actors():
		if interacting or actor == self or actor.health<=0 or absf(actor.global_position.y-global_position.y)>1.5:
			continue
		var away = global_position-actor.global_position
		away.y = 0
		var distance = away.length()
		if distance>0.01 and distance<1.3:
			movement += away.normalized()*(1.3-distance)*4
	velocity.x = move_toward(velocity.x,movement.x,18*delta)
	velocity.z = move_toward(velocity.z,movement.z,18*delta)
	velocity.y -= 24*delta
	move_and_slide()
	presentation.end_tick(global_transform)
	if is_on_wall() and movement.length_squared()>.25:
		wall_stall+=delta
		if wall_stall>=.25:
			strafe_sign *= -1
			route_timer=0
			wall_stall=0
	else:
		wall_stall=0
	impact_pose = maxf(0,impact_pose-delta*4)
	step_clock += delta*Vector2(velocity.x,velocity.z).length()
	if step_clock>2.2 and is_on_floor():
		step_clock = 0
		game.world_sound("step_"+game.surface_at(global_position),global_position,-27)

func animate_pose(delta: float) -> void:
	Rig.animate(rig,presentation_speed(),pose_clock,impact_pose,reload_time,muzzle_time,true)
	weapon_node.rotation.x=lerpf(weapon_node.rotation.x,-muzzle_time*.7,1-exp(-25*delta))
	weapon_node.rotation.z=lerpf(weapon_node.rotation.z,sin(reload_time*3)*.15 if reload_time>0 else 0.0,1-exp(-18*delta))

func acquire_target() -> void:
	var best: Node3D = null
	var nearest = 32.0
	for actor in combat.actors():
		if actor == self or actor.health<=0 or actor.team==team:
			continue
		var distance = global_position.distance_to(actor.global_position)
		if distance<nearest and combat.sight_clear(global_position+Vector3.UP*1.38,actor.global_position+Vector3.UP*1.05):
			nearest = distance
			best = actor
	if best != opponent:
		reaction = rng.randf_range(profile.reaction,profile.reaction+.35)
	opponent = best

func route_toward(destination: Vector3, delta: float) -> Vector3:
	route_timer -= delta
	if route_timer<=0:
		route_timer = .8+rng.randf()*.35
		path = combat.path_between(global_position,destination)
		path_cursor = 1 if path.size()>1 else 0
		# Skip grid corners only when the full standing capsule has a clear route.
		# Elevated waypoints remain explicit so a shortcut cannot bypass a ramp.
		for index in range(mini(path.size()-1,path_cursor+4),path_cursor,-1):
			if absf(path[index].y-global_position.y)>.15: continue
			var query=PhysicsShapeQueryParameters3D.new()
			var shape=CapsuleShape3D.new(); shape.radius=.38; shape.height=1.8
			query.shape=shape; query.collision_mask=1
			query.transform=Transform3D(Basis.IDENTITY,global_position+Vector3.UP*.93)
			query.motion=path[index]-global_position; query.motion.y=0
			var sweep=get_world_3d().direct_space_state.cast_motion(query)
			if sweep.size()==2 and sweep[0]>=.999:
				path_cursor=index; break
	while path_cursor<path.size() and Vector2(path[path_cursor].x-position.x,path[path_cursor].z-position.z).length()<.35:
		path_cursor += 1
	if path_cursor>=path.size():
		return Vector3.ZERO
	var offset = path[path_cursor]-global_position
	offset.y = 0
	return offset.normalized()*profile.speed
