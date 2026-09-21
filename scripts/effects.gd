extends Node
## Bounded cosmetic effects; no effect collides with a player or changes damage.
const Geo = preload("res://scripts/geo.gd")
var game: Node3D
var root: Node3D
var particles: Array = []
var marks: Array[Node3D] = []
var bodies: Array = []
var fading_shaders: Dictionary = {}
var rng = RandomNumberGenerator.new()
func _ready() -> void:
	root = Node3D.new()
	game.add_child(root)
	rng.seed = 602026
func clear() -> void:
	for child in root.get_children(): child.queue_free()
	particles.clear()
	marks.clear()
	bodies.clear()
func puff(at: Vector3, velocity: Vector3, color: Color, scale: float, life: float) -> void:
	if particles.size()>=(30 if game.prefs.data.quality==0 else 100):
		particles[0].node.queue_free()
		particles.pop_front()
	var node = Geo.box(root,at,Vector3.ONE*scale,color)
	particles.append({"node":node,"velocity":velocity,"life":life,"total":life})
func impact(at: Vector3, normal: Vector3, metal: bool) -> void:
	if marks.size()>=(16 if game.prefs.data.quality==0 else 48):
		marks[0].queue_free()
		marks.pop_front()
	var mark = Geo.sphere(root,at+normal*.012,.045,Color("253239"))
	mark.scale = Vector3(1,1,.13)
	mark.look_at(at+normal,Vector3.FORWARD if absf(normal.y)>.98 else Vector3.UP)
	marks.append(mark)
	for i in range(2 if game.prefs.data.quality==0 else 5):
		var velocity = normal*rng.randf_range(1,3)+Vector3(rng.randf_range(-1,1),rng.randf_range(0,2),rng.randf_range(-1,1))
		puff(at+normal*.025,velocity,Color("f1ca79") if metal else Color("c8bfa4"),.025 if metal else .06,.24+rng.randf()*.18)
	game.world_sound("impact_metal" if metal else "impact_concrete",at,-22)
func burst(at: Vector3) -> void:
	for i in range(10 if game.prefs.data.quality==0 else 26):
		var direction = Vector3(rng.randf_range(-1,1),rng.randf_range(.1,1),rng.randf_range(-1,1)).normalized()
		puff(at,direction*rng.randf_range(3,10),Color("edc67e") if i%3==0 else Color("b9af93"),rng.randf_range(.035,.10),rng.randf_range(.3,.65))
func fall(visual: Node3D) -> void:
	if game.prefs.data.quality==0: return
	if bodies.size()>=12:
		bodies[0].node.queue_free()
		bodies.pop_front()
	var copy = visual.duplicate() as Node3D
	root.add_child(copy)
	copy.global_transform = visual.global_transform
	var mats: Array = []
	fade_materials(copy,mats)
	bodies.append({"node":copy,"life":.8,"materials":mats})
func fade_materials(node: Node, mats: Array) -> void:
	if node is MeshInstance3D and node.material_override!=null:
		var mat=node.material_override.duplicate()
		if mat is StandardMaterial3D:
			mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		elif mat is ShaderMaterial:
			var source=mat.shader
			if not fading_shaders.has(source):
				var fading=Shader.new()
				fading.code=source.code.replace("void fragment() {","uniform float corpse_alpha = 1.0;\nvoid fragment() {\n ALPHA = corpse_alpha;")
				fading_shaders[source]=fading
			mat.shader=fading_shaders[source]
			mat.set_shader_parameter("corpse_alpha",1.0)
		node.material_override=mat
		mats.append(mat)
	for child in node.get_children(): fade_materials(child,mats)
func _process(delta: float) -> void:
	if not game.active: return
	for item in particles:
		item.life -= delta
		item.velocity.y -= 10*delta
		item.node.position += item.velocity*delta
		item.node.rotate_x(delta*6)
		item.node.scale = Vector3.ONE*clampf(item.life/.12,0,1)
		if item.life<=0: item.node.queue_free()
	particles = particles.filter(func(p): return p.life>0)
	for body in bodies:
		body.life -= delta
		body.node.rotation.x = lerpf(body.node.rotation.x,-1.25,1-exp(-8*delta))
		for mat in body.materials:
			var opacity=clampf(body.life/.35,0,1)
			if mat is StandardMaterial3D: mat.albedo_color.a=opacity
			elif mat is ShaderMaterial: mat.set_shader_parameter("corpse_alpha",opacity)
		if body.life<=0: body.node.queue_free()
	bodies = bodies.filter(func(b): return b.life>0)
