extends Node
const Rig = preload("res://scripts/rig.gd")
const Geo = preload("res://scripts/geo.gd")
const Optimizer = preload("res://scripts/optimizer.gd")
var player: CharacterBody3D
var root: Node3D
var rig: Dictionary
var title: Label3D
var gun: Node3D
var guns: Array[Node3D] = []
var flash: MeshInstance3D
var flash_time = 0.0
var presentation=preload("res://scripts/actor_presentation.gd").new()
var pose_clock=0.0
var label_timer=0.0
var label_clear=false
var crouch_blend=1.0
func _ready() -> void:
	var color = Color("30bac6") if player.team==1 else Color("ed6c46")
	var collection = preload("res://scripts/cosmetics.gd")
	var loadout = collection.clean_loadout(player.cosmetics)
	rig = Rig.build(player,color,collection.catalog()[loadout.armor].variant)
	collection.paint(rig.root,loadout.armor,true)
	root = rig.root
	root.rotation.y = PI
	presentation.reset(player.global_transform)
	Optimizer.rig(rig)
	title = Geo.sign_text(player,Vector3(0,2.18,0),player.target_name,18,color)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.visibility_range_begin = 2
	title.visibility_range_end = 30
	title.visible = player.team==player.game.player.team
	guns.resize(4)
	gun = weapon_model(player.weapon)
	flash = Geo.sphere(root,Vector3(.28,1.1,.8),.09,Color("ffdfaa"))
	flash.hide()
func update_pose(delta: float) -> void:
	root.visible = player.health>0
	if delta<=0:
		presentation.reset(player.global_transform); rig.erase("animation")
		crouch_blend=.65 if player.crouched else 1.0
	pose_clock+=delta
	# Network avatars already interpolate; only host-simulated humans need this layer.
	if player.has_method("simulate_movement"):
		presentation.apply(root,player,Engine.get_physics_interpolation_fraction())
		root.rotate_object_local(Vector3.UP,PI)
	label_timer-=delta
	var teammate=player.health>0 and player.team==player.game.player.team and player.position.distance_squared_to(player.game.player.position)<324
	if not teammate: label_clear=false
	elif label_timer<=0:
		label_timer=.1
		label_clear=player.game.unobstructed(player.game.player.camera.global_position,player.global_position+Vector3.UP*1.7)
	title.visible=teammate and label_clear
	title.text = player.game.net.display_name(player.target_name) if player.game.net.running and player.game.net.server else player.target_name
	crouch_blend=lerpf(crouch_blend,.65 if player.crouched else 1.0,1-exp(-18*delta))
	root.scale.y=crouch_blend
	title.global_position=root.global_position+Vector3.UP*(2.18*crouch_blend)
	flash_time = maxf(0,flash_time-delta)
	flash.visible = flash_time>0
	var speed=0.0 if player.game.net.running and not player.game.net.combat_allowed() else Vector2(player.velocity.x,player.velocity.z).length()
	Rig.animate(rig,speed,pose_clock,player.hurt_flash,player.reload_timer,flash_time,true)
	gun = weapon_model(player.weapon)
	for i in range(4):
		if is_instance_valid(guns[i]): guns[i].visible = i==player.weapon
	gun.rotation.x = -flash_time
	gun.rotation.z = .9 if player.parry_timer>0 else 0.0
	if player.parry_timer>0:
		rig.arms[1].rotation.x = -1.8
		rig.elbows[1].rotation.x = -.4
func on_shot() -> void: flash_time = .065

func weapon_model(index: int) -> Node3D:
	if not is_instance_valid(guns[index]):
		var model = preload("res://scripts/weapon_art.gd").world(root,index)
		if index==0: preload("res://scripts/loadouts.gd").decorate(model,player.class_id)
		model.position = Vector3(.26,1.13,.3)
		model.rotation.y = PI
		var collection = preload("res://scripts/cosmetics.gd")
		collection.paint(model,collection.clean_loadout(player.cosmetics)[["rifle","pistol","sword","sniper"][index]])
		guns[index] = model
	return guns[index]

func apply_cosmetics() -> void:
	var orientation = root.rotation.y
	root.free()
	title.free()
	guns.clear()
	_ready()
	root.rotation.y = orientation
