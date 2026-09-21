extends RefCounted
## Original compact districts. Walkable interiors, upper galleries and boost-access roofs.
const Geo = preload("res://scripts/geo.gd")
const NAMES = ["FOUNDRY YARD","DRY DOCK","SUNSPIRE","RELAY"]
const DESCRIPTIONS = ["Brick workshops, furnace court and elevated service galleries.","Harbor offices, gantry cranes and a dockside warehouse route.","Terracotta rooftops, market arcades and a sunlit fountain square.","Mountain communications campus, skybridge and antenna decks."]
const FLOORS = ["concrete","metal","tile","metal"]
const PADS = [Vector3(-5,.06,20),Vector3(-5,.06,20),Vector3(-5,.06,20),Vector3(-5,.06,20)]
# [center X, center Z, yaw]. Every building has two usable floors and an open roof.
const BLOCKS = [
	[Vector3(-14,-7,0),Vector3(13,7,PI)],
	[Vector3(-13,7,0),Vector3(13,-8,PI/2)],
	[Vector3(-14,-5,0),Vector3(12,8,PI)],
	[Vector3(-13,6,0),Vector3(13,-7,PI)]]
const PRACTICE = [
	[Vector3(-5,.05,-12),Vector3(4,.05,-17),Vector3(-14,3.25,-5),Vector3(-12,.05,17),Vector3(8,.05,20),Vector3(-2,.05,3),Vector3(-2,.05,-2)],
	[Vector3(-4,.05,-12),Vector3(4,.05,-17),Vector3(-13,3.25,9),Vector3(-12,.05,19),Vector3(8,.05,20),Vector3(-2,.05,3),Vector3(-2,.05,-2)],
	[Vector3(-5,.05,-13),Vector3(5,.05,-17),Vector3(-14,3.25,-3),Vector3(-12,.05,17),Vector3(8,.05,20),Vector3(-4,.05,4),Vector3(-4,.05,0)],
	[Vector3(-4,.05,-12),Vector3(4,.05,-17),Vector3(-13,3.25,8),Vector3(-12,.05,19),Vector3(8,.05,20),Vector3(-2,.05,3),Vector3(-2,.05,-2)]]
static func footprints(index: int) -> Array:
	var result: Array = []
	for block in BLOCKS[index]:
		var size = Vector2(10,12) if absf(sin(block.z))>.5 else Vector2(12,10)
		result.append(Rect2(Vector2(block.x,block.y)-size*.5,size))
	return result

static func environment(parent: Node3D, index: int) -> void:
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = [Color("778e9a"),Color("5c788c"),Color("629cad"),Color("182c48")][index]
	sky_mat.sky_horizon_color = [Color("d5ded2"),Color("c8d2c8"),Color("ebcf9f"),Color("71939e")][index]
	sky_mat.ground_bottom_color = Color("4d5860")
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cdd7de")
	env.ambient_light_energy = .44 if index==3 else .25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	parent.add_child(env_node)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32 if index!=2 else 28,0)
	sun.light_color = Color("fff0d9") if index!=3 else Color("a2d7eb")
	sun.light_energy = .64 if index!=3 else .6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	parent.add_child(sun)

static func ramp(parent: Node3D, center: Vector3, width: float, run: float, rise: float, color: Color) -> Node3D:
	# Wedge geometry keeps bot routes at ground level; human movement can walk up.
	var mesh = ArrayMesh.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a = Vector3(-width/2,0,run/2)
	var b = Vector3(width/2,0,run/2)
	var c = Vector3(width/2,rise,-run/2)
	var d = Vector3(-width/2,rise,-run/2)
	var e = Vector3(-width/2,0,-run/2)
	var f = Vector3(width/2,0,-run/2)
	for v in [a,c,b,a,d,c,a,e,d,b,c,f,e,f,c,e,c,d,a,b,f,a,f,e]:
		st.add_vertex(v)
	st.generate_normals()
	st.index()
	mesh = st.commit()
	var body = StaticBody3D.new()
	parent.add_child(body)
	body.position = center
	body.set_meta("surface","metal")
	var visual = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = Geo.textured(color,"metal")
	body.add_child(visual)
	var collision = CollisionShape3D.new()
	var shape = ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a,b,c,d,e,f])
	collision.shape = shape
	body.add_child(collision)
	return body


static func stairs(parent: Node3D, origin: Vector3, width: float, run: float, rise: float, color: Color) -> Node3D:
	var body = ramp(parent,origin,width,run,rise,color)
	body.get_child(0).free() # Invisible ramp collider; visible steps cannot z-fight its sides.
	body.set_meta("stairs",true)
	# The visible treads have NO collision. One uninterrupted wedge is the walking surface.
	var count = 20
	for i in range(count):
		var h = rise*(i+.5)/count
		Geo.box(body,Vector3(0,h*.5,run*.5-run*(i+.5)/count),Vector3(width,h,run/count),color,false,"concrete")
		Geo.box(body,Vector3(0,rise*(i+1)/count,run*.5-run*(i+1)/count),Vector3(width,.035,.06),color.lightened(.14))
	for side in [-1,1]:
		for t in [0.0,.5,1.0]:
			Geo.box(body,Vector3(side*(width*.5+.05),rise*t+.48,run*.5-run*t),Vector3(.06,.96,.06),Color("53666a"))
		Geo.beam(body,Vector3(side*(width*.5+.05),1,run*.5),Vector3(side*(width*.5+.05),rise+1,-run*.5),.06,Color("a9b7b1"))
	return body

static func building(parent: Node3D, block: Vector3, color: Color, trim: Color, index: int, number: int) -> void:
	var root = Node3D.new()
	parent.add_child(root)
	root.position = Vector3(block.x,0,block.y)
	root.rotation.y = block.z
	root.set_meta("building",true)
	var material = "brick" if index in [0,2] else "panel"
	var floor_color = Color("b7b9a8") if index!=3 else Color("889b9e")
	Geo.box(root,Vector3(0,3.06,0),Vector3(12,.28,10),floor_color,true,"concrete")
	Geo.box(root,Vector3(0,6.26,0),Vector3(12.6,.28,10.6),floor_color,true,"concrete")
	for level in range(2):
		var base = level*3.2
		for side in [-1,1]:
			# Wide central doors and two real window openings on each street facade.
			for x in [-5.6,-2.8,2.8,5.6]:
				Geo.box(root,Vector3(x,base+1.6,side*5),Vector3(.8,3.2,.35),color,true,material)
			for x in [-4.2,4.2]:
				Geo.box(root,Vector3(x,base+.55,side*5),Vector3(2,1.1,.35),color,true,material)
				Geo.box(root,Vector3(x,base+2.8,side*5),Vector3(2,.8,.35),color,true,material)
				Geo.box(root,Vector3(x,base+1.1,side*5.08),Vector3(2.2,.12,.48),trim)
			Geo.box(root,Vector3(0,base+2.85,side*5),Vector3(4.8,.7,.35),color,true,material)
			# Side walls: ground-floor passage; upper stair entrance on the east side.
			if level==1 and side==1:
				Geo.box(root,Vector3(6,base+1.6,1.6),Vector3(.35,3.2,6.8),color,true,material)
				Geo.box(root,Vector3(6,base+1.6,-4.7),Vector3(.35,3.2,.6),color,true,material)
				Geo.box(root,Vector3(6,base+2.9,-3.1),Vector3(.35,.6,2.6),color,true,material)
			else:
				for z in [-3.25,3.25]: Geo.box(root,Vector3(side*6,base+1.6,z),Vector3(.35,3.2,3.5),color,true,material)
				Geo.box(root,Vector3(side*6,base+2.85,0),Vector3(.35,.7,3),color,true,material)
		# Interior columns and waist-high workbenches leave the central cross-route open.
		for x in [-4,4]:
			Geo.box(root,Vector3(x,base+1.6,-2.4),Vector3(.3,3.2,.3),trim,true,"metal")
			Geo.box(root,Vector3(x,base+.45,2.4),Vector3(1.5,.9,.85),trim,true,"wood" if index==2 else "panel")
		for side in [-1,1]:
			Geo.box(root,Vector3(0,base+3.14,side*5.23),Vector3(12.5,.14,.2),trim)
			Geo.box(root,Vector3(0,base+2.7,side*5.9),Vector3(4,.12,1.6),trim)
			for x in [-2,2]: Geo.box(root,Vector3(x,base+1.35,side*6.45),Vector3(.09,2.7,.09),trim)
	stairs(root,Vector3(7.7,0,.6),2.6,8,3.2,floor_color)
	Geo.box(root,Vector3(7.1,3.06,-4.2),Vector3(2.6,.28,1.6),floor_color,true,"metal")
	# Low parapets protect roof edges without enclosing the boost landing area.
	for side in [-1,1]:
		Geo.box(root,Vector3(0,6.65,side*5.1),Vector3(12,.5,.22),color,true,material)
		Geo.box(root,Vector3(side*6.1,6.65,0),Vector3(.22,.5,10),color,true,material)
	Geo.box(root,Vector3(-3,6.85,-2),Vector3(2,.9,1.7),trim,true,"panel")
	for x in [-3.5,-2.5]:
		var fan = Geo.cylinder(root,Vector3(x,7.32,-2),.35,.08,Color("405258"))
		for angle in range(3):
			var blade = Geo.box(fan,Vector3.ZERO,Vector3(.55,.03,.10),Color("94aaa7"))
			blade.rotation.y = angle*PI/3
	Geo.sign_text(root,Vector3(0,2.5,5.22),["SMELT / WORKSHOP","HARBOR OFFICE","MERCATO","COMMS LAB"][index]+" 0"+str(number+1),23,Color("f2dfaf"))
	var route: Array = []
	for point in [Vector3(7.7,.05,5.4),Vector3(7.7,.45,3.5),Vector3(7.7,1.25,1.5),Vector3(7.7,2.05,-.5),Vector3(7.7,2.85,-2.5),Vector3(7.7,3.25,-4.1),Vector3(5,3.25,-3.6),Vector3(2,3.25,-3.6),Vector3(0,3.25,0),Vector3(0,3.25,3.6)]:
		route.append(root.to_global(point))
	var routes: Array = parent.get_meta("upper_routes",[])
	routes.append(route)
	parent.set_meta("upper_routes",routes)

static func build(parent: Node3D, index: int) -> void:
	var ground = [Color("a2aaa0"),Color("99a7a7"),Color("d8c49d"),Color("748c95")][index]
	var wall = [Color("ac6950"),Color("d5c6a8"),Color("e2bb83"),Color("bccbd0")][index]
	var trim = [Color("3c777d"),Color("396b89"),Color("3c9294"),Color("3f6e7f")][index]
	Geo.box(parent,Vector3(0,-.3,0),Vector3(64,.6,62),ground,true,FLOORS[index])
	# Streets, sidewalks and floor markings establish traversable lanes.
	Geo.box(parent,Vector3(0,.012,0),Vector3(9,.02,60),ground.darkened(.26),false,"concrete")
	for side in [-1,1]:
		Geo.box(parent,Vector3(side*4.6,.025,0),Vector3(.15,.03,60),Color("d4c592"))
		for z in range(-27,28,6): Geo.box(parent,Vector3(side*1.7,.03,z),Vector3(.1,.025,2),Color("ded4b4"))
	for number in range(BLOCKS[index].size()): building(parent,BLOCKS[index][number],wall,trim,index,number)
	# Boundary reads as a district edge, with skyline outside and a clear playable railing.
	for side in [-1,1]:
		Geo.box(parent,Vector3(side*31,1.1,0),Vector3(.4,2.2,62),trim,true,"metal")
		Geo.box(parent,Vector3(0,1.1,side*30),Vector3(62,2.2,.4),trim,true,"metal")
		for z in range(-27,29,7):
			Geo.box(parent,Vector3(side*34,4,z),Vector3(4,8,5),wall.darkened(.25),false,"brick")
			for y in [2.5,5.5]: Geo.box(parent,Vector3(side*31.95,y,z),Vector3(.04,1.3,2),trim)
		var boundary = StaticBody3D.new()
		parent.add_child(boundary)
		for axis in range(2):
			var shape = CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			shape.shape.size = Vector3(.5,45,64) if axis==0 else Vector3(64,45,.5)
			shape.position = Vector3(side*31.5,22,0) if axis==0 else Vector3(0,22,side*30.5)
			boundary.add_child(shape)
	# Offset cover protects the long street while preserving flank routes and all spawns.
	for pos in [Vector3(-2.4,.65,-8),Vector3(2.4,.65,11),Vector3(-21,.65,15),Vector3(22,.65,-16)]:
		Geo.crate(parent,pos,Vector3(2.8,1.3,1.5),trim)
	match index:
		0: foundry(parent,wall,trim)
		1: dock(parent,wall,trim)
		2: sunspire(parent,wall,trim)
		3: relay(parent,wall,trim)
	Geo.box(parent,PADS[index]-Vector3.UP*.04,Vector3(2,.025,2),Color("d2ae61"))

static func foundry(parent: Node3D, wall: Color, trim: Color) -> void:
	# A furnace pavilion with an open passage and exposed exhaust stacks.
	for x in [-3,3]:
		Geo.box(parent,Vector3(x,2.5,-20),Vector3(.5,5,.5),trim,true,"metal")
	Geo.box(parent,Vector3(0,5.2,-20),Vector3(8,.5,5),trim,true,"metal")
	for x in [-2,2]:
		Geo.box(parent,Vector3(x,1.4,-21),Vector3(1.8,2.8,2),wall,true,"brick")
		Geo.cylinder(parent,Vector3(x,6.7,-21),.65,4,trim)
	for x in [-26,26]:
		Geo.box(parent,Vector3(x,.35,0),Vector3(2,.7,9),wall,true,"brick")
		for z in [-3,0,3]: Geo.cylinder(parent,Vector3(x,1.9,z),.55,2.4,trim)

static func dock(parent: Node3D, _wall: Color, trim: Color) -> void:
	# Two loading gantries frame the harbor; open dock sheds interrupt long angles.
	for z in [-21,21]:
		for x in [-9,9]: Geo.box(parent,Vector3(x,5,z),Vector3(.6,10,.6),Color("c49a53"),true,"metal")
		Geo.box(parent,Vector3(0,10,z),Vector3(19,.65,.8),Color("c49a53"))
		for x in range(-8,8,2): Geo.beam(parent,Vector3(x,9.7,z),Vector3(x+2,10.4,z),.1,trim)
		Geo.beam(parent,Vector3(0,9.8,z),Vector3(0,6,z),.045,trim)
	for x in [-25,25]:
		Geo.box(parent,Vector3(x,3,0),Vector3(5,.3,7),trim,true,"panel")
		for z in [-3,3]: Geo.box(parent,Vector3(x,1.5,z),Vector3(.2,3,.2),trim,true,"metal")
	Geo.box(parent,Vector3(0,-.5,-43),Vector3(100,.1,24),Color("377b8a"))

static func sunspire(parent: Node3D, wall: Color, trim: Color) -> void:
	# Two market arcades, fountain and planted courtyard edges.
	for side in [-1,1]:
		for x in [-4,0,4]:
			Geo.box(parent,Vector3(x,1.7,side*22),Vector3(.6,3.4,.6),wall,true,"brick")
		Geo.box(parent,Vector3(0,3.5,side*22),Vector3(10,.35,4),Color("b66f4e"),true,"tile")
	Geo.box(parent,Vector3(0,.35,-7),Vector3(2.8,.7,2.8),wall,true,"tile")
	Geo.cylinder(parent,Vector3(0,.75,-7),1.15,.12,trim)
	Geo.box(parent,Vector3(0,1.8,-7),Vector3(.6,2.1,.6),wall,true,"tile")
	for x in [-25,25]:
		for z in [-13,13]:
			Geo.box(parent,Vector3(x,.45,z),Vector3(2,.9,2),wall,true,"brick")
			Geo.cylinder(parent,Vector3(x,2,z),.14,3.3,Color("826543"))
			for turn in range(6):
				var leaf = Geo.sphere(parent,Vector3(x,3.7,z),.9,Color("547a5b"))
				leaf.scale = Vector3(.55,.22,2.4)
				leaf.rotation = Vector3(.2,turn*TAU/6,0)

static func relay(parent: Node3D, _wall: Color, trim: Color) -> void:
	# Open communications court and antenna towers; roof height stays boost-accessible.
	Geo.box(parent,Vector3(0,3.06,-18),Vector3(15,.28,3),trim,true,"metal")
	stairs(parent,Vector3(-8,0,-12.5),2.8,8,3.2,Color("9bb0b5"))
	Geo.box(parent,Vector3(-7.5,3.06,-17.2),Vector3(3,.28,2),trim,true,"metal")
	for x in [-6,6]: Geo.box(parent,Vector3(x,1.5,-18),Vector3(.35,3,.35),trim,true,"metal")
	for x in [-25,25]:
		Geo.box(parent,Vector3(x,1,0),Vector3(3,2,4),trim,true,"panel")
		Geo.cylinder(parent,Vector3(x,5,0),.24,6,Color("bac8c5"))
		for y in [6,7.5]: Geo.box(parent,Vector3(x,y,0),Vector3(2,.2,.5),Color("bd9554"))
	for z in [-26,26]:
		Geo.box(parent,Vector3(0,2.5,z),Vector3(4,5,.8),trim,true,"panel")
		Geo.sign_text(parent,Vector3(0,3,z+.45),"UPLINK",28,Color("a8e7dc"))
