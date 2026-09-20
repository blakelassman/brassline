extends CharacterBody3D
## Swept sphere movement avoids tunneling through thin cover.

const Rules = preload("res://scripts/rules.gd")
const Geo = preload("res://scripts/geo.gd")
var replica = false
var predicted = false
var prediction_action = 0
var confirmed_state: Array = []
var confirmation_age = 0.0
var visual_offset = Vector3.ZERO
var owner_actor: Node
var source_team = 1
var owner_name = "YOU"
var net_id = 0
var game: Node
var kind = "blast"
var fuse = Rules.FUSE
var bounces = 0
var last_beep = -1
var cap: Node3D
var body: MeshInstance3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var collider = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.14
	collider.shape = shape
	add_child(collider)
	body = Geo.sphere(self, Vector3.ZERO, 0.14, Color("ffc35a") if kind == "blast" else Color("b4e1de"))
	cap = Geo.box(self, Vector3(0, 0.12, 0), Vector3(0.11, 0.11, 0.11), Color("283b42"))

func _physics_process(delta: float) -> void:
	if not game.active:
		return
	if not confirmed_state.is_empty():
		var previous = position
		position = confirmed_state[0]
		velocity = confirmed_state[1]
		fuse = confirmed_state[2]
		var remaining = confirmation_age
		while remaining>0:
			var step = minf(1.0/60,remaining)
			advance_motion(step,false)
			fuse -= step
			remaining -= step
		confirmed_state = []
		if previous.distance_to(position)<3: visual_offset += previous-position
		else: visual_offset = Vector3.ZERO
	visual_offset *= exp(-20*delta)
	body.position = visual_offset
	cap.position = Vector3(0,.12,0)+visual_offset
	if game.net.running and not game.net.combat_allowed(): return
	fuse -= delta
	advance_motion(delta,true)
	var pulse = int((Rules.FUSE - fuse) / 0.25)
	if pulse != last_beep and kind == "blast":
		last_beep = pulse
		game.world_sound("tick",global_position,-15.0,false) if game.net.running else game.sound("tick",-15.0)
	body.rotate_x(delta*velocity.length()*1.5)
	body.rotate_z(delta*velocity.length())
	body.scale = Vector3.ONE * (1.0 + 0.15 * sin(fuse * 30.0))
	if fuse <= 0.0:
		if replica or predicted:
			# Visual prediction cannot damage, boost, award XP or create smoke.
			# Keep a confirmed replica until the host removes it; expire rejected throws.
			if predicted and fuse<-.75: queue_free()
			return
		if kind == "blast":
			game.explode(global_position,owner_actor,source_team,owner_name)
		else:
			game.make_smoke(global_position)
		queue_free()

func advance_motion(delta: float, audible: bool) -> void:
	velocity.y -= Rules.GRAVITY * delta
	var collision = move_and_collide(velocity * delta)
	if collision:
		if audible and velocity.length()>1.5: game.world_sound("grenade_bounce",global_position,-18,false)
		var normal = collision.get_normal()
		velocity = velocity.bounce(normal) * 0.32
		if normal.y > 0.6:
			velocity.x *= 0.65
			velocity.z *= 0.65
			if absf(velocity.y) < 0.5:
				velocity.y = 0.0
		bounces += 1
