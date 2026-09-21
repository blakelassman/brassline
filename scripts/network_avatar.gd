extends CharacterBody3D
const RemoteView = preload("res://scripts/remote_view.gd")
var cosmetics: Dictionary = {}
var game: Node
var team = 1
var target_name = "Player"
var health = 100
var class_id = "vanguard"
var weapon = 0
var crouched = false
var parry_timer = 0.0
var reload_timer = 0.0
var hurt_flash = 0.0
var life_id = 0
var net_slot = -1
var viewmodel: Node
var goal = Vector3.ZERO
var goal_yaw = 0.0
var samples: Array = []
var human = false
var body_shape: CollisionShape3D
func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	body_shape = CollisionShape3D.new()
	body_shape.shape = CapsuleShape3D.new()
	body_shape.shape.radius = .32
	body_shape.shape.height = 1.8
	body_shape.position.y = .9
	add_child(body_shape)
	viewmodel = RemoteView.new()
	viewmodel.player = self
	add_child(viewmodel)
func receive(row: Array, time: float) -> void:
	if row.size()>12 and row[12]!=class_id:
		class_id=row[12]
		viewmodel.apply_cosmetics()
	var incoming = row[11] if row.size()>11 else {}
	if cosmetics!=incoming:
		cosmetics = incoming.duplicate()
		viewmodel.apply_cosmetics()
	if life_id!=row[8] or position.distance_to(row[1])>8:
		samples.clear()
		position = row[1]
	life_id = row[8]
	health = row[5]
	weapon = row[6]
	crouched = row[7]
	reload_timer = row[9]
	parry_timer = row[10] if row.size()>10 else 0.0
	collision_layer = 4 if health>0 else 0
	body_shape.shape.height = 1.1 if crouched else 1.8
	body_shape.position.y = body_shape.shape.height*.5
	samples.append({"time":time,"position":row[1],"velocity":row[2],"yaw":row[3]})
	while samples.size()>8: samples.pop_front()
func _process(delta: float) -> void:
	if samples.is_empty(): return
	var render_time = game.net.presentation_time
	while samples.size()>1 and samples[1].time<=render_time: samples.pop_front()
	if samples.size()>1:
		var a = samples[0]
		var b = samples[1]
		var weight = clampf((render_time-a.time)/maxf(.001,b.time-a.time),0,1)
		position = a.position.lerp(b.position,weight)
		rotation.y = lerp_angle(a.yaw,b.yaw,weight)
		velocity = b.velocity
	else:
		var state = samples[0]
		position = state.position+state.velocity*clampf(render_time-state.time,0,.08)
		rotation.y = state.yaw
		velocity = state.velocity
	viewmodel.update_pose(delta)
