extends SubViewportContainer
const Collection = preload("res://scripts/cosmetics.gd")
const Rig = preload("res://scripts/rig.gd")
var viewport: SubViewport
var stage: Node3D
var model: Node3D
var turn = .35
func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(320,230)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.size = Vector2i(450,330)
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("0b1c25")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c0d8e3")
	env.environment.ambient_light_energy = .75
	viewport.add_child(env)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32,-35,0)
	light.light_energy = 1.2
	viewport.add_child(light)
	var camera = Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0,1.35,3.4)
	camera.look_at(Vector3(0,.95,0))
	camera.fov = 41
	camera.current = true
	stage = Node3D.new()
	viewport.add_child(stage)
func show_item(id: String, loadout: Dictionary) -> void:
	if not Collection.catalog().has(id): return
	if is_instance_valid(model): model.free()
	model = Node3D.new()
	stage.add_child(model)
	var item = Collection.catalog()[id]
	if item.slot=="armor":
		var rig = Rig.build(model,Color("30bac6"),item.variant)
		Collection.paint(rig.root,id,true)
		Rig.animate(rig,0,0,0,0,0,true)
		var weapon = preload("res://scripts/weapon_art.gd").world(model,0)
		weapon.position = Vector3(.26,1.13,.3)
		weapon.rotation.y = PI
		Collection.paint(weapon,loadout.rifle)
	else:
		var index = ["rifle","pistol","sword","sniper"].find(item.slot)
		var weapon = preload("res://scripts/weapon_art.gd").world(model,index)
		weapon.position.y = .95
		weapon.rotation = Vector3(-.12,PI/2,1.15 if index==2 else 0.0)
		weapon.scale = Vector3.ONE*(2.1 if index==1 else 1.55)
		Collection.paint(weapon,id)
func _process(delta: float) -> void:
	if viewport==null: return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if is_visible_in_tree():
		turn += delta*.35
		stage.rotation.y = sin(turn)*.48
