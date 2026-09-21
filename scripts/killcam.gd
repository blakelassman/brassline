extends Node
## Render-only ghosts in a separate World3D. The actual match never rewinds.
const History = preload("res://scripts/replay_history.gd")
const Geo = preload("res://scripts/geo.gd")
const Rig = preload("res://scripts/rig.gd")
const Art = preload("res://scripts/weapon_art.gd")
const Collection = preload("res://scripts/cosmetics.gd")
const AFTER_HIT = .65
const SLOW_WINDOW = .65
const SLOW_RATE = .25
const REGULAR_PRE_ROLL = 3.0
const FINAL_PRE_ROLL = 4.0
const FINAL_AFTER_HIT = .8
const OUTRO_SECONDS = 1.2
const FINAL_LOCK = 9.0
const DEATH_TIMEOUT = 5.0
var game: Node
var history = History.new()
var gun_container: SubViewportContainer
var weapon_viewport: SubViewport
var weapon_camera: Camera3D
var saved_disable_3d = false
var saved_weapon_update = SubViewport.UPDATE_ALWAYS
var deaths: Dictionary = {}
var skip_ready = true
var pending_final: Dictionary = {}
var outro_left = 0.0
var outro_title = ""
var outro_detail = ""
var outro_outcome = 0
var active = false
var final = false
var clip: Dictionary = {}
var cursor = 0.0
var finish_hold = 0.0
var elapsed = 0.0
var playback_speed = 1.0
var scoped = false
var event_index = 0
var hit_played = false
var recoil = 0.0
var last_death_id = -1
var last_final_id = -1
var viewport: SubViewport
var container: SubViewportContainer
var scene: Node3D
var scenery: Node3D
var cached_world_id = 0
var camera: Camera3D
var ghosts: Dictionary = {}
var smoke_views: Array = []
var grenade_views: Array = []
var gun: Node3D
var gun_id = -1
var muzzle: MeshInstance3D
var speakers: Array[AudioStreamPlayer] = []
var speaker_index = 0
var tracer_nodes: Array = []
var flush_queued = false
func _ready() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	container = SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(viewport)
	scene = Node3D.new(); viewport.add_child(scene)
	camera = Camera3D.new(); camera.near=.03; scene.add_child(camera); camera.make_current()
	gun_container=SubViewportContainer.new()
	gun_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gun_container.stretch=true; gun_container.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(gun_container)
	weapon_viewport=SubViewport.new(); weapon_viewport.own_world_3d=true
	weapon_viewport.transparent_bg=true; weapon_viewport.handle_input_locally=false
	weapon_viewport.size=Vector2i(1280,720)
	weapon_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	gun_container.add_child(weapon_viewport)
	weapon_camera=Camera3D.new(); weapon_camera.near=.025; weapon_camera.fov=75
	weapon_viewport.add_child(weapon_camera); weapon_camera.make_current()
	var environment=WorldEnvironment.new(); environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("dce9ef")
	environment.environment.ambient_light_energy=.7
	weapon_viewport.add_child(environment)
	var light=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-30,-25,0); light.light_energy=.6
	weapon_viewport.add_child(light)
	gun_container.hide()
	for i in range(8):
		var speaker = AudioStreamPlayer.new()
		speaker.bus="Weapons"; add_child(speaker); speakers.append(speaker)
	container.hide()
func note_kill(victim: String, killer: String, weapon: String, head: bool, view_lag: float = 0.0) -> void:
	if game.net.running and not game.net.server: return
	history.sample(game,0,true)
	if history.frames.is_empty(): return
	history.pending.append({"view_lag":clampf(view_lag,0,.5),"frame":history.frames[-1].duplicate(true),"roster":history.roster.duplicate(true),"killer":killer,"victim":victim,"weapon":weapon,"head":head,"time":game.clock})
	if not flush_queued:
		flush_queued=true
		flush.call_deferred()
func flush() -> void:
	flush_queued=false
	var kills = history.pending.duplicate(); history.pending.clear()
	for kill in kills:
		var recorded = history.make_clip(game,kill)
		if recorded.is_empty(): continue
		if game.net.running:
			game.net.deliver_death_replay(recorded)
		elif kill.victim=="YOU" and game.prefs.data.killcams:
			play(recorded,false)
func has_final() -> bool:
	return not history.pending.is_empty() or not history.last_clip.is_empty()
func present_final(recorded: Dictionary, title: String) -> void:
	if recorded.is_empty() or recorded.map!=game.current_map or recorded.id<=last_final_id: return
	if not pending_final.is_empty() and recorded.id<=pending_final.id: return
	stop(false)
	pending_final=recorded.duplicate(true)
	outro_left=OUTRO_SECONDS
	outro_detail=title
	var winning_team=int(recorded.get("result_team",0))
	outro_outcome=0 if winning_team==0 else (1 if winning_team==game.player.team else -1)
	var scope="GAME" if recorded.get("result_match",false) else "ROUND"
	outro_title=scope+(" DRAW" if outro_outcome==0 else (" WON" if outro_outcome>0 else " LOST"))
	game.sound("ui",-20)
	_build_world() # Warm static replay scenery during the result window, before the camera cut.
func transitioning() -> bool:
	return not pending_final.is_empty()
func fade_alpha() -> float:
	return 0.0 # Never cover live play or replays with a black transition.
func play(recorded: Dictionary, mandatory: bool) -> bool:
	if recorded.is_empty() or recorded.map!=game.current_map: return false
	if mandatory:
		if recorded.id<=last_final_id: return false
		last_final_id=recorded.id
	else:
		if transitioning() or active and final or recorded.id<=last_death_id or recorded.id<=last_final_id or game.player.health>0: return false
		if not game.prefs.data.killcams: return false
		last_death_id=recorded.id
	stop(false)
	clip=recorded; final=mandatory; active=true
	skip_ready=not Input.is_action_pressed("jump")
	if not game.menu_open: Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	saved_disable_3d=game.get_viewport().disable_3d
	saved_weapon_update=game.player.viewmodel.viewport.render_target_update_mode
	game.get_viewport().disable_3d=true
	game.player.viewmodel.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	deaths.clear()
	var previous: Dictionary = {}
	for frame in clip.frames:
		for row in frame[1]:
			if row[4]<=0 and previous.has(row[0]) and previous[row[0]][0]>0 and previous[row[0]][1]==row[8]: deaths[row[0]]=[frame[0],row[8]]
			previous[row[0]]=[row[4],row[8]]
	deaths[clip.victim]=[clip.time,clip.victim_life]
	cursor=clip.time-(FINAL_PRE_ROLL if mandatory else REGULAR_PRE_ROLL); finish_hold=0; elapsed=0; event_index=0; hit_played=false; recoil=0
	while event_index<clip.events.size() and clip.events[event_index][0]<cursor: event_index+=1
	_build_world()
	for id in clip.roster:
		var root = Node3D.new(); scene.add_child(root)
		var info = clip.roster[id]
		var loadout = Collection.clean_loadout(info[2])
		var rig = Rig.build(root,Color("30bac6") if info[1]==1 else Color("ed6c46"),Collection.catalog()[loadout.armor].variant)
		Collection.paint(rig.root,loadout.armor,true)
		preload("res://scripts/optimizer.gd").rig(rig)
		ghosts[id]={"root":root,"rig":rig,"gun":null,"weapon":-1,"loadout":loadout,"class_id":info[3] if info.size()>3 else "vanguard"}
	container.show(); gun_container.show()
	weapon_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Cut off old live voices; new live events are suppressed while replay audio plays.
	for pool in [game.sound_pool,game.world_sounds]:
		for speaker in pool: speaker.stop()
	game.player.fire_requested=false; game.player.jump_requested=false
	game.player.fire_blocked_until_release=true
	_render(0)
	return true
func _build_world() -> void:
	if cached_world_id==game.world_root.get_instance_id() and is_instance_valid(scenery): return
	if is_instance_valid(scenery): scenery.free()
	scenery=Node3D.new(); scene.add_child(scenery)
	_copy_static(game.world_root)
	cached_world_id=game.world_root.get_instance_id()
func _copy_static(node: Node) -> void:
	if node.is_queued_for_deletion(): return
	var copy
	if node is MeshInstance3D and node.visible:
		copy=MeshInstance3D.new(); copy.mesh=node.mesh; copy.material_override=node.material_override
		copy.cast_shadow=node.cast_shadow
	elif node is DirectionalLight3D: copy=node.duplicate()
	elif node is WorldEnvironment:
		copy=WorldEnvironment.new(); copy.environment=node.environment
	elif node is Label3D: copy=node.duplicate()
	if copy!=null:
		scenery.add_child(copy)
		if copy is Node3D: copy.global_transform=node.global_transform
	for child in node.get_children(): _copy_static(child)
func _process(delta: float) -> void:
	if transitioning():
		outro_left=maxf(0,outro_left-delta)
		if outro_left<=0:
			var recorded=pending_final
			pending_final={}
			play(recorded,true)
		return
	if not active: return
	elapsed+=delta
	if not Input.is_action_pressed("jump"): skip_ready=true
	if skip_ready and not final and not game.menu_open and Input.is_action_pressed("jump") and Input.is_action_just_pressed("jump"):
		stop(true); return
	advance(delta)
func advance(delta: float) -> void:
	if not active: return
	# Integrate real time across boundaries so duration is independent of frame rate.
	var end=float(clip.time)
	var remaining=delta
	var slow_start=end-SLOW_WINDOW
	if final and cursor<slow_start:
		var normal=minf(remaining,slow_start-cursor)
		cursor+=normal; remaining-=normal
	playback_speed=SLOW_RATE if final and cursor>=slow_start else 1.0
	if cursor<end:
		var travel=minf(remaining,(end-cursor)/playback_speed)
		cursor=minf(end,cursor+travel*playback_speed); remaining-=travel
	if cursor>=end: finish_hold+=remaining
	_render(delta)
	if finish_hold>=(FINAL_AFTER_HIT if final else AFTER_HIT): stop(true)
func _render(delta: float) -> void:
	if clip.is_empty(): return
	var a = clip.frames[0]
	var b = a
	for frame in clip.frames:
		if frame[0]<=cursor: a=frame
		b=frame
		if frame[0]>=cursor: break
	var blend = clampf((cursor-a[0])/maxf(.001,b[0]-a[0]),0,1)
	var lag_a=clip.frames[0]
	var lag_b=lag_a
	var past=cursor-float(clip.get("view_lag",0.0))
	for frame in clip.frames:
		if frame[0]<=past: lag_a=frame
		lag_b=frame
		if frame[0]>=past: break
	var lag_blend=clampf((past-lag_a[0])/maxf(.001,lag_b[0]-lag_a[0]),0,1)
	var lag_rows: Dictionary = {}
	var lag_next: Dictionary = {}
	for row in lag_a[1]: lag_rows[row[0]]=row
	for row in lag_b[1]: lag_next[row[0]]=row
	var next: Dictionary = {}
	for row in b[1]: next[row[0]]=row
	for row in a[1]:
		var id = row[0]
		if not ghosts.has(id): continue
		var other = next.get(id,row)
		if other[8]!=row[8]: other=row
		var ghost = ghosts[id]
		var pose=row; var pose_next=other; var pose_blend=blend
		if id!=clip.killer and lag_rows.has(id) and lag_next.has(id) and lag_rows[id][8]==row[8] and lag_next[id][8]==row[8]:
			pose=lag_rows[id]; pose_next=lag_next[id]; pose_blend=lag_blend
		ghost.root.position = pose[1].lerp(pose_next[1],pose_blend)
		var yaw = lerp_angle(pose[2],pose_next[2],pose_blend)
		ghost.root.rotation.y = yaw+PI
		ghost.root.visible = id!=clip.killer and (row[4]>0 or (deaths.has(id) and deaths[id][1]==row[8]))
		ghost.rig.root.scale.y = .65 if row[7] else 1.0
		Rig.animate(ghost.rig,row[9],cursor,0,row[10],0,true)
		ghost.rig.root.rotation.x=0; ghost.rig.root.position.y=0
		if deaths.has(id) and row[8]==deaths[id][1] and cursor>=deaths[id][0]:
			var age=cursor-deaths[id][0]+finish_hold
			ghost.rig.root.rotation.x = minf(PI*.48,age*3)
			ghost.rig.root.position.y = -minf(.45,age)
		if ghost.weapon!=row[5]:
			if is_instance_valid(ghost.gun): ghost.gun.free()
			ghost.gun=Art.world(ghost.root,row[5]);
			if row[5]==0: preload("res://scripts/loadouts.gd").decorate(ghost.gun,ghost.class_id)
			ghost.gun.position=Vector3(.28,1.1,.3); ghost.gun.rotation.y=PI
			Collection.paint(ghost.gun,ghost.loadout[["rifle","pistol","sword","sniper"][row[5]]])
			ghost.weapon=row[5]
		if id==clip.killer:
			camera.position=ghost.root.position+Vector3.UP*lerpf(row[11],other[11],blend)
			camera.rotation=Vector3(lerpf(row[3],other[3],blend),yaw,0)
			camera.fov=lerpf(row[12],other[12],blend)
			scoped=row[5]==3 and camera.fov<40
			if gun_id!=row[5]:
				if is_instance_valid(gun): gun.free()
				gun=Art.world(weapon_camera,row[5]); gun_id=row[5]
				if gun_id==0: preload("res://scripts/loadouts.gd").decorate(gun,ghost.class_id)
				Collection.paint(gun,ghost.loadout[["rifle","pistol","sword","sniper"][gun_id]])
				Geo.sphere(gun,Vector3(0,-.19,.16),.075,Color("354c53"))
				Geo.beam(gun,Vector3(0,-.22,.2),Vector3(.16,-.35,.65),.12,Color("58767b"))
				if gun_id in [0,3]:
					Geo.sphere(gun,Vector3(-.04,-.09,-.3),.065,Color("354c53"))
					Geo.beam(gun,Vector3(-.09,-.13,-.3),Vector3(-.28,-.36,.5),.12,Color("58767b"))
				muzzle=Geo.sphere(gun,Vector3(0,.025,-.96 if gun_id==3 else -.78),.08,Color("ffe0a0"))
				muzzle.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
				muzzle.visible=false
			gun.visible=not scoped
			muzzle.visible=recoil>.5 and gun_id!=2
			gun.position=Vector3(.25,-.25,-.6)+Vector3(0,recoil*.025,recoil*.10)
			gun.rotation=Vector3(recoil*.07,0,-.04) if gun_id!=2 else Vector3(-.3*recoil,-.9*recoil,-.5*recoil)
	while event_index<clip.events.size() and clip.events[event_index][0]<=cursor:
		var event = clip.events[event_index]; event_index+=1
		if event[4]!=2:
			var beam = Geo.beam(scene,event[2],event[3],.012,Color("ffe6a8"))
			tracer_nodes.append([beam,.07])
		if event[1]==clip.killer: recoil=1
		play_audio(["rifle","pistol","sword","sniper"][event[4]],-12 if event[1]==clip.killer else -23)
	if cursor>=clip.time and not hit_played:
		hit_played=true
		play_audio("head" if clip.head else "hit",-8)
		if clip.weapon=="BLAST":
			play_audio("blast",-6)
			if ghosts.has(clip.victim):
				var blast=Geo.sphere(scene,ghosts[clip.victim].root.position+Vector3.UP*.6,1.2,Color("ffba6e"))
				tracer_nodes.append([blast,.2])
	for i in range(tracer_nodes.size()-1,-1,-1):
		tracer_nodes[i][1]-=delta*playback_speed
		if tracer_nodes[i][1]<=0:
			tracer_nodes[i][0].queue_free(); tracer_nodes.remove_at(i)
	recoil=move_toward(recoil,0,delta*6*playback_speed)
	_sync_effects(a[2],a[3])
func _sync_effects(smokes: Array, grenades: Array) -> void:
	while smoke_views.size()<smokes.size():
		var smoke=Geo.sphere(scene,Vector3.ZERO,3.5,Color(.65,.72,.72,.88))
		smoke_views.append(smoke)
	for i in range(smoke_views.size()):
		smoke_views[i].visible=i<smokes.size()
		if i<smokes.size(): smoke_views[i].position=smokes[i]
	while grenade_views.size()<grenades.size(): grenade_views.append(Geo.sphere(scene,Vector3.ZERO,.12,Color("d1b36d")))
	for i in range(grenade_views.size()):
		grenade_views[i].visible=i<grenades.size()
		if i<grenades.size(): grenade_views[i].position=grenades[i][0]
func play_audio(key: String, volume: float) -> void:
	if not game.audio_mix.enabled or not game.audio.has(key): return
	var speaker=speakers[speaker_index%speakers.size()]; speaker_index+=1
	speaker.stream=game.audio[key]; speaker.volume_db=volume
	speaker.bus=game.audio_mix.bus_for(key)
	speaker.pitch_scale=.7 if final and playback_speed<1 else 1.0
	speaker.play()
func stop(resume: bool = false) -> void:
	pending_final={}; outro_left=0
	var was_active=active
	var was_final=final
	active=false; final=false; scoped=false
	if was_active:
		game.get_viewport().disable_3d=saved_disable_3d
		game.player.viewmodel.viewport.render_target_update_mode=saved_weapon_update
	if is_instance_valid(gun_container): gun_container.hide(); weapon_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if is_instance_valid(container): container.hide(); viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	for ghost in ghosts.values(): ghost.root.queue_free()
	ghosts.clear()
	for node in smoke_views+grenade_views:
		if is_instance_valid(node): node.queue_free()
	smoke_views.clear(); grenade_views.clear()
	for row in tracer_nodes:
		if is_instance_valid(row[0]): row[0].queue_free()
	tracer_nodes.clear()
	for speaker in speakers: speaker.stop()
	if is_instance_valid(gun): gun.queue_free()
	gun=null; gun_id=-1
	if was_active and not game.menu_open:
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if game.net.running and not game.net.round_active else Input.MOUSE_MODE_CAPTURED
	if resume and was_active and not was_final:
		if game.net.running: game.net.finish_death_replay()
		elif game.mode=="combat": game.combat.respawn_player()
func reset() -> void:
	stop(false); history.clear(); last_death_id=-1; last_final_id=-1; flush_queued=false
	if is_instance_valid(scenery): scenery.queue_free(); scenery=null
	cached_world_id=0
