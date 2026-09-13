extends CharacterBody3D

const Rig = preload("res://scripts/rig.gd")
var rig: Dictionary = {}
var visual_variant = 0
var impact_pose = 0.0

const Geo = preload("res://scripts/geo.gd")
var game: Node
var team = 2
var health = 100
var target_name = "TARGET"
var moving = false
var anchor = Vector3.ZERO
var time = 0.0
var dead_time = 0.0
var hitboxes: Array[Area3D] = []
var title: Label3D

func _ready() -> void:
	anchor = position
	collision_layer = 4
	collision_mask = 1
	var collider = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	var color = Color("ed6c46") if team == 2 else Color("30bac6")
	rig = Rig.build(self,color,visual_variant)
	preload("res://scripts/optimizer.gd").rig(rig)
	_hitbox("body", Vector3(0, 0.8, 0), false)
	_hitbox("head", Vector3(0, 1.68, 0), true)
	title = Geo.sign_text(self, Vector3(0, 2.18, 0), target_name, 22, color)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.visibility_range_begin = 1.5
	title.visibility_range_end = 32
	_refresh_label()

func _hitbox(zone: String, pos: Vector3, head: bool) -> void:
	var area = Area3D.new()
	area.collision_layer = 8
	area.collision_mask = 0
	area.set_meta("target", self)
	area.set_meta("zone", zone)
	var collision = CollisionShape3D.new()
	if head:
		var sphere = SphereShape3D.new()
		sphere.radius = 0.24
		collision.shape = sphere
	else:
		var shape = BoxShape3D.new()
		shape.size = Vector3(0.68, 1.36, 0.4)
		collision.shape = shape
	area.add_child(collision)
	add_child(area)
	area.position = pos
	hitboxes.append(area)

func _physics_process(delta: float) -> void:
	if not game.active:
		return
	if health <= 0:
		dead_time -= delta
		if dead_time <= 0.0:
			reset()
		return
	time += delta
	impact_pose = maxf(0,impact_pose-delta*4)
	Rig.animate(rig,velocity.length(),time,impact_pose,0,0,false)
	if moving:
		velocity.x = (anchor.x + sin(time * 1.2) * 2.4 - position.x) * 6.0
	else:
		velocity.x = 0
	velocity.y -= 24.0 * delta
	move_and_slide()

func take_damage(amount: int, source_team: int) -> bool:
	if source_team == team or health <= 0:
		return false
	impact_pose = .8
	health = maxi(0, health - amount)
	_refresh_label()
	if health == 0:
		if is_instance_valid(game.effects): game.effects.fall(rig.root)
		visible = false
		collision_layer = 0
		for area in hitboxes:
			area.collision_layer = 0
		dead_time = 2.6
		return true
	return false

func reset() -> void:
	health = 100
	dead_time = 0.0
	position = anchor
	velocity = Vector3.ZERO
	visible = true
	collision_layer = 4
	for area in hitboxes:
		area.collision_layer = 8
	_refresh_label()

func _refresh_label() -> void:
	title.text = target_name
	title.visible = game.mode=="training" or team==game.player.team
