extends Node
const Rig = preload("res://scripts/rig.gd")
const Geo = preload("res://scripts/geo.gd")
const Optimizer = preload("res://scripts/optimizer.gd")
var player: CharacterBody3D
var root: Node3D
var rig: Dictionary
var title: Label3D
var gun: Node3D
var flash: MeshInstance3D
var flash_time = 0.0
func _ready() -> void:
	var color = Color("30bac6") if player.team==1 else Color("ed6c46")
	rig = Rig.build(player,color,0)
	root = rig.root
	root.rotation.y = PI
	Optimizer.rig(rig)
	title = Geo.sign_text(player,Vector3(0,2.18,0),player.target_name,18,color)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.visibility_range_begin = 2
	title.visibility_range_end = 30
	gun = Geo.box(root,Vector3(.28,1.1,.40),Vector3(.12,.14,.65),Color("2f424d"))
	flash = Geo.sphere(root,Vector3(.28,1.1,.8),.09,Color("ffdfaa"))
	flash.hide()
func update_pose(delta: float) -> void:
	root.visible = player.health>0
	title.visible = player.health>0
	title.text = player.game.net.display_name(player.target_name) if player.game.net.running and player.game.net.server else player.target_name
	root.scale.y = .65 if player.crouched else 1.0
	title.position.y = 1.45 if player.crouched else 2.18
	flash_time = maxf(0,flash_time-delta)
	flash.visible = flash_time>0
	Rig.animate(rig,Vector2(player.velocity.x,player.velocity.z).length(),player.game.clock,player.hurt_flash,player.reload_timer,flash_time,true)
	gun.rotation.x = -flash_time
func on_shot() -> void: flash_time = .065
